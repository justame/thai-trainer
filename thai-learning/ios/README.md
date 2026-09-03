# Thai Trainer for iPhone

This is a deliberately small personal SwiftUI player. The Mac generates approved
audio and publishes a static content folder; the iPhone downloads that folder and
always plays the resulting local MP3 files.

## Why generation stays on the Mac

- The iOS app contains no Azure key, login, authentication, or TTS client. Its only
  network job is downloading public static files.
- Text approval and paid-request authorization remain enforced by the existing Python
  generator before it reads credentials.
- Once generated, the tracks play entirely offline, including while the phone is
  locked.

The Xcode project also bundles these existing workspace folders as a fallback:

- `thai-learning/days/` as `days/`
- `thai-learning/audio/generated/` as `generated/`

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

The bundled Day 1 text remains readable when no download is available. Its Play
controls stay disabled until a valid four-file audio pack is downloaded (or valid
audio is bundled). The app never falls back to device speech synthesis and never
requests TTS itself.

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

Keep `AZURE_SPEECH_KEY` and `AZURE_SPEECH_REGION` in the desktop terminal environment;
never add them to Swift, Info.plist, an Xcode configuration, or this workspace.
