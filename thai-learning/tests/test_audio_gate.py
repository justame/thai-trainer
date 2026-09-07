from __future__ import annotations

import base64
import copy
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "audio" / "generate_audio.py"
SPEC = importlib.util.spec_from_file_location("thai_audio", MODULE_PATH)
assert SPEC and SPEC.loader
audio = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audio)


LESSON_PATH = Path(__file__).resolve().parents[1] / "days" / "day-001.json"


def fake_linear16_wav(frame_count: int = 2, sample: int = 1) -> bytes:
    destination = io.BytesIO()
    with wave.open(destination, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(audio.GOOGLE_SAMPLE_RATE_HERTZ)
        output.writeframes(sample.to_bytes(2, "little", signed=True) * frame_count)
    return destination.getvalue()


class FakeProvider:
    def __init__(self, fail_on_call: int | None = None):
        self.calls: list[str] = []
        self.fail_on_call = fail_on_call

    def synthesize(self, ssml: str) -> bytes:
        self.calls.append(ssml)
        if self.fail_on_call == len(self.calls):
            raise RuntimeError("simulated provider failure")
        return b"ID3" + len(self.calls).to_bytes(1, "big")


class FakeGoogleProvider:
    def __init__(self, fail_on_call: int | None = None):
        self.calls: list[dict] = []
        self.fail_on_call = fail_on_call

    def synthesize_segment(self, request: dict) -> bytes:
        self.calls.append(copy.deepcopy(request))
        if self.fail_on_call == len(self.calls):
            raise RuntimeError("simulated provider failure")
        return fake_linear16_wav(sample=len(self.calls))


class FakeGoogleAssembler:
    def __init__(self):
        self.calls: list[tuple[dict, dict[str, bytes]]] = []

    def __call__(self, request: dict, segment_audio: dict[str, bytes]) -> bytes:
        self.calls.append((copy.deepcopy(request), dict(segment_audio)))
        speech_hashes = {
            item["segment_sha256"]
            for item in request["timeline"]
            if item["kind"] == "speech"
        }
        if speech_hashes != set(segment_audio):
            raise AssertionError("assembler did not receive every speech segment")
        return b"ID3-google-track-" + len(self.calls).to_bytes(1, "big")


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
            "provider": lesson["voices"]["provider"],
            "authorized_at": "2026-09-03T00:01:00Z",
        }
        return approval, authorization

    def google_lesson(self, *, approved: bool = True):
        lesson = self.approved_lesson() if approved else copy.deepcopy(self.lesson)
        lesson["audio_program"].pop("practice_variations", None)
        lesson["voices"] = {
            "provider": "google_cloud_tts",
            "thai": {
                "language_code": "th-TH",
                "name": "th-TH-Chirp3-HD-Erinome",
            },
            "hebrew": {
                "language_code": "he-IL",
                "name": "he-IL-Chirp3-HD-Charon",
            },
        }
        lesson["audio_program"]["pitch_semitones"] = 0
        configured_rates = {
            "listening": [0.82, 1.0],
            "shadowing": [0.9, 0.9, 0.9],
            "recall": [0.9],
            "scenario": [1.0],
        }
        for track in lesson["audio_program"]["tracks"]:
            track["thai_speaking_rates"] = configured_rates[track["id"]]
            if track.get("hebrew_prompt"):
                track["hebrew_speaking_rate"] = 1.0
        return lesson

    def azure_lesson(self, *, approved: bool = True):
        lesson = self.approved_lesson() if approved else copy.deepcopy(self.lesson)
        lesson["audio_program"].pop("practice_variations", None)
        lesson["voices"] = {
            "provider": "azure_speech",
            "thai": "th-TH-PremwadeeNeural",
            "hebrew": "he-IL-HilaNeural",
        }
        lesson["audio_program"]["pitch_semitones"] = 0
        return lesson

    def test_pending_google_lesson_cannot_read_credentials_run_gcloud_or_use_network(self):
        lesson = self.google_lesson(approved=False)

        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                mock.patch.object(
                    audio.os.environ,
                    "get",
                    side_effect=AssertionError("credentials must not be read"),
                ) as environment_get,
                mock.patch.object(
                    audio.subprocess,
                    "run",
                    side_effect=AssertionError("gcloud must not execute"),
                ) as gcloud_run,
                mock.patch.object(
                    audio.urllib.request,
                    "urlopen",
                    side_effect=AssertionError("network must not be contacted"),
                ) as urlopen,
                mock.patch.object(
                    audio,
                    "provider_from_environment",
                    side_effect=AssertionError("provider must not be constructed"),
                ) as provider_factory,
                mock.patch.object(
                    audio,
                    "assemble_google_track",
                    side_effect=AssertionError("assembler must not run"),
                ) as assembler,
            ):
                with self.assertRaises(audio.GateError):
                    audio.generate_tracks(lesson, {}, {}, Path(temp_dir))
            environment_get.assert_not_called()
            gcloud_run.assert_not_called()
            urlopen.assert_not_called()
            provider_factory.assert_not_called()
            assembler.assert_not_called()
            self.assertEqual(list(Path(temp_dir).iterdir()), [])

    def test_approved_text_without_paid_authorization_blocks(self):
        lesson = self.approved_lesson()
        approval, _ = self.receipts(lesson)
        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                mock.patch.object(audio.os.environ, "get") as environment_get,
                mock.patch.object(audio.subprocess, "run") as subprocess_run,
                mock.patch.object(audio.urllib.request, "urlopen") as urlopen,
            ):
                with self.assertRaises(audio.GateError):
                    audio.generate_tracks(lesson, approval, {}, Path(temp_dir))
            environment_get.assert_not_called()
            subprocess_run.assert_not_called()
            urlopen.assert_not_called()
            self.assertEqual(list(Path(temp_dir).iterdir()), [])

    def test_google_cost_authorization_caps_all_unique_request_characters(self):
        lesson = self.google_lesson()
        lesson["audio_program"]["practice_variations"] = {
            "hebrew_speaking_rate": 1.0,
            "thai_speaking_rate": 1.0,
        }
        approval, authorization = self.receipts(lesson)
        planned_characters = audio.planned_google_billable_characters(lesson)
        authorization.update(
            {
                "max_cost_usd": planned_characters * 0.00003,
                "price_usd_per_character": 0.00003,
                "max_billable_characters": planned_characters,
            }
        )

        self.assertEqual(
            audio.preflight(lesson, approval, authorization),
            audio.content_sha256(lesson),
        )

        authorization["max_billable_characters"] = planned_characters - 1
        with self.assertRaisesRegex(audio.GateError, "authorized character cap"):
            audio.preflight(lesson, approval, authorization)

        authorization["max_billable_characters"] = planned_characters
        authorization["max_cost_usd"] = planned_characters * 0.00003 - 0.000001
        with self.assertRaisesRegex(audio.GateError, "authorized dollar cap"):
            audio.preflight(lesson, approval, authorization)

    def test_one_character_change_invalidates_both_receipts(self):
        lesson = self.approved_lesson()
        approval, authorization = self.receipts(lesson)
        lesson["sentences"][0]["thai"] += " "
        with self.assertRaises(audio.GateError):
            audio.preflight(lesson, approval, authorization)

    def test_spoken_hebrew_rejects_slashes_dashes_and_latin_letters(self):
        invalid_prompts = (
            "את/ה מגיע לכאן?",
            "אפשר לשלם ב קיו-אר?",
            "אתה פנוי – הערב?",
            "אני רוצה להטעין כרטיס Rabbit.",
        )

        for prompt in invalid_prompts:
            with self.subTest(prompt=prompt):
                lesson = self.approved_lesson()
                lesson["sentences"][0]["prompt_he"] = prompt
                with self.assertRaisesRegex(
                    audio.GateError,
                    "spoken Hebrew must use Hebrew words without slash, dash, or Latin letters",
                ):
                    audio.canonical_content(lesson)

    def test_spoken_variation_text_and_settings_are_approval_bound(self):
        lesson = self.google_lesson()
        lesson["audio_program"]["practice_variations"] = {
            "hebrew_speaking_rate": 1.0,
            "thai_speaking_rate": 1.0,
        }
        approval, authorization = self.receipts(lesson)

        changed_text = copy.deepcopy(lesson)
        changed_text["sentences"][0]["variation"]["thai"] += " "
        with self.assertRaises(audio.GateError):
            audio.preflight(changed_text, approval, authorization)

        changed_rate = copy.deepcopy(lesson)
        changed_rate["audio_program"]["practice_variations"][
            "thai_speaking_rate"
        ] = 0.9
        with self.assertRaises(audio.GateError):
            audio.preflight(changed_rate, approval, authorization)

    def test_google_practice_variations_plan_exact_approved_pairs(self):
        lesson = self.google_lesson()
        lesson["audio_program"]["practice_variations"] = {
            "hebrew_speaking_rate": 1.0,
            "thai_speaking_rate": 1.0,
        }

        requests = audio.build_google_practice_variation_requests(lesson)

        self.assertEqual(len(requests), 20)
        self.assertEqual(requests[0]["sentence_id"], "d001-s01")
        self.assertEqual(
            requests[0]["hebrew"]["request"]["input"]["text"],
            lesson["sentences"][0]["variation"]["prompt_he"],
        )
        self.assertEqual(
            requests[0]["thai"]["request"]["input"]["text"],
            lesson["sentences"][0]["variation"]["thai"],
        )
        self.assertTrue(
            all(
                item[language]["request"]["audioConfig"]["speakingRate"] == 1.0
                for item in requests
                for language in ("hebrew", "thai")
            )
        )

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
        if isinstance(changed_voice["voices"]["thai"], dict):
            changed_voice["voices"]["thai"]["name"] = "different-voice"
        else:
            changed_voice["voices"]["thai"] = "different-voice"
        with self.assertRaises(audio.GateError):
            audio.preflight(changed_voice, approval, authorization)

    def test_ssml_encodes_per_utterance_rates_without_pitch_change(self):
        lesson = self.azure_lesson()
        track = lesson["audio_program"]["tracks"][0]
        track["sequence"] = [lesson["sentences"][0]["id"]]
        track["thai_repetitions"] = 2
        track["thai_speaking_rates"] = [0.82, 1.0]

        ssml = audio.build_track_ssml(lesson, track)

        self.assertIn('name="th-TH-PremwadeeNeural"', ssml)
        self.assertEqual(ssml.count('<prosody rate="0.82">'), 1)
        self.assertEqual(ssml.count('<prosody rate="1">'), 1)
        self.assertNotIn("pitch=", ssml)

    def test_ssml_rejects_rate_count_mismatch_and_nonzero_pitch(self):
        lesson = self.azure_lesson()
        track = lesson["audio_program"]["tracks"][0]
        track["thai_speaking_rates"] = [0.82]
        with self.assertRaisesRegex(audio.GateError, "matching thai_repetitions"):
            audio.build_track_ssml(lesson, track)

        lesson = self.azure_lesson()
        lesson["audio_program"]["pitch_semitones"] = 1
        with self.assertRaisesRegex(audio.GateError, "must remain 0"):
            audio.build_track_ssml(lesson, lesson["audio_program"]["tracks"][0])

        lesson = self.azure_lesson()
        lesson["audio_program"]["tracks"][0]["thai_speaking_rates"] = [0.49, 1.0]
        with self.assertRaisesRegex(audio.GateError, "0.5 and 2.0"):
            audio.build_track_ssml(lesson, lesson["audio_program"]["tracks"][0])

    def test_google_plan_uses_plain_text_explicit_voice_rate_and_exact_order(self):
        lesson = self.google_lesson()
        track = lesson["audio_program"]["tracks"][0]
        track["sequence"] = [item["id"] for item in lesson["sentences"][:2]]

        request = audio.build_google_track_request(lesson, track)
        timeline = request["timeline"]

        self.assertEqual(
            [item["kind"] for item in timeline],
            ["speech", "silence", "speech", "silence", "speech", "silence", "speech"],
        )
        speech = [item["request"] for item in timeline if item["kind"] == "speech"]
        self.assertEqual(
            [item["input"]["text"] for item in speech],
            [
                lesson["sentences"][0]["thai"],
                lesson["sentences"][0]["thai"],
                lesson["sentences"][1]["thai"],
                lesson["sentences"][1]["thai"],
            ],
        )
        self.assertEqual(
            [item["audioConfig"]["speakingRate"] for item in speech],
            [0.82, 1.0, 0.82, 1.0],
        )
        self.assertEqual(
            [item["milliseconds"] for item in timeline if item["kind"] == "silence"],
            [1200, 2800, 1200],
        )
        for item in speech:
            self.assertNotIn("ssml", item["input"])
            self.assertLessEqual(
                len(item["input"]["text"].encode("utf-8")),
                audio.GOOGLE_SYNTHESIS_MAX_BYTES,
            )
            self.assertEqual(item["voice"]["languageCode"], "th-TH")
            self.assertEqual(item["voice"]["name"], "th-TH-Chirp3-HD-Erinome")
            self.assertEqual(item["audioConfig"]["audioEncoding"], "LINEAR16")
            self.assertEqual(
                item["audioConfig"]["sampleRateHertz"], audio.GOOGLE_SAMPLE_RATE_HERTZ
            )
            self.assertNotIn("pitch", item["audioConfig"])

    def test_google_recall_switches_voice_per_plain_text_segment(self):
        lesson = self.google_lesson()
        track = next(
            item for item in lesson["audio_program"]["tracks"] if item["id"] == "recall"
        )
        track["sequence"] = [lesson["sentences"][0]["id"]]

        request = audio.build_google_track_request(lesson, track)
        speech = [item["request"] for item in request["timeline"] if item["kind"] == "speech"]

        self.assertEqual(len(speech), 2)
        self.assertEqual(speech[0]["input"], {"text": lesson["sentences"][0]["prompt_he"]})
        self.assertEqual(speech[0]["voice"]["languageCode"], "he-IL")
        self.assertEqual(speech[0]["voice"]["name"], "he-IL-Chirp3-HD-Charon")
        self.assertEqual(speech[0]["audioConfig"]["speakingRate"], 1.0)
        self.assertEqual(speech[1]["input"], {"text": lesson["sentences"][0]["thai"]})
        self.assertEqual(speech[1]["voice"]["languageCode"], "th-TH")
        self.assertEqual(speech[1]["audioConfig"]["speakingRate"], 0.9)

    def test_google_segment_over_five_thousand_bytes_fails_before_provider(self):
        lesson = self.google_lesson()
        lesson["sentences"][0]["thai"] = "ก" * 1700
        track = lesson["audio_program"]["tracks"][0]
        track["sequence"] = [lesson["sentences"][0]["id"]]
        approval, authorization = self.receipts(lesson)
        with tempfile.TemporaryDirectory() as temp_dir:
            with mock.patch.object(
                audio,
                "provider_from_environment",
                side_effect=AssertionError("provider must not be constructed"),
            ) as provider_factory:
                with self.assertRaisesRegex(audio.GateError, "5,000-byte"):
                    audio.generate_tracks(
                        lesson, approval, authorization, Path(temp_dir)
                    )
            provider_factory.assert_not_called()

    def test_google_request_hash_covers_provider_voice_rate_order_and_assembly(self):
        lesson = self.google_lesson()
        track = lesson["audio_program"]["tracks"][0]
        track["sequence"] = [item["id"] for item in lesson["sentences"][:2]]
        request = audio.build_google_track_request(lesson, track)
        original = audio.request_sha256(request)

        mutations = []
        provider_change = copy.deepcopy(request)
        provider_change["provider"] = "different-provider"
        mutations.append(provider_change)
        voice_change = copy.deepcopy(request)
        voice_change["timeline"][0]["request"]["voice"]["name"] = "different-voice"
        mutations.append(voice_change)
        rate_change = copy.deepcopy(request)
        rate_change["timeline"][0]["request"]["audioConfig"]["speakingRate"] = 0.75
        mutations.append(rate_change)
        order_change = copy.deepcopy(request)
        order_change["timeline"] = list(reversed(order_change["timeline"]))
        mutations.append(order_change)
        assembly_change = copy.deepcopy(request)
        assembly_change["assembly"]["version"] = 2
        mutations.append(assembly_change)

        for changed in mutations:
            self.assertNotEqual(audio.request_sha256(changed), original)

    def test_google_provider_decodes_linear16_and_sends_expected_rest_request(self):
        captured: dict[str, object] = {}

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return json.dumps(
                    {"audioContent": base64.b64encode(b"RIFF-google").decode("ascii")}
                ).encode("utf-8")

        def fake_urlopen(request, timeout):
            captured["request"] = request
            captured["timeout"] = timeout
            return Response()

        provider = audio.GoogleCloudTTSProvider(
            access_token="offline-test-token",
            quota_project="offline-project",
        )
        request_body = audio._google_speech_request(
            "สวัสดี",
            dict(audio.DEFAULT_GOOGLE_THAI_VOICE),
            0.82,
        )
        with mock.patch.object(audio.urllib.request, "urlopen", side_effect=fake_urlopen):
            result = provider.synthesize_segment(request_body)

        self.assertEqual(result, b"RIFF-google")
        request = captured["request"]
        self.assertEqual(request.full_url, audio.GOOGLE_TTS_ENDPOINT)
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.get_header("Authorization"), "Bearer offline-test-token")
        self.assertEqual(request.get_header("X-goog-user-project"), "offline-project")
        payload = json.loads(request.data.decode("utf-8"))
        self.assertEqual(payload["input"], {"text": "สวัสดี"})
        self.assertEqual(payload["voice"]["languageCode"], "th-TH")
        self.assertEqual(payload["voice"]["name"], "th-TH-Chirp3-HD-Erinome")
        self.assertEqual(
            payload["audioConfig"],
            {
                "audioEncoding": "LINEAR16",
                "sampleRateHertz": 24000,
                "speakingRate": 0.82,
            },
        )
        self.assertEqual(captured["timeout"], 45)

    def test_google_provider_selection_happens_after_preflight_and_uses_gcloud_adc(self):
        lesson = self.google_lesson()
        approval, authorization = self.receipts(lesson)
        selected_provider = FakeGoogleProvider()
        assembler = FakeGoogleAssembler()
        completed = subprocess.CompletedProcess(
            args=[], returncode=0, stdout="adc-test-token\n", stderr=""
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                mock.patch.dict(
                    os.environ,
                    {"GOOGLE_CLOUD_QUOTA_PROJECT": "offline-project"},
                    clear=True,
                ),
                mock.patch.object(audio.subprocess, "run", return_value=completed) as run,
                mock.patch.object(
                    audio.GoogleCloudTTSProvider,
                    "synthesize_segment",
                    side_effect=selected_provider.synthesize_segment,
                ),
            ):
                manifest = audio.generate_tracks(
                    lesson,
                    approval,
                    authorization,
                    Path(temp_dir) / "generated",
                    google_assembler=assembler,
                )

        self.assertEqual(manifest["provider"], "google_cloud_tts")
        unique_segments = {
            item["segment_sha256"]
            for track in lesson["audio_program"]["tracks"]
            for item in audio.build_google_track_request(lesson, track)["timeline"]
            if item["kind"] == "speech"
        }
        self.assertEqual(len(selected_provider.calls), len(unique_segments))
        self.assertEqual(len(assembler.calls), len(lesson["audio_program"]["tracks"]))
        run.assert_called_once_with(
            ["gcloud", "auth", "application-default", "print-access-token"],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_review_pack_contains_exactly_twenty_sentences(self):
        self.assertEqual(len(self.lesson["sentences"]), 20)

    def test_canonical_hash_normalizes_audio_numbers_without_mutating_requests(self):
        lesson = self.google_lesson()

        canonical = audio.canonical_content(lesson)

        self.assertEqual(canonical["audio_program"]["pitch_semitones"], "0")
        normalized_rates = {
            track["id"]: track["thai_speaking_rates"]
            for track in canonical["audio_program"]["tracks"]
        }
        self.assertEqual(normalized_rates["listening"], ["0.82", "1"])
        self.assertEqual(normalized_rates["shadowing"], ["0.9", "0.9", "0.9"])
        recall = next(
            track
            for track in canonical["audio_program"]["tracks"]
            if track["id"] == "recall"
        )
        self.assertEqual(recall["hebrew_speaking_rate"], "1")

        original_listening = lesson["audio_program"]["tracks"][0]
        self.assertEqual(original_listening["thai_speaking_rates"], [0.82, 1.0])
        request = audio.build_google_track_request(lesson, original_listening)
        first_audio_config = next(
            segment["request"]["audioConfig"]
            for segment in request["timeline"]
            if segment["kind"] == "speech"
        )
        self.assertEqual(first_audio_config["speakingRate"], 0.82)
        self.assertIsInstance(first_audio_config["speakingRate"], float)

    def test_free_form_track_text_is_rejected(self):
        lesson = self.approved_lesson()
        lesson["audio_program"]["tracks"][0]["sequence"].append("unapproved-line")
        with self.assertRaises(audio.GateError):
            audio.content_sha256(lesson)

    def test_valid_mock_run_generates_only_reviewed_text_and_reuses_cache(self):
        lesson = self.azure_lesson()
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
            self.assertEqual(factory_calls, 1)

    def test_partial_failure_resumes_only_missing_tracks(self):
        lesson = self.azure_lesson()
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

    def test_google_generation_deduplicates_identical_speech_requests(self):
        lesson = self.google_lesson()
        lesson["audio_program"]["tracks"] = [lesson["audio_program"]["tracks"][0]]
        track = lesson["audio_program"]["tracks"][0]
        track["sequence"] = [item["id"] for item in lesson["sentences"][:2]]
        track["thai_speaking_rates"] = [1.0, 1.0]
        approval, authorization = self.receipts(lesson)
        provider = FakeGoogleProvider()
        assembler = FakeGoogleAssembler()

        with tempfile.TemporaryDirectory() as temp_dir:
            manifest = audio.generate_tracks(
                lesson,
                approval,
                authorization,
                Path(temp_dir) / "generated",
                lambda: provider,
                assembler,
            )

        self.assertEqual(len(provider.calls), 2)
        self.assertEqual(len(assembler.calls), 1)
        self.assertEqual(manifest["tracks"][0]["speech_segments"], 4)
        self.assertEqual(manifest["tracks"][0]["assembly"], audio.GOOGLE_ASSEMBLY)

    def test_google_generation_caches_every_authorized_practice_variation(self):
        lesson = self.google_lesson()
        lesson["audio_program"]["tracks"] = [lesson["audio_program"]["tracks"][3]]
        lesson["audio_program"]["tracks"][0]["sequence"] = [
            item["id"] for item in lesson["sentences"][:2]
        ]
        lesson["audio_program"]["practice_variations"] = {
            "hebrew_speaking_rate": 1.0,
            "thai_speaking_rate": 1.0,
        }
        approval, authorization = self.receipts(lesson)
        provider = FakeGoogleProvider()

        with tempfile.TemporaryDirectory() as temp_dir:
            output_root = Path(temp_dir) / "generated"
            with (
                mock.patch.object(audio, "preflight_google_assembler"),
                mock.patch.object(
                    audio,
                    "assemble_google_track",
                    return_value=b"ID3-practice-variations",
                ),
            ):
                first = audio.generate_tracks(
                    lesson,
                    approval,
                    authorization,
                    output_root,
                    lambda: provider,
                )
                first_call_count = len(provider.calls)
                second = audio.generate_tracks(
                    lesson,
                    approval,
                    authorization,
                    output_root,
                    lambda: provider,
                )

        self.assertEqual(first_call_count, 42)
        self.assertEqual(len(provider.calls), first_call_count)
        self.assertEqual(first["practice_variations"]["count"], 20)
        self.assertEqual(len(first["practice_variations"]["pairs"]), 20)
        self.assertEqual(first["practice_variations"], second["practice_variations"])

    def test_google_checks_local_encoder_before_provider_or_network(self):
        lesson = self.google_lesson()
        lesson["audio_program"]["tracks"] = [lesson["audio_program"]["tracks"][0]]
        approval, authorization = self.receipts(lesson)
        provider_factory = mock.Mock(side_effect=AssertionError("provider must not run"))

        with tempfile.TemporaryDirectory() as temp_dir:
            with mock.patch.object(
                audio,
                "preflight_google_assembler",
                side_effect=RuntimeError("sox unavailable"),
            ) as encoder_preflight:
                with self.assertRaisesRegex(RuntimeError, "sox unavailable"):
                    audio.generate_tracks(
                        lesson,
                        approval,
                        authorization,
                        Path(temp_dir) / "generated",
                        provider_factory,
                    )

        encoder_preflight.assert_called_once_with()
        provider_factory.assert_not_called()

    def test_google_invalid_first_wav_stops_before_more_paid_requests(self):
        lesson = self.google_lesson()
        lesson["audio_program"]["tracks"] = [lesson["audio_program"]["tracks"][0]]
        approval, authorization = self.receipts(lesson)
        provider = FakeGoogleProvider()
        provider.synthesize_segment = mock.Mock(return_value=b"not-a-wav")
        assembler = FakeGoogleAssembler()

        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                mock.patch.object(audio, "preflight_google_assembler"),
                mock.patch.object(
                    audio, "assemble_google_track", side_effect=assembler
                ) as assemble,
            ):
                with self.assertRaisesRegex(RuntimeError, "invalid LINEAR16 WAV"):
                    audio.generate_tracks(
                        lesson,
                        approval,
                        authorization,
                        Path(temp_dir) / "generated",
                        lambda: provider,
                    )

        self.assertEqual(provider.synthesize_segment.call_count, 1)
        self.assertEqual(assembler.calls, [])
        assemble.assert_not_called()

    def test_google_partial_failure_resumes_from_persistent_segment_cache(self):
        lesson = self.google_lesson()
        lesson["audio_program"]["tracks"] = [lesson["audio_program"]["tracks"][0]]
        track = lesson["audio_program"]["tracks"][0]
        track["sequence"] = [item["id"] for item in lesson["sentences"][:2]]
        track["thai_speaking_rates"] = [1.0, 1.0]
        approval, authorization = self.receipts(lesson)
        failing = FakeGoogleProvider(fail_on_call=2)
        assembler = FakeGoogleAssembler()

        with tempfile.TemporaryDirectory() as temp_dir:
            output_root = Path(temp_dir) / "generated"
            with (
                mock.patch.object(audio, "preflight_google_assembler"),
                mock.patch.object(
                    audio, "assemble_google_track", side_effect=assembler
                ),
            ):
                with self.assertRaisesRegex(RuntimeError, "simulated provider failure"):
                    audio.generate_tracks(
                        lesson,
                        approval,
                        authorization,
                        output_root,
                        lambda: failing,
                    )
                self.assertEqual(len(failing.calls), 2)

                resumed = FakeGoogleProvider()
                manifest = audio.generate_tracks(
                    lesson,
                    approval,
                    authorization,
                    output_root,
                    lambda: resumed,
                )

        self.assertEqual(len(resumed.calls), 1)
        self.assertEqual(len(manifest["tracks"]), 1)

    def test_google_assembler_inserts_exact_silence_and_invokes_sox_once(self):
        def wav_with_frames(frame_count: int) -> bytes:
            destination = io.BytesIO()
            with wave.open(destination, "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(audio.GOOGLE_SAMPLE_RATE_HERTZ)
                output.writeframes(b"\x01\x00" * frame_count)
            return destination.getvalue()

        speech_request = audio._google_speech_request(
            "สวัสดี", dict(audio.DEFAULT_GOOGLE_THAI_VOICE), 1.0
        )
        speech = audio._speech_segment(speech_request)
        track_request = {
            "request_version": 1,
            "provider": "google_cloud_tts",
            "timeline": [speech, {"kind": "silence", "milliseconds": 100}, speech],
            "assembly": dict(audio.GOOGLE_ASSEMBLY),
        }
        segment_audio = {speech["segment_sha256"]: wav_with_frames(2)}
        observed_frames: list[int] = []

        def fake_run(command, **kwargs):
            with wave.open(command[1], "rb") as combined:
                observed_frames.append(combined.getnframes())
                self.assertEqual(combined.getnchannels(), 1)
                self.assertEqual(combined.getsampwidth(), 2)
                self.assertEqual(combined.getframerate(), 24000)
            Path(command[-1]).write_bytes(b"ID3-assembled")
            return subprocess.CompletedProcess(command, 0, stdout=b"", stderr=b"")

        with (
            mock.patch.dict(os.environ, {"THAI_TTS_SOX": "/opt/homebrew/bin/sox"}),
            mock.patch.object(audio.subprocess, "run", side_effect=fake_run) as run,
        ):
            result = audio.assemble_google_track(track_request, segment_audio)

        self.assertEqual(result, b"ID3-assembled")
        self.assertEqual(observed_frames, [2 + 2400 + 2])
        self.assertEqual(run.call_count, 1)
        command = run.call_args.args[0]
        self.assertEqual(command[0], "/opt/homebrew/bin/sox")
        self.assertEqual(command[2:4], ["-C", "48"])
        self.assertEqual(
            run.call_args.kwargs,
            {"check": False, "capture_output": True, "timeout": 120},
        )


if __name__ == "__main__":
    unittest.main()
