# Thai Echo

A small personal Thai speaking and listening system:

- a 20-sentence written lesson-review workflow;
- an approval-gated desktop audio generator;
- a static GitHub Pages content feed; and
- a SwiftUI iPhone player that downloads approved audio and keeps it offline;
- private Easy/Again spaced review across saved lesson days; and
- word-by-word Thai, pronunciation, and Hebrew meaning for every released phrase.

The private source-of-truth repository is `justame/thai-echo`. The app's public,
credential-free content source remains
[`https://justame.github.io/thai-trainer/`](https://justame.github.io/thai-trainer/).
No API server, account, database, or token is required in the app.

## Current status

The iPhone player, static publisher, adaptive review loop, daily written-review
workflow, and Days 1–5 are implemented. All 100 released core phrases include a
word-learning breakdown. New lesson text and paid TTS remain behind their separate
explicit approval gates.

See [the workspace guide](thai-learning/README.md) for the exact review, generation,
publishing, and iPhone installation flow.
