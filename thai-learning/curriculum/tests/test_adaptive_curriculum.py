from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5


MODULE_PATH = Path(__file__).resolve().parents[1] / "adaptive_curriculum.py"
SPEC = importlib.util.spec_from_file_location("thai_adaptive_curriculum", MODULE_PATH)
assert SPEC and SPEC.loader
curriculum = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(curriculum)

LESSONS_DIRECTORY = Path(__file__).resolve().parents[2] / "days"


class AdaptiveCurriculumTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lessons = curriculum.load_approved_lessons(LESSONS_DIRECTORY)
        self.catalog = curriculum.build_catalog(self.lessons)
        self.now = curriculum.parse_datetime("2026-09-06T05:00:00Z")

    def progress(self, events: list[dict] | None = None) -> dict:
        return {
            "schema_version": 1,
            "timezone": "Asia/Bangkok",
            "updated_at": curriculum.isoformat(self.now),
            "events": events or [],
        }

    def event(self, item: dict, rating: str, reviewed_at: datetime, event_id: str) -> dict:
        return {
            "id": str(uuid5(NAMESPACE_URL, event_id)),
            "phrase": deepcopy(item["phrase"]),
            "rating": rating,
            "reviewed_at": curriculum.isoformat(reviewed_at),
        }

    def written_draft(self, day: int) -> dict:
        sentences = deepcopy(self.lessons[0]["sentences"])
        for index, sentence in enumerate(sentences, start=1):
            sentence["id"] = f"d{day:03d}-s{index:02d}"
            sentence["review_status"] = "pending"
        return {
            "schema_version": 1,
            "draft_type": "written_only",
            "lesson_id": f"day-{day:03d}",
            "revision": 1,
            "day": day,
            "week": 1,
            "theme": "Fixture",
            "status": "pending_review",
            "provisional": False,
            "adaptation": {
                "progress_export_used": False,
                "note": "No explicit learner feedback was available.",
            },
            "sentences": sentences,
            "mini_dialogue": [
                {
                    "id": f"d{day:03d}-dialogue-01",
                    "speaker": "learner",
                    "prompt_he": "אפשר לעזור לי?",
                    "thai": "ช่วยผมหน่อยได้ไหมครับ",
                    "review_status": "pending",
                },
                {
                    "id": f"d{day:03d}-dialogue-02",
                    "speaker": "partner",
                    "prompt_he": "כן, בשמחה.",
                    "thai": "ได้ครับ ยินดีครับ",
                    "review_status": "pending",
                },
            ],
            "approval_checklist": [
                {"sentence_id": f"d{day:03d}-s{index:02d}", "decision": "pending"}
                for index in range(1, 21)
            ],
        }

    def test_easy_ladder_again_reset_and_revision_isolation(self) -> None:
        item = self.catalog[0]
        first_at = self.now - timedelta(days=5)
        first = self.event(item, "easy", first_at, "one")
        events = curriculum.validate_progress(self.progress([first]))
        state = curriculum.progress_for(item["phrase"], events)
        assert state is not None
        self.assertEqual(state.easy_streak, 1)
        self.assertEqual(
            state.next_review_at,
            curriculum._start_of_bangkok_day(first_at, 1),
        )

        second_at = state.next_review_at + timedelta(minutes=1)
        second = self.event(item, "easy", second_at, "two")
        again_at = curriculum._start_of_bangkok_day(second_at, 3)
        again = self.event(item, "again", again_at, "three")
        events = curriculum.validate_progress(self.progress([first, second, again]))
        state = curriculum.progress_for(item["phrase"], events)
        assert state is not None
        self.assertEqual(state.easy_streak, 0)
        self.assertEqual(state.again_count, 1)
        self.assertEqual(state.next_review_at, again_at + timedelta(minutes=10))

        revised = deepcopy(item["phrase"])
        revised["revision"] += 1
        revised["content_sha256"] = "b" * 64
        self.assertIsNone(curriculum.progress_for(revised, events))

    def test_due_reviews_precede_new_and_three_day_forecast_is_pure(self) -> None:
        due = self.catalog[22]
        unseen = self.catalog[0]
        progress = self.progress(
            [self.event(due, "again", self.now - timedelta(days=1), "due")]
        )
        before = deepcopy(progress)
        plan = curriculum.three_day_plan(
            self.lessons,
            progress,
            starting_at=self.now,
            daily_limit=2,
        )

        self.assertEqual(plan["days"][0]["items"][0]["phrase"], due["phrase"])
        self.assertEqual(plan["days"][0]["items"][0]["kind"], "review")
        self.assertEqual(plan["days"][0]["items"][1]["phrase"], unseen["phrase"])
        self.assertEqual(progress, before, "Forecasting must never mutate real progress")
        self.assertEqual(len(plan["days"]), 3)

    def test_weekly_summary_is_derived_from_events_and_backlog(self) -> None:
        first, second = self.catalog[0], self.catalog[20]
        events = [
            self.event(first, "easy", self.now - timedelta(days=2), "one"),
            self.event(first, "again", self.now - timedelta(days=1), "two"),
            self.event(second, "easy", self.now, "three"),
        ]
        summary = curriculum.weekly_summary(
            self.lessons,
            self.progress(events),
            at=self.now,
        )
        self.assertEqual(summary["review_count"], 3)
        self.assertEqual(summary["easy_count"], 2)
        self.assertEqual(summary["again_count"], 1)
        self.assertEqual(summary["unique_phrase_count"], 2)
        self.assertEqual(summary["practice_day_count"], 3)
        self.assertAlmostEqual(summary["easy_rate"], 2 / 3)
        self.assertEqual(summary["new_phrase_count"], len(self.catalog) - 2)
        self.assertGreaterEqual(summary["due_review_count"], 1)

    def test_invalid_progress_fails_closed(self) -> None:
        item = self.catalog[0]
        invalid = self.progress([self.event(item, "hard", self.now, "one")])
        with self.assertRaisesRegex(curriculum.CurriculumError, "easy or again"):
            curriculum.three_day_plan(
                self.lessons,
                invalid,
                starting_at=self.now,
            )

    def test_offline_hash_matches_immutable_approval_contract(self) -> None:
        expected = {
            "day-001": "2ee17250cd9ca59e8218e62fcb1b8c6b3e80aed406aa7ddfe58a83100df1138c",
            "day-002": "c4ca956c55e0deea37a0cb889ca222a1e76ede9fdf11cef8b6ad8a0b6c21ce7a",
            "day-003": "8c4d57d06d4fbf4f9b24b808e3258304f973fda7c7a48b86214e6f087741df65",
            "day-004": "8ebc79bb8e7082073ff2760e1f490f78f7fa79f9db1f54cfe61f72ed4d5d6b30",
            "day-005": "562c3573786628a4812ff5bd595c82e3df6dfa0ce80bdb31fb20bbb024f8f4ab",
        }
        self.assertEqual(
            {lesson["lesson_id"]: curriculum.content_sha256(lesson) for lesson in self.lessons},
            expected,
        )

    def test_draft_horizon_keeps_earliest_pending_and_fills_three_slots(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            drafts = Path(temporary)
            first_unpublished_day = max(lesson["day"] for lesson in self.lessons) + 1
            existing = self.written_draft(first_unpublished_day)
            (drafts / f"day-{first_unpublished_day:03d}.json").write_text(
                json.dumps(existing), encoding="utf-8"
            )
            horizon = curriculum.draft_horizon(self.lessons, drafts)

        self.assertEqual(horizon["earliest_unresolved_day"], first_unpublished_day)
        self.assertEqual(
            [slot["day"] for slot in horizon["slots"]],
            [first_unpublished_day, first_unpublished_day + 1, first_unpublished_day + 2],
        )
        self.assertEqual(horizon["slots"][0]["status"], "pending_review")
        self.assertFalse(horizon["slots"][0]["provisional"])
        self.assertTrue(horizon["slots"][1]["provisional"])

    def test_written_draft_rejects_publishable_audio_fields(self) -> None:
        draft = self.written_draft(3)
        draft["voices"] = {"provider": "forbidden-in-written-draft"}
        with self.assertRaisesRegex(curriculum.CurriculumError, "audio fields"):
            curriculum.validate_written_draft(draft)

    def test_written_draft_requires_ordered_mini_dialogue(self) -> None:
        draft = self.written_draft(4)
        draft["mini_dialogue"] = []
        with self.assertRaisesRegex(curriculum.CurriculumError, "mini-dialogue"):
            curriculum.validate_written_draft(draft)

        draft = self.written_draft(4)
        draft["mini_dialogue"][1]["id"] = "d004-dialogue-03"
        with self.assertRaisesRegex(curriculum.CurriculumError, "complete and ordered"):
            curriculum.validate_written_draft(draft)

    def test_written_draft_rejects_unsafe_spoken_hebrew(self) -> None:
        for invalid in ("את/ה מוכן?", "אני צריך קיו-אר.", "Rabbit בבקשה"):
            with self.subTest(invalid=invalid):
                draft = self.written_draft(4)
                draft["sentences"][0]["prompt_he"] = invalid
                with self.assertRaisesRegex(
                    curriculum.CurriculumError,
                    "slash, dash, or Latin letters",
                ):
                    curriculum.validate_written_draft(draft)


if __name__ == "__main__":
    unittest.main()
