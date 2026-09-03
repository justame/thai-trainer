# Thai learning workspace

This directory is the durable source of truth for the personalized Thai program.

## Current state

- Day 1 is `pending_review`.
- No sentence is approved yet.
- No audio provider is configured.
- No audio has been generated and no paid request has been made.

## Approval sequence

1. Review every core sentence and dialogue line in `days/day-001.json`.
2. Approve, edit, replace, or reject them in chat.
3. Create an immutable text-approval receipt for the final revision and hash.
4. Ask separately before creating an immutable paid-TTS authorization receipt.
5. Generate audio only when the approved hash and authorization hash match.

Changing any approved spoken text, order, voice, or audio settings creates a new
revision and invalidates both gates.

## Files

- `state.json`: current course position and provider state.
- `days/day-001.json`: first written review pack and its approval/audio status.
- `templates/day.schema.json`: validation contract for daily packs.
- `templates/approval.schema.json`: immutable sentence-approval receipt contract.
- `templates/tts-authorization.schema.json`: separate paid-request authorization.
- `audio/generate_audio.py`: dry-run and paid-generation entry point.
- `publish/publish_static_pack.py`: validates and builds the public static folder
  from already-generated audio; it never contacts TTS.
- `publish/publish_to_pages.py`: safely validates/builds the same pack directly
  into repository `docs/`; Git commit/push requires an explicit `--push`.
- `../docs/index.html`: GitHub Pages landing page and current publishing status.
- `ios/ThaiTrainer.xcodeproj`: personal iPhone player with one-URL refresh and an
  offline last-good cache.
- `tests/test_audio_gate.py`: no-network approval-boundary tests.
- `prompts/daily-written-review.md`: reusable prompt for the daily scheduled review.

## Safe commands

These commands do not contact a speech provider:

```bash
python3 -m unittest discover -s thai-learning/tests -v
python3 thai-learning/audio/generate_audio.py thai-learning/days/day-001.json --dry-run
```

The generator defaults to dry-run behavior. Its paid execution path additionally
requires matching immutable approval and TTS-authorization receipts, the
`--execute-paid-request` flag, and Azure credentials supplied outside this workspace.

## Deliver approved audio to the app

After approval and separately authorized generation have produced all four MP3s,
build the GitHub Pages folder locally with one command:

```bash
python3 thai-learning/publish/publish_to_pages.py
```

This updates `docs/` only after a complete approved pack validates. It never calls
TTS and does not run Git. Pass `--dry-run` for disposable validation, or pass
`--push` explicitly to commit only `docs/` and push `origin HEAD`. In Thai Trainer,
use the published Pages directory's base URL and tap **Refresh**. The app downloads
the lesson and audio once, then plays the cached MP3s offline.

For a simulator-only local test, serve the folder from the Mac:

```bash
python3 -m http.server 8787 --directory docs
```

Then use `http://127.0.0.1:8787/` as the base URL in a Debug build. The publisher
currently refuses Day 1, by design, because its sentences have not yet been approved
and no authorized audio exists.
