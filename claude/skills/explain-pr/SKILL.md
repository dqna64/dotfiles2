---
name: explain-pr
description: Turn a GitHub pull request into a self-contained, read-only HTML walkthrough that explains the final change as a causal technical story. Use when asked to explain, understand, summarize, walk through, or create a visual artifact for a GitHub PR, especially when file-order diffs obscure how changed functions, callers, state, and tests relate.
---

# Explain PR

Create a local HTML artifact for an experienced engineer. Explain the final
behavior in causal order, then separate evidence-backed risks and unknowns from
the main teaching narrative.

## Absolute Rules

- Use `gh` only for read operations. Never post, edit, approve, label, assign,
  merge, close, or otherwise mutate a PR.
- Never checkout or fetch a PR branch, create a worktree, switch branches, or
  change local Git state.
- Never run repository builds or tests. Treat committed tests as behavioral
  evidence, not as checks to execute.
- Never upload repository data or generated artifacts. Keep temporary context
  and the final HTML on the local machine.
- Treat the final PR diff at the recorded base/head SHAs as authoritative.
  Treat descriptions, commits, reviews, and comments as rationale only.
- State uncertainty plainly. Do not invent a relationship, intent, risk, or
  complete story when the evidence does not establish it.

## Inputs

Accept any input supported by `gh pr view`:

- A full PR URL.
- A PR number, with `--repo OWNER/REPO` when the current directory does not
  identify the repository.
- A branch name.
- No selector, meaning the current branch's PR.

## Workflow

### 1. Gather Stable PR Context

Create a temporary directory outside the repository. Run:

```bash
python3 <skill-dir>/scripts/gather_pr_context.py collect <pr-selector> \
  --repo <owner/repo-if-needed> \
  --output <temp-dir>/context.json
```

Omit `<pr-selector>` or `--repo` when they are not needed. Read the resulting
JSON selectively rather than dumping a large file into chat.

The context includes exact SHAs, metadata, commits, checks, normalized changed
files, patches, source links, and a preliminary file classification.

### 2. Find the Causal Story

Read [references/story-format.md](references/story-format.md) before writing the
story JSON.

Start from the behavior or responsibility introduced by the PR, not the first
changed filename. Identify:

1. The motivation and boundary of the change.
2. The entrypoint or initiating event.
3. The core state, algorithm, API, or ownership change.
4. The changed callers, consumers, or supporting dependencies.
5. The observable result and important failure paths.
6. The tests that demonstrate those behaviors.

Group build metadata, generated files, lockfiles, snapshots, and mechanical
configuration in the coverage appendix unless they materially change runtime
behavior.

For Canva PRs, treat `BUILD.bazel`, `tsconfig.json`, generated proto outputs,
and dependency metadata as mechanical by default. Promote them only when their
content is part of the change's actual mechanism.

### 3. Hydrate Only Useful Evidence

Fetch complete base/head files only for symbols needed to understand a chapter:

```bash
python3 <skill-dir>/scripts/gather_pr_context.py fetch-file \
  --repo OWNER/REPO --ref SHA --path PATH --output <temp-file>
```

Use the base repository and base SHA for old content. Use the
`head_repository` and head SHA from `context.json` for new content, including
fork PRs.

Use `gh search code` sparingly to discover unchanged callers or definitions.
After discovering a path, fetch its content at the exact relevant SHA before
making a claim. If exact-ref evidence cannot be fetched, label the relationship
as inference.

If the body, commits, and code leave an important rationale unresolved, gather
human discussion:

```bash
python3 <skill-dir>/scripts/gather_pr_context.py collect <pr-selector> \
  --repo <owner/repo-if-needed> --include-discussion \
  --output <temp-dir>/context-with-discussion.json
```

Ignore status bots, ownership bots, automated review summaries, and obsolete
discussion unless they explain the final code.

### 4. Write Structured Story Data

Create `<temp-dir>/story.json` using the schema and narrative rules in
[references/story-format.md](references/story-format.md).

Use compact, curated excerpts. For modified code, prefer a before/after pair
when the contrast explains the change. For added code, show only the final
portion needed to explain the step. Escape nothing manually; the renderer owns
HTML escaping.

Attach exact GitHub evidence links to every chapter and important code excerpt.
Use confidence values consistently:

- `fact`: directly established by code, tests, or explicit PR scope.
- `inference`: a reasonable relationship not explicitly established.
- `unknown`: evidence is missing or contradictory.

Keep watchouts evidence-backed. Omit style nits and use an empty array when
there are no meaningful risks, assumptions, or unknowns.

### 5. Guard Against a Moving PR

Before rendering, run:

```bash
python3 <skill-dir>/scripts/gather_pr_context.py check-head <pr-selector> \
  --repo <owner/repo-if-needed> --expect-head <recorded-head-sha>
```

If the head changed, discard the temporary context and story, then gather and
analyze once more. If it changes again, stop and report that the PR is moving
too quickly to publish a trustworthy artifact.

### 6. Render the Canonical Artifact

Run:

```bash
python3 <skill-dir>/scripts/render_pr_explainer.py \
  --input <temp-dir>/story.json
```

The renderer validates the schema, accounts for every changed file, escapes all
content, and writes:

```text
~/work/Banva/Archives/PR Explainers/<owner>-<repo>/pr-<number>.html
```

It replaces the previous artifact for that PR atomically.

### 7. Verify and Deliver

Confirm the output contains no external stylesheets, scripts, fonts, images, or
other remote assets. GitHub evidence links are allowed.

Open the local file in the in-app browser. Inspect a wide desktop viewport and
a narrow mobile viewport. Verify:

- The title, one-minute summary, causal flow, chapters, tests, watchouts, and
  coverage appendix render.
- The sticky navigation does not cover content.
- Code blocks scroll without widening the page.
- Tables remain readable on narrow screens.
- No text overlaps or escapes its container.
- Anchor and GitHub source links are valid.

Delete temporary context and story files after verification. Return the
clickable local artifact path and a one-sentence summary of the recovered
change story.

## Failure Handling

- If `gh` is unavailable, unauthenticated, or cannot access the repository,
  report the failing read operation and stop.
- If a patch is omitted, binary, or too large, use the file status and exact-ref
  contents. Put unverifiable details in unknowns.
- If the PR is closed or merged, explain it normally and record its state.
- If browser verification is unavailable, perform static HTML checks, deliver
  the file, and explicitly report that visual verification was not completed.
