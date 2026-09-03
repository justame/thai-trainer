#!/usr/bin/env python3
"""Generate approved Thai practice audio with a fail-closed paid-request gate.

Dry-run is the default. The network-capable path is reached only after two immutable
receipts match the current lesson content hash and --execute-paid-request is present.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


OUTPUT_FORMAT = "audio-24khz-48kbitrate-mono-mp3"


class GateError(RuntimeError):
    """Raised before provider construction when authorization is incomplete."""


class OutputCollisionError(RuntimeError):
    """Raised instead of overwriting audio whose request hash does not match."""


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise GateError(f"Expected a JSON object: {path}")
    return value


def canonical_content(lesson: dict[str, Any]) -> dict[str, Any]:
    """Return every value that can affect outbound speech-provider input."""

    sentences = lesson.get("sentences")
    if not isinstance(sentences, list) or len(sentences) != 20:
        raise GateError("A review pack must contain exactly 20 sentences")

    ordered: list[dict[str, str]] = []
    seen: set[str] = set()
    for sentence in sentences:
        if not isinstance(sentence, dict):
            raise GateError("Every sentence must be an object")
        sentence_id = sentence.get("id")
        prompt_he = sentence.get("prompt_he")
        thai = sentence.get("thai")
        if not all(isinstance(value, str) and value.strip() for value in (sentence_id, prompt_he, thai)):
            raise GateError("Every sentence needs non-empty id, prompt_he, and thai")
        if sentence_id in seen:
            raise GateError(f"Duplicate sentence id: {sentence_id}")
        seen.add(sentence_id)
        ordered.append({"id": sentence_id, "prompt_he": prompt_he, "thai": thai})

    voices = lesson.get("voices")
    audio_program = lesson.get("audio_program")
    if not isinstance(voices, dict) or not isinstance(audio_program, dict):
        raise GateError("Lesson voices and audio_program must be objects")

    tracks = audio_program.get("tracks")
    if not isinstance(tracks, list) or not tracks:
        raise GateError("audio_program.tracks must be a non-empty list")
    for track in tracks:
        if not isinstance(track, dict):
            raise GateError("Every track must be an object")
        sequence = track.get("sequence")
        if not isinstance(sequence, list) or not sequence:
            raise GateError("Every track must have a non-empty sentence-id sequence")
        unknown = [item for item in sequence if item not in seen]
        if unknown:
            raise GateError(f"Track contains unapproved/free-form ids: {unknown}")

    return {
        "schema_version": lesson.get("schema_version"),
        "lesson_id": lesson.get("lesson_id"),
        "revision": lesson.get("revision"),
        "voices": voices,
        "audio_program": audio_program,
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
    statuses = [item.get("review_status") for item in lesson["sentences"]]
    if lesson.get("status") != "approved" or any(status != "approved" for status in statuses):
        raise GateError("Lesson text is still pending review")
    return digest


def preflight(
    lesson: dict[str, Any],
    approval: dict[str, Any],
    authorization: dict[str, Any],
) -> str:
    """Validate all gates without reading credentials or constructing a provider."""

    digest = validate_lesson_for_approval(lesson)
    lesson_id = lesson.get("lesson_id")
    revision = lesson.get("revision")
    sentence_ids = [item["id"] for item in canonical_content(lesson)["sentences"]]

    if approval.get("lesson_id") != lesson_id or approval.get("revision") != revision:
        raise GateError("Approval receipt targets a different lesson revision")
    if approval.get("approved_sentence_ids") != sentence_ids:
        raise GateError("Approval receipt does not approve all 20 sentences in order")
    if approval.get("content_sha256") != digest or not approval.get("approved_at"):
        raise GateError("Approval receipt hash or timestamp is missing/stale")

    if authorization.get("lesson_id") != lesson_id or authorization.get("revision") != revision:
        raise GateError("Paid-TTS authorization targets a different lesson revision")
    if authorization.get("provider") != lesson["voices"].get("provider"):
        raise GateError("Paid-TTS authorization targets a different provider")
    if authorization.get("content_sha256") != digest or not authorization.get("authorized_at"):
        raise GateError("Paid-TTS authorization hash or timestamp is missing/stale")
    return digest


def _break(milliseconds: int) -> str:
    if not isinstance(milliseconds, int) or milliseconds < 0 or milliseconds > 15000:
        raise GateError(f"Unsafe break duration: {milliseconds!r}")
    return f'<break time="{milliseconds}ms"/>'


def build_track_ssml(lesson: dict[str, Any], track: dict[str, Any]) -> str:
    sentence_by_id = {item["id"]: item for item in lesson["sentences"]}
    thai_voice = html.escape(lesson["voices"]["thai"], quote=True)
    hebrew_voice = html.escape(lesson["voices"]["hebrew"], quote=True)
    repetitions = track.get("thai_repetitions", 1)
    if not isinstance(repetitions, int) or repetitions < 1 or repetitions > 5:
        raise GateError("thai_repetitions must be between 1 and 5")

    parts = [
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="th-TH">'
    ]
    sequence = track["sequence"]
    for index, sentence_id in enumerate(sequence):
        sentence = sentence_by_id[sentence_id]
        if track.get("hebrew_prompt"):
            prompt = html.escape(sentence["prompt_he"])
            parts.append(f'<voice name="{hebrew_voice}">{prompt}</voice>')
            parts.append(_break(track["recall_pause_ms"]))

        thai = html.escape(sentence["thai"])
        for repetition in range(repetitions):
            parts.append(f'<voice name="{thai_voice}">{thai}</voice>')
            if repetition + 1 < repetitions:
                parts.append(_break(track.get("pause_between_repetitions_ms", 0)))
        if index + 1 < len(sequence):
            parts.append(_break(track.get("pause_between_sentences_ms", 0)))
    parts.append("</speak>")
    return "".join(parts)


def request_sha256(ssml: str) -> str:
    material = f"{OUTPUT_FORMAT}\n{ssml}".encode("utf-8")
    return hashlib.sha256(material).hexdigest()


class AzureSpeechProvider:
    def __init__(self, key: str, region: str) -> None:
        self.key = key
        self.region = region

    def synthesize(self, ssml: str) -> bytes:
        endpoint = f"https://{self.region}.tts.speech.microsoft.com/cognitiveservices/v1"
        request = urllib.request.Request(
            endpoint,
            data=ssml.encode("utf-8"),
            method="POST",
            headers={
                "Ocp-Apim-Subscription-Key": self.key,
                "Content-Type": "application/ssml+xml",
                "X-Microsoft-OutputFormat": OUTPUT_FORMAT,
                "User-Agent": "personalized-thai-learning",
            },
        )
        with urllib.request.urlopen(request, timeout=45) as response:
            payload = response.read()
        if not payload:
            raise RuntimeError("Speech provider returned empty audio")
        return payload


def provider_from_environment() -> AzureSpeechProvider:
    """Read credentials only after preflight has succeeded."""

    key = os.environ.get("AZURE_SPEECH_KEY")
    region = os.environ.get("AZURE_SPEECH_REGION")
    if not key or not region:
        raise RuntimeError(
            "AZURE_SPEECH_KEY and AZURE_SPEECH_REGION are required only for an authorized paid run"
        )
    return AzureSpeechProvider(key=key, region=region)


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def generate_tracks(
    lesson: dict[str, Any],
    approval: dict[str, Any],
    authorization: dict[str, Any],
    output_root: Path,
    provider_factory: Callable[[], Any] = provider_from_environment,
) -> dict[str, Any]:
    """Generate or safely reuse tracks after all authorization gates pass."""

    digest = preflight(lesson, approval, authorization)
    provider = provider_factory()
    lesson_dir = output_root / lesson["lesson_id"] / f"r{lesson['revision']}"
    lesson_dir.mkdir(parents=True, exist_ok=True)

    generated: list[dict[str, Any]] = []
    for track in lesson["audio_program"]["tracks"]:
        track_id = track.get("id")
        if not isinstance(track_id, str) or not track_id:
            raise GateError("Every track needs a non-empty id")
        ssml = build_track_ssml(lesson, track)
        request_hash = request_sha256(ssml)
        audio_path = lesson_dir / f"{track_id}.mp3"
        sidecar_path = lesson_dir / f"{track_id}.request.json"

        if audio_path.exists() or sidecar_path.exists():
            if not (audio_path.is_file() and sidecar_path.is_file()):
                raise OutputCollisionError(f"Incomplete existing output for {track_id}")
            sidecar = load_json(sidecar_path)
            if sidecar.get("request_sha256") != request_hash or audio_path.stat().st_size <= 0:
                raise OutputCollisionError(f"Refusing to overwrite mismatched output for {track_id}")
            generated.append(sidecar)
            continue

        audio = provider.synthesize(ssml)
        audio_path.write_bytes(audio)
        sidecar = {
            "lesson_id": lesson["lesson_id"],
            "revision": lesson["revision"],
            "content_sha256": digest,
            "track_id": track_id,
            "request_sha256": request_hash,
            "file": audio_path.name,
            "bytes": len(audio),
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }
        _write_json(sidecar_path, sidecar)
        generated.append(sidecar)

    manifest = {
        "schema_version": 1,
        "lesson_id": lesson["lesson_id"],
        "revision": lesson["revision"],
        "content_sha256": digest,
        "provider": lesson["voices"]["provider"],
        "voices": lesson["voices"],
        "tracks": generated,
    }
    _write_json(lesson_dir / "audio-manifest.json", manifest)
    return manifest


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lesson", type=Path)
    parser.add_argument("--approval", type=Path)
    parser.add_argument("--authorization", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Validate locally; never contact TTS")
    mode.add_argument(
        "--execute-paid-request",
        action="store_true",
        help="Generate only after matching approval and paid-TTS receipts",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path(__file__).resolve().parent / "generated",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    lesson = load_json(args.lesson)
    digest = content_sha256(lesson)

    if not args.execute_paid_request:
        try:
            validate_lesson_for_approval(lesson)
        except GateError as error:
            print(f"BLOCKED (safe dry run): {error}")
            print(f"Current content SHA-256: {digest}")
            print("No credentials read. No provider constructed. No network request made.")
            return 0
        if not args.approval or not args.authorization:
            print("BLOCKED (safe dry run): immutable approval and paid-TTS receipts are required")
            print(f"Current content SHA-256: {digest}")
            print("No credentials read. No provider constructed. No network request made.")
            return 0
        preflight(lesson, load_json(args.approval), load_json(args.authorization))
        print(f"READY (safe dry run): {lesson['lesson_id']} r{lesson['revision']} {digest}")
        print("No credentials read. No provider constructed. No network request made.")
        return 0

    if not args.approval or not args.authorization:
        raise GateError("Paid execution requires --approval and --authorization receipts")

    manifest = generate_tracks(
        lesson,
        load_json(args.approval),
        load_json(args.authorization),
        args.output_root,
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (GateError, OutputCollisionError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
