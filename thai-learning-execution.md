---
schema_version: 1
plan: thai-learning-plan.md
instructions: none
program_status: in_progress
current_wave: weekly_integration
current_task: run_week_001_review
last_verified_commit: uncommitted-private-checkpoint
updated_at: 2026-09-07
---

# Execution Ledger: Personalized Thai Speaking and Listening Program

## Authority

- Canonical plan: `thai-learning-plan.md`
- Scoped instructions: none found in the workspace
- Verification environment: unversioned macOS workspace; Python 3 standard library;
  Xcode 26.3 and Swift 6.2.4; Google TTS used only for approval-bound,
  cost-authorized synthesis; public Pages and a paired iPhone used for release checks

## Protected Existing Changes

| Path | Owner | Reason it must be preserved |
| --- | --- | --- |
| `video-summary.md` | prior research task | Existing video analysis supplied program context |
| `youtube-research/**` | prior research task | Existing metadata, captions, and transcript evidence |
| `thai-learning/audio/**`, `thai-learning/publish/**`, `docs/**` | prior audio enablement task | Approved/generated Day 1 content and live Pages artifacts must remain unchanged unless the configurable player explicitly needs a derived local resource |
| `thai-learning/ios/ThaiTrainer/AudioPlayerModel.swift` | prior device-audio incident task | Physical-iPhone `.playback` session repair and diagnostics must be preserved |
| `thai-learning/ios/ThaiTrainer.xcodeproj/project.pbxproj` | prior device deployment task | Existing signing team and build-number changes must be extended rather than replaced |

## Task Board

| Wave | Task | Status | Owned paths | Closure gate |
| --- | --- | --- | --- | --- |
| `foundation` | `implement_review_and_audio_gate` | complete | `thai-learning-plan.md`, `thai-learning-execution.md`, `thai-learning/**` | Schema, dry-run gate tests, and first safe written-review workflow are complete; scheduling remains separately pending |
| `foundation` | `revise_first_pack_to_twenty_varied_sentences` | complete | `thai-learning-plan.md`, `thai-learning-execution.md`, `thai-learning/**` | First pack contains 20 cross-checked, varied sentences; contracts and no-network tests pass |
| `daily_review` | `approve_day_001_text` | complete | `thai-learning/days/day-001.json`, `thai-learning/approvals/day-001-r3-2026-09-03.json` | User approved all 20 Day 1 items for the exact revision-3 content hash |
| `offline_player` | `scaffold_offline_ios_player` | complete | `thai-learning/ios/**`, `thai-learning/audio/generated/**`, `thai-learning-plan.md`, `thai-learning-execution.md` | SwiftUI app and test target compile; app bundle contains Day 1; source scan finds no credential or network path |
| `offline_player` | `verify_offline_ios_player_runtime` | complete | `thai-learning/ios/**`, `thai-learning-execution.md` | Focused XCTest passed in an iOS simulator and screenshots confirm the 20-item list plus fail-closed missing-audio state |
| `remote_delivery` | `implement_static_audio_delivery` | complete | `thai-learning/ios/**`, `thai-learning/publish/**`, `thai-learning-plan.md`, `thai-learning-execution.md` | One base URL downloads and verifies `latest.json` plus a 20-sentence/four-track pack, retains one last-good offline cache, and the immutable publisher builds the static folder without contacting TTS |
| `public_delivery` | `publish_github_pages_and_hardcode_url` | complete | repository metadata, `docs/**`, `thai-learning/ios/**`, `thai-learning/publish/**`, plan, ledger, local automation | Public repo and Pages URL exist, app uses the built-in URL, authorized publish is one command, and the 11:00 job prepares text without audio generation or charges |
| `audio_provider_setup` | `configure_google_chirp3_erinome` | complete | `thai-learning/audio/**`, `thai-learning/tests/**`, `thai-learning/templates/**`, `thai-learning/days/day-001.json`, `thai-learning/state.json`, `thai-learning/publish/**`, affected iOS fixtures, `thai-learning-plan.md`, `thai-learning-execution.md`, provider documentation | Google Chirp 3 HD Erinome requests and learner/natural speeds are implemented and locally verified; pending text still prevents credentials or network use |
| `audio_enablement` | `configure_and_generate_day_001_audio` | complete | `thai-learning/audio/**`, `thai-learning/days/day-001.json`, `thai-learning/approvals/**`, `thai-learning/authorizations/**`, `thai-learning/state.json`, `thai-learning/ios/ThaiTrainer/AudioPlayerModel.swift`, `thai-learning/ios/ThaiTrainerTests/ThaiTrainerTests.swift`, `docs/**` | Generated files, public delivery, and direct physical-iPhone playback are verified |
| `offline_player` | `implement_configurable_practice_player` | complete | `thai-learning/ios/**`, approved Day 1 r4/r5 contracts and audio, `thai-learning/audio/**`, `thai-learning/publish/**`, approval/authorization receipts, `thai-learning-execution.md` | The native configurable player plays each core phrase plus its independently cued related variation; Day 1 and Day 2 remain selectable in the offline library; audio/publisher/iOS suites pass; signed build 5 installs and launches on the paired iPhone |
| `offline_player` | `fix_background_lock_playback` | complete | `thai-learning/ios/ThaiTrainer/PracticeSessionPlayer.swift`, `thai-learning/ios/ThaiTrainer/AudioPlayerModel.swift`, `thai-learning/ios/ThaiTrainer/NowPlayingCoordinator.swift`, `thai-learning/ios/ThaiTrainerTests/ThaiTrainerTests.swift`, build number, plan, ledger | Configured speech and silent pauses continue across screen lock; build 7 exposes a branded native Now Playing card with play/pause and phrase navigation; the paired-device user verified it after a non-destructive signed install |
| `weekly_integration` | `implement_adaptive_curriculum_loop` | complete | `thai-learning/ios/**`, `thai-learning/curriculum/**`, curriculum schemas/prompts, publisher gate tests, plan, state, ledger | Easy/Again persists privately; cross-day reviews, a non-mutating three-day preview, and weekly summaries work; publisher receipt checks and no-audio/no-publish automation boundaries pass |
| `weekly_integration` | `run_week_001_review` | in_progress | `thai-learning/state.json`, future day manifests | The first exported weekly summary is reviewed and the next written draft horizon is adapted |
| `product_upgrade` | `implement_vocabulary_and_private_source` | complete | `thai-learning/ios/**`, vocabulary contract, documentation, ledger, private Git remote | Every one of the 100 released sentences has a word-by-word learning view; existing adaptive Easy/Again review remains available across all lessons; the current source snapshot is simulator-verified and pushed to a dedicated private repository without changing the public Pages feed |
| `daily_review` | `approve_day_003_text` | complete | `thai-learning/days/day-003.json`, `thai-learning/approvals/day-003-r1-2026-09-06.json` | User approved the exact displayed 20 core and 20 related pairs; promoted manifest preserves every displayed and explanatory field and binds the spoken program to its canonical hash |
| `audio_enablement` | `generate_day_003_audio` | complete | Day 3 authorization receipt, `thai-learning/audio/generated/day-003/r1/**`, `thai-learning/audio/practice/day-003/r1/**`, cost gate/tests, state, ledger | User authorized Google TTS up to US$0.10; preflight bounded 3,034 characters at US$0.09102; four MP3s and 80 verified WAVs exist locally; nothing was published, pushed, built, or installed |
| `audio_enablement` | `release_day_005_timed_pipeline` | complete | Day 5 lesson/receipts, generated and practice audio, immutable Pages pack | Exact text and US$0.10 cap were approved; the single deterministic pipeline generated, packaged, verified, pushed, and deployed Day 5 in 3m58s from automation start to live-feed confirmation |
| `audio_enablement` | `release_day_004_pipeline` | complete | Day 4 lesson/receipts, generated and practice audio, immutable Pages pack | Exact text and US$0.09 cap were approved; the deterministic pipeline generated, packaged, verified, pushed, and deployed Day 4 in 3m44s from automation start to live-feed confirmation |

