# Daily Thai written-review heartbeat

Continue Yaron's Thai Echo curriculum in this same task. Read
`thai-learning-plan.md`, `thai-learning-execution.md`, `thai-learning/state.json`,
and this prompt before acting.

## Adaptive inputs

- Treat only an explicit Thai Echo progress export or a direct learner report in chat
  as Easy/Again evidence. Never infer practice results from elapsed time, app content,
  approvals, or silence.
- If an explicit export is available, validate it with
  `thai-learning/curriculum/adaptive_curriculum.py`; use its due-review ordering,
  three-day preview, and weekly summary. Keep that private input out of `docs/`.
- If no new feedback exists, preserve the current horizon and say that no adaptation
  was applied. Do not invent learner performance or personal facts.

## Rolling written horizon

Maintain exactly three upcoming written lesson drafts in `thai-learning/drafts/`.
They remain `pending_review` and outside the app's bundled `days/` directory. Only
the earliest unresolved draft is shown for decisions; the other two are explicitly
provisional and may be reshaped after new feedback. Do not create a duplicate for a
day that already exists.

Each draft has exactly 20 candidate sentences across recurring real-life categories;
unless the learner requests a theme, no category occupies more than four slots. For
every sentence provide:

1. Hebrew recall prompt.
2. Natural everyday Thai, using male `ผม`/`ครับ` forms only where natural.
3. Tone-marked romanization.
4. Short literal structure in Hebrew.
5. Context, register, and ambiguity note in Hebrew.
6. One reusable Thai pattern.
7. One useful variation with its own Hebrew cue.
8. A vocabulary breakdown of meaningful Thai chunks, each with tone-marked
   romanization and a concise Hebrew meaning.

Include a short mini-dialogue with every spoken line visible in Hebrew and Thai. End
the earliest draft with an item-by-item approve/edit/replace/reject checklist. Never
overload editorial `review_status` with Easy/Again learning feedback.

At the first run in each Asia/Bangkok calendar week, show the derived weekly totals:
reviews, Easy, Again, unique phrases, practice days, Easy rate, due backlog, and new
phrases. If there is no explicit progress export, state that the summary has no new
learner data.

## Absolute safety boundary

This heartbeat writes and presents text only. It must not approve text, create or
modify approval receipts, create paid-request authorization, read credentials,
construct or contact any TTS provider, generate or derive audio, run either publisher,
change `docs/`, commit, push, or deploy. A draft or Easy/Again event is never audio or
publishing authorization. After exact text approval, stop and ask separately before
any cost authorization; do not take the next step in the same run.
