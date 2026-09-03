from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "audio" / "generate_audio.py"
SPEC = importlib.util.spec_from_file_location("thai_audio", MODULE_PATH)
assert SPEC and SPEC.loader
audio = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audio)


LESSON_PATH = Path(__file__).resolve().parents[1] / "days" / "day-001.json"


class FakeProvider:
    def __init__(self, fail_on_call: int | None = None):
        self.calls: list[str] = []
        self.fail_on_call = fail_on_call

    def synthesize(self, ssml: str) -> bytes:
        self.calls.append(ssml)
        if self.fail_on_call == len(self.calls):
            raise RuntimeError("simulated provider failure")
        return b"ID3" + len(self.calls).to_bytes(1, "big")


class AudioGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lesson = json.loads(LESSON_PATH.read_text(encoding="utf-8"))

    def approved_lesson(self):
        lesson = copy.deepcopy(self.lesson)
        lesson["status"] = "approved"
        for sentence in lesson["sentences"]:
            sentence["review_status"] = "approved"
        return lesson

    def receipts(self, lesson):
        digest = audio.content_sha256(lesson)
        sentence_ids = [item["id"] for item in lesson["sentences"]]
        approval = {
            "schema_version": 1,
            "lesson_id": lesson["lesson_id"],
            "revision": lesson["revision"],
            "approved_sentence_ids": sentence_ids,
            "content_sha256": digest,
            "approved_at": "2026-09-03T00:00:00Z",
        }
        authorization = {
            "schema_version": 1,
            "lesson_id": lesson["lesson_id"],
            "revision": lesson["revision"],
            "content_sha256": digest,
            "provider": "azure_speech",
            "authorized_at": "2026-09-03T00:01:00Z",
        }
        return approval, authorization

    def test_pending_lesson_blocks_before_provider_construction(self):
        provider_constructed = False

        def forbidden_factory():
            nonlocal provider_constructed
            provider_constructed = True
            raise AssertionError("provider must not be constructed")

        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaises(audio.GateError):
                audio.generate_tracks(self.lesson, {}, {}, Path(temp_dir), forbidden_factory)
            self.assertFalse(provider_constructed)
            self.assertEqual(list(Path(temp_dir).iterdir()), [])

    def test_approved_text_without_paid_authorization_blocks(self):
        lesson = self.approved_lesson()
        approval, _ = self.receipts(lesson)
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaises(audio.GateError):
                audio.generate_tracks(lesson, approval, {}, Path(temp_dir), lambda: None)
            self.assertEqual(list(Path(temp_dir).iterdir()), [])

    def test_one_character_change_invalidates_both_receipts(self):
        lesson = self.approved_lesson()
        approval, authorization = self.receipts(lesson)
        lesson["sentences"][0]["thai"] += " "
        with self.assertRaises(audio.GateError):
            audio.preflight(lesson, approval, authorization)

    def test_order_or_voice_change_invalidates_receipts(self):
        lesson = self.approved_lesson()
        approval, authorization = self.receipts(lesson)

        reordered = copy.deepcopy(lesson)
        reordered["sentences"][0], reordered["sentences"][1] = (
            reordered["sentences"][1],
            reordered["sentences"][0],
        )
        with self.assertRaises(audio.GateError):
            audio.preflight(reordered, approval, authorization)

        changed_voice = copy.deepcopy(lesson)
        changed_voice["voices"]["thai"] = "different-voice"
        with self.assertRaises(audio.GateError):
            audio.preflight(changed_voice, approval, authorization)

    def test_review_pack_contains_exactly_twenty_sentences(self):
        self.assertEqual(len(self.lesson["sentences"]), 20)

    def test_free_form_track_text_is_rejected(self):
        lesson = self.approved_lesson()
        lesson["audio_program"]["tracks"][0]["sequence"].append("unapproved-line")
        with self.assertRaises(audio.GateError):
            audio.content_sha256(lesson)

    def test_valid_mock_run_generates_only_reviewed_text_and_reuses_cache(self):
        lesson = self.approved_lesson()
        approval, authorization = self.receipts(lesson)
        provider = FakeProvider()
        factory_calls = 0

        def factory():
            nonlocal factory_calls
            factory_calls += 1
            return provider

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first = audio.generate_tracks(lesson, approval, authorization, root, factory)
            self.assertEqual(len(provider.calls), len(lesson["audio_program"]["tracks"]))
            all_thai = [item["thai"] for item in lesson["sentences"]]
            for ssml in provider.calls:
                self.assertTrue(any(text in ssml for text in all_thai))
            for track in first["tracks"]:
                self.assertGreater(track["bytes"], 0)

            before = len(provider.calls)
            second = audio.generate_tracks(lesson, approval, authorization, root, factory)
            self.assertEqual(len(provider.calls), before)
            self.assertEqual(first["content_sha256"], second["content_sha256"])
            self.assertEqual(factory_calls, 2)

    def test_partial_failure_resumes_only_missing_tracks(self):
        lesson = self.approved_lesson()
        approval, authorization = self.receipts(lesson)
        failing = FakeProvider(fail_on_call=2)
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            with self.assertRaises(RuntimeError):
                audio.generate_tracks(lesson, approval, authorization, root, lambda: failing)
            self.assertEqual(len(failing.calls), 2)

            resumed = FakeProvider()
            audio.generate_tracks(lesson, approval, authorization, root, lambda: resumed)
            self.assertEqual(
                len(resumed.calls),
                len(lesson["audio_program"]["tracks"]) - 1,
            )


if __name__ == "__main__":
    unittest.main()
