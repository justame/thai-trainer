# Adaptive curriculum tooling

`adaptive_curriculum.py` derives a three-day practice preview, weekly summary, and
three-slot written-draft horizon from approved local lesson files plus an explicit
Thai Echo progress export.

It is an offline-only boundary: it has no speech-provider, credential, network,
publishing, or Git operation. Omitting `--progress` means “no learner feedback”; it
does not infer results.

```bash
python3 thai-learning/curriculum/adaptive_curriculum.py \
  --lessons-dir thai-learning/days \
  --progress /path/to/explicit-learning-progress.json
```

The command prints JSON unless `--output` is supplied. Three-day forecasting is pure:
it simulates Easy outcomes only inside the returned preview and never changes the
progress export. Written lesson candidates belong in `thai-learning/drafts/` and stay
`pending_review`; the tool only identifies the rolling horizon that the review
heartbeat should maintain.