## Current Checkpoint

- Product upgrade complete: the existing adaptive Easy/Again loop remains the single
  review owner across all saved days, and every one of the 100 released core sentences
  now exposes meaningful Thai chunks, tone-marked romanization, and Hebrew meanings in
  one native disclosure. The vocabulary contract is optional for future lesson JSON;
  an app catalog covers immutable released packs without changing their approved hashes.
  The current five-day source snapshot is prepared for private `justame/thai-echo`;
  public `justame/thai-trainer` remains the static Pages feed only.
- Completed objective: the user-requested adaptive loop now records private Easy/Again
  feedback, schedules deterministic 1/3/7/14/30-day reviews across saved lesson
  packages, presents a non-mutating three-day practice preview and event-derived weekly
  summary, and maintains a rolling three-day written-only draft horizon that cannot
  generate or publish audio.
- Day 3 generation: the exact displayed 20 core and 20 related pairs were approved and
  promoted unchanged as revision 1, hash
  `8c4d57d06d4fbf4f9b24b808e3258304f973fda7c7a48b86214e6f087741df65`.
  The user's direct reply authorized Google TTS up to US$0.10. A cost-bound receipt
  limited the request to 3,333 characters; the complete no-cache plan used 3,034
  characters, estimated at US$0.09102 at the verified US$0.00003 rate.
- Local Day 3 artifacts: four generated MP3 tracks and the configurable 80-WAV bundle
  are present and independently checked for identity, request hash, byte count, SHA-256,
  mono 24 kHz Int16 format, and decodability. The immutable static pack and latest index
  were published by commit `17314a3`; no new app build or device installation occurred.
- Pending curriculum review: Day 6 is the earliest unresolved written draft and is
  non-provisional; Days 7 and 8 are provisional written-only candidates. All three now
  include 20 core/related pairs plus a four-line mini-dialogue. No explicit progress
  export exists, so no learner result was inferred or used to adapt them.
- Current weekly summary: the Bangkok week beginning 2026-09-07 contains zero review,
  Easy, Again, unique-phrase, or practice-day events because no progress export was
  available. The approved catalog therefore has 100 unseen phrases and zero scheduled
  review backlog. The summary is persisted under `thai-learning/summaries/` and linked
  from curriculum state without changing learner progress.
- Timed Day 5 release: the user's explicit benchmark request promoted the provisional
  Day 5 candidate out of order while leaving Day 4 unreleased. One pipeline command
  bound the approved hash `562c3573...f4ab`, consumed the US$0.10 authorization,
  generated four tracks and 80 practice WAVs, pushed `a8b77f7`, and advanced the live
  Pages feed. Automation-to-live elapsed time was 238 seconds; the earlier read-only
  review calculation took 0.32 seconds and user approval wait was excluded.
- Day 4 release: after the exact 20 core/related pairs and US$0.09 cap were displayed,
  the user approved them. The pipeline bound hash `8ebc79bb...d5d6b30`, consumed the
  authorization, produced four tracks and 80 practice WAVs, pushed `7892aa2`, and made
  Day 4 the live latest feed. Days 1–5 now all have approved published packs, despite
  Day 5 having been released first for the benchmark.
- Completed foundation: the phrase-centered configurable player supports independently
  cued core and related variations, persistent per-mode settings, and a non-destructive
  multi-day lesson library. Day 1 and Day 2 are both present and selectable; older days
  are retained when a newer day or same-day revision is downloaded.
- Release content: Day 1 revision 5 binds the eight approved masculine/phonetic Hebrew
  replacements to SHA-256
  `2ee17250cd9ca59e8218e62fcb1b8c6b3e80aed406aa7ddfe58a83100df1138c`.
  Exact cache preflight found only eight missing Hebrew requests (157 characters), and
  the authorized Google synthesis completed below the US$0.01 maximum authorization.
- Release state: public `main` tracks `origin/main` at `98c6ddd`; immutable Day 1 r5 was
  published by `b839796`, and `latest.json` now selects the separately approved Day 2 r1
  pack from `98c6ddd`. Signed Thai Echo 1.0 build 7 is installed and launched on `YaronN`.
- Durable/reusable artifacts: SwiftUI source and Xcode project under
  `thai-learning/ios/**`; approval-bound lessons and receipts; generated four-track packs;
  deterministic 80-WAV practice packages; immutable Pages packs. Disposable build caches
  remain under `/private/tmp/ThaiTrainerDerivedData` and
  `/private/tmp/ThaiTrainerDeviceSessionFix` and
  `/private/tmp/ThaiTrainerDeviceNowPlaying`.
