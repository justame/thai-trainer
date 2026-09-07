# Thai Trainer for iPhone

This is a focused personal SwiftUI practice player. The Mac generates approved
audio and publishes a static content folder; the iPhone keeps all playback local.
The main practice flow uses approved sentence-level clips so its timing, repetition,
speed, ordering, and auto-advance controls change real playback rather than only the
interface.

## Why generation stays on the Mac

- The iOS app contains no Google Cloud credential, login, authentication, or TTS
  client. Its only network job is downloading public static files.
- Text approval and paid-request authorization remain enforced by the existing Python
  generator before it reads credentials.
- Once generated, the tracks play entirely offline, including while the phone is
  locked.

The Xcode project also bundles these existing workspace folders as a fallback:

- `thai-learning/days/` as `days/`
- `thai-learning/audio/generated/` as `generated/`
- `thai-learning/audio/practice/` as `practice/`

No rebuild is required for a remotely published update.

## Updates from GitHub Pages

The app is zero-configuration. Its single compiled update location is:

```text
https://justame.github.io/thai-trainer/
```

When the main view first appears, the app immediately displays the last valid cached
pack or the bundled lesson. It then attempts one background refresh from GitHub Pages.
The compact **Updates: GitHub Pages** row also keeps a manual **Refresh** control for
checking again at any time.

The published directory should expose `latest.json` at the URL above. The app downloads
the referenced lesson, manifest, and exact four MP3s, validates their lesson/revision
IDs, filenames, content hash, and byte counts, then atomically activates the pack under
Application Support in `ThaiTrainerContent`. A failed refresh never replaces or hides
the current cached/bundled lesson. If `latest.json` has not been published yet, the app
shows only a short informational status and continues using its local content.

## Current behavior

Each saved day opens as a phrase-centered practice session with four independently saved modes:
Listen, Shadow, Recall, and Scene. Each mode can configure the Hebrew prompt, the
Hebrew-to-Thai pause, Thai repetitions, gaps, first/later Thai speed, sentence order,
auto-advance, and session looping. A collapsible **Words in this phrase** section shows
meaningful Thai chunks, tone-marked pronunciation, and Hebrew meaning for every released
core phrase. The adaptive mix records Easy/Again feedback and schedules reviews across
lesson days. The player validates each lesson's Hebrew/Thai clip pairs against byte
counts and SHA-256 values before enabling playback.

The existing four-track download/cache flow remains available for content refresh and
offline fallback. The app never falls back to device speech synthesis and never
requests TTS itself.

## Rebuild the bundled practice clips

After Day 1 text and generated Google audio have been approved, derive the sentence
clips from the already-authorized local cache:

```bash
python3 thai-learning/audio/build_practice_audio.py \
  thai-learning/days/day-001.json \
  thai-learning/audio/practice/day-001/r3
```

This command performs no provider initialization and no network request. It validates
the approved revision and exact cached request hashes, then writes a deterministic
manifest plus 20 Hebrew/Thai WAV pairs. It refuses to replace a different existing
bundle.

## Build in the simulator

From the workspace root:

```bash
xcodebuild \
  -project thai-learning/ios/ThaiTrainer.xcodeproj \
  -scheme ThaiTrainer \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Install on a personal iPhone

1. Open `ThaiTrainer.xcodeproj` in Xcode.
2. In the ThaiTrainer target's Signing & Capabilities tab, select your Personal Team.
3. Connect or pair the iPhone, select it as the run destination, and press Run.

No TestFlight or App Store release is needed for this personal workflow.

## Add audio later

Only after the written lesson is approved and a separate paid-TTS authorization
receipt exists, run the existing generator with its approval and authorization paths,
the explicit `--execute-paid-request` flag, and this output root:

```text
thai-learning/audio/generated
```

Keep Google Cloud authentication in the Mac's external Application Default
Credentials or `gcloud` configuration; never add access tokens, service-account JSON,
API keys, or other credentials to Swift, Info.plist, an Xcode configuration, or this
workspace.
