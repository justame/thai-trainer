# Static lesson publisher

`publish_static_pack.py` turns one approved lesson plus its already-generated MP3s
into plain files that any static host can serve. It never calls TTS, reads speech
credentials, or uses the network.

## GitHub Pages helper

From the repository root, the safe one-command local build is:

```bash
python3 thai-learning/publish/publish_to_pages.py
```

It validates existing local audio and builds directly into `docs/`; it does not
run Git or contact TTS. Use `--dry-run` to validate the complete pack in a
temporary directory without changing `docs/`. Only an explicit `--push` permits
the helper to commit `docs/` changes and run `git push origin HEAD`:

```bash
python3 thai-learning/publish/publish_to_pages.py --dry-run
python3 thai-learning/publish/publish_to_pages.py --push
```

While Day 1 is pending text approval, all of these commands fail before publishing
a pack. In particular, `docs/latest.json` must remain absent until an approved
lesson and its four validated, already-generated MP3s exist.

The audio argument may be either the generator output root or the matching
`<lesson-id>/r<revision>` directory:

```bash
python3 thai-learning/publish/publish_static_pack.py \
  thai-learning/days/day-001.json \
  thai-learning/audio/generated \
  thai-learning/publish/site
```

Publishing fails unless the lesson and all 20 sentences are approved, exact immutable
text-approval and paid-request authorization receipts exist for the same revision and
content hash, every generated request hash is current, and the manifest describes
exactly four nonempty files: `listening.mp3`, `shadowing.mp3`, `recall.mp3`, and
`scenario.mp3` with their exact byte sizes.

Each revision is assembled completely in a private sibling staging directory and
then installed with an atomic no-replace rename. A published
`packs/<lesson-id>/r<revision>` directory is never edited or replaced. Republishing
the same revision is accepted as an idempotent no-op only when all six expected
files are byte-for-byte identical; any conflict leaves both the live pack and
`latest.json` unchanged. Failed staging directories are removed automatically.

The output is ordinary static content:

```text
site/
  latest.json
  packs/<lesson-id>/r<revision>/
    lesson.json
    audio-manifest.json
    listening.mp3
    shadowing.mp3
    recall.mp3
    scenario.mp3
```

`latest.json` contains relative `lesson_path` and `audio_manifest_path` values. A
client resolves those against the URL used to fetch `latest.json`, then resolves
each manifest track's `file` against the manifest directory.

For local testing, serve the generated tree and use
`http://127.0.0.1:8787/latest.json` as the feed URL:

```bash
python3 -m http.server 8787 --directory thai-learning/publish/site
```

Run the publisher tests with:

```bash
python3 -m unittest discover -s thai-learning/publish/tests -v
```
