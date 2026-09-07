# Thai learning workspace

This directory is the durable source of truth for the personalized Thai program.

## Current state

- Days 1–5 are approved and released with immutable text and paid-TTS authorization
  receipts.
- Google Cloud Text-to-Speech is configured outside this workspace with billing and API access.
- The four generated MP3s are published at `https://justame.github.io/thai-trainer/`
  and have been verified by the iOS simulator's manifest and offline-cache path.
- Thai Trainer build 3 is installed on the paired iPhone. Its local diagnostic log confirms
  the actual cached MP3 decoded and started playing through the phone speaker.
- Thai Echo now records private, revision-bound Easy/Again feedback, schedules
  cross-day reviews on a 1/3/7/14/30-day ladder, previews three practice days, and
  derives a weekly summary from immutable events. The desktop adapts only from an
  export the learner explicitly shares.
- Every released core phrase has a reusable word-learning breakdown with Thai chunks,
  tone-marked pronunciation, and a concise Hebrew meaning.
- Full development lives in the private `justame/thai-echo` repository. The public
  `justame/thai-trainer` repository remains the credential-free GitHub Pages feed.

Day 1 revision 3 uses the Thai voice
`th-TH-Chirp3-HD-Erinome` and the Hebrew recall-prompt voice
`he-IL-Chirp3-HD-Charon`. Listening plays each Thai sentence first at `0.82`
and then at `1.0`; shadowing and recall use `0.9`; scenario playback uses
`1.0`. Pitch remains unchanged.

## Approval sequence

1. Review every core sentence and dialogue line in `days/day-001.json`.
2. Approve, edit, replace, or reject them in chat.
3. Create an immutable text-approval receipt for the final revision and hash.
4. Ask separately before creating an immutable paid-TTS authorization receipt.
5. Generate audio only when the approved hash and authorization hash match.

Changing any approved spoken text, order, provider, voice, or audio setting
creates a new revision and invalidates both gates. The approval hash therefore
binds the selected Google voices, speaking rates, pauses, and unchanged-pitch
policy as well as the spoken text.

## Files

- `state.json`: current course position and provider state.
- `days/day-001.json`: first written review pack and its approval/audio status.
- `templates/day.schema.json`: validation contract for daily packs.
- `templates/approval.schema.json`: immutable sentence-approval receipt contract.
- `templates/tts-authorization.schema.json`: separate paid-request authorization.
- `templates/learning-progress.schema.json`: private Easy/Again event contract.
- `templates/three-day-plan.schema.json`: non-mutating practice-preview contract.
- `templates/weekly-summary.schema.json`: derived weekly-summary contract.
- `templates/written-draft.schema.json`: written-only, non-publishable lesson draft.
- `curriculum/adaptive_curriculum.py`: offline planner and summary tool; no TTS,
  network, publisher, or Git capability.
- `drafts/`: rolling three-day written horizon, always pending review.
- `audio/generate_audio.py`: dry-run and paid-generation entry point.
- `publish/publish_static_pack.py`: validates and builds the public static folder
  from already-generated audio; it never contacts TTS.
- `publish/publish_to_pages.py`: safely validates/builds the same pack directly
  into repository `docs/`; Git commit/push requires an explicit `--push`.
- `../docs/index.html`: GitHub Pages landing page and current publishing status.
- `ios/ThaiTrainer.xcodeproj`: personal iPhone player with one-URL refresh, an offline
  last-good cache, spaced review, and word-by-word learning.
- `tests/test_audio_gate.py`: no-network approval-boundary tests.
- `prompts/daily-written-review.md`: reusable prompt for the daily scheduled review.

## Safe commands

These commands do not contact a speech provider:

```bash
python3 -m unittest discover -s thai-learning/tests -v
python3 thai-learning/audio/generate_audio.py thai-learning/days/day-001.json --dry-run
```

The generator defaults to dry-run behavior. Its billable execution path additionally
requires matching immutable approval and TTS-authorization receipts, the
`--execute-paid-request` flag, and Google Cloud billing, API access, and credentials
configured outside this workspace.

For an authorized run, the Mac obtains a short-lived token from Application Default
Credentials (`gcloud auth application-default login`) and a billing/quota project
from `GOOGLE_CLOUD_QUOTA_PROJECT`, `GOOGLE_CLOUD_PROJECT`, or the active `gcloud`
project. The generator checks local SoX MP3 support before contacting Google. It
keeps validated, hash-keyed sentence WAVs in the ignored
`audio/.google-segment-cache-v1/` directory so an interrupted retry does not request
the same speech again; that cache is outside `audio/generated/` and is never bundled
into the iPhone app.

## Deliver approved audio to the app

After approval and separately authorized generation have produced all four MP3s,
build the GitHub Pages folder locally with one command:

```bash
python3 thai-learning/publish/publish_to_pages.py
```

This updates `docs/` only after a complete approved pack and its exact immutable
text-approval and paid-request authorization receipts validate. It never calls TTS
and does not run Git. Pass `--dry-run` for disposable validation, or pass
`--push` explicitly to commit only `docs/` and push `origin HEAD`. In Thai Trainer,
use the published Pages directory's base URL and tap **Refresh**. The app downloads
the lesson and audio once, then plays the cached MP3s offline.

For a simulator-only local test, serve the folder from the Mac:

```bash
python3 -m http.server 8787 --directory docs
```

Then use `http://127.0.0.1:8787/` as the base URL in a Debug build. The published Day 1
revision 3 pack is immutable; a changed revision needs new approval, paid-TTS authorization,
generation, and publication.
