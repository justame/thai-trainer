#!/usr/bin/env python3
"""Build the Thai Trainer GitHub Pages tree from existing local audio only.

The default command writes a validated pack directly to ``docs``.  ``--dry-run``
validates into a disposable directory instead.  Git commit and push commands are
available only through the explicit ``--push`` flag.  This module never creates
audio, constructs a speech provider, reads speech credentials, or calls TTS.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LESSON = REPOSITORY_ROOT / "thai-learning" / "days" / "day-001.json"
DEFAULT_AUDIO_DIRECTORY = REPOSITORY_ROOT / "thai-learning" / "audio" / "generated"
DOCS_DIRECTORY = REPOSITORY_ROOT / "docs"


class PagesPublishError(RuntimeError):
    """Raised when the local Pages command cannot finish safely."""


def _load_publisher() -> ModuleType:
    module_path = Path(__file__).with_name("publish_static_pack.py")
    spec = importlib.util.spec_from_file_location("thai_static_publisher_for_pages", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load static publisher: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


publisher = _load_publisher()


def _run_git(
    repository_root: Path,
    *arguments: str,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    command = ["git", *arguments]
    try:
        return subprocess.run(
            command,
            cwd=repository_root,
            check=True,
            capture_output=capture_output,
            text=True,
        )
    except FileNotFoundError as error:
        raise PagesPublishError("Cannot run Git: git executable was not found") from error
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip()
        suffix = f": {detail}" if detail else ""
        raise PagesPublishError(
            f"Git command failed ({' '.join(command)}){suffix}"
        ) from error


def _commit_and_push(
    repository_root: Path,
    docs_directory: Path,
    latest: dict[str, Any],
) -> None:
    try:
        docs_path = docs_directory.resolve().relative_to(repository_root.resolve())
    except ValueError as error:
        raise PagesPublishError("Pages output must be inside the repository") from error
    if docs_path != Path("docs"):
        raise PagesPublishError("Only the repository's docs directory may be pushed")

    status = _run_git(
        repository_root,
        "status",
        "--porcelain",
        "--",
        docs_path.as_posix(),
        capture_output=True,
    )
    if status.stdout.strip():
        _run_git(repository_root, "add", "--", docs_path.as_posix())
        message = f"Publish Thai Trainer {latest['lesson_id']} r{latest['revision']}"
        # A path-limited commit ignores unrelated staged changes and records only docs/.
        _run_git(
            repository_root,
            "commit",
            "-m",
            message,
            "--",
            docs_path.as_posix(),
        )
    else:
        print("No docs changes to commit; pushing the current branch.")

    _run_git(repository_root, "push", "origin", "HEAD")


def publish_to_pages(
    lesson_path: Path,
    generated_audio_directory: Path,
    docs_directory: Path,
    *,
    repository_root: Path,
    dry_run: bool = False,
    push: bool = False,
) -> dict[str, Any]:
    """Validate/build a pack and optionally commit and push only ``docs``."""

    if dry_run and push:
        raise PagesPublishError("--dry-run and --push cannot be used together")

    if dry_run:
        with tempfile.TemporaryDirectory(prefix="thai-trainer-pages-check-") as temporary:
            return publisher.publish_static_pack(
                lesson_path,
                generated_audio_directory,
                Path(temporary),
            )

    latest = publisher.publish_static_pack(
        lesson_path,
        generated_audio_directory,
        docs_directory,
    )
    if push:
        _commit_and_push(repository_root, docs_directory, latest)
    return latest


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--lesson",
        type=Path,
        default=DEFAULT_LESSON,
        help=f"Approved lesson JSON (default: {DEFAULT_LESSON})",
    )
    parser.add_argument(
        "--audio-dir",
        type=Path,
        default=DEFAULT_AUDIO_DIRECTORY,
        help="Existing generated-audio root or matching lesson revision directory",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate a full pack in a temporary directory without changing docs or Git",
    )
    mode.add_argument(
        "--push",
        action="store_true",
        help="After a successful build, commit only docs and push origin HEAD",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        latest = publish_to_pages(
            args.lesson,
            args.audio_dir,
            DOCS_DIRECTORY,
            repository_root=REPOSITORY_ROOT,
            dry_run=args.dry_run,
            push=args.push,
        )
    except (publisher.PublishError, PagesPublishError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    print(json.dumps(latest, ensure_ascii=False, indent=2, sort_keys=True))
    if args.dry_run:
        print("Validated in a temporary directory; docs and Git were unchanged.")
    elif args.push:
        print("Built docs, committed only docs changes when needed, and pushed origin HEAD.")
    else:
        print("Built docs locally; Git was unchanged. Pass --push explicitly to commit and push.")
    print("Existing local audio only; no TTS request was made.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
