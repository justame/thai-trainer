#!/usr/bin/env python3
"""Build a non-billable sentence-audio bundle from the approved Google cache.

The configurable iOS player needs individual Hebrew and Thai clips so it can
insert user-selected pauses at runtime. This command never creates a provider,
reads credentials, or makes a network request. It only validates and copies
already-authorized LINEAR16 WAV cache entries.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

import generate_audio as audio


class PracticeBundleError(RuntimeError):
    pass


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _request_hash(lesson: dict, spoken_pair: dict, language: str) -> str:
    voice = audio._google_voice_for(lesson["voices"], language)
    text_key = "prompt_he" if language == "hebrew" else "thai"
    request = audio._google_speech_request(
        spoken_pair[text_key],
        voice,
        1.0,
    )
    return audio.request_sha256(request)


def build(lesson_path: Path, output_directory: Path) -> dict:
    lesson = audio.load_json(lesson_path)
    content_sha256 = audio.validate_lesson_for_approval(lesson)
    if lesson.get("status") != "approved" or not all(
        sentence.get("review_status") == "approved"
        for sentence in lesson.get("sentences", [])
    ):
        raise PracticeBundleError("Practice audio requires an approved lesson revision")
    if lesson.get("voices", {}).get("provider") != "google_cloud_tts":
        raise PracticeBundleError("Practice audio currently requires the approved Google cache")

    generated_root = lesson_path.parents[1] / "audio" / "generated"
    cache_root = generated_root.parent / ".google-segment-cache-v1"
    output_parent = output_directory.parent
    output_parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(
        prefix=f".{output_directory.name}.staging-",
        dir=output_parent,
    ) as temporary:
        staging = Path(temporary)
        entries = []
        def copy_pair(sentence_id: str, spoken_pair: dict, name: str) -> dict:
            clips = {}
            for language, suffix in (("hebrew", "he"), ("thai", "th")):
                segment_sha256 = _request_hash(lesson, spoken_pair, language)
                source = cache_root / f"{segment_sha256}.wav"
                if not source.is_file():
                    raise PracticeBundleError(
                        f"Missing authorized {language} cache clip for {sentence_id}: {source}"
                    )
                payload = source.read_bytes()
                audio._linear16_wav_frames(payload)
                filename = f"{sentence_id}-{name}-{suffix}.wav"
                (staging / filename).write_bytes(payload)
                clips[language] = {
                    "file": filename,
                    "bytes": len(payload),
                    "sha256": _sha256(payload),
                    "source_request_sha256": segment_sha256,
                }
            return clips

        for sentence in lesson["sentences"]:
            variation = sentence.get("variation")
            if not isinstance(variation, dict):
                raise PracticeBundleError(
                    f"Approved variation is missing for {sentence['id']}"
                )
            entries.append(
                {
                    "sentence_id": sentence["id"],
                    "core": copy_pair(sentence["id"], sentence, "core"),
                    "variations": [
                        copy_pair(sentence["id"], variation, "variation-1")
                    ],
                }
            )

        manifest = {
            "schema_version": 2,
            "lesson_id": lesson["lesson_id"],
            "revision": lesson["revision"],
            "content_sha256": content_sha256,
            "sample_rate_hertz": audio.GOOGLE_SAMPLE_RATE_HERTZ,
            "sentences": entries,
        }
        (staging / "practice-manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        if output_directory.exists():
            existing = output_directory / "practice-manifest.json"
            if existing.is_file() and existing.read_bytes() == (staging / existing.name).read_bytes():
                for path in staging.iterdir():
                    existing_path = output_directory / path.name
                    if not existing_path.is_file() or existing_path.read_bytes() != path.read_bytes():
                        raise PracticeBundleError(
                            f"Existing practice bundle differs at {existing_path}"
                        )
                return manifest
            raise PracticeBundleError(
                f"Refusing to replace an existing different practice bundle: {output_directory}"
            )

        shutil.copytree(staging, output_directory)
        return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("lesson", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = build(args.lesson.resolve(), args.output.resolve())
    print(
        f"Built {len(manifest['sentences'])} approved core/variation sentence sets at "
        f"{args.output.resolve()} without provider or network access."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
