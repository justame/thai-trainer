# Personalized Thai Speaking and Listening Program

## Objective

Build a six-week, adaptive Thai program from Yaron's real-life language needs. The
program develops recall, listening, pronunciation, and spontaneous use rather than
teaching disconnected vocabulary. Hebrew is the recall language; Thai output uses
natural male forms such as `ผม` and `ครับ` when context calls for them.

The first cycle targets 120 durable sentences in six broad, 20-sentence review packs.
After a pack is approved, daily practice activates a manageable subset rather than
trying to memorize all 20 at once. Six weeks is a training cycle, not a guaranteed
fluency deadline.

## Non-negotiable approval and cost gate

1. Every spoken item is presented in writing before audio generation: 20 varied core
   sentences plus any dialogue lines.
2. The user may approve, edit, replace, or reject each item.
3. Approval is stored as an immutable receipt that locks a hash of the exact Thai and
   Hebrew text, order, voices, and audio-program settings.
4. Paid-request authorization is stored as a separate immutable receipt tied to the
   same content hash.
5. Drafting, validation, rendering, scheduling, and dry runs must not call a speech
   service or incur cost.
6. No subscription, credit purchase, credential creation, or paid request occurs
   without explicit user authorization.

Changing approved text, order, voice, or audio-program settings creates a new revision
and invalidates the old receipts. Existing audio is retained as historical evidence but
is never presented as matching the new revision.

## Daily workflow

At 11:00 Asia/Bangkok, the course returns to the ongoing Thai-learning context and
prepares or continues one written review pack. It must not generate audio. A pack
contains:

- 20 Hebrew recall prompts drawn across several real-life categories;
- natural spoken Thai;
- tone-marked romanization;
- literal structure and a short context/politeness note;
- one reusable pattern and one useful variation per sentence;
- an optional mini-dialogue whose every line is separately visible for approval;
- due reviews from days 1, 3, 7, 14, and 30;
- an explicit approval checklist.

After approval and separate audio authorization, the approved pack can produce:

- a normal-speed listening track;
- a pause-and-repeat track;
- a normal-speed shadowing track;
- a Hebrew-cue recall track;
- a mini-dialogue track when dialogue lines were approved.

The target voices are `th-TH-NiwatNeural` for Thai and `he-IL-AvriNeural` for Hebrew.
Tracks use SSML pauses rather than slowed or distorted speech. Proper names and unusual
phrases must be manually reviewed before audio authorization.

## Personal offline iPhone player

The fastest personal-use architecture keeps generation and playback separate and uses
plain static file hosting rather than a custom API:

- The desktop owns text approval, paid-request authorization, cloud credentials, and
  audio generation.
- A publishing step copies the approved lesson, manifest, and MP3s into one static
  folder and writes a tiny `latest.json` index. That folder can be served from any
  public HTTPS file host; no database, server code, login, or token is required.
- A small SwiftUI app fetches `latest.json`, downloads the referenced lesson and four
  MP3s once, and stores the last valid pack locally for offline playback. The one base
  URL is ordinary non-secret configuration.
- Before approved audio exists, the app may show the written lesson but must report
  that audio is unavailable and keep playback disabled. It must not substitute device
  speech synthesis for unapproved audio.
- Before a remote URL is configured or a download succeeds, the bundled written lesson
  remains available and playback stays disabled. A failed refresh never removes the
  last working local pack.

The first player release supports the sentence list, track-level play/pause and
seeking, and background listening for the existing `listening`, `shadowing`, `recall`,
and `scenario` MP3s. Sentence-by-sentence playback is deferred because the current
generator produces complete lesson tracks without per-sentence files or timestamps.

The static host contract is:

```text
latest.json
packs/day-001/r2/lesson.json
packs/day-001/r2/audio-manifest.json
packs/day-001/r2/listening.mp3
packs/day-001/r2/shadowing.mp3
packs/day-001/r2/recall.mp3
packs/day-001/r2/scenario.mp3
```

For the personal deployment, the workspace is published as the public GitHub
repository `justame/thai-trainer`. GitHub Pages serves the static content from
`docs/` at `https://justame.github.io/thai-trainer/`; that base URL is the app's
built-in default, so normal use needs no URL entry. The app checks that location on
launch and retains a manual Refresh control plus its last-good offline cache.