- Reuse/ownership: `LessonPackageLoader` remains the canonical lesson/hash owner;
  `PracticeAudioPackageLoader` remains the validated sentence-audio owner;
  `LearningProgressStore` owns private immutable events; `ReviewScheduler` is the sole
  interval/queue/summary planner; and `PracticeSessionPlayer` consumes mixed-package
  queue items without duplicating scheduling rules. The publisher reuses the generator's
  pure receipt preflight and has no provider access.
- Written-only heartbeat 2026-09-07: refreshed the exact three-draft horizon to Day 6
  non-provisional and Days 7–8 provisional, each with 20 core/related pairs and a
  four-line dialogue. No progress export existed, so the drafts contain no inferred
  adaptation. No approval, authorization, TTS, audio derivation, publishing, commit,
  push, deployment, or spending occurred.
- Reusable artifacts: existing player/session/cache code and
  `/private/tmp/ThaiTrainerDeviceSessionFix`; durable artifacts: Swift/Python sources,
  tests, schemas, prompt, plan, ledger, and the locally generated Day 3 revision. Day 3
  TTS execution was explicitly approved and completed; no docs mutation, publication,
  commit, push, app build, or device install occurred.

## Evidence

### Acceptance or ATDD

- Status: complete
- RED command and observed failure: not_applicable; this is a new offline player
- GREEN command and observed result: after a user tap on the paired physical iPhone,
  the persisted diagnostic shows the speaker route, the real cached MP3 parsed as
  24 kHz Layer III, a duration of 163.368 seconds, and a successful `play()` call

### TDD

- Status: complete
- RED command and observed failure: the first revision 3 simulator test exposed
  different Python/Foundation renderings of decimal speaking rates in the content
  hash; the provider audit also identified encoder, retry-cache, and quota-project
  checks that had to move ahead of billable requests
- GREEN command and observed result: 22/22 audio tests and 10/10 publisher tests
  previously passed; the configurable-player simulator suite now passes 7/7, including
  exact 20-pair bundle validation, persisted bounded per-mode settings, and real sequence
  steps. Runtime screenshots also show the player advancing from Hebrew through the
  configured pause into Thai pass two of two.
- Variation RED: the focused approval-boundary tests failed as expected because
  `canonical_content` ignored `sentence.variation` and no
  `build_google_practice_variation_requests` owner existed. This proves r3 receipts
  cannot be reused safely for the requested spoken variations.
- Variation GREEN: Day 1 r4 hash
  `bdbea6f016c1c31a4144974b152035717b6f220af359ed90b437d2ca448f94e2`
  now binds every Hebrew/Thai variation and both supplemental rates. Matching approval
  and paid-request receipts pass the no-network dry run, and 25/25 audio tests pass,
  including exact 20-pair planning, mutation rejection, and persistent cache reuse.
- Hebrew normalization RED: `test_spoken_hebrew_rejects_slashes_dashes_and_latin_letters`
  failed for all four representative inputs because the canonical approval path still
  accepted slash, ASCII dash, Unicode dash, and Latin-letter spoken Hebrew.
- Hebrew normalization GREEN: the approval boundary now rejects slash, ASCII/Unicode
  dash, and Latin letters before provider access; Day 1 r5 uses the exact eight approved
  masculine/phonetic prompts, and the complete audio policy suite passes 26/26.
- Background-lock RED: the focused
  `testConfiguredPauseProducesPlayableBackgroundSilence` build failed because
  `PracticeSilenceAudio` did not exist. The existing player therefore had no playable
  pause media and still relied on foreground-only `Task.sleep` gaps.
- Background-lock GREEN: configurable pause steps now produce validated mono 24 kHz
  silent WAV media and play it through the same `AVAudioPlayer`/`.playback` session as
  speech. The app's existing `UIBackgroundModes=audio` declaration remains verified,
  persistent practice events are bounded to a 512 KiB rolling log, and the full iOS
  simulator suite passes 12/12.
- Adaptive-loop RED: focused tests initially had no owners for feedback persistence,
  exact revision/hash phrase identity, cross-day due-first scheduling, pure three-day
  forecasts, event-derived weekly summaries, or mixed-package practice queues.
- Adaptive-loop GREEN: `LearningProgressStore`, `ReviewScheduler`, and the mixed-package
  player now own those boundaries. The iOS simulator suite passes 20/20, including seven
  adaptive cases; the independent offline curriculum suite passes 9/9; and the publisher
  suite passes 12/12 with missing or stale approval/authorization receipts rejected
  before any audio inspection or output mutation.
- Day 3 cost-gate GREEN: the new test proves a Google plan at the exact character and
  dollar ceilings passes, while one character or US$0.000001 below the required ceiling
  fails during preflight. The full audio-policy suite now passes 27/27.

### Verification

