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
maintains a rolling horizon of three written lesson drafts. Drafts live outside the
app's bundled `days/` directory, remain `pending_review`, and must not generate audio.
Only the earliest unresolved draft is presented for approval; the later two are
provisional and may be reshaped by new learner feedback. A pack contains:

- 20 Hebrew recall prompts drawn across several real-life categories;
- natural spoken Thai;
- tone-marked romanization;
- literal structure and a short context/politeness note;
- one reusable pattern and one useful variation per sentence;
- an optional mini-dialogue whose every line is separately visible for approval;
- due reviews from days 1, 3, 7, 14, and 30;
- an explicit approval checklist.

The heartbeat may adapt those drafts only from a learner-provided progress export or
an explicit chat report. Phone progress is private local data and is never uploaded to
the public lesson feed. If no new progress is available, the heartbeat keeps the
existing horizon instead of inventing results or personal facts.

After approval and separate audio authorization, the approved pack can produce:

- a listening track that presents each Thai sentence once at learner speed and once
  at natural speed;
- a clear near-natural-speed pause-and-repeat shadowing track;
- a Hebrew-cue recall track;
- a natural-speed scenario track using the approved items in sequence.

The selected provider is Google Cloud Text-to-Speech with
`th-TH-Chirp3-HD-Erinome` for Thai and `he-IL-Chirp3-HD-Charon` for Hebrew. Thai
learner playback uses provider-native speaking-rate control—initially `0.82x` for a
learner repetition, `0.90x` for shadowing and recall, and `1.0x` for the natural
repetition and scenario—without changing pitch. Tracks use SSML sentence boundaries
for the legacy Azure path. The Google path synthesizes one complete utterance at a
time with an explicit voice and rate, reuses identical segments, inserts exact silence
from a validated hash-keyed cache, inserts exact silence locally, and assembles the
four final MP3s with SoX after checking encoder capability before any cloud call. This
avoids mixed-language synthesis, duplicate retry charges, and provider request-size
limits while keeping pauses deterministic. Proper names,
loanwords, and unusual phrases must be manually reviewed before audio authorization.

`thai-learning/audio/generate_audio.py` remains the sole owner of provider requests,
authentication lookup, response decoding, and generated-file metadata. The day and
authorization schemas own the provider/voice/rate contract; the static publisher only
validates already-generated artifacts plus matching immutable approval and paid-request
receipts; the iOS app remains provider-agnostic and only downloads MP3 files. This
extends the existing approval-gated generator rather than creating a second generation
path or putting provider logic in the publisher or app. Provider billing, API
enablement, and credentials remain outside the repository and require the separate
authorization gate before any real request.

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

The configurable sentence player extends that background-listening contract. Its
Hebrew-to-Thai, repetition, variation, and next-sentence pauses are represented as
real silent audio segments rather than foreground-only timers, so one continuous
practice sequence can survive device locking and app backgrounding. It reuses the
same `.playback`/`.spokenAudio` session and `audio` background mode as the track player.
Both players write bounded persistent playback diagnostics for physical-device
verification without storing lesson text or credentials.

The adaptive layer stores Easy/Again events in the app's private Application Support
directory. Each phrase identity binds lesson ID, revision, canonical content hash, and
sentence ID, so edited lesson text never inherits old progress accidentally. A due
review session may mix validated sentence audio from several saved lesson packages.
The app can export an explicit progress snapshot for desktop curriculum drafting, but
it never writes progress, summaries, or feedback into the public `docs/` feed.

Each released sentence also exposes a pedagogical vocabulary breakdown: meaningful
Thai chunks, tone-marked romanization, and concise Hebrew meaning. The lesson schema
accepts vocabulary inline for future packs, while the app keeps a catalog for the
already released immutable packs so their approved audio hashes and public artifacts
do not change.

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

Full application and curriculum development uses the private repository
`justame/thai-echo` as the source of truth. The public `justame/thai-trainer` repository
continues to serve the credential-free static Pages feed; no app secret or learner
progress is added to that public delivery path.

A local 11:00 Asia/Bangkok Codex heartbeat maintains the next three written drafts
only. It never approves text on the user's behalf, generates speech, authorizes a paid
request, publishes, or pushes. After explicit text and cost authorization, one local
publish command validates the exact receipts and existing generated audio before any
`docs/` update; pushing remains a separate explicit action.

## Practice and adaptation

The focused session lasts 30 minutes:

1. Five minutes of delayed recall from Hebrew.
2. Eight minutes learning a rotating subset of up to six approved sentences and one
   reusable structure.
3. Seven minutes recognizing normal-speed Thai.
4. Five minutes shadowing and comparing a self-recording.
5. Five minutes using the material in an improvised role-play.

Optional passive listening lasts 20–40 minutes during commuting, walking, or chores.
Each active phrase gets one simple learner decision:

- `Again` records difficulty, resets the success ladder, and returns the phrase later
  in the current session; it remains due for another short review.
- `Easy` advances the phrase through the 1, 3, 7, 14, and 30 day intervals using
  Asia/Bangkok calendar boundaries.

Unseen and overdue phrases are mixed across saved approved lesson revisions, with due
reviews ahead of new material and a default cap of six phrases per focused session.
The app previews three daily practice drafts by simulating an Easy result for planned
items, without mutating real progress. A weekly summary is derived from immutable
events and reports Easy/Again counts, unique phrases, practice days, Easy rate, and the
current due backlog. It is a view of event history, not a second mutable source of
truth. Weak weeks reduce new material automatically until the backlog recovers.

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
7. **Weekly integration:** capture revision-bound Easy/Again events, schedule cross-day
   reviews, preview the next three practice days, export a private weekly summary, and
   use it to reprioritize the rolling written-draft horizon. Gate: deterministic
   scheduling/persistence tests pass, the iOS flow is usable with no network or TTS,
   and the written heartbeat remains unable to synthesize or publish.

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
- Publishing refuses a lesson whose exact immutable text approval and paid-request
  authorization receipts are absent or stale.
- Easy/Again feedback survives relaunch, edited revisions start with independent
  progress, and Again is requeued while Easy follows the configured interval ladder.
- A three-day preview never mutates real progress, and weekly totals are reproducible
  from the stored immutable event history.
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
