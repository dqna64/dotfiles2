---
name: commit-working-tree
description: Review uncommitted working-tree changes, group them into distinct tasks, and create one concise commit per task. Use when the user asks to understand, stage, and commit working-tree changes, or to split changes into multiple logical commits.
disable-model-invocation: true
---

# Commit Working Tree by Task

Inspect uncommitted changes, identify the distinct tasks they accomplish, and commit each unrelated task separately with a super concise message.

## Workflow

```
- [ ] 1. Survey the working tree
- [ ] 2. Read the full diff
- [ ] 3. Group changes into tasks
- [ ] 4. Commit each task (stage specific files, then commit)
- [ ] 5. Verify clean working tree
```

### 1. Survey

Run in one batch:

```bash
git status
git diff --stat
git diff --cached --stat   # catch anything already staged
git log --oneline -15      # match the repo's message style
```

### 2. Read the full diff

Read the complete `git diff`. If output is truncated, re-run `git diff -- <files>` scoped to the truncated files. Understand WHAT changed and WHY before grouping — do not group from filenames alone.

### 3. Group into tasks

Cluster changes by the logical task they accomplish, not by directory. A task is a coherent unit of intent (one refactor, one feature, one fix). Include its tests, build files (`BUILD.bazel`, `tsconfig.json`), and stories in the same group.

Prefer fewer, well-scoped commits. Only split when tasks are genuinely independent.

- **Coupling check**: if removing one group's changes would break the other group's compile/build, they are coupled — keep them in one commit. Each commit should ideally leave the tree buildable.
- When unsure whether to split, ask the user with `AskQuestion`.

### 4. Commit each task

Stage **specific files** (never `git add -A` / `git add .`). Order commits so coupled prerequisites land first.

```bash
git add path/to/file_a path/to/file_b
git commit -m "$(cat <<'EOF'
<message>
EOF
)"
```

### 5. Verify

End with `git status` to confirm `nothing to commit, working tree clean`.

## Commit message style

- Super concise, to-the-point, imperative — describe the change, not the diff.
- One subject line per commit unless a body adds real value.

## Rules

- Never force push. Prefer new commits over `--amend`.
- Stage specific files only.
- Do not commit likely-secret files (`.env`, credentials); warn if asked.
- Do not push unless explicitly asked.
