#!/usr/bin/env python3
"""Publish an already-generated lesson as a deterministic static HTTP tree.

This module only validates and copies local files.  It deliberately imports the
audio generator's pure validation/hash helpers, but never constructs a provider,
reads credentials, calls TTS, or performs network I/O.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import Any


EXPECTED_TRACK_IDS = ("listening", "shadowing", "recall", "scenario")
SUPPORTED_AUDIO_PROVIDERS = frozenset({"azure_speech", "google_cloud_tts"})
LATEST_SCHEMA_VERSION = 1
_LESSON_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class PublishError(RuntimeError):
    """Raised before a static pack is made visible through latest.json."""


def _load_audio_helpers() -> ModuleType:
    module_path = Path(__file__).resolve().parents[1] / "audio" / "generate_audio.py"
    spec = importlib.util.spec_from_file_location("thai_audio_for_publish", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load audio validation helpers: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audio = _load_audio_helpers()


def _load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        return audio.load_json(path)
    except (OSError, ValueError, audio.GateError) as error:
        raise PublishError(f"Cannot read {label} {path}: {error}") from error


def _require_positive_int(value: Any, label: str) -> int:
    if type(value) is not int or value <= 0:
        raise PublishError(f"{label} must be a positive integer")
    return value


def _validated_lesson(lesson: dict[str, Any]) -> tuple[str, str, int]:
    try:
        digest = audio.validate_lesson_for_approval(lesson)
    except audio.GateError as error:
        raise PublishError(f"Lesson is not publishable: {error}") from error

    if lesson.get("schema_version") != 1:
        raise PublishError("Lesson schema_version must be 1")

    lesson_id = lesson.get("lesson_id")
    if (
        not isinstance(lesson_id, str)
        or not _LESSON_ID_PATTERN.fullmatch(lesson_id)
        or lesson_id in {".", ".."}
    ):
        raise PublishError("lesson_id is missing or unsafe for a static path")

    revision = _require_positive_int(lesson.get("revision"), "Lesson revision")
    _require_positive_int(lesson.get("day"), "Lesson day")
    if not isinstance(lesson.get("theme"), str) or not lesson["theme"].strip():
        raise PublishError("Lesson theme must be a non-empty string")

    voices = lesson.get("voices")
    if (
        not isinstance(voices, dict)
        or voices.get("provider") not in SUPPORTED_AUDIO_PROVIDERS
    ):
        raise PublishError("Lesson voices use an unsupported audio provider")
    for voice_name in ("thai", "hebrew"):
        voice = voices.get(voice_name)
        if isinstance(voice, str):
            valid_voice = bool(voice.strip())
        else:
            valid_voice = (
                isinstance(voice, dict)
                and isinstance(voice.get("language_code"), str)
                and bool(voice["language_code"].strip())
                and isinstance(voice.get("name"), str)
                and bool(voice["name"].strip())
            )
        if not valid_voice:
            raise PublishError(
                f"Lesson {voice_name} voice must identify a language code and voice name"
            )

    for index, sentence in enumerate(lesson["sentences"], start=1):
        romanization = sentence.get("romanization")
        if not isinstance(romanization, str) or not romanization.strip():
            raise PublishError(f"Sentence {index} needs a non-empty romanization")

    audio_program = lesson.get("audio_program", {})
    if audio_program.get("pitch_semitones", 0) != 0:
        raise PublishError("Lesson audio_program must not alter lexical-tone pitch")
    tracks = audio_program.get("tracks")
    track_ids = [track.get("id") if isinstance(track, dict) else None for track in tracks or []]
    if tuple(track_ids) != EXPECTED_TRACK_IDS:
        raise PublishError(
            "audio_program must contain exactly these tracks in order: "
            + ", ".join(EXPECTED_TRACK_IDS)
        )

    return digest, lesson_id, revision


def _course_root_for_lesson(lesson_path: Path) -> Path:
    return lesson_path.parent.parent if lesson_path.parent.name == "days" else lesson_path.parent


def _find_matching_receipt(
    directory: Path,
    lesson_id: str,
    revision: int,
    digest: str,
    *,
    label: str,
) -> dict[str, Any]:
    pattern = f"{lesson_id}-r{revision}-*.json"
    matches: list[dict[str, Any]] = []
    for path in sorted(directory.glob(pattern)):
        receipt = _load_json(path, label)
        if (
            receipt.get("schema_version") == 1
            and receipt.get("lesson_id") == lesson_id
            and receipt.get("revision") == revision
            and receipt.get("content_sha256") == digest
        ):
            matches.append(receipt)
    if not matches:
        raise PublishError(
            f"Missing exact immutable {label} for {lesson_id} r{revision} "
            f"and content hash {digest}"
        )
    return matches[-1]


def _validated_receipts(
    lesson_path: Path,
    lesson: dict[str, Any],
    digest: str,
    lesson_id: str,
    revision: int,
) -> None:
    course_root = _course_root_for_lesson(lesson_path)
    approval = _find_matching_receipt(
        course_root / "approvals",
        lesson_id,
        revision,
        digest,
        label="text-approval receipt",
    )
    authorization = _find_matching_receipt(
        course_root / "authorizations",
        lesson_id,
        revision,
        digest,
        label="paid-request authorization receipt",
    )
    try:
        audio.preflight(lesson, approval, authorization)
    except audio.GateError as error:
        raise PublishError(f"Approval receipts do not authorize this pack: {error}") from error


def _find_generated_revision(
    generated_audio_directory: Path,
    lesson_id: str,
    revision: int,
) -> Path:
    """Accept either the generator output root or its lesson revision directory."""

    direct_manifest = generated_audio_directory / "audio-manifest.json"
    if direct_manifest.is_file():
        return generated_audio_directory

    revision_directory = generated_audio_directory / lesson_id / f"r{revision}"
    if (revision_directory / "audio-manifest.json").is_file():
        return revision_directory

    raise PublishError(
        "Missing generated audio manifest; expected "
        f"{direct_manifest} or {revision_directory / 'audio-manifest.json'}"
    )


def _validated_audio(
    lesson: dict[str, Any],
    digest: str,
    lesson_id: str,
    revision: int,
    generated_revision: Path,
) -> tuple[dict[str, Any], dict[str, bytes]]:
    manifest_path = generated_revision / "audio-manifest.json"
    manifest = _load_json(manifest_path, "audio manifest")

    identity_checks = (
        ("schema_version", manifest.get("schema_version"), 1),
        ("lesson_id", manifest.get("lesson_id"), lesson_id),
        ("revision", manifest.get("revision"), revision),
        ("content_sha256", manifest.get("content_sha256"), digest),
        ("provider", manifest.get("provider"), lesson["voices"].get("provider")),
        ("voices", manifest.get("voices"), lesson["voices"]),
    )
    for field, actual, expected in identity_checks:
        if actual != expected:
            raise PublishError(f"Audio manifest {field} does not match the approved lesson")

    manifest_tracks = manifest.get("tracks")
    if not isinstance(manifest_tracks, list):
        raise PublishError("Audio manifest tracks must be a list")
    manifest_track_ids = [
        item.get("track_id") if isinstance(item, dict) else None for item in manifest_tracks
    ]
    if tuple(manifest_track_ids) != EXPECTED_TRACK_IDS:
        raise PublishError(
            "Audio manifest must contain exactly these tracks in order: "
            + ", ".join(EXPECTED_TRACK_IDS)
        )

    actual_mp3_names = {
        item.name for item in generated_revision.iterdir() if item.name.lower().endswith(".mp3")
    }
    expected_mp3_names = {f"{track_id}.mp3" for track_id in EXPECTED_TRACK_IDS}
    if actual_mp3_names != expected_mp3_names:
        raise PublishError("Generated directory must contain exactly the four expected MP3 files")

    lesson_tracks = {track["id"]: track for track in lesson["audio_program"]["tracks"]}
    payloads: dict[str, bytes] = {}
    for track in manifest_tracks:
        track_id = track["track_id"]
        expected_filename = f"{track_id}.mp3"

        track_checks = (
            ("lesson_id", track.get("lesson_id"), lesson_id),
            ("revision", track.get("revision"), revision),
            ("content_sha256", track.get("content_sha256"), digest),
            ("file", track.get("file"), expected_filename),
        )
        for field, actual, expected in track_checks:
            if actual != expected:
                raise PublishError(f"Track {track_id} {field} does not match the approved lesson")

        expected_request_hash = audio.request_sha256(
            audio.build_track_request(lesson, lesson_tracks[track_id])
        )
        if track.get("request_sha256") != expected_request_hash:
            raise PublishError(f"Track {track_id} request hash is stale")

        declared_bytes = _require_positive_int(track.get("bytes"), f"Track {track_id} bytes")
        audio_path = generated_revision / expected_filename
        if not audio_path.is_file():
            raise PublishError(f"Track {track_id} is not a regular file")
        try:
            payload = audio_path.read_bytes()
        except OSError as error:
            raise PublishError(f"Cannot read track {track_id}: {error}") from error
        if not payload or len(payload) != declared_bytes:
            raise PublishError(f"Track {track_id} does not match its manifest byte count")
        payloads[expected_filename] = payload

    return manifest, payloads


def _find_practice_revision(
    practice_audio_directory: Path,
    lesson_id: str,
    revision: int,
) -> Path:
    direct_manifest = practice_audio_directory / "practice-manifest.json"
    if direct_manifest.is_file():
        return practice_audio_directory

    revision_directory = practice_audio_directory / lesson_id / f"r{revision}"
    if (revision_directory / "practice-manifest.json").is_file():
        return revision_directory

    raise PublishError(
        "Missing practice audio manifest; expected "
        f"{direct_manifest} or {revision_directory / 'practice-manifest.json'}"
    )


def _validated_practice_audio(
    lesson: dict[str, Any],
    digest: str,
    lesson_id: str,
    revision: int,
    practice_revision: Path,
) -> tuple[dict[str, Any], dict[str, bytes]]:
    manifest = _load_json(practice_revision / "practice-manifest.json", "practice manifest")
    identity_checks = (
        ("lesson_id", manifest.get("lesson_id"), lesson_id),
        ("revision", manifest.get("revision"), revision),
        ("content_sha256", manifest.get("content_sha256"), digest),
        ("sample_rate_hertz", manifest.get("sample_rate_hertz"), 24_000),
    )
    if manifest.get("schema_version") not in {1, 2}:
        raise PublishError("Practice manifest schema_version must be 1 or 2")
    for field, actual, expected in identity_checks:
        if actual != expected:
            raise PublishError(f"Practice manifest {field} does not match the approved lesson")

    entries = manifest.get("sentences")
    if not isinstance(entries, list):
        raise PublishError("Practice manifest sentences must be a list")
    expected_sentence_ids = [item["id"] for item in lesson["sentences"]]
    actual_sentence_ids = [
        item.get("sentence_id") if isinstance(item, dict) else None for item in entries
    ]
    if actual_sentence_ids != expected_sentence_ids:
        raise PublishError("Practice manifest sentence order does not match the approved lesson")

    payloads: dict[str, bytes] = {}

    def validate_clip(clip: Any) -> None:
        if not isinstance(clip, dict):
            raise PublishError("Practice manifest contains an invalid clip declaration")
        filename = clip.get("file")
        if (
            not isinstance(filename, str)
            or not filename.endswith(".wav")
            or PurePosixPath(filename).name != filename
        ):
            raise PublishError("Practice clip filename is unsafe")
        if filename in payloads:
            raise PublishError(f"Practice clip filename is duplicated: {filename}")
        declared_bytes = _require_positive_int(clip.get("bytes"), f"Practice clip {filename} bytes")
        declared_sha256 = clip.get("sha256")
        if (
            not isinstance(declared_sha256, str)
            or not re.fullmatch(r"[0-9a-f]{64}", declared_sha256)
        ):
            raise PublishError(f"Practice clip {filename} has an invalid SHA-256")
        source_request_sha256 = clip.get("source_request_sha256")
        if (
            not isinstance(source_request_sha256, str)
            or not re.fullmatch(r"[0-9a-f]{64}", source_request_sha256)
        ):
            raise PublishError(f"Practice clip {filename} has an invalid request hash")

        path = practice_revision / filename
        if path.is_symlink() or not path.is_file():
            raise PublishError(f"Practice clip is not a regular file: {filename}")
        try:
            payload = path.read_bytes()
        except OSError as error:
            raise PublishError(f"Cannot read practice clip {filename}: {error}") from error
        if len(payload) != declared_bytes:
            raise PublishError(f"Practice clip {filename} does not match its byte count")
        if hashlib.sha256(payload).hexdigest() != declared_sha256:
            raise PublishError(f"Practice clip {filename} failed integrity checking")
        payloads[filename] = payload

    for entry in entries:
        if not isinstance(entry, dict):
            raise PublishError("Practice manifest contains an invalid sentence entry")
        if "core" in entry:
            core = entry.get("core")
            variations = entry.get("variations", [])
        else:
            core = {"hebrew": entry.get("hebrew"), "thai": entry.get("thai")}
            variations = []
        if not isinstance(core, dict):
            raise PublishError("Practice manifest contains an invalid core pair")
        validate_clip(core.get("hebrew"))
        validate_clip(core.get("thai"))
        if not isinstance(variations, list):
            raise PublishError("Practice manifest variations must be a list")
        if manifest["schema_version"] == 2 and not variations:
            raise PublishError("Practice manifest schema 2 needs a variation for every sentence")
        for variation in variations:
            if not isinstance(variation, dict):
                raise PublishError("Practice manifest contains an invalid variation pair")
            validate_clip(variation.get("hebrew"))
            validate_clip(variation.get("thai"))

    actual_wav_names = {
        item.name for item in practice_revision.iterdir() if item.name.lower().endswith(".wav")
    }
    if actual_wav_names != set(payloads):
        raise PublishError("Practice directory contains missing or unexpected WAV files")
    return manifest, payloads


def _encoded_json(value: dict[str, Any]) -> bytes:
    try:
        rendered = json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
            allow_nan=False,
        )
    except (TypeError, ValueError) as error:
        raise PublishError(f"JSON cannot be published deterministically: {error}") from error
    return (rendered + "\n").encode("utf-8")


def _atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
        os.replace(temporary_path, path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def _entry_exists(path: Path) -> bool:
    """Return whether a directory entry exists, including a broken symlink."""

    try:
        path.lstat()
    except FileNotFoundError:
        return False
    except OSError as error:
        raise PublishError(f"Cannot inspect publish path {path}: {error}") from error
    return True


def _rename_directory_no_replace(source: Path, destination: Path) -> None:
    """Atomically rename a directory, failing if destination already exists.

    Plain POSIX ``rename`` may replace an existing empty directory.  The pack
    contract forbids replacing *any* live revision directory, so use each
    supported platform's exclusive rename primitive and fail closed elsewhere.
    """

    source_bytes = os.fsencode(source)
    destination_bytes = os.fsencode(destination)

    if sys.platform == "darwin":
        # renamex_np(2): RENAME_EXCL prevents replacement of any destination.
        renamex_np = ctypes.CDLL(None, use_errno=True).renamex_np
        renamex_np.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
        renamex_np.restype = ctypes.c_int
        result = renamex_np(source_bytes, destination_bytes, 0x00000004)
    elif sys.platform.startswith("linux"):
        # renameat2(2): RENAME_NOREPLACE provides the same atomic guarantee.
        library = ctypes.CDLL(None, use_errno=True)
        try:
            renameat2 = library.renameat2
        except AttributeError as error:
            raise OSError(
                errno.ENOTSUP,
                "The runtime does not expose an atomic no-replace rename",
                destination,
            ) from error
        renameat2.argtypes = (
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        )
        renameat2.restype = ctypes.c_int
        result = renameat2(-100, source_bytes, -100, destination_bytes, 0x00000001)
    elif os.name == "nt":
        # Windows os.rename already fails when the destination exists.
        os.rename(source, destination)
        return
    else:
        raise OSError(
            errno.ENOTSUP,
            "This platform has no configured atomic no-replace directory rename",
            destination,
        )

    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number), destination)


def _remove_staging_directory(staging_directory: Path) -> None:
    try:
        shutil.rmtree(staging_directory)
    except FileNotFoundError:
        pass


def _build_staged_pack(
    pack_parent: Path,
    pack_name: str,
    payloads: dict[str, bytes],
) -> Path:
    """Build a complete pack in a private sibling directory."""

    try:
        pack_parent.mkdir(parents=True, exist_ok=True)
        staging_directory = Path(
            tempfile.mkdtemp(prefix=f".{pack_name}.staging-", dir=pack_parent)
        )
    except OSError as error:
        raise PublishError(f"Cannot create pack staging directory: {error}") from error

    try:
        for filename, payload in payloads.items():
            _atomic_write(staging_directory / filename, payload)
    except BaseException as error:
        try:
            _remove_staging_directory(staging_directory)
        except OSError as cleanup_error:
            raise PublishError(
                f"Cannot clean failed pack staging directory {staging_directory}: "
                f"{cleanup_error}"
            ) from error
        if isinstance(error, OSError):
            raise PublishError(f"Cannot build staged pack: {error}") from error
        raise

    return staging_directory


def _require_identical_pack(
    pack_directory: Path,
    payloads: dict[str, bytes],
) -> None:
    """Accept an existing revision only when it is the exact desired pack."""

    try:
        if pack_directory.is_symlink() or not pack_directory.is_dir():
            raise PublishError(f"Pack path is not a regular directory: {pack_directory}")

        actual_names: set[str] = set()
        for item in pack_directory.rglob("*"):
            if item.is_symlink():
                raise PublishError(f"Existing pack entry is a symlink: {item}")
            if item.is_file():
                actual_names.add(item.relative_to(pack_directory).as_posix())
        expected_names = set(payloads)
        if actual_names != expected_names:
            missing = sorted(expected_names - actual_names)
            unexpected = sorted(actual_names - expected_names)
            details = []
            if missing:
                details.append(f"missing: {', '.join(missing)}")
            if unexpected:
                details.append(f"unexpected: {', '.join(unexpected)}")
            raise PublishError(
                "Existing pack does not exactly match the desired immutable pack "
                f"({'; '.join(details)})"
            )

        for filename, desired_payload in payloads.items():
            existing_path = pack_directory / filename
            if existing_path.is_symlink() or not existing_path.is_file():
                raise PublishError(
                    f"Existing pack entry is not a regular file: {existing_path}"
                )
            if existing_path.read_bytes() != desired_payload:
                raise PublishError(
                    "Existing immutable pack conflicts with desired content: "
                    f"{existing_path}"
                )
    except PublishError:
        raise
    except OSError as error:
        raise PublishError(f"Cannot verify existing pack {pack_directory}: {error}") from error


def _commit_staged_pack(
    staging_directory: Path,
    pack_directory: Path,
    payloads: dict[str, bytes],
) -> None:
    """Install a new pack once, or verify an identical concurrent/existing pack."""

    if _entry_exists(pack_directory):
        _require_identical_pack(pack_directory, payloads)
        return

    try:
        _rename_directory_no_replace(staging_directory, pack_directory)
    except OSError as error:
        # Another publisher may have committed the same revision after our
        # initial check.  It is safe only when that winner is byte-identical.
        if _entry_exists(pack_directory):
            _require_identical_pack(pack_directory, payloads)
            return
        raise PublishError(f"Cannot commit staged pack {pack_directory}: {error}") from error


def _atomic_write_if_changed(path: Path, payload: bytes) -> None:
    """Preserve a byte-identical index as a true idempotent no-op."""

    try:
        if path.is_file() and not path.is_symlink() and path.read_bytes() == payload:
            return
        _atomic_write(path, payload)
    except OSError as error:
        raise PublishError(f"Cannot update {path}: {error}") from error


def publish_static_pack(
    lesson_path: Path,
    generated_audio_directory: Path,
    output_directory: Path,
    practice_audio_directory: Path | None = None,
) -> dict[str, Any]:
    """Validate local inputs, write one immutable pack, then update latest.json."""

    lesson_path = Path(lesson_path)
    generated_audio_directory = Path(generated_audio_directory)
    output_directory = Path(output_directory)
    practice_audio_directory = (
        Path(practice_audio_directory) if practice_audio_directory is not None else None
    )

    lesson = _load_json(lesson_path, "lesson")
    digest, lesson_id, revision = _validated_lesson(lesson)
    _validated_receipts(lesson_path, lesson, digest, lesson_id, revision)
    generated_revision = _find_generated_revision(
        generated_audio_directory, lesson_id, revision
    )
    manifest, audio_payloads = _validated_audio(
        lesson, digest, lesson_id, revision, generated_revision
    )
    practice_manifest: dict[str, Any] | None = None
    practice_payloads: dict[str, bytes] = {}
    if practice_audio_directory is not None:
        practice_revision = _find_practice_revision(
            practice_audio_directory, lesson_id, revision
        )
        practice_manifest, practice_payloads = _validated_practice_audio(
            lesson, digest, lesson_id, revision, practice_revision
        )

    relative_pack_directory = PurePosixPath("packs") / lesson_id / f"r{revision}"
    pack_directory = output_directory.joinpath(*relative_pack_directory.parts)
    pack_payloads = {
        "lesson.json": _encoded_json(lesson),
        "audio-manifest.json": _encoded_json(manifest),
        **{
            f"{track_id}.mp3": audio_payloads[f"{track_id}.mp3"]
            for track_id in EXPECTED_TRACK_IDS
        },
    }
    if practice_manifest is not None:
        pack_payloads["practice/practice-manifest.json"] = _encoded_json(practice_manifest)
        pack_payloads.update(
            {f"practice/{filename}": payload for filename, payload in practice_payloads.items()}
        )

    lesson_relative_path = relative_pack_directory / "lesson.json"
    manifest_relative_path = relative_pack_directory / "audio-manifest.json"
    latest = {
        "schema_version": LATEST_SCHEMA_VERSION,
        "lesson_id": lesson_id,
        "revision": revision,
        "content_sha256": digest,
        "lesson_path": lesson_relative_path.as_posix(),
        "audio_manifest_path": manifest_relative_path.as_posix(),
    }
    if practice_manifest is not None:
        latest["practice_manifest_path"] = (
            relative_pack_directory / "practice" / "practice-manifest.json"
        ).as_posix()
    latest_payload = _encoded_json(latest)

    # Build outside the live path.  The directory-level rename makes the whole
    # pack visible at once, and the exclusive flag can never replace a prior
    # revision directory.  Every failure path removes the private staging tree.
    staging_directory = _build_staged_pack(
        pack_directory.parent,
        pack_directory.name,
        pack_payloads,
    )
    try:
        _commit_staged_pack(staging_directory, pack_directory, pack_payloads)
    finally:
        if _entry_exists(staging_directory):
            try:
                _remove_staging_directory(staging_directory)
            except OSError as error:
                raise PublishError(
                    f"Cannot clean pack staging directory {staging_directory}: {error}"
                ) from error

    # The pointer changes only after a complete new pack is live or an existing
    # immutable pack has been proven byte-identical.
    _atomic_write_if_changed(output_directory / "latest.json", latest_payload)
    return latest


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lesson", type=Path, help="Approved lesson JSON")
    parser.add_argument(
        "generated_audio_directory",
        type=Path,
        help="Generator output root, or the lesson's generated revision directory",
    )
    parser.add_argument("output_directory", type=Path, help="Static site output directory")
    parser.add_argument(
        "--practice-dir",
        type=Path,
        help="Optional practice-audio root or matching lesson revision directory",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    latest = publish_static_pack(
        args.lesson,
        args.generated_audio_directory,
        args.output_directory,
        args.practice_dir,
    )
    print(json.dumps(latest, ensure_ascii=False, indent=2, sort_keys=True))
    print("Published from existing local audio only; no TTS or network request was made.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PublishError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