| Command | Result | Source revision | Recorded at |
| --- | --- | --- | --- |
| `python3 -m unittest discover -s thai-learning/tests -v` | PASS: 8 tests | uncommitted | 2026-09-03 |
| `python3 -m unittest discover -s thai-learning/publish/tests -v` | PASS: 10 tests; immutable/idempotent publish, conflict preservation, interrupted-build cleanup, and Pages wrapper safety | `b039416` working tree | 2026-09-03 |
| `jq` structural summary of `thai-learning/days/day-001.json` | PASS: revision 2; 20 pending sentences; nine categories; maximum category count 4 | uncommitted | 2026-09-03 |
| `python3 thai-learning/audio/generate_audio.py thai-learning/days/day-001.json --dry-run` | PASS: safely blocked pending review; SHA-256 `45e667d6fa54b4f440bb9511dba8d329471d13b567db946422744edbc5bbd365`; no credentials, provider, or network | uncommitted | 2026-09-03 |
| `python3 /Users/yaronn/.codex/skills/plan-continuity/scripts/validate_execution_ledger.py thai-learning-execution.md` | PASS after checkpoint update | uncommitted | 2026-09-03 |
| `xcodebuild ... -destination 'generic/platform=iOS Simulator' ... build` | PASS: `BUILD SUCCEEDED` | uncommitted | 2026-09-03 |
| `xcodebuild ... -destination 'generic/platform=iOS Simulator' ... build-for-testing` | PASS: `TEST BUILD SUCCEEDED`; app and XCTest targets compile and link | uncommitted | 2026-09-03 |
| built app bundle inspection | PASS: app contains `days/day-001.json`; no audio manifest or MP3 is bundled | uncommitted | 2026-09-03 |
| iOS source inspection | PASS: public HTTPS static downloads only; no Azure credential, API key, authentication, TTS client, database, or custom endpoint in the app | uncommitted | 2026-09-03 |
| focused `xcodebuild ... test` on iOS simulator | PASS: 3/3; canonical hash, download/cache/integrity/playback fixture, pruning, and fallback | uncommitted | 2026-09-03 |
| generic iOS simulator build | PASS: final `BUILD SUCCEEDED` after integrity and cache fixes | uncommitted | 2026-09-03 |
| real simulator launch and screenshot capture | PASS: refreshed one-URL UI captured as `thai-learning/ios/screenshots/thai-trainer-static-url.png` | uncommitted | 2026-09-03 |
| independent static-delivery audit | PASS: no blockers after hash binding, immutable publish, fresh-index, fallback, pruning, and playback-fixture fixes | uncommitted | 2026-09-03 |
| final iOS zero-configuration build/test | PASS: built-in `https://justame.github.io/thai-trainer/`, automatic one-shot refresh, manual retry, and all 4 simulator tests | `b039416` working tree | 2026-09-03 |
| public repository push | PASS: public `justame/thai-trainer`, `main` pushed at `b0394162acaae1d8ece17845cc494ff9b4700299` | `b039416` | 2026-09-03 |
| GitHub Pages deployment | PASS: `https://justame.github.io/thai-trainer/` returned HTTP 200; expected pre-audio `latest.json` returned HTTP 404 | `b039416` | 2026-09-03 |
| daily local heartbeat | PASS: active automation `daily-thai-lesson-review` at 11:00; prompt explicitly prohibits audio/TTS/payment/push | external scheduler | 2026-09-03 |
| final secret scan | PASS: no high-confidence credential/private-key/embedded-password matches; sensitive file patterns ignored; third-party transcript kept local | `b039416` working tree | 2026-09-03 |
| independent public-delivery audit | PASS: live repo/Pages, hardcoded iOS URL and neutral 404 fallback, publisher isolation, 18/18 Python tests, 4/4 simulator tests, secret scan, and pre-audio gate all verified with no blockers | `b039416` working tree | 2026-09-03 |
| interactive simulator demonstration | PASS: iPhone 17 Pro on iOS 26.3 visibly launched the app, refreshed Pages, showed the expected no-update/audio-disabled state, and scrolled through the sentence list; 8.2-second MP4 plus three PNGs retained locally | `afb0c8f` | 2026-09-03 |
| audio-provider readiness check | PASS: Azure REST generator and four-track MP3 path exist; Azure key/region and CLI are absent; installed free local voices are Thai Kanya and Hebrew Carmit, while the configured male voices require Azure | `afb0c8f` | 2026-09-03 |
| Google lesson/schema validation | PASS: revision 3, 20 pending sentences, Erinome/Charon, four exact track definitions and rates, pitch 0; lesson instance and both metaschemas validate | uncommitted | 2026-09-04 |
| `python3 -m unittest discover -s thai-learning/tests -v` | PASS: 22/22; gate isolation, exact Google REST requests, language/voice switching, rate/order/hash binding, input limit, WAV validation, pre-call SoX check, persistent dedupe/retry, local silence, and legacy Azure coverage | uncommitted | 2026-09-04 |
| `python3 -m unittest discover -s thai-learning/publish/tests -v` | PASS: 10/10 with Google nested voices and provider-neutral request-hash verification | uncommitted | 2026-09-04 |
| pending revision 3 dry run | PASS: safely blocked before credentials/provider/network; SHA-256 `b0c14c9eb413c8b8452c83a6fe0653b14aa9c9e79821baf8ddc1ca34cb0170f8` | uncommitted | 2026-09-04 |
| real local SoX smoke | PASS: synthetic 24 kHz mono 16-bit WAV timeline plus exact silence produced 2,160 MP3 bytes with frame header `ff f3 64` | uncommitted | 2026-09-04 |
| revision 3 iOS simulator test | PASS: 4/4 on iPhone 17 Pro; bundled r3/hash, provider-neutral static refresh, integrity/cache fallback, and local playback fixture | uncommitted | 2026-09-04 |
| independent Erinome integration reviews | PASS after fixes: no remaining audio request, cost-safety, publisher, or iOS compatibility blocker | uncommitted | 2026-09-04 |
| authorized Google generation | PASS: 80 deduplicated Google Chirp 3 HD source segments assembled into four Day 1 r3 MP3s matching content SHA-256 `b0c14c9e...170f8` | uncommitted | 2026-09-04 |
| `soxi -D` and `afplay -t 1 scenario.mp3` | PASS: four decodable MP3s (62.304–231.480 seconds); macOS decoded scenario audio successfully | uncommitted | 2026-09-04 |
| `python3 -m unittest discover -s thai-learning/publish/tests -v` | PASS: 10/10 after making the pending-lesson test construct its own pending fixture rather than mutating the approved source lesson | uncommitted | 2026-09-04 |
| `python3 thai-learning/publish/publish_to_pages.py --dry-run` | PASS: approved four-track static pack validates without external calls | uncommitted | 2026-09-04 |
| `python3 thai-learning/publish/publish_to_pages.py --push` | PASS: immutable `docs/packs/day-001/r3` plus `latest.json` committed and pushed as `2355754` | `2355754` | 2026-09-04 |
| live Pages + iOS simulator | PASS: `latest.json` served revision 3; iPhone 17 Pro simulator downloaded, manifest-validated, cached all four tracks, and enabled every playback control | `2355754` plus uncommitted app source | 2026-09-04 |
| physical cached-pack inspection | PASS: paired iPhone contains all four r3 MP3s at the manifest byte counts; copied listening file hash is `d91b165...f167a`, matches the published source, and `afplay` decodes it locally | `2355754` plus uncommitted app source | 2026-09-04 |
| physical diagnostic build 2 | PASS: installed build 2 persisted `NSOSStatusErrorDomain -50` at `audio session configuration`; the real cached MP3 had not yet been decoded, eliminating download and decoder as the first failure | uncommitted | 2026-09-04 |
| physical audio-session repair | PASS: Apple documents that `.allowAirPlay` may only be explicitly set for `.playAndRecord`; removing it from the `.playback`/`.spokenAudio` session removed the device `-50` failure | uncommitted | 2026-09-04 |
| physical Debug build 3 + playback | PASS: signed, installed, and launched `com.yaron.ThaiTrainer` build 3 on `YaronN`; copied device log records `category=Playback`, `mode=SpokenAudio`, `route=Speaker`, parsed MP3 duration `163.368`, and `play_started` | uncommitted | 2026-09-04 |
| post-repair Swift test target | PASS: `xcodebuild build-for-testing` compiled and linked app plus tests; runtime simulator test host launch was interrupted by simulator infrastructure after the tests were built | uncommitted | 2026-09-04 |
| deterministic configurable-player audio derivation | PASS: `build_practice_audio.py` validated approved Day 1 r3 hash `b0c14c9e...170f8`, selected the exact authorized Hebrew/Thai cache requests, and produced 20 pairs/40 WAVs without provider initialization or network access; an idempotent rerun passed | uncommitted | 2026-09-04 |
| configurable-player simulator build and tests | PASS: generic `build-for-testing` and 7/7 focused tests on `Repose 393 Audit`; bundle pair count/order/integrity, approved lesson, refresh fallback, settings persistence/bounds, content hash, and configured sequence all pass | uncommitted | 2026-09-04 |
| configurable-player visual and runtime inspection | PASS: target-size main and native settings-sheet renders are clean; automated playback visibly advanced through Hebrew, the exact 3.0-second `Your turn` pause, and Thai pass 2 of 2 after fixing completion polling to use a monotonic pause-aware clock | uncommitted | 2026-09-04 |
| physical Debug build 4 install | PASS: signed device build completed for `YaronN`; app bundle contains all 40 validated WAVs; CoreDevice reports Thai Trainer `1.0` build `4` installed as `com.yaron.ThaiTrainer` | uncommitted | 2026-09-04 |
| physical Debug build 4 remote launch | NOT RUN: iOS denied the launch while `YaronN` was locked; installation is complete and simulator runtime verification passed | uncommitted | 2026-09-04 |
| variation-audio cache and cost preflight | BLOCKED SAFELY: Day 1 contains 20 written Hebrew/Thai variations, but exact request-hash inspection found 0/40 variation clips in the cache. Synthesizing all 851 characters is at most about US$0.026 at the current Chirp 3 HD list price before the monthly free allowance; no provider or network request was made | uncommitted | 2026-09-04 |
| variation-audio revision 4 generation and practice derivation | PASS: matching approval/authorization receipts produced the 40 missing variation clips; the complete practice bundle now contains 20 canonical and 20 related Hebrew/Thai pairs (80 WAVs) while reusing the existing authorized core cache | uncommitted | 2026-09-04 |
| persistent multi-day library XCTest | PASS: 10/10 tests, including Day 2 download without Day 1 deletion, switching back to Day 1, selection restoration after store recreation, same-day-only revision replacement, and per-package variation-audio lookup | uncommitted | 2026-09-04 |
| complete static publisher suite | PASS: 11/11 tests; immutable packs now include and validate the nested practice manifest and all 80 WAVs | uncommitted | 2026-09-04 |
| complete audio policy suite | PASS: 25/25 tests; variation approval binding, request planning, cache reuse, provider isolation, and local assembly remain green | uncommitted | 2026-09-04 |
| multi-day lesson-library visual inspection | PASS: target-size simulator capture shows the native full-height Saved lessons sheet, explicit retention/revision copy, selected-day state, and refresh action without the clipping seen in the first medium-height render | uncommitted | 2026-09-04 |
| `ui-ux-repair` implementation gate | PASS: 18 checks passed and one optical multi-row check is not applicable until a real second day exists; derived status is `Implementation complete — awaiting independent verification` | uncommitted | 2026-09-04 |
| Hebrew spoken-prompt validation RED/GREEN | PASS: the new focused test first failed on slash, ASCII dash, Unicode dash, and Latin-letter inputs; after the fail-closed validator was added, the complete audio policy suite passed 26/26 | uncommitted | 2026-09-04 |
| Day 1 r5 exact paid-request preflight | PASS: approval/authorization hash matched; exactly eight uncached Hebrew Charon requests totaling 157 characters were identified; maximum list-price exposure was US$0.004710, below the authorized US$0.01 cap | uncommitted | 2026-09-04 |
| authorized Day 1 r5 Google synthesis | PASS: generated only the eight missing approval-bound Hebrew requests, retained Thai Erinome and Hebrew Charon, and assembled four revision-5 tracks plus 20 core/variation pairs for hash `2ee17250...1138c` | uncommitted | 2026-09-04 |
| deterministic Day 1 r5 practice derivation | PASS: generated 20 core/variation sentence sets and 80 validated WAVs from the authorized cache without additional provider calls | uncommitted | 2026-09-04 |
| complete post-r5 audio and publisher suites | PASS: 26/26 audio tests and 11/11 immutable static-publisher tests | uncommitted | 2026-09-04 |
| Day 1 r5 public release | PASS: immutable `docs/packs/day-001/r5` and its index update were committed and pushed as `b839796`; the live immutable lesson returns revision 5 with 20 sentences | `b839796` | 2026-09-04 |
| final two-day iOS simulator suite | PASS: 10/10 tests after updating the revision-bound fixture; bundled and remote Day 1 r5 practice, non-destructive Day 2 retention, selection restoration, and same-day revision replacement all pass | uncommitted | 2026-09-04 |
| real two-day lesson-library visual inspection | PASS: target-size capture `outputs/thai-trainer-two-day-library.png` shows Day 1 and Day 2 together, with Day 1 selectable after Day 2 exists | `98c6ddd` plus uncommitted app source | 2026-09-04 |
| physical Thai Echo 1.0 build 5 release | PASS: signed device build succeeded; app bundle contains both lesson manifests and Day 1's 80-WAV practice package; install without uninstall and terminate-existing launch both succeeded on paired iPhone `YaronN` | `98c6ddd` plus uncommitted app source | 2026-09-04 |
| physical build-5 log and cache inspection | PASS WITH LIMITATION: no Thai Echo crash report or new persisted playback failure exists; the historical diagnostic ends with successful speaker-route preparation and playback for Listening, Shadowing, and Recall. The active Day 2 cache contains the complete 20-sentence/80-WAV practice package, and copied Hebrew/Thai sentence-1 WAVs match manifest byte counts and SHA-256 values and decode as mono 24 kHz Int16. A live console launch emitted no app error, but the configurable sentence player currently persists neither success events nor its OSLog-only failures for retrospective inspection | `98c6ddd` plus uncommitted app source | 2026-09-04 |
| background-lock focused RED/GREEN | PASS: focused test first failed because `PracticeSilenceAudio` was absent, then passed with a playable 1.25-second RIFF/WAVE silence segment at mono 24 kHz Int16 | `98c6ddd` plus uncommitted app source | 2026-09-04 |
| post-background-repair iOS simulator suite | PASS: 12/12, including exact core/variation packages, configuration sequencing/persistence, two-day cache retention, app background-mode declaration, and playable silent pause media | `98c6ddd` plus uncommitted app source | 2026-09-04 |
| signed physical build 6 install | PASS WITH DEVICE CHECK PENDING: signed Debug build succeeded, built Info.plist contains `UIBackgroundModes = [audio]`, and Thai Echo 1.0 build 6 installed on `YaronN` without uninstalling or deleting saved content. Remote launch was safely denied because the phone was locked; post-lock phrase advancement still needs one user-started playback run | `98c6ddd` plus uncommitted app source | 2026-09-04 |
| Now Playing presentation contract | SOURCE/BUILD VERIFIED: a focused XCTest encodes phrase title, Thai Echo/Day/mode identity, live phase, segment timing, and queue position; build 7 compiles it. Its simulator execution was not counted because CoreSimulator's test-host service crashed while launching, so the physical-device check is the runtime evidence for this change | `98c6ddd` plus uncommitted app source | 2026-09-04 |
| signed physical build 7 Now Playing install | PASS: signed Debug build succeeded, codesign verification passed, built Info.plist retains `UIBackgroundModes = [audio]`, and Thai Echo 1.0 build 7 installed non-destructively on `YaronN` | `98c6ddd` plus uncommitted app source | 2026-09-04 |
| physical build-7 lock-screen UI | PASS: user launched a practice session, locked the phone, and confirmed the branded native media card and lock-screen controls work well | user physical-device confirmation | 2026-09-04 |
| adaptive iOS build-for-testing | PASS: app and test targets compile and link with the new progress, scheduler, mixed-queue, weekly-summary, and three-day-preview owners | `98c6ddd` plus uncommitted app source | 2026-09-06 |
| focused adaptive iOS simulator cases | PASS: 7/7 for Easy ladder/Again reset, revision/hash isolation, persistence/corruption, due-before-new ordering, pure three-day preview, weekly summary, and cross-package playback | `98c6ddd` plus uncommitted app source | 2026-09-06 |
| full adaptive iOS simulator suite | PASS: 20/20 on iPhone 17 Pro; existing player/library/background behavior remains green with the adaptive loop | `98c6ddd` plus uncommitted app source | 2026-09-06 |
| adaptive main-screen visual check | PASS: iPhone 17 Pro render cleanly shows the due/new adaptive card, Start mix action, existing mode/player hierarchy, and no clipping | `98c6ddd` plus uncommitted app source | 2026-09-06 |
| `python3 -m unittest discover -s thai-learning/curriculum/tests -v` | PASS: 7/7; offline hashing, exact feedback validation, spacing/revision isolation, pure forecast, weekly derivation, three-slot horizon, and rejection of publishable audio fields | `98c6ddd` plus uncommitted curriculum source | 2026-09-06 |
| offline adaptive curriculum command with no progress export | PASS: no feedback was inferred; preview contains six new phrases today, six simulated reviews tomorrow, and six further new phrases on day three; weekly counts remain zero; draft horizon is Day 3 plus provisional Days 4 and 5 | `98c6ddd` plus uncommitted curriculum source | 2026-09-06 |
| written-only Day 3–5 validation | PASS: three pending-review drafts, exactly 20 ordered phrases and 20 pending checklist entries each, category cap respected, and no `voices` or `audio_program` fields | `98c6ddd` plus uncommitted drafts | 2026-09-06 |
| `python3 -m unittest discover -s thai-learning/publish/tests -v` | PASS: 12/12; exact immutable approval and paid-authorization receipts are required before generated-audio inspection or publisher output | `98c6ddd` plus uncommitted publisher source | 2026-09-06 |
| `python3 -m unittest discover -s thai-learning/tests -v` | PASS: 26/26 audio safety and generation-policy tests; all provider paths remained mocked or blocked | `98c6ddd` plus uncommitted source | 2026-09-06 |
| adaptive-loop JSON syntax validation | PASS: state, all three written drafts, and all four new schemas parse with `jq empty` | `98c6ddd` plus uncommitted source | 2026-09-06 |
| daily adaptive curriculum heartbeat | PASS: active `Daily Thai Echo Curriculum` automation at 11:00; it is attached to this thread and explicitly limited to written drafts/summaries with no approval, audio, publishing, Git, or deployment authority | external scheduler | 2026-09-06 |
| adaptive-loop external-effects audit | PASS: no TTS/provider request, audio generation or derivation, lesson approval, receipt creation, publishing, docs mutation, Git commit/push, or physical-device deployment was run | operator audit | 2026-09-06 |
| exact Day 3 promotion | PASS: the skill validator reports 20 core pairs, 20 related pairs, four ordered tracks, and canonical hash `8c4d57d0...df65`; a separate parity check confirms every draft sentence field is unchanged | `98c6ddd` plus uncommitted Day 3 source | 2026-09-06 |
| Day 3 immutable approval and cost authorization | PASS: exact ordered IDs and hash are bound to approval and Google authorization receipts; the authorization records US$0.10, US$0.00003 per character, and a 3,333-character ceiling | uncommitted receipts | 2026-09-06 |
| Day 3 paid-request preflight | PASS: 200 raw speech placements deduplicate to 120 unique provider requests totaling 3,034 characters; zero were cached; maximum estimated list-price exposure US$0.09102; safe dry run reported READY and no credential/provider/network access | uncommitted Day 3 source | 2026-09-06 |
| authorized Day 3 Google synthesis | PASS: the single approved execution generated four MP3 tracks and cached all 120 exact requests for canonical hash `8c4d57d0...df65`; no retry was performed | uncommitted generated artifacts | 2026-09-06 |
| Day 3 MP3 verification | PASS: exactly four non-empty, request-hash-bound tracks; listening 183.480 s, shadowing 221.208 s, recall 244.776 s, scenario 70.368 s; all decode with SoX | uncommitted generated artifacts | 2026-09-06 |
| Day 3 configurable bundle | PASS: deterministic offline builder produced exactly 20 core/related sets and 80 WAVs; every declared byte count and SHA-256 matches and every clip is mono 24 kHz Int16 PCM; idempotent rebuild passed without provider/network access | uncommitted practice artifacts | 2026-09-06 |
| post-Day-3 safe preflight and policy suites | PASS: second dry run remains READY with no credential/provider/network access; audio suite 27/27 and publisher suite 12/12 | `98c6ddd` plus uncommitted source | 2026-09-06 |
| post-Day-3 adaptive horizon | PASS: approved lessons now total 60 new phrases; earliest unresolved draft is Day 4, Day 5 is provisional, and Day 6 is a written-draft slot | uncommitted curriculum state | 2026-09-06 |
| Day 3 release boundary | PASS: no publisher command, docs mutation, Git commit/push, iOS build, or physical-device installation was run | operator audit | 2026-09-06 |
| first Bangkok weekly summary | PASS: no progress export was supplied, so the event-derived summary records 0 reviews, 0 Easy, 0 Again, 0 due reviews, and 60 unseen approved phrases for 2026-08-31 through 2026-09-07 | uncommitted written-only curriculum state | 2026-09-06 |
| second Bangkok weekly summary | PASS: no progress export was supplied, so the event-derived summary records 0 reviews, 0 Easy, 0 Again, 0 due reviews, and 100 unseen approved phrases for 2026-09-07 through 2026-09-14 | uncommitted written-only curriculum state | 2026-09-07 |
| refreshed Day 4–6 written horizon | PASS: exactly three top-level draft JSONs remain; Day 4 is non-provisional, Days 5–6 are provisional, and each has 20 ordered pending pairs, a four-line pending mini-dialogue, a complete checklist, category counts capped at four, and no voice or audio-program fields | uncommitted drafts | 2026-09-06 |
| written heartbeat external-effects audit | PASS: no learner feedback was inferred; no approval or authorization receipt, credential, TTS/provider request, audio derivation, publishing, docs mutation, Git operation, build, deployment, or spend occurred | operator audit | 2026-09-06 |
| post-refresh curriculum verification | PASS: 9/9 offline curriculum tests; Day 4–6 horizon and persisted weekly summary exactly match a fresh deterministic CLI run; no duplicate core Thai exists across approved Days 1–3 and drafts 4–6; JSON syntax, ledger structure, and `git diff --check` pass | `98c6ddd` plus uncommitted written-only source | 2026-09-06 |
| 2026-09-07 written horizon verification | PASS: 9/9 offline curriculum tests; exactly three top-level drafts; Day 6 non-provisional and Days 7–8 provisional; all contain 20 core/related pairs, 20 checklist entries, and four dialogue lines | uncommitted written-only source | 2026-09-07 |
| Day 3 static release | PASS: the approval-bound existing MP3 and 80-WAV practice pack was validated without TTS, committed only under `docs/` as `17314a3`, pushed to `origin/main`, deployed successfully by GitHub Pages, and the cache-bypassed live `latest.json` selects Day 3 revision 1 with canonical hash `8c4d57d0...df65` | `17314a3` | 2026-09-06 |
| timed Day 5 pipeline release | PASS: review calculation 0.32s; approval-to-push pipeline 135.87s; GitHub Pages completed successfully and cache-bypassed live `latest.json` selected Day 5 at 238s total. Verified 4 MP3s, 80 WAVs, matching manifests/hash, immutable approval and US$0.10 authorization, consumption marker, and `origin/main` commit `a8b77f7` | `a8b77f7` | 2026-09-06 |
| Day 4 pipeline release | PASS: approval-to-push pipeline 175.65s; live feed selected Day 4 at 224s; full deployment and local integrity checks completed by 248s. Verified 4 MP3s, 80 WAVs, matching manifests/hash, immutable approval and US$0.09 authorization, consumption marker, successful Pages run, and `origin/main` commit `7892aa2` | `7892aa2` | 2026-09-06 |
| private-source vocabulary upgrade | PASS: generic simulator build-for-testing; 21/21 iPhone 17 Pro XCTest cases; all 100 released sentences have non-empty, exact-cover word breakdowns; 9/9 curriculum tests; normal and adaptive simulator captures; UI repair gate 19/19 with self-review boundary retained; secret-pattern scan found no credential or private-key match | uncommitted private checkpoint | 2026-09-07 |

