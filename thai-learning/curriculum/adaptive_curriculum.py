#!/usr/bin/env python3
"""Build Thai Echo review plans and summaries from explicit local feedback.

This module is intentionally offline. It reads approved lesson JSON and an optional
learner-exported progress file; it has no speech, credential, network, publishing,
or Git capability.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from collections import defaultdict
from copy import deepcopy
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, NamedTuple
from uuid import UUID
from zoneinfo import ZoneInfo


BANGKOK = ZoneInfo("Asia/Bangkok")
INTERVALS_DAYS = (1, 3, 7, 14, 30)
AGAIN_DELAY = timedelta(minutes=10)
DEFAULT_DAILY_LIMIT = 6
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
SPOKEN_HEBREW_FORBIDDEN_PUNCTUATION = set("/\\-‐‑‒–—―−")


class CurriculumError(RuntimeError):
    """Raised when local curriculum input cannot be trusted."""


def _canonical_number(value: Any, field: str) -> str:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CurriculumError(f"{field} must be a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise CurriculumError(f"{field} must be a finite number")
    return format(number, ".15g")


def _canonical_audio_program(audio_program: dict[str, Any]) -> dict[str, Any]:
    normalized = deepcopy(audio_program)
    if "pitch_semitones" in normalized:
        normalized["pitch_semitones"] = _canonical_number(
            normalized["pitch_semitones"], "audio_program.pitch_semitones"
        )
    tracks = normalized.get("tracks")
    if not isinstance(tracks, list) or not tracks:
        raise CurriculumError("audio_program.tracks must be a non-empty list")
    for track_index, track in enumerate(tracks):
        if not isinstance(track, dict):
            raise CurriculumError("Every audio track must be an object")
        if "thai_speaking_rates" in track:
            rates = track["thai_speaking_rates"]
            if not isinstance(rates, list):
                raise CurriculumError("thai_speaking_rates must be an array")
            track["thai_speaking_rates"] = [
                _canonical_number(
                    rate,
                    f"audio_program.tracks[{track_index}].thai_speaking_rates[{rate_index}]",
                )
                for rate_index, rate in enumerate(rates)
            ]
        if "hebrew_speaking_rate" in track:
            track["hebrew_speaking_rate"] = _canonical_number(
                track["hebrew_speaking_rate"],
                f"audio_program.tracks[{track_index}].hebrew_speaking_rate",
            )
    variations = normalized.get("practice_variations")
    if variations is not None:
        if not isinstance(variations, dict):
            raise CurriculumError("audio_program.practice_variations must be an object")
        for field in ("hebrew_speaking_rate", "thai_speaking_rate"):
            if field in variations:
                variations[field] = _canonical_number(
                    variations[field], f"audio_program.practice_variations.{field}"
                )
    return normalized


def canonical_content(lesson: dict[str, Any]) -> dict[str, Any]:
    sentences = lesson.get("sentences")
    voices = lesson.get("voices")
    audio_program = lesson.get("audio_program")
    if not isinstance(sentences, list) or len(sentences) != 20:
        raise CurriculumError("An approved lesson must contain exactly 20 sentences")
    if not isinstance(voices, dict) or not isinstance(audio_program, dict):
        raise CurriculumError("Approved lesson voices and audio_program must be objects")
    variations_enabled = audio_program.get("practice_variations") is not None
    ordered: list[dict[str, Any]] = []
    seen: set[str] = set()
    for sentence in sentences:
        if not isinstance(sentence, dict):
            raise CurriculumError("Every approved sentence must be an object")
        sentence_id = sentence.get("id")
        prompt_he = sentence.get("prompt_he")
        thai = sentence.get("thai")
        if not all(
            isinstance(value, str) and value.strip()
            for value in (sentence_id, prompt_he, thai)
        ):
            raise CurriculumError("Approved sentences need id, prompt_he, and thai")
        if sentence_id in seen:
            raise CurriculumError(f"Duplicate sentence id: {sentence_id}")
        seen.add(sentence_id)
        canonical_sentence: dict[str, Any] = {
            "id": sentence_id,
            "prompt_he": prompt_he,
            "thai": thai,
        }
        if variations_enabled:
            variation = sentence.get("variation")
            if not isinstance(variation, dict) or not all(
                isinstance(variation.get(field), str) and variation[field].strip()
                for field in ("prompt_he", "thai")
            ):
                raise CurriculumError(f"Approved variation is invalid for {sentence_id}")
            canonical_sentence["variation"] = {
                "prompt_he": variation["prompt_he"],
                "thai": variation["thai"],
            }
        ordered.append(canonical_sentence)
    canonical_voices = deepcopy(voices)
    if voices.get("provider") == "google_cloud_tts" and "thai" not in canonical_voices:
        canonical_voices["thai"] = {
            "language_code": "th-TH",
            "name": "th-TH-Chirp3-HD-Erinome",
        }
    return {
        "schema_version": lesson.get("schema_version"),
        "lesson_id": lesson.get("lesson_id"),
        "revision": lesson.get("revision"),
        "voices": canonical_voices,
        "audio_program": _canonical_audio_program(audio_program),
        "sentences": ordered,
    }


def content_sha256(lesson: dict[str, Any]) -> str:
    encoded = json.dumps(
        canonical_content(lesson),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def validate_lesson_for_approval(lesson: dict[str, Any]) -> str:
    digest = content_sha256(lesson)
    if lesson.get("status") != "approved" or any(
        sentence.get("review_status") != "approved" for sentence in lesson["sentences"]
    ):
        raise CurriculumError("Lesson text is not fully approved")
    return digest


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise CurriculumError(f"Cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise CurriculumError(f"Expected a JSON object: {path}")
    return value


def parse_datetime(value: str) -> datetime:
    if not isinstance(value, str) or not value.strip():
        raise CurriculumError("reviewed_at must be an ISO-8601 timestamp")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise CurriculumError(f"Invalid reviewed_at timestamp: {value}") from error
    if parsed.tzinfo is None:
        raise CurriculumError("reviewed_at must include a timezone")
    return parsed


def isoformat(value: datetime) -> str:
    rendered = value.astimezone(timezone.utc).isoformat(timespec="seconds")
    return rendered.replace("+00:00", "Z")


def phrase_identity(lesson: dict[str, Any], sentence_id: str) -> dict[str, Any]:
    return {
        "lesson_id": lesson["lesson_id"],
        "revision": lesson["revision"],
        "content_sha256": content_sha256(lesson),
        "sentence_id": sentence_id,
    }


def phrase_token(phrase: dict[str, Any]) -> tuple[str, int, str, str]:
    lesson_id = phrase.get("lesson_id")
    revision = phrase.get("revision")
    digest = phrase.get("content_sha256")
    sentence_id = phrase.get("sentence_id")
    if (
        not isinstance(lesson_id, str)
        or not lesson_id
        or type(revision) is not int
        or revision <= 0
        or not isinstance(digest, str)
        or not SHA256_PATTERN.fullmatch(digest)
        or not isinstance(sentence_id, str)
        or not sentence_id
    ):
        raise CurriculumError("Progress contains an invalid phrase identity")
    return lesson_id, revision, digest, sentence_id


def validate_progress(progress: dict[str, Any]) -> list[dict[str, Any]]:
    if progress.get("schema_version") != 1:
        raise CurriculumError("Progress schema_version must be 1")
    if progress.get("timezone") != "Asia/Bangkok":
        raise CurriculumError("Progress timezone must be Asia/Bangkok")
    events = progress.get("events")
    if not isinstance(events, list):
        raise CurriculumError("Progress events must be a list")
    seen_ids: set[str] = set()
    validated: list[dict[str, Any]] = []
    for event in events:
        if not isinstance(event, dict):
            raise CurriculumError("Every progress event must be an object")
        event_id = event.get("id")
        rating = event.get("rating")
        phrase = event.get("phrase")
        if not isinstance(event_id, str) or not event_id or event_id in seen_ids:
            raise CurriculumError("Progress event IDs must be non-empty and unique")
        try:
            UUID(event_id)
        except ValueError as error:
            raise CurriculumError("Progress event IDs must be UUIDs") from error
        if rating not in {"easy", "again"}:
            raise CurriculumError("Progress rating must be easy or again")
        if not isinstance(phrase, dict):
            raise CurriculumError("Progress event phrase must be an object")
        phrase_token(phrase)
        reviewed_at = parse_datetime(event.get("reviewed_at"))
        seen_ids.add(event_id)
        normalized = deepcopy(event)
        normalized["_reviewed_at"] = reviewed_at
        validated.append(normalized)
    return sorted(validated, key=lambda item: (item["_reviewed_at"], item["id"]))


def empty_progress(at: datetime | None = None) -> dict[str, Any]:
    at = at or datetime.now(timezone.utc)
    return {
        "schema_version": 1,
        "timezone": "Asia/Bangkok",
        "updated_at": isoformat(at),
        "events": [],
    }


def load_approved_lessons(directory: Path) -> list[dict[str, Any]]:
    lessons: list[dict[str, Any]] = []
    for path in sorted(Path(directory).glob("day-*.json")):
        lesson = _load_json(path)
        sentences = lesson.get("sentences")
        if (
            lesson.get("status") != "approved"
            or not isinstance(sentences, list)
            or any(
                not isinstance(sentence, dict)
                or sentence.get("review_status") != "approved"
                for sentence in sentences
            )
        ):
            continue
        try:
            validate_lesson_for_approval(lesson)
        except CurriculumError as error:
            raise CurriculumError(f"Approved lesson {path} is invalid: {error}") from error
        lessons.append(lesson)
    return sorted(lessons, key=lambda item: (item["day"], item["lesson_id"]))


def build_catalog(lessons: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    catalog: list[dict[str, Any]] = []
    seen: set[tuple[str, int, str, str]] = set()
    for lesson in lessons:
        digest = content_sha256(lesson)
        for sentence in lesson["sentences"]:
            phrase = {
                "lesson_id": lesson["lesson_id"],
                "revision": lesson["revision"],
                "content_sha256": digest,
                "sentence_id": sentence["id"],
            }
            token = phrase_token(phrase)
            if token in seen:
                continue
            seen.add(token)
            catalog.append(
                {
                    "phrase": phrase,
                    "lesson_day": lesson["day"],
                    "lesson_theme": lesson["theme"],
                    "sentence": deepcopy(sentence),
                }
            )
    return catalog


class ProgressState(NamedTuple):
    review_count: int
    easy_streak: int
    again_count: int
    last_rating: str
    last_reviewed_at: datetime
    next_review_at: datetime


def _start_of_bangkok_day(value: datetime, adding_days: int = 0) -> datetime:
    local_day = value.astimezone(BANGKOK).date() + timedelta(days=adding_days)
    return datetime.combine(local_day, time.min, tzinfo=BANGKOK)


def progress_for(
    phrase: dict[str, Any],
    events: Iterable[dict[str, Any]],
) -> ProgressState | None:
    token = phrase_token(phrase)
    matching = [event for event in events if phrase_token(event["phrase"]) == token]
    if not matching:
        return None
    matching.sort(key=lambda item: (item["_reviewed_at"], item["id"]))
    easy_streak = 0
    again_count = 0
    next_review_at = matching[0]["_reviewed_at"]
    for event in matching:
        reviewed_at = event["_reviewed_at"]
        if event["rating"] == "again":
            easy_streak = 0
            again_count += 1
            next_review_at = reviewed_at + AGAIN_DELAY
        else:
            interval = INTERVALS_DAYS[min(easy_streak, len(INTERVALS_DAYS) - 1)]
            next_review_at = _start_of_bangkok_day(reviewed_at, interval)
            easy_streak = min(easy_streak + 1, len(INTERVALS_DAYS))
    latest = matching[-1]
    return ProgressState(
        review_count=len(matching),
        easy_streak=easy_streak,
        again_count=again_count,
        last_rating=latest["rating"],
        last_reviewed_at=latest["_reviewed_at"],
        next_review_at=next_review_at,
    )


def scheduled_entries(
    catalog: list[dict[str, Any]],
    events: list[dict[str, Any]],
    at: datetime,
) -> list[tuple[dict[str, Any], str, ProgressState | None]]:
    entries = [(item, progress_for(item["phrase"], events)) for item in catalog]
    due = [(item, "review", state) for item, state in entries if state and state.next_review_at <= at]
    due.sort(
        key=lambda row: (
            0 if row[2] and row[2].last_rating == "again" else 1,
            row[2].next_review_at if row[2] else datetime.max.replace(tzinfo=timezone.utc),
            row[0]["lesson_day"],
            row[0]["sentence"]["id"],
        )
    )
    unseen = [(item, "new", None) for item, state in entries if state is None]
    unseen.sort(key=lambda row: (row[0]["lesson_day"], row[0]["sentence"]["id"]))
    return due + unseen


def three_day_plan(
    lessons: list[dict[str, Any]],
    progress: dict[str, Any],
    *,
    starting_at: datetime,
    daily_limit: int = DEFAULT_DAILY_LIMIT,
) -> dict[str, Any]:
    if daily_limit < 0:
        raise CurriculumError("daily_limit must not be negative")
    catalog = build_catalog(lessons)
    source_events = validate_progress(progress)
    simulated_events = deepcopy(source_events)
    days: list[dict[str, Any]] = []
    for offset in range(3):
        practice_at = (
            starting_at
            if offset == 0
            else _start_of_bangkok_day(starting_at, offset) + timedelta(hours=12)
        )
        selected = scheduled_entries(catalog, simulated_events, practice_at)[:daily_limit]
        items: list[dict[str, Any]] = []
        for index, (item, kind, _state) in enumerate(selected):
            sentence = item["sentence"]
            items.append(
                {
                    "kind": kind,
                    "phrase": deepcopy(item["phrase"]),
                    "lesson_day": item["lesson_day"],
                    "lesson_theme": item["lesson_theme"],
                    "prompt_he": sentence["prompt_he"],
                    "thai": sentence["thai"],
                    "romanization": sentence["romanization"],
                }
            )
            simulated_events.append(
                {
                    "id": f"forecast-{offset}-{index}",
                    "phrase": deepcopy(item["phrase"]),
                    "rating": "easy",
                    "reviewed_at": isoformat(practice_at + timedelta(seconds=index)),
                    "_reviewed_at": practice_at + timedelta(seconds=index),
                }
            )
        days.append(
            {
                "date": _start_of_bangkok_day(practice_at).date().isoformat(),
                "review_count": sum(item["kind"] == "review" for item in items),
                "new_count": sum(item["kind"] == "new" for item in items),
                "items": items,
            }
        )
    return {
        "schema_version": 1,
        "timezone": "Asia/Bangkok",
        "generated_at": isoformat(starting_at),
        "source_event_count": len(source_events),
        "forecast_assumption": "Each planned item is simulated as Easy; real progress is unchanged.",
        "days": days,
    }


def weekly_summary(
    lessons: list[dict[str, Any]],
    progress: dict[str, Any],
    *,
    at: datetime,
) -> dict[str, Any]:
    catalog = build_catalog(lessons)
    events = validate_progress(progress)
    local = at.astimezone(BANGKOK)
    week_start_date = local.date() - timedelta(days=local.weekday())
    week_start = datetime.combine(week_start_date, time.min, tzinfo=BANGKOK)
    week_end = week_start + timedelta(days=7)
    weekly_events = [
        event for event in events if week_start <= event["_reviewed_at"].astimezone(BANGKOK) < week_end
    ]
    easy_count = sum(event["rating"] == "easy" for event in weekly_events)
    again_count = sum(event["rating"] == "again" for event in weekly_events)
    reviewed_tokens = {phrase_token(event["phrase"]) for event in events}
    due_count = sum(
        1
        for item in catalog
        if (state := progress_for(item["phrase"], events)) is not None
        and state.next_review_at <= at
    )
    return {
        "schema_version": 1,
        "timezone": "Asia/Bangkok",
        "generated_at": isoformat(at),
        "week_start": week_start.date().isoformat(),
        "week_end_exclusive": week_end.date().isoformat(),
        "review_count": len(weekly_events),
        "easy_count": easy_count,
        "again_count": again_count,
        "unique_phrase_count": len({phrase_token(event["phrase"]) for event in weekly_events}),
        "practice_day_count": len(
            {event["_reviewed_at"].astimezone(BANGKOK).date() for event in weekly_events}
        ),
        "easy_rate": easy_count / len(weekly_events) if weekly_events else 0.0,
        "due_review_count": due_count,
        "new_phrase_count": sum(
            phrase_token(item["phrase"]) not in reviewed_tokens for item in catalog
        ),
    }


def draft_horizon(
    approved_lessons: list[dict[str, Any]],
    drafts_directory: Path,
    *,
    count: int = 3,
) -> dict[str, Any]:
    if count <= 0:
        raise CurriculumError("Draft horizon count must be positive")
    approved_days = {lesson["day"] for lesson in approved_lessons}
    existing: dict[int, dict[str, Any]] = {}
    for path in sorted(Path(drafts_directory).glob("day-*.json")):
        draft = _load_json(path)
        validate_written_draft(draft)
        day = draft.get("day")
        if (
            type(day) is int
            and day > 0
            and day not in approved_days
            and draft.get("status") == "pending_review"
        ):
            existing[day] = draft
    next_day = max(approved_days | {0}) + 1
    candidate_days = sorted(existing)
    while len(candidate_days) < count:
        if next_day not in approved_days and next_day not in candidate_days:
            candidate_days.append(next_day)
        next_day += 1
    candidate_days = sorted(candidate_days)[:count]
    return {
        "schema_version": 1,
        "horizon_size": count,
        "earliest_unresolved_day": candidate_days[0],
        "slots": [
            {
                "position": index + 1,
                "day": day,
                "lesson_id": f"day-{day:03d}",
                "status": "pending_review" if day in existing else "needs_draft",
                "provisional": index > 0,
            }
            for index, day in enumerate(candidate_days)
        ],
    }


def validate_written_draft(draft: dict[str, Any]) -> None:
    prohibited = {"voices", "audio_program"}.intersection(draft)
    if prohibited:
        raise CurriculumError(
            "Written drafts must not contain publishable audio fields: "
            + ", ".join(sorted(prohibited))
        )
    day = draft.get("day")
    if (
        draft.get("schema_version") != 1
        or draft.get("draft_type") != "written_only"
        or type(day) is not int
        or day <= 0
        or draft.get("lesson_id") != f"day-{day:03d}"
        or type(draft.get("revision")) is not int
        or draft["revision"] <= 0
        or draft.get("status") != "pending_review"
        or type(draft.get("provisional")) is not bool
    ):
        raise CurriculumError("Written draft identity or status is invalid")
    adaptation = draft.get("adaptation")
    if (
        not isinstance(adaptation, dict)
        or type(adaptation.get("progress_export_used")) is not bool
        or not isinstance(adaptation.get("note"), str)
        or not adaptation["note"].strip()
    ):
        raise CurriculumError("Written draft adaptation metadata is invalid")
    sentences = draft.get("sentences")
    if not isinstance(sentences, list) or len(sentences) != 20:
        raise CurriculumError("Written draft must contain exactly 20 sentences")
    expected_ids = [f"d{day:03d}-s{index:02d}" for index in range(1, 21)]
    actual_ids: list[str] = []
    categories: defaultdict[str, int] = defaultdict(int)
    required_text = (
        "category",
        "prompt_he",
        "thai",
        "romanization",
        "literal_he",
        "context_he",
        "pattern",
    )

    def validate_spoken_hebrew(value: str) -> None:
        if any(character in SPOKEN_HEBREW_FORBIDDEN_PUNCTUATION for character in value) or any(
            character.isascii() and character.isalpha() for character in value
        ):
            raise CurriculumError(
                "Written spoken Hebrew must not contain slash, dash, or Latin letters"
            )

    for sentence in sentences:
        if not isinstance(sentence, dict):
            raise CurriculumError("Written draft sentence must be an object")
        if sentence.get("review_status") != "pending" or any(
            not isinstance(sentence.get(field), str) or not sentence[field].strip()
            for field in required_text
        ):
            raise CurriculumError("Written draft sentence text or status is invalid")
        variation = sentence.get("variation")
        if not isinstance(variation, dict) or any(
            not isinstance(variation.get(field), str) or not variation[field].strip()
            for field in ("prompt_he", "thai")
        ):
            raise CurriculumError("Written draft variation is invalid")
        validate_spoken_hebrew(sentence["prompt_he"])
        validate_spoken_hebrew(variation["prompt_he"])
        actual_ids.append(sentence.get("id"))
        categories[sentence["category"]] += 1
    if actual_ids != expected_ids:
        raise CurriculumError("Written draft sentence IDs must be complete and ordered")
    if any(count > 4 for count in categories.values()):
        raise CurriculumError("Written draft may use at most four sentences per category")
    dialogue = draft.get("mini_dialogue")
    if not isinstance(dialogue, list) or not 2 <= len(dialogue) <= 6:
        raise CurriculumError("Written draft needs a two-to-six-line mini-dialogue")
    expected_dialogue_ids = [
        f"d{day:03d}-dialogue-{index:02d}"
        for index in range(1, len(dialogue) + 1)
    ]
    actual_dialogue_ids: list[str] = []
    for line in dialogue:
        if (
            not isinstance(line, dict)
            or line.get("review_status") != "pending"
            or any(
                not isinstance(line.get(field), str) or not line[field].strip()
                for field in ("id", "speaker", "prompt_he", "thai")
            )
        ):
            raise CurriculumError("Written draft mini-dialogue line is invalid")
        validate_spoken_hebrew(line["prompt_he"])
        actual_dialogue_ids.append(line["id"])
    if actual_dialogue_ids != expected_dialogue_ids:
        raise CurriculumError("Written draft mini-dialogue IDs must be complete and ordered")
    checklist = draft.get("approval_checklist")
    if not isinstance(checklist, list) or [
        item.get("sentence_id") if isinstance(item, dict) else None for item in checklist
    ] != expected_ids or any(
        not isinstance(item, dict) or item.get("decision") != "pending"
        for item in checklist
    ):
        raise CurriculumError("Written draft approval checklist must cover every sentence")


def _parse_at(value: str | None) -> datetime:
    return parse_datetime(value) if value else datetime.now(timezone.utc)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lessons-dir", type=Path, required=True)
    parser.add_argument("--progress", type=Path)
    parser.add_argument("--drafts-dir", type=Path)
    parser.add_argument("--at", help="ISO-8601 timestamp; defaults to now")
    parser.add_argument("--daily-limit", type=int, default=DEFAULT_DAILY_LIMIT)
    parser.add_argument("--output", type=Path, help="Optional JSON output; stdout is default")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        at = _parse_at(args.at)
        lessons = load_approved_lessons(args.lessons_dir)
        progress = _load_json(args.progress) if args.progress else empty_progress(at)
        result = {
            "schema_version": 1,
            "three_day_plan": three_day_plan(
                lessons,
                progress,
                starting_at=at,
                daily_limit=args.daily_limit,
            ),
            "weekly_summary": weekly_summary(lessons, progress, at=at),
            "draft_horizon": draft_horizon(
                lessons,
                args.drafts_dir or args.lessons_dir.parent / "drafts",
            ),
        }
        rendered = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8")
        else:
            print(rendered, end="")
        return 0
    except CurriculumError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