A local 11:00 Asia/Bangkok Codex heartbeat prepares or continues the next written
review pack only. It never approves text on the user's behalf, generates speech, or
authorizes a paid request. After explicit text and cost authorization, one local
publish command validates existing generated audio, updates `docs/`, and pushes the
new immutable pack to the same repository.

## Practice and adaptation

The focused session lasts 30 minutes:

1. Five minutes of delayed recall from Hebrew.
2. Eight minutes learning a rotating subset of up to six approved sentences and one
   reusable structure.
3. Seven minutes recognizing normal-speed Thai.
4. Five minutes shadowing and comparing a self-recording.
5. Five minutes using the material in an improvised role-play.

Optional passive listening lasts 20–40 minutes during commuting, walking, or chores.
Each review is scored `immediate`, `hesitant`, `incorrect`, or `not_understood`. A
sentence becomes `automatic` only after correct production and normal-speed recognition
on two separated days. Weekly delayed recall below 80% reduces the next week's new
material until weak sentences recover.

New questions from the Thai project enter a sentence inbox. Recurring daily-life needs
outrank one-off specialist translations. Every 20-sentence pack must span multiple
categories; no single category may occupy more than four slots unless the user asks
for a themed pack.

## Program waves and gates

1. **Foundation:** create the durable plan, execution ledger, day schema, safe audio
   generator, tests, and the first pending review pack. Gate: local validation passes
   without network access or credentials.
2. **Text review:** present 20 varied written items per pack and record user decisions.
   Gate: exact text is approved and its approval hash is stored.
3. **Offline player foundation:** create and locally build the personal SwiftUI player
   with lesson text and fail-closed handling for absent or invalid audio. Gate: the app
   builds without network access, contains no credentials, and disables playback when
   no valid generated manifest exists.
4. **Static content delivery:** add the deterministic publisher and one-URL iOS
   downloader/cache. Gate: a locally served fixture downloads, validates, plays from
   cache, and remains available after the server stops.
5. **Public personal deployment:** create and push `justame/thai-trainer`, enable
   GitHub Pages from `docs/`, hardcode the Pages base URL, and add the local daily
   written-review heartbeat plus one-command authorized publish path. Gate: the Pages
   URL is live, the app builds with that default, and the scheduler cannot generate
   or pay for audio.
6. **Audio enablement:** only after separate authorization, configure official cloud
   speech credentials outside the workspace and generate the approved tracks. The
   generator validates both receipts before reading credentials or creating a provider
   client. Gate: files match the approved hash and play on phone and desktop.
7. **Weekly integration:** run an unscripted conversation, record errors, and reprioritize
   the next week's queue. Gate: 80% delayed recall and recognition, or a documented
   remediation week.

## Acceptance criteria

- A pending or edited pack cannot make a network request.
- An approved pack without paid-request authorization cannot make a network request.
- A mismatched approval or authorization hash cannot make a network request.
- A dry run never requires credentials and never makes a network request.
- Generated file metadata records day, content hash, provider, voices, and generation
  time.
- The personal iOS app has no speech-service secret or authenticated backend and
  rejects missing, stale, incomplete, or size-mismatched audio packs as unavailable.
- The app can display all 20 written items before audio exists and can play all four
  downloaded tracks offline after a matching manifest exists.
- Publishing requires only copying a static folder; changing `latest.json` makes a new
  pack available without rebuilding or reinstalling the app.
- Weekly target: at least 80% delayed recall, 80% normal-speed recognition, and four of
  each six-sentence active subset used successfully in role-play.
- Six-week target: three mixed daily-life conversations with limited prompting and the
  ability to recover using Thai clarification phrases.

## Source context

- Video notes: `video-summary.md`
- Extracted transcript: `youtube-research/_wYjXdt4a2I/en/transcript.txt`
- ChatGPT project: `Thai language learning`
- Initial source thread: `สรุป שיטת לימוד שפה` / thread
  `6a9878d4-8760-83ec-8c30-43c5ed687a36`
