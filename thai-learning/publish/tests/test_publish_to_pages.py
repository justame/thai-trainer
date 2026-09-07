from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


HELPER_PATH = Path(__file__).resolve().parents[1] / "publish_to_pages.py"
SPEC = importlib.util.spec_from_file_location("thai_pages_publisher", HELPER_PATH)
assert SPEC and SPEC.loader
pages = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pages)

PENDING_LESSON = Path(__file__).resolve().parents[2] / "days" / "day-001.json"
LATEST = {
    "schema_version": 1,
    "lesson_id": "day-001",
    "revision": 1,
    "content_sha256": "a" * 64,
    "lesson_path": "packs/day-001/r1/lesson.json",
    "audio_manifest_path": "packs/day-001/r1/audio-manifest.json",
}


class PagesPublishHelperTests(unittest.TestCase):
    def test_pending_lesson_fails_before_docs_or_git_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            docs = root / "docs"
            docs.mkdir()
            landing = docs / "index.html"
            landing.write_text("pending landing", encoding="utf-8")
            pending_lesson = root / "pending-lesson.json"
            lesson = json.loads(PENDING_LESSON.read_text(encoding="utf-8"))
            lesson["status"] = "pending_review"
            for sentence in lesson["sentences"]:
                sentence["review_status"] = "pending"
            pending_lesson.write_text(json.dumps(lesson), encoding="utf-8")

            with mock.patch.object(pages, "_run_git") as run_git:
                with self.assertRaisesRegex(
                    pages.publisher.PublishError,
                    "Lesson is not publishable",
                ):
                    pages.publish_to_pages(
                        pending_lesson,
                        root / "missing-audio",
                        docs,
                        repository_root=root,
                        push=True,
                    )

            run_git.assert_not_called()
            self.assertEqual(landing.read_text(encoding="utf-8"), "pending landing")
            self.assertFalse((docs / "latest.json").exists())
            self.assertEqual({path.name for path in docs.iterdir()}, {"index.html"})

    def test_dry_run_uses_disposable_output_and_leaves_docs_untouched(self) -> None:
        observed_output: Path | None = None

        def fake_publish(_lesson: Path, _audio: Path, output: Path) -> dict:
            nonlocal observed_output
            observed_output = output
            self.assertTrue(output.is_dir())
            (output / "latest.json").write_text("temporary", encoding="utf-8")
            return LATEST

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            docs = root / "docs"
            docs.mkdir()
            (docs / "index.html").write_text("landing", encoding="utf-8")

            with mock.patch.object(
                pages.publisher,
                "publish_static_pack",
                side_effect=fake_publish,
            ), mock.patch.object(pages, "_run_git") as run_git:
                result = pages.publish_to_pages(
                    root / "lesson.json",
                    root / "generated",
                    docs,
                    repository_root=root,
                    dry_run=True,
                )

            self.assertEqual(result, LATEST)
            self.assertIsNotNone(observed_output)
            assert observed_output is not None
            self.assertNotEqual(observed_output, docs)
            self.assertFalse(observed_output.exists())
            self.assertEqual({path.name for path in docs.iterdir()}, {"index.html"})
            run_git.assert_not_called()

    def test_default_build_targets_docs_without_running_git(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            docs = root / "docs"
            with mock.patch.object(
                pages.publisher,
                "publish_static_pack",
                return_value=LATEST,
            ) as publish, mock.patch.object(pages, "_run_git") as run_git:
                result = pages.publish_to_pages(
                    root / "lesson.json",
                    root / "generated",
                    docs,
                    repository_root=root,
                )

            self.assertEqual(result, LATEST)
            publish.assert_called_once_with(
                root / "lesson.json",
                root / "generated",
                docs,
            )
            run_git.assert_not_called()

    def test_push_flag_commits_only_docs_then_pushes_without_real_git(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            docs = root / "docs"
            docs.mkdir()
            git_results = [
                SimpleNamespace(stdout="?? docs/latest.json\n"),
                SimpleNamespace(stdout=""),
                SimpleNamespace(stdout=""),
                SimpleNamespace(stdout=""),
            ]
            with mock.patch.object(
                pages.publisher,
                "publish_static_pack",
                return_value=LATEST,
            ), mock.patch.object(
                pages,
                "_run_git",
                side_effect=git_results,
            ) as run_git:
                pages.publish_to_pages(
                    root / "lesson.json",
                    root / "generated",
                    docs,
                    repository_root=root,
                    push=True,
                )

            self.assertEqual(
                run_git.call_args_list,
                [
                    mock.call(
                        root,
                        "status",
                        "--porcelain",
                        "--",
                        "docs",
                        capture_output=True,
                    ),
                    mock.call(root, "add", "--", "docs"),
                    mock.call(
                        root,
                        "commit",
                        "-m",
                        "Publish Thai Trainer day-001 r1",
                        "--",
                        "docs",
                    ),
                    mock.call(root, "push", "origin", "HEAD"),
                ],
            )


if __name__ == "__main__":
    unittest.main()