## Decisions and Blockers

- Decisions: daily adaptive delivery; 20 varied written items per approval pack with
  up to six activated per practice session; 30 focused
  minutes plus passive listening; official cloud TTS only after approval and separate
  cost authorization; desktop-only generation and a credential-free SwiftUI player;
  one public static base URL plus an offline cache
  replaces rebuild-per-audio-pack delivery and requires no custom endpoint; on
  2026-09-03 the user rejected Azure Niwat/Premwadee quality and selected Google
  `th-TH-Chirp3-HD-Erinome` after hearing Google's official Thai sample.
- Player implementation decision: real timing and speed controls require sentence-level
  media rather than the four pre-rendered session MP3s. The app therefore derives and
  validates 20 Hebrew/Thai clip pairs from the already-authorized local Google cache;
  it performs no new TTS request and incurs no new provider charge.
- Variation decision: the existing `variation` values are useful related formulations,
  but several change specificity, time, or outcome rather than being strict synonyms.
  To avoid misleading recall audio, a variation will have its own Hebrew cue whenever
  Hebrew prompting is enabled, followed by its Thai form. Making these fields spoken
  content requires a new approval-bound revision and separate paid-request receipt.
- Resolved Hebrew speech authorization: at 2026-09-03T21:20:31Z the user approved the
  exact eight replacements in the retained review and authorized up to US$0.01 of
  Google TTS synthesis. Revision 5 keeps `he-IL-Chirp3-HD-Charon`, uses masculine
  spoken Hebrew, spells `QR` and `Rabbit` phonetically, and rejects future slash, dash,
  or Latin-letter content in spoken Hebrew prompts before provider access. Exact
  preflight limited the request to 157 characters (US$0.004710 maximum at the checked
  Chirp 3 HD list price), and the authorized generation completed successfully.
