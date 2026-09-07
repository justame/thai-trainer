#!/usr/bin/env python3
"""Generate approved Thai practice audio with a fail-closed paid-request gate.

Dry-run is the default. The network-capable path is reached only after two immutable
receipts match the current lesson content hash and --execute-paid-request is present.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import copy
import hashlib
import html
import io
import json
import math
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


OUTPUT_FORMAT = "audio-24khz-48kbitrate-mono-mp3"
GOOGLE_TTS_ENDPOINT = "https://texttospeech.googleapis.com/v1/text:synthesize"
GOOGLE_SYNTHESIS_MAX_BYTES = 5000
GOOGLE_SAMPLE_RATE_HERTZ = 24000
DEFAULT_GOOGLE_THAI_VOICE = {
    "language_code": "th-TH",
    "name": "th-TH-Chirp3-HD-Erinome",
}
GOOGLE_ASSEMBLY = {
    "version": 1,
    "input_encoding": "LINEAR16_WAV",
    "sample_rate_hertz": GOOGLE_SAMPLE_RATE_HERTZ,
    "sample_width_bytes": 2,
    "channels": 1,
    "output_encoding": "MP3",
    "output_bitrate_kbps": 48,
    "tool": "sox",
}


class GateError(RuntimeError):
    """Raised before provider construction when authorization is incomplete."""


class OutputCollisionError(RuntimeError):
    """Raised instead of overwriting audio whose request hash does not match."""


def _validate_spoken_hebrew(value: str, field: str) -> None:
    """Keep TTS cues masculine and phonetic instead of punctuation-dependent."""

    forbidden_punctuation = set("/\\-‐‑‒–—―−")
    has_forbidden_punctuation = any(character in forbidden_punctuation for character in value)
    has_latin_letters = any(character.isascii() and character.isalpha() for character in value)
    if has_forbidden_punctuation or has_latin_letters:
        raise GateError(
            f"{field} spoken Hebrew must use Hebrew words without slash, dash, or Latin letters"
        )


def _canonical_number(value: Any, field: str) -> str:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise GateError(f"{field} must be a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise GateError(f"{field} must be a finite number")
    return format(number, ".15g")


def _canonical_audio_program(audio_program: dict[str, Any]) -> dict[str, Any]:
    """Normalize cross-runtime floating-point fields in a detached hash copy."""

    normalized = copy.deepcopy(audio_program)
    if "pitch_semitones" in normalized:
        normalized["pitch_semitones"] = _canonical_number(
            normalized["pitch_semitones"], "audio_program.pitch_semitones"
        )
    tracks = normalized.get("tracks")
    if isinstance(tracks, list):
        for track_index, track in enumerate(tracks):
            if not isinstance(track, dict):
                continue
            if "thai_speaking_rates" in track:
                rates = track["thai_speaking_rates"]
                if not isinstance(rates, list):
                    raise GateError("thai_speaking_rates must be an array")
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
    practice_variations = normalized.get("practice_variations")
    if practice_variations is not None:
        if not isinstance(practice_variations, dict):
            raise GateError("audio_program.practice_variations must be an object")
        for field in ("hebrew_speaking_rate", "thai_speaking_rate"):
            if field in practice_variations:
                practice_variations[field] = _canonical_number(
                    practice_variations[field],
                    f"audio_program.practice_variations.{field}",
                )
    return normalized


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

    voices = lesson.get("voices")
    audio_program = lesson.get("audio_program")
    if not isinstance(voices, dict) or not isinstance(audio_program, dict):
        raise GateError("Lesson voices and audio_program must be objects")
    practice_variations = audio_program.get("practice_variations")
    if practice_variations is not None and not isinstance(practice_variations, dict):
        raise GateError("audio_program.practice_variations must be an object")

    ordered: list[dict[str, Any]] = []
    seen: set[str] = set()
    for sentence in sentences:
        if not isinstance(sentence, dict):
            raise GateError("Every sentence must be an object")
        sentence_id = sentence.get("id")
        prompt_he = sentence.get("prompt_he")
        thai = sentence.get("thai")
        if not all(isinstance(value, str) and value.strip() for value in (sentence_id, prompt_he, thai)):
            raise GateError("Every sentence needs non-empty id, prompt_he, and thai")
        _validate_spoken_hebrew(prompt_he, f"sentences[{sentence_id}].prompt_he")
        if sentence_id in seen:
            raise GateError(f"Duplicate sentence id: {sentence_id}")
        seen.add(sentence_id)
        canonical_sentence: dict[str, Any] = {
            "id": sentence_id,
            "prompt_he": prompt_he,
            "thai": thai,
        }
        if practice_variations is not None:
            variation = sentence.get("variation")
            if not isinstance(variation, dict):
                raise GateError(
                    f"Spoken variation is missing for sentence {sentence_id}"
                )
            variation_prompt = variation.get("prompt_he")
            variation_thai = variation.get("thai")
            if not all(
                isinstance(value, str) and value.strip()
                for value in (variation_prompt, variation_thai)
            ):
                raise GateError(
                    f"Spoken variation needs non-empty Hebrew and Thai for {sentence_id}"
                )
            _validate_spoken_hebrew(
                variation_prompt,
                f"sentences[{sentence_id}].variation.prompt_he",
            )
            canonical_sentence["variation"] = {
                "prompt_he": variation_prompt,
                "thai": variation_thai,
            }
        ordered.append(canonical_sentence)

    canonical_voices = dict(voices)
    if voices.get("provider") == "google_cloud_tts":
        # Bind an omitted Thai voice to the concrete default in approval hashes.
        # A future default change therefore cannot silently alter paid output.
        canonical_voices["thai"] = _google_voice_for(voices, "thai")

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

    # Validate every outbound descriptor before credentials, subprocesses, or
    # network access become reachable.
    for track in lesson["audio_program"]["tracks"]:
        build_track_request(lesson, track)
    build_google_practice_variation_requests(lesson)

    cost_fields = (
        "max_cost_usd",
        "price_usd_per_character",
        "max_billable_characters",
    )
    supplied_cost_fields = [field for field in cost_fields if field in authorization]
    if supplied_cost_fields:
        if len(supplied_cost_fields) != len(cost_fields):
            raise GateError("Paid-TTS cost authorization is incomplete")
        max_cost = authorization["max_cost_usd"]
        unit_price = authorization["price_usd_per_character"]
        character_cap = authorization["max_billable_characters"]
        if (
            isinstance(max_cost, bool)
            or not isinstance(max_cost, (int, float))
            or not math.isfinite(float(max_cost))
            or float(max_cost) <= 0
            or isinstance(unit_price, bool)
            or not isinstance(unit_price, (int, float))
            or not math.isfinite(float(unit_price))
            or float(unit_price) <= 0
            or isinstance(character_cap, bool)
            or not isinstance(character_cap, int)
            or character_cap <= 0
        ):
            raise GateError("Paid-TTS cost authorization is invalid")
        planned_characters = planned_google_billable_characters(lesson)
        if planned_characters > character_cap:
            raise GateError("Paid-TTS request exceeds the authorized character cap")
        if planned_characters * float(unit_price) > float(max_cost) + 1e-12:
            raise GateError("Paid-TTS request exceeds the authorized dollar cap")
    return digest


def _break_milliseconds(milliseconds: Any) -> int:
    if not isinstance(milliseconds, int) or milliseconds < 0 or milliseconds > 15000:
        raise GateError(f"Unsafe break duration: {milliseconds!r}")
    return milliseconds


def _break(milliseconds: Any) -> str:
    return f'<break time="{_break_milliseconds(milliseconds)}ms"/>'


def _voice_name(
    voices: dict[str, Any],
    language: str,
    *,
    default: str | None = None,
) -> str:
    """Read a current nested voice config while accepting legacy Azure strings."""

    configured = voices.get(language)
    if isinstance(configured, str) and configured.strip():
        return configured
    if isinstance(configured, dict):
        name = configured.get("name")
        if isinstance(name, str) and name.strip():
            return name
    if default:
        return default
    raise GateError(f"voices.{language} must provide a non-empty voice name")


def _speaking_rate(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise GateError(f"{field} must be a number between 0.25 and 2.0")
    rate = float(value)
    if not math.isfinite(rate) or rate < 0.25 or rate > 2.0:
        raise GateError(f"{field} must be a number between 0.25 and 2.0")
    return rate


def _azure_speaking_rate(value: Any, field: str) -> float:
    rate = _speaking_rate(value, field)
    if rate < 0.5:
        raise GateError(f"{field} must be between 0.5 and 2.0 for azure_speech")
    return rate


def _prosody(text: str, rate: float) -> str:
    return f'<prosody rate="{format(rate, ".15g")}">{text}</prosody>'


def _track_rates(lesson: dict[str, Any], track: dict[str, Any]) -> tuple[int, list[float]]:
    repetitions = track.get("thai_repetitions", 1)
    if not isinstance(repetitions, int) or repetitions < 1 or repetitions > 5:
        raise GateError("thai_repetitions must be between 1 and 5")

    configured_rates = track.get("thai_speaking_rates")
    if configured_rates is None:
        # Preserve existing Azure lesson compatibility. New lessons should encode
        # every learner/natural repetition explicitly in thai_speaking_rates.
        thai_rates = [1.0] * repetitions
    else:
        if not isinstance(configured_rates, list) or len(configured_rates) != repetitions:
            raise GateError(
                "thai_speaking_rates must be an array matching thai_repetitions"
            )
        thai_rates = [
            _speaking_rate(value, f"thai_speaking_rates[{index}]")
            for index, value in enumerate(configured_rates)
        ]

    pitch = lesson["audio_program"].get("pitch_semitones", 0)
    if (
        isinstance(pitch, bool)
        or not isinstance(pitch, (int, float))
        or not math.isfinite(float(pitch))
        or float(pitch) != 0.0
    ):
        raise GateError("audio_program.pitch_semitones must remain 0")
    return repetitions, thai_rates


def build_track_ssml(lesson: dict[str, Any], track: dict[str, Any]) -> str:
    """Build the legacy Azure track-level SSML request."""

    if lesson["voices"].get("provider") != "azure_speech":
        raise GateError("Track-level SSML is only used by azure_speech")

    sentence_by_id = {item["id"]: item for item in lesson["sentences"]}
    voices = lesson["voices"]
    thai_voice = html.escape(_voice_name(voices, "thai"), quote=True)
    repetitions, thai_rates = _track_rates(lesson, track)
    thai_rates = [
        _azure_speaking_rate(rate, f"thai_speaking_rates[{index}]")
        for index, rate in enumerate(thai_rates)
    ]

    parts = [
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="th-TH">'
    ]
    sequence = track["sequence"]
    for index, sentence_id in enumerate(sequence):
        sentence = sentence_by_id[sentence_id]
        if track.get("hebrew_prompt"):
            hebrew_voice = html.escape(_voice_name(voices, "hebrew"), quote=True)
            hebrew_rate = _azure_speaking_rate(
                track.get("hebrew_speaking_rate", 1.0), "hebrew_speaking_rate"
            )
            prompt = html.escape(sentence["prompt_he"])
            parts.append(
                f'<voice name="{hebrew_voice}">{_prosody(prompt, hebrew_rate)}</voice>'
            )
            parts.append(_break(track["recall_pause_ms"]))

        thai = html.escape(sentence["thai"])
        for repetition in range(repetitions):
            parts.append(
                f'<voice name="{thai_voice}">{_prosody(thai, thai_rates[repetition])}</voice>'
            )
            if repetition + 1 < repetitions:
                parts.append(_break(track.get("pause_between_repetitions_ms", 0)))
        if index + 1 < len(sequence):
            parts.append(_break(track.get("pause_between_sentences_ms", 0)))
    parts.append("</speak>")
    return "".join(parts)


def _google_voice_for(voices: dict[str, Any], language: str) -> dict[str, str]:
    configured = voices.get(language)
    default = DEFAULT_GOOGLE_THAI_VOICE if language == "thai" else None
    if configured is None and default is not None:
        return dict(default)
    if isinstance(configured, str):
        if not configured.strip():
            if default is not None:
                return dict(default)
            raise GateError(f"voices.{language} must provide a non-empty voice name")
        locale = "-".join(configured.split("-")[:2])
        return {"language_code": locale, "name": configured}
    if not isinstance(configured, dict):
        raise GateError(f"voices.{language} must be a voice object for google_cloud_tts")

    fallback_language = default["language_code"] if default else None
    fallback_name = default["name"] if default else None
    language_code = configured.get("language_code", fallback_language)
    name = configured.get("name", fallback_name)
    if not isinstance(language_code, str) or not language_code.strip():
        raise GateError(f"voices.{language}.language_code must be non-empty")
    if not isinstance(name, str) or not name.strip():
        raise GateError(f"voices.{language}.name must be non-empty")
    return {"language_code": language_code, "name": name}


def _google_speech_request(
    text: str,
    voice: dict[str, str],
    speaking_rate: float,
) -> dict[str, Any]:
    if not isinstance(text, str) or not text.strip():
        raise GateError("Google Cloud TTS segment text must be non-empty")
    if len(text.encode("utf-8")) > GOOGLE_SYNTHESIS_MAX_BYTES:
        raise GateError("Google Cloud TTS segment exceeds the 5,000-byte input limit")
    return {
        "input": {"text": text},
        "voice": {
            "languageCode": voice["language_code"],
            "name": voice["name"],
        },
        "audioConfig": {
            "audioEncoding": "LINEAR16",
            "sampleRateHertz": GOOGLE_SAMPLE_RATE_HERTZ,
            "speakingRate": speaking_rate,
        },
    }


def _speech_segment(request: dict[str, Any]) -> dict[str, Any]:
    return {
        "kind": "speech",
        "segment_sha256": request_sha256(request),
        "request": request,
    }


def _silence_segment(milliseconds: Any) -> dict[str, Any]:
    return {"kind": "silence", "milliseconds": _break_milliseconds(milliseconds)}


def build_google_practice_variation_requests(
    lesson: dict[str, Any],
) -> list[dict[str, Any]]:
    """Plan supplemental approved clips used by the sentence-level iOS player."""

    config = lesson.get("audio_program", {}).get("practice_variations")
    if config is None:
        return []
    if lesson.get("voices", {}).get("provider") != "google_cloud_tts":
        raise GateError("Practice variations currently require google_cloud_tts")
    if not isinstance(config, dict):
        raise GateError("audio_program.practice_variations must be an object")

    hebrew_rate = _speaking_rate(
        config.get("hebrew_speaking_rate"),
        "practice_variations.hebrew_speaking_rate",
    )
    thai_rate = _speaking_rate(
        config.get("thai_speaking_rate"),
        "practice_variations.thai_speaking_rate",
    )
    hebrew_voice = _google_voice_for(lesson["voices"], "hebrew")
    thai_voice = _google_voice_for(lesson["voices"], "thai")

    planned: list[dict[str, Any]] = []
    for sentence in lesson["sentences"]:
        variation = sentence.get("variation")
        if not isinstance(variation, dict):
            raise GateError(f"Spoken variation is missing for {sentence.get('id')}")
        planned.append(
            {
                "sentence_id": sentence["id"],
                "hebrew": _speech_segment(
                    _google_speech_request(
                        variation.get("prompt_he"), hebrew_voice, hebrew_rate
                    )
                ),
                "thai": _speech_segment(
                    _google_speech_request(
                        variation.get("thai"), thai_voice, thai_rate
                    )
                ),
            }
        )
    return planned


def build_google_track_request(
    lesson: dict[str, Any], track: dict[str, Any]
) -> dict[str, Any]:
    """Plan explicit, plain-text utterances and local pauses for one Google track."""

    if lesson["voices"].get("provider") != "google_cloud_tts":
        raise GateError("Google track requests require voices.provider=google_cloud_tts")
    sentence_by_id = {item["id"]: item for item in lesson["sentences"]}
    thai_voice = _google_voice_for(lesson["voices"], "thai")
    repetitions, thai_rates = _track_rates(lesson, track)
    hebrew_voice = (
        _google_voice_for(lesson["voices"], "hebrew")
        if track.get("hebrew_prompt")
        else None
    )
    hebrew_rate = (
        _speaking_rate(track.get("hebrew_speaking_rate", 1.0), "hebrew_speaking_rate")
        if hebrew_voice
        else None
    )

    timeline: list[dict[str, Any]] = []
    sequence = track["sequence"]
    for index, sentence_id in enumerate(sequence):
        sentence = sentence_by_id[sentence_id]
        if hebrew_voice and hebrew_rate is not None:
            timeline.append(
                _speech_segment(
                    _google_speech_request(
                        sentence["prompt_he"], hebrew_voice, hebrew_rate
                    )
                )
            )
            timeline.append(_silence_segment(track.get("recall_pause_ms")))

        for repetition, thai_rate in enumerate(thai_rates):
            timeline.append(
                _speech_segment(
                    _google_speech_request(sentence["thai"], thai_voice, thai_rate)
                )
            )
            if repetition + 1 < repetitions:
                timeline.append(
                    _silence_segment(track.get("pause_between_repetitions_ms", 0))
                )
        if index + 1 < len(sequence):
            timeline.append(_silence_segment(track.get("pause_between_sentences_ms", 0)))

    return {
        "request_version": 1,
        "provider": "google_cloud_tts",
        "timeline": timeline,
        "assembly": dict(GOOGLE_ASSEMBLY),
    }


def build_track_request(lesson: dict[str, Any], track: dict[str, Any]) -> dict[str, Any]:
    provider = lesson["voices"].get("provider")
    if provider == "google_cloud_tts":
        return build_google_track_request(lesson, track)
    if provider == "azure_speech":
        return {
            "request_version": 1,
            "provider": "azure_speech",
            "ssml": build_track_ssml(lesson, track),
            "audio_config": {"output_format": OUTPUT_FORMAT},
        }
    raise GateError(f"Unsupported speech provider: {provider!r}")


def planned_google_billable_characters(lesson: dict[str, Any]) -> int:
    """Return a conservative no-cache character total for unique Google requests."""

    if lesson.get("voices", {}).get("provider") != "google_cloud_tts":
        raise GateError("Billable-character planning requires google_cloud_tts")

    unique_requests: dict[str, str] = {}

    def include(segment: dict[str, Any]) -> None:
        if segment.get("kind") != "speech":
            return
        request = segment.get("request")
        text = request.get("input", {}).get("text") if isinstance(request, dict) else None
        segment_hash = segment.get("segment_sha256")
        if not isinstance(segment_hash, str) or not isinstance(text, str):
            raise GateError("Google speech segment is missing its hash or text")
        existing = unique_requests.get(segment_hash)
        if existing is not None and existing != text:
            raise GateError("Google speech request hash collision")
        unique_requests[segment_hash] = text

    for track in lesson.get("audio_program", {}).get("tracks", []):
        request = build_track_request(lesson, track)
        for segment in request.get("timeline", []):
            include(segment)
    for variation in build_google_practice_variation_requests(lesson):
        include(variation["hebrew"])
        include(variation["thai"])

    return sum(len(text) for text in unique_requests.values())


def request_sha256(request: Any) -> str:
    if isinstance(request, str):
        # Accept legacy direct-SSML callers while hashing the provider-bound
        # descriptor used by new generation and publishing code.
        request = {
            "request_version": 1,
            "provider": "azure_speech",
            "ssml": request,
            "audio_config": {"output_format": OUTPUT_FORMAT},
        }
    material = json.dumps(
        request,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
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


class GoogleCloudTTSProvider:
    def __init__(
        self,
        access_token: str,
        quota_project: str | None = None,
    ) -> None:
        self.access_token = access_token
        self.quota_project = quota_project

    def synthesize_segment(self, request_body: dict[str, Any]) -> bytes:
        body = json.dumps(
            request_body,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        headers = {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "personalized-thai-learning",
        }
        if self.quota_project:
            headers["X-Goog-User-Project"] = self.quota_project
        request = urllib.request.Request(
            GOOGLE_TTS_ENDPOINT,
            data=body,
            method="POST",
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                raw_response = response.read()
        except urllib.error.HTTPError as error:
            raise RuntimeError(
                f"Google Cloud TTS returned HTTP {error.code}; ensure the Text-to-Speech "
                "API and billing are enabled and set GOOGLE_CLOUD_QUOTA_PROJECT when "
                "user ADC needs an explicit quota project"
            ) from error
        except urllib.error.URLError as error:
            raise RuntimeError("Google Cloud TTS request could not reach the service") from error

        try:
            decoded = json.loads(raw_response.decode("utf-8"))
            encoded_audio = decoded["audioContent"]
            if not isinstance(encoded_audio, str) or not encoded_audio:
                raise ValueError("audioContent is empty")
            payload = base64.b64decode(encoded_audio, validate=True)
        except (
            UnicodeDecodeError,
            json.JSONDecodeError,
            KeyError,
            ValueError,
            binascii.Error,
        ) as error:
            raise RuntimeError(
                "Google Cloud TTS returned invalid base64 LINEAR16 audio"
            ) from error
        if not payload:
            raise RuntimeError("Google Cloud TTS returned empty audio")
        return payload


def _google_access_token() -> str:
    """Mint a short-lived ADC token without adding a Python SDK dependency."""

    explicit_token = os.environ.get("GOOGLE_CLOUD_ACCESS_TOKEN")
    if explicit_token:
        return explicit_token

    gcloud = os.environ.get("GOOGLE_CLOUD_GCLOUD", "gcloud")
    command = [gcloud, "auth", "application-default", "print-access-token"]
    guidance = (
        "Google Cloud TTS needs Application Default Credentials. For a scheduled "
        "Mac job, run `gcloud auth application-default login` once as the same macOS "
        "user and set GOOGLE_CLOUD_GCLOUD to the absolute gcloud path if the job has "
        "a minimal PATH; alternatively provide a short-lived "
        "GOOGLE_CLOUD_ACCESS_TOKEN."
    )
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(guidance) from error
    token = completed.stdout.strip() if completed.returncode == 0 else ""
    if not token:
        raise RuntimeError(guidance)
    return token


def _google_quota_project() -> str:
    explicit = os.environ.get("GOOGLE_CLOUD_QUOTA_PROJECT") or os.environ.get(
        "GOOGLE_CLOUD_PROJECT"
    )
    if explicit:
        return explicit

    gcloud = os.environ.get("GOOGLE_CLOUD_GCLOUD", "gcloud")
    guidance = (
        "Google Cloud TTS needs a billing/quota project for raw REST calls. Set "
        "GOOGLE_CLOUD_QUOTA_PROJECT in the scheduled Mac job, or configure the "
        "same gcloud user with `gcloud config set project PROJECT_ID`."
    )
    try:
        completed = subprocess.run(
            [gcloud, "config", "get-value", "project"],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(guidance) from error
    project = completed.stdout.strip() if completed.returncode == 0 else ""
    if not project or project == "(unset)":
        raise RuntimeError(guidance)
    return project


def provider_from_environment(voices: dict[str, Any]) -> Any:
    """Select a provider and read credentials only after preflight succeeds."""

    provider = voices.get("provider")
    if provider == "google_cloud_tts":
        token = _google_access_token()
        quota_project = _google_quota_project()
        return GoogleCloudTTSProvider(
            access_token=token,
            quota_project=quota_project,
        )
    if provider != "azure_speech":
        raise GateError(f"Unsupported speech provider: {provider!r}")

    key = os.environ.get("AZURE_SPEECH_KEY")
    region = os.environ.get("AZURE_SPEECH_REGION")
    if not key or not region:
        raise RuntimeError(
            "AZURE_SPEECH_KEY and AZURE_SPEECH_REGION are required only for an authorized paid run"
        )
    return AzureSpeechProvider(key=key, region=region)


def _linear16_wav_frames(payload: bytes) -> bytes:
    try:
        with wave.open(io.BytesIO(payload), "rb") as source:
            actual = (
                source.getnchannels(),
                source.getsampwidth(),
                source.getframerate(),
                source.getcomptype(),
            )
            expected = (
                GOOGLE_ASSEMBLY["channels"],
                GOOGLE_ASSEMBLY["sample_width_bytes"],
                GOOGLE_ASSEMBLY["sample_rate_hertz"],
                "NONE",
            )
            if actual != expected:
                raise RuntimeError(
                    f"Google LINEAR16 WAV format mismatch: expected {expected}, got {actual}"
                )
            return source.readframes(source.getnframes())
    except (EOFError, wave.Error) as error:
        raise RuntimeError("Google Cloud TTS returned an invalid LINEAR16 WAV") from error


def _sox_guidance() -> str:
    return (
        "Google track assembly requires sox with MP3 support. On the scheduled Mac, "
        "install it with Homebrew and set THAI_TTS_SOX to its absolute path when the "
        "job has a minimal PATH."
    )


def preflight_google_assembler() -> None:
    """Prove the local encoder is available before any billable provider request."""

    sox = os.environ.get("THAI_TTS_SOX", "sox")
    try:
        completed = subprocess.run(
            [sox, "--help"],
            check=False,
            capture_output=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(_sox_guidance()) from error
    capabilities = (completed.stdout or b"") + (completed.stderr or b"")
    if completed.returncode != 0 or b"mp3" not in capabilities.lower():
        raise RuntimeError(_sox_guidance())


def _google_segment_cache_path(output_root: Path, segment_hash: str) -> Path:
    # Keep raw WAV cache data beside, never inside, generated/. The iOS bundling
    # contract copies generated/ wholesale and must contain only final artifacts.
    return output_root.parent / ".google-segment-cache-v1" / f"{segment_hash}.wav"


def _load_google_segment_cache(output_root: Path, segment_hash: str) -> bytes | None:
    path = _google_segment_cache_path(output_root, segment_hash)
    if not path.exists():
        return None
    if not path.is_file():
        raise OutputCollisionError(f"Invalid Google segment cache entry: {path}")
    payload = path.read_bytes()
    _linear16_wav_frames(payload)
    return payload


def _store_google_segment_cache(
    output_root: Path, segment_hash: str, payload: bytes
) -> None:
    _linear16_wav_frames(payload)
    cache_path = _google_segment_cache_path(output_root, segment_hash)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            prefix=f".{segment_hash}.",
            suffix=".tmp",
            dir=cache_path.parent,
            delete=False,
        ) as temporary:
            temporary.write(payload)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, cache_path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def assemble_google_track(
    track_request: dict[str, Any],
    segment_audio: dict[str, bytes],
) -> bytes:
    """Join validated LINEAR16 frames and transcode one complete track with sox."""

    if track_request.get("provider") != "google_cloud_tts":
        raise GateError("Google assembly received a non-Google track request")
    if track_request.get("assembly") != GOOGLE_ASSEMBLY:
        raise GateError("Google assembly format/version is unsupported")

    sox = os.environ.get("THAI_TTS_SOX", "sox")
    with tempfile.TemporaryDirectory(prefix="thai-tts-assembly-") as temporary:
        temporary_path = Path(temporary)
        combined_wav = temporary_path / "combined.wav"
        output_mp3 = temporary_path / "track.mp3"
        with wave.open(str(combined_wav), "wb") as destination:
            destination.setnchannels(GOOGLE_ASSEMBLY["channels"])
            destination.setsampwidth(GOOGLE_ASSEMBLY["sample_width_bytes"])
            destination.setframerate(GOOGLE_ASSEMBLY["sample_rate_hertz"])
            for segment in track_request["timeline"]:
                kind = segment.get("kind")
                if kind == "speech":
                    segment_hash = segment.get("segment_sha256")
                    payload = segment_audio.get(segment_hash)
                    if payload is None:
                        raise RuntimeError(
                            f"Missing synthesized audio for segment {segment_hash!r}"
                        )
                    destination.writeframes(_linear16_wav_frames(payload))
                elif kind == "silence":
                    milliseconds = _break_milliseconds(segment.get("milliseconds"))
                    frames = GOOGLE_SAMPLE_RATE_HERTZ * milliseconds // 1000
                    destination.writeframes(
                        b"\0" * frames * GOOGLE_ASSEMBLY["sample_width_bytes"]
                    )
                else:
                    raise GateError(f"Unsupported Google timeline segment: {kind!r}")

        command = [
            sox,
            str(combined_wav),
            "-C",
            str(GOOGLE_ASSEMBLY["output_bitrate_kbps"]),
            str(output_mp3),
        ]
        try:
            completed = subprocess.run(
                command,
                check=False,
                capture_output=True,
                timeout=120,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise RuntimeError(_sox_guidance()) from error
        if completed.returncode != 0 or not output_mp3.is_file():
            raise RuntimeError(_sox_guidance())
        payload = output_mp3.read_bytes()
        if not payload:
            raise RuntimeError("sox produced an empty MP3 track")
        return payload


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
    provider_factory: Callable[[], Any] | None = None,
    google_assembler: Callable[
        [dict[str, Any], dict[str, bytes]], bytes
    ]
    | None = None,
) -> dict[str, Any]:
    """Generate or safely reuse tracks after all authorization gates pass."""

    digest = preflight(lesson, approval, authorization)
    practice_variation_requests = build_google_practice_variation_requests(lesson)
    provider: Any | None = None
    google_segment_cache: dict[str, bytes] = {}
    google_assembler_preflighted = False
    lesson_dir = output_root / lesson["lesson_id"] / f"r{lesson['revision']}"
    lesson_dir.mkdir(parents=True, exist_ok=True)

    generated: list[dict[str, Any]] = []
    for track in lesson["audio_program"]["tracks"]:
        track_id = track.get("id")
        if not isinstance(track_id, str) or not track_id:
            raise GateError("Every track needs a non-empty id")
        track_request = build_track_request(lesson, track)
        request_hash = request_sha256(track_request)
        audio_path = lesson_dir / f"{track_id}.mp3"
        sidecar_path = lesson_dir / f"{track_id}.request.json"

        if audio_path.exists() or sidecar_path.exists():
            if not (audio_path.is_file() and sidecar_path.is_file()):
                raise OutputCollisionError(f"Incomplete existing output for {track_id}")
            sidecar = load_json(sidecar_path)
            if (
                sidecar.get("content_sha256") != digest
                or sidecar.get("request_sha256") != request_hash
                or audio_path.stat().st_size <= 0
            ):
                raise OutputCollisionError(
                    f"Refusing to overwrite mismatched output for {track_id}"
                )
            generated.append(sidecar)
            continue

        if track_request["provider"] == "google_cloud_tts":
            if google_assembler is None and not google_assembler_preflighted:
                preflight_google_assembler()
                google_assembler_preflighted = True
            track_segment_audio: dict[str, bytes] = {}
            for segment in track_request["timeline"]:
                if segment["kind"] != "speech":
                    continue
                segment_hash = segment["segment_sha256"]
                if segment_hash not in google_segment_cache:
                    cached = (
                        _load_google_segment_cache(output_root, segment_hash)
                        if google_assembler is None
                        else None
                    )
                    if cached is None:
                        if provider is None:
                            provider = (
                                provider_factory()
                                if provider_factory is not None
                                else provider_from_environment(lesson["voices"])
                            )
                        cached = provider.synthesize_segment(segment["request"])
                        if google_assembler is None:
                            _store_google_segment_cache(output_root, segment_hash, cached)
                    google_segment_cache[segment_hash] = cached
                track_segment_audio[segment_hash] = google_segment_cache[segment_hash]
            assembler = google_assembler or assemble_google_track
            audio = assembler(track_request, track_segment_audio)
        else:
            if provider is None:
                provider = (
                    provider_factory()
                    if provider_factory is not None
                    else provider_from_environment(lesson["voices"])
                )
            audio = provider.synthesize(track_request["ssml"])
        audio_path.write_bytes(audio)
        sidecar = {
            "lesson_id": lesson["lesson_id"],
            "revision": lesson["revision"],
            "content_sha256": digest,
            "track_id": track_id,
            "request_sha256": request_hash,
            "file": audio_path.name,
            "bytes": len(audio),
            "provider": track_request["provider"],
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }
        if track_request["provider"] == "google_cloud_tts":
            sidecar["speech_segments"] = sum(
                1 for segment in track_request["timeline"] if segment["kind"] == "speech"
            )
            sidecar["assembly"] = track_request["assembly"]
        _write_json(sidecar_path, sidecar)
        generated.append(sidecar)

    practice_variations: list[dict[str, Any]] = []
    for item in practice_variation_requests:
        generated_pair: dict[str, Any] = {"sentence_id": item["sentence_id"]}
        for language in ("hebrew", "thai"):
            segment = item[language]
            segment_hash = segment["segment_sha256"]
            if segment_hash not in google_segment_cache:
                cached = (
                    _load_google_segment_cache(output_root, segment_hash)
                    if google_assembler is None
                    else None
                )
                if cached is None:
                    if provider is None:
                        provider = (
                            provider_factory()
                            if provider_factory is not None
                            else provider_from_environment(lesson["voices"])
                        )
                    cached = provider.synthesize_segment(segment["request"])
                    if google_assembler is None:
                        _store_google_segment_cache(output_root, segment_hash, cached)
                google_segment_cache[segment_hash] = cached
            generated_pair[language] = {"segment_sha256": segment_hash}
        practice_variations.append(generated_pair)

    manifest = {
        "schema_version": 1,
        "lesson_id": lesson["lesson_id"],
        "revision": lesson["revision"],
        "content_sha256": digest,
        "provider": lesson["voices"]["provider"],
        "voices": lesson["voices"],
        "tracks": generated,
    }
    if practice_variations:
        manifest["practice_variations"] = {
            "count": len(practice_variations),
            "pairs": practice_variations,
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
