---
name: brief
description: Answer a quick side question as tersely as possible - a few sentences at most, no preamble, no tool use unless the answer genuinely requires reading the code. Use when the user types /brief.
disable-model-invocation: true
---

# brief

The user asked a side question, not a task. They want the answer and nothing
else. This overrides the global response-style instructions for this one turn:
no TL;DR-then-detail structure, no next-step options, no question-quality
assessment.

## Rules

1. **Answer first, answer only.** Ideally one to three sentences. A bare word or
   number is a fine answer if that's the whole answer.
2. **No preamble.** Don't restate the question, don't say what you're about to
   do, don't summarise at the end.
3. **No headers or sections.** Prose or a short list. Code blocks only if the
   answer *is* code.
4. **Minimal tool use.** Answer from what you already know or have in context.
   Read a file or run one command only if the answer is codebase-specific and
   you'd otherwise be guessing - then still answer in a sentence or two.
5. **Don't do the work.** If the question implies a change, describe the answer;
   don't start editing. The user will ask if they want it done.
6. **Keep calibration.** If you're unsure, say so in a clause ("not verified,
   inferred from naming") rather than a paragraph. Still push back if the
   premise is wrong - just do it in one line.
7. **Offer the escape hatch only when it matters.** If the honest answer really
   doesn't fit in a few sentences, give the compressed version and end with one
   short line saying more detail is available - don't expand unprompted.