- Resolved authorization: on 2026-09-04 the user approved the exact 20 variation pairs
  in the retained review and authorized generation up to US$0.03. Revision 4 must bind
  the variation text and settings into both immutable receipts before provider access.
- Resolved incident: `.allowAirPlay` was passed explicitly with the `.playback` category.
  iOS rejects that combination with parameter error `-50`; playback categories already
  support AirPlay implicitly. Build 3 removes the invalid option and preserves a local
  diagnostic log for any future file/session/player failure.
- Observed diagnostic limitation: `LocalAudioPlayer` persists detailed track-level
  selection, file, session, preparation, start, and failure events, but the newer
  `PracticeSessionPlayer` previously wrote only failures to transient OSLog. Build 6
  resolves this by recording session, speech-clip, silent-pause, stop, finish, and
  failure events with phrase IDs and phases in the same bounded persistent log.
- Lock-screen UI decision: use iOS's genuine Now Playing card instead of imitating a
  Spotify screen inside the app. Build 7 publishes Thai Echo cover art, Thai phrase,
  Day/mode/phrase position, current phase, segment progress, and native play/pause plus
  previous/next phrase commands; it deliberately does not expose a seek control because
  a configurable sentence sequence has no stable whole-session duration.
- Approved reordering: the user's 2026-09-03 request moves the offline player foundation
  and static delivery ahead of text approval and audio enablement.
