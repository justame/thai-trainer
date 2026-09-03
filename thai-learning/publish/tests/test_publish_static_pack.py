from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from typing import Callable
from unittest import mock


PUBLISHER_PATH = Path(__file__).resolve().parents[1] / "publish_static_pack.py"
SPEC = importlib.util.spec_from_file_location("thai_static_publisher", PUBLISHER_PATH)
assert SPEC and SPEC.loader
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)

LESSON_PATH = Path(__file__).resolve().parents[2] / "days" / "day-001.json"


class FakeProvider:
    def __init__(self) -> None:
        self.calls = 0

    def synthesize(self, _ssml: str) -> bytes:
        self.calls += 1
        return b"ID3-fake-audio-" + str(self.calls).encode("ascii")


class StaticPackPublisherTests(unittest.TestCase):
    def approved_lesson(self) -> dict:
        lesson = json.loads(LESSON_PATH.read_text(encoding="utf-8"))
        lesson["status"] = "approved"
        for sentence in lesson["sentences"]:
            sentence["review_status"] = "approved"
        return lesson

    def write_json(self, path: Path, value: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")

    def generate_fake_audio(self, lesson: dict, root: Path) -> tuple[Path, FakeProvider]:
        digest = publisher.audio.content_sha256(lesson)
        approval = {
            "lesson_id": lesson["lesson_id"],
            "revision": lesson["revision"],
            "approved_sentence_ids": [item["id"] for item in lesson["sentences"]],
            "content_sha256": digest,
            "approved_at": "2026-09-03T00:00:00Z",
        }
        authorization = {
            "lesson_id": lesson["lesson_id"],
            "revision": lesson["revision"],
            "provider": lesson["voices"]["provider"],
            "content_sha256": digest,
            "authorized_at": "2026-09-03T00:01:00Z",
        }
        provider = FakeProvider()
        publisher.audio.generate_tracks(
            lesson,
            approval,
            authorization,
            root,
            lambda: provider,
        )
        revision_directory = root / lesson["lesson_id"] / f"r{lesson['revision']}"
        return revision_directory, provider

    def test_publishes_exact_deterministic_tree_from_existing_audio(self) -> None:
        lesson = self.approved_lesson()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            lesson_path = root / "approved.json"
            generated_root = root / "generated"
            site = root / "site"
            self.write_json(lesson_path, lesson)
            revision_directory, provider = self.generate_fake_audio(lesson, generated_root)
            calls_before_publish = provider.calls

            latest = publisher.publish_static_pack(lesson_path, generated_root, site)
            self.assertEqual(provider.calls, calls_before_publish)
            digest = publisher.audio.content_sha256(lesson)
            self.assertEqual(
                latest,
                {
                    "schema_version": 1,
                    "lesson_id": "day-001",
                    "revision": lesson["revision"],
                    "content_sha256": digest,
                    "lesson_path": f"packs/day-001/r{lesson['revision']}/lesson.json",
                    "audio_manifest_path": (
                        f"packs/day-001/r{lesson['revision']}/audio-manifest.json"
                    ),
                },
            )

            pack = site / "packs" / "day-001" / f"r{lesson['revision']}"
            self.assertEqual(
                {item.name for item in pack.iterdir()},
                {
                    "lesson.json",
                    "audio-manifest.json",
                    "listening.mp3",
                    "shadowing.mp3",
                    "recall.mp3",
                    "scenario.mp3",
                },
            )
            for track_id in publisher.EXPECTED_TRACK_IDS:
                filename = f"{track_id}.mp3"
                self.assertEqual(
                    (pack / filename).read_bytes(),
                    (revision_directory / filename).read_bytes(),
                )

            first_bytes = {
                path.relative_to(site): path.read_bytes()
                for path in site.rglob("*")
                if path.is_file()
            }
            first_inodes = {
                path.relative_to(site): path.stat().st_ino
                for path in site.rglob("*")
                if path.is_file()
            }
            publisher.publish_static_pack(lesson_path, revision_directory, site)
            second_bytes = {
                path.relative_to(site): path.read_bytes()
                for path in site.rglob("*")
                if path.is_file()
            }
            second_inodes = {
                path.relative_to(site): path.stat().st_ino
                for path in site.rglob("*")
                if path.is_file()
            }
            self.assertEqual(first_bytes, second_bytes)
            self.assertEqual(first_inodes, second_inodes)

    def test_conflicting_republish_preserves_live_pack_and_latest(self) -> None:
        lesson = self.approved_lesson()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            lesson_path = root / "approved.json"
            generated_root = root / "generated"
            site = root / "site"
            self.write_json(lesson_path, lesson)
            revision_directory, _provider = self.generate_fake_audio(lesson, generated_root)
            publisher.publish_static_pack(lesson_path, generated_root, site)

            pack = site / "packs" / "day-001" / f"r{lesson['revision']}"
            before_pack = {
                path.name: path.read_bytes() for path in pack.iterdir() if path.is_file()
            }
            before_latest = (site / "latest.json").read_bytes()

            generated_track = revision_directory / "listening.mp3"
            conflicting_audio = bytearray(generated_track.read_bytes())
            conflicting_audio[-1] ^= 1
            generated_track.write_bytes(conflicting_audio)

            with self.assertRaisesRegex(
                publisher.PublishError,
                "conflicts with desired content",
            ):
                publisher.publish_static_pack(lesson_path, generated_root, site)

            self.assertEqual(
                before_pack,
                {path.name: path.read_bytes() for path in pack.iterdir() if path.is_file()},
            )
            self.assertEqual(before_latest, (site / "latest.json").read_bytes())
            self.assertFalse(
                any(
                    path.name.startswith(f".r{lesson['revision']}.staging-")
                    for path in pack.parent.iterdir()
                )
            )

    def test_exclusive_directory_commit_never_replaces_existing_entry(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            staged = root / ".r1.staging-test"
            live = root / "r1"
            staged.mkdir()
            live.mkdir()
            (staged / "marker").write_bytes(b"staged")

            with self.assertRaises(OSError):
                publisher._rename_directory_no_replace(staged, live)

            self.assertTrue(staged.is_dir())
            self.assertEqual((staged / "marker").read_bytes(), b"staged")
            self.assertTrue(live.is_dir())
            self.assertEqual(list(live.iterdir()), [])

    def test_mid_build_failure_preserves_last_good_and_cleans_staging(self) -> None:
        lesson = self.approved_lesson()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            lesson_path = root / "approved.json"
            generated_root = root / "generated"
            site = root / "site"
            self.write_json(lesson_path, lesson)
            self.generate_fake_audio(lesson, generated_root)
            publisher.publish_static_pack(lesson_path, generated_root, site)

            previous_latest = (site / "latest.json").read_bytes()
            previous_pack = site / "packs" / lesson["lesson_id"] / f"r{lesson['revision']}"
            previous_pack_bytes = {
                path.name: path.read_bytes()
                for path in previous_pack.iterdir()
                if path.is_file()
            }

            next_lesson = copy.deepcopy(lesson)
            next_lesson["revision"] += 1
            next_lesson_path = root / "approved-next.json"
            self.write_json(next_lesson_path, next_lesson)
            self.generate_fake_audio(next_lesson, generated_root)

            real_atomic_write = publisher._atomic_write
            staged_write_count = 0

            def fail_during_staging(path: Path, payload: bytes) -> None:
                nonlocal staged_write_count
                if ".staging-" in str(path):
                    staged_write_count += 1
                    if staged_write_count == 3:
                        raise OSError("injected staged write failure")
                real_atomic_write(path, payload)

            with mock.patch.object(
                publisher,
                "_atomic_write",
                side_effect=fail_during_staging,
            ):
                with self.assertRaisesRegex(
                    publisher.PublishError,
                    "Cannot build staged pack",
                ):
                    publisher.publish_static_pack(next_lesson_path, generated_root, site)

            self.assertEqual(previous_latest, (site / "latest.json").read_bytes())
            self.assertEqual(
                previous_pack_bytes,
                {
                    path.name: path.read_bytes()
                    for path in previous_pack.iterdir()
                    if path.is_file()
                },
            )
            next_pack = previous_pack.parent / f"r{next_lesson['revision']}"
            self.assertFalse(next_pack.exists())
            self.assertFalse(
                any(
                    path.name.startswith(f".r{next_lesson['revision']}.staging-")
                    for path in next_pack.parent.iterdir()
                )
            )

    def test_lesson_approval_and_track_contract_table(self) -> None:
        def pending_lesson(value: dict) -> None:
            value["status"] = "pending_review"

        def pending_sentence(value: dict) -> None:
            value["sentences"][7]["review_status"] = "pending"

        def nineteen_sentences(value: dict) -> None:
            value["sentences"].pop()

        def wrong_track_order(value: dict) -> None:
            value["audio_program"]["tracks"].reverse()

        cases: list[tuple[str, Callable[[dict], None]]] = [
            ("lesson pending", pending_lesson),
            ("one sentence pending", pending_sentence),
            ("only nineteen sentences", nineteen_sentences),
            ("wrong track order", wrong_track_order),
        ]
        for label, mutate in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                lesson = self.approved_lesson()
                mutate(lesson)
                lesson_path = root / "lesson.json"
                self.write_json(lesson_path, lesson)
                with self.assertRaises(publisher.PublishError):
                    publisher.publish_static_pack(lesson_path, root / "generated", root / "site")
                self.assertFalse((root / "site" / "latest.json").exists())

    def test_manifest_and_file_integrity_table(self) -> None:
        def wrong_manifest_lesson(manifest: dict, _revision: Path) -> None:
            manifest["lesson_id"] = "day-999"

        def wrong_manifest_revision(manifest: dict, _revision: Path) -> None:
            manifest["revision"] += 1

        def wrong_content_hash(manifest: dict, _revision: Path) -> None:
            manifest["content_sha256"] = "0" * 64

        def missing_track(manifest: dict, _revision: Path) -> None:
            manifest["tracks"].pop()

        def wrong_track_filename(manifest: dict, _revision: Path) -> None:
            manifest["tracks"][0]["file"] = "other.mp3"

        def stale_request_hash(manifest: dict, _revision: Path) -> None:
            manifest["tracks"][0]["request_sha256"] = "0" * 64

        def wrong_byte_count(manifest: dict, _revision: Path) -> None:
            manifest["tracks"][0]["bytes"] += 1

        def empty_file(_manifest: dict, revision: Path) -> None:
            (revision / "listening.mp3").write_bytes(b"")

        def extra_mp3(_manifest: dict, revision: Path) -> None:
            (revision / "extra.mp3").write_bytes(b"ID3-extra")

        cases: list[tuple[str, Callable[[dict, Path], None]]] = [
            ("wrong lesson", wrong_manifest_lesson),
            ("wrong revision", wrong_manifest_revision),
            ("wrong content hash", wrong_content_hash),
            ("missing track", missing_track),
            ("wrong filename", wrong_track_filename),
            ("stale request hash", stale_request_hash),
            ("wrong byte count", wrong_byte_count),
            ("empty file", empty_file),
            ("extra mp3", extra_mp3),
        ]

        for label, mutate in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                lesson = self.approved_lesson()
                lesson_path = root / "lesson.json"
                self.write_json(lesson_path, lesson)
                revision, _provider = self.generate_fake_audio(lesson, root / "generated")
                manifest_path = revision / "audio-manifest.json"
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                mutate(manifest, revision)
                self.write_json(manifest_path, manifest)

                with self.assertRaises(publisher.PublishError):
                    publisher.publish_static_pack(lesson_path, root / "generated", root / "site")
                self.assertFalse((root / "site" / "latest.json").exists())


if __name__ == "__main__":
    unittest.main()