- Approved external actions: on 2026-09-03 the user explicitly authorized creating a
  Git repository and pushing it; selected target is public `justame/thai-trainer` with
  GitHub Pages at `https://justame.github.io/thai-trainer/`.
- Public delivery result: repo and Pages are live; the app URL is compiled in and the
  editable URL field is removed. Full locally extracted YouTube captions remain local
  and ignored rather than being republished.
- 2026-09-07 curriculum decision: retain Day 6 as the only draft presented for current
  review and keep Days 7–8 provisional. With no explicit progress export, record only
  the derived zero-event weekly totals and do not infer feedback or learner adaptation.
- Adaptive scheduling decision: Easy advances through 1/3/7/14/30-day intervals;
  Again resets the Easy streak, becomes due after ten minutes, and is placed at the end
  of the active six-item mix. Due phrases across all saved lesson revisions precede
  unseen phrases. Phrase identity includes lesson ID, revision, canonical content hash,
  and sentence ID so revised text never inherits stale progress.
- Privacy and forecasting decision: progress is stored only in the app's Application
  Support directory and leaves the app only through an explicit share action. Desktop
  curriculum adaptation accepts only that explicit export; without it, weekly metrics
  remain empty and written drafts disclose that they are unadapted. Three-day previews
  simulate Easy results in memory and never mutate real progress.
- Written-draft decision: after Day 3 approval, the rolling horizon is Day 4 plus
  provisional Days 5 and 6. Drafts live outside the publishable `days/` directory,
  remain `pending_review`, include a short mini-dialogue, and structurally forbid voice
  and audio-program fields. Promoted draft history moves to `drafts/archive/` and does
  not count toward the three upcoming slots. Approval, paid authorization, audio
  generation, and publishing remain separate actions.
- Day 3 authorization decision: the user's “Both looks good, generate” reply was treated
  as approval of the exact displayed core/related pairs and the separately stated
  US$0.10 Google cap. The promoted text was byte-for-byte preserved. The one paid run
  used 3,034 authorized characters at an estimated US$0.09102 maximum and succeeded.
- Day 3 publication decision: the user's later “Push it already” request authorized the
  existing release helper to publish the already-generated Day 3 pack and advance the
  remote latest index. The helper committed only `docs/`, preserved Days 1 and 2, and
  did not contact TTS, build the app, or install a device.
- Timed Day 5 decision: the user explicitly selected Day 5 as an out-of-order benchmark,
  approved the exact displayed core/related text, authorized Google TTS up to US$0.10,
  and requested publication. Day 4 remains unreleased. Approval wait is reported
  separately from deterministic automation time.
- Day 4 completion decision: the user's “appvoed” reply was accepted as approval of the
  immediately preceding exact Day 4 review, US$0.09 Google cap, and publication request.
  The consumed authorization prevents the skill from replaying that paid request.
- Future paid-run blocker: the new cap gate safely bounds each invocation, but historical
  schema-1 authorizations remain replayable after deliberate cache/output removal and do
  not provide an atomic cumulative-spend ledger. Do not reuse the Day 3 authorization or
  execute another paid request until one-shot/cumulative consumption is implemented.
- Private-source decision: `justame/thai-echo` is the private development source of
  truth. The public `justame/thai-trainer` remote is retained unchanged as the Pages
  content endpoint; this avoids breaking installed apps and does not put learner
  progress or credentials into public delivery.

## Next Action

- Action: present Day 6 as the next non-provisional written review and retain Days 7–8
  as provisional; adapt only from an explicit learner progress export or direct report.
- Owned paths: `thai-learning/drafts/day-006.json`, `thai-learning/drafts/day-007.json`,
  `thai-learning/drafts/day-008.json`, `thai-learning/state.json`, and this ledger.
- Verification command: `python3 -m unittest discover -s thai-learning/curriculum/tests -v`

## Handoff

- Resume by reading scoped instructions, the canonical plan, and this ledger.
- Inspect Git status and relevant diffs before editing.
- Run the ledger validator.
- Verify the last checkpoint when its evidence is uncertain.
- Continue only with the written Day 6 review under **Next Action**. Do not generate
  audio, mutate immutable Pages packs, or replay any consumed paid authorization.
