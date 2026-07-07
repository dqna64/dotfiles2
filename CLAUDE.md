# CLAUDE.md

Guidance for AI agents working on this repo. Read this before changing
`install.sh`, `uninstall.sh`, `git/git-setup.sh`, or anything that touches the
user's home directory.

## What this repo is

Gordon's cross-machine dotfiles. The model is: tracked config lives in this
repo, and `install.sh` creates **symlinks** from the expected locations
(`~/.zshrc`, `~/.gitignore_global`, `~/.tmux.conf`, …) back into the repo, so
edits to the repo take effect without re-running the installer. `~/.zshrc`
sources lots of other files directly out of the repo (aliases, `omz-setup.zsh`,
yabai). See `README.md` for the full layout and user-facing setup steps.

## Target machines (must work on all of them)

These dotfiles must work across **every** machine Gordon uses. Any change to
`install.sh`, `uninstall.sh`, `git/git-setup.sh`, or the shell config must keep
working everywhere — not just on the machine you happen to be testing on:

- **macOS laptops** — Canva work MacBook and a personal MacBook (M1, Apple
  Silicon). Both Apple Silicon and Intel brew paths should be handled.
- **Canva work devboxes** — `DVBX1`, `DVBX2`, `DVBX3`, `DVBX4`, `DVBX5`, and potentially more
  (Linux).
- **Linux VPS** — DigitalOcean, OVH, and similar.

Design implications to uphold:

- **Cross-platform.** Don't assume macOS. Guard macOS-only steps (Homebrew,
  yabai, karabiner) behind an OS check (`is_macos`) or a config flag, and make
  them no-ops/skips elsewhere. Prefer POSIX-portable shell; don't rely on
  GNU-only or BSD-only flags without a fallback (see `canonicalize_path` in
  `utils/common.sh` for the kind of portability care expected).
- **Sensible defaults, zero-fuss to run.** The common path on a fresh machine
  should "just work" with defaults — no required edits before the first run.
  Anything machine-specific should have a reasonable default and only need
  tweaking when the machine genuinely differs.
- **Tailored per environment via config vars, not forks.** When a decision is
  device-specific, drive it from a **config variable / flag** (e.g.
  `DQNA64_MACHINE`, `ENABLE_YABAI_DQNA64`, `ZSH_THEME_MY`, the per-machine
  `aliases.<suffix>/` dirs and `zsh/.zshrc.<machine>` files) rather than
  hardcoding or branching on hostname. Add a new machine by setting vars /
  dropping files (see "Adding machines / aliases" below), not by editing
  script internals. Keep the `*.example` files and the `case`/flag plumbing in
  sync when you introduce a new knob.
- **One script, every machine.** There should be a single `install.sh` /
  `uninstall.sh` / `git-setup.sh` that adapts to its environment — avoid
  per-machine script variants.

## Golden rules (most important)

The whole repo is built around being **safe to run on a machine that already
has config**. Preserve these invariants in any change:

1. **Idempotent.** Every script must be safe to run repeatedly. Re-running
   produces the same end state and never re-does work that's already done
   (check before acting; print "already …, skipping" and move on).
2. **Non-destructive by default.** Never overwrite or delete a user's existing
   file. When something is in the way, move it aside to
   `<file>.backup_dqna64.<YYYYMMDDHHMMSS>` rather than clobbering it. The
   `backup_dqna64` marker is load-bearing: it's matched by `.gitignore` and by
   `uninstall.sh`'s restore logic. Don't invent a different backup naming
   scheme — use `dotfiles_backup_path` in `utils/common.sh` (the single source
   of truth). `install.sh` keeps a deliberate hand-copy of the format because in
   a `curl | bash` bootstrap it runs before the repo (and `common.sh`) is on
   disk; if you touch the format, keep both in sync.
3. **Respect what's already there.** Detect existing files/configs/clones and
   adapt. Distinguish "our symlink", "a real file the user owns", and "a symlink
   pointing elsewhere" — and only ever touch the first.
4. **Never edit user-owned files in place.** `~/.gitconfig` and `~/.ssh/config`
   are NEVER modified by scripts. Instead, render standalone snippets the user
   `[include]`s / `Include`s, and **print** the exact lines for them to add.
   Same spirit for the login shell: prompt / print, don't silently force.
5. **Tell the user everything, concisely.** Scripts should narrate what they do,
   why, and what (if anything) the user must do next — comprehensive but
   scannable. Use the colored `echo_*` helpers (`echo_info`, `echo_warn`,
   `echo_error`, `echo_note`, `echo_success`) rather than bare `echo` for
   anything the user should notice. Prefer actionable messages ("run X to fix")
   over bare errors.
6. **Reversible.** Every action `install.sh` takes must be undoable by
   `uninstall.sh` (or, for out-of-tree deps it deliberately won't remove,
   documented with the exact by-hand removal steps). When you add a new install
   step, add the matching teardown — never leave the machine in a state the
   uninstaller can't return to its pre-install shape.

### `install.sh` specifically

- Must be **idempotent**, **non-destructive**, and respect pre-existing files
  and configs.
- Back up (never overwrite) anything in the way, via `symlink_dotfile`'s
  `backup_dqna64` mechanism.
- Give the user full, useful information about everything it does, while staying
  concise and easy to follow.
- It can install **out-of-tree** dependencies (Homebrew, oh-my-zsh + plugins,
  TPM) — but always guarded by an "already installed?" check first, and failures
  to install optional pieces (e.g. Homebrew) should warn and continue, not abort.

### `uninstall.sh` specifically

- Must be **idempotent**.
- Must **not be destructive** to anything outside this repo. Concretely: it only
  removes symlinks that **resolve back into `$DOTFILES_DIR`** (see
  `path_inside` + `canonicalize_path` in `utils/common.sh`); real files, foreign
  symlinks, and directories are reported and left alone.
- **Bias hard toward asking** before any destructive or surprising action.
  - Core symlink removal + backup restore is prompted (and is what `--yes`
    auto-confirms).
  - Out-of-tree deps (oh-my-zsh, TPM) are shared tools — **never removed**, only
    reported with by-hand removal commands.
  - Removing the cloned `$DOTFILES_DIR` requires an explicit `--remove-repo`;
    `--yes` must never trigger it.
  - All prompts default to **"no"** when non-interactive.
- Always support `--dry-run` (`-n`) for previewing without changes; route real
  filesystem mutations through `do_cmd` so dry-run is honored automatically.
- Agent-skill links (opted into via `claude/sync-skills.sh`) are torn down by
  delegating to `claude/unsync-skills.sh` — the skill-removal logic lives there
  in one place, and `uninstall.sh` forwards `--dry-run`. Keep that delegation
  rather than duplicating the link-removal loop.

## Conventions to follow

- **Repo location is dynamic.** Scripts resolve `$DOTFILES_DIR` from their own
  location (the checkout they run from), allow a `DOTFILES_DIR=…` env override,
  and fall back to `$HOME/dotfiles_dqna64`. `zsh/.zshenv` re-derives it from the
  `~/.zshenv` symlink at shell startup. Don't hardcode `$HOME/dotfiles_dqna64`.
- **Shared helpers live in `utils/common.sh`.** The safety-critical primitives
  (`dotfiles_backup_path`, `do_cmd`, `canonicalize_path`, `path_inside`,
  `restore_latest_backup`, `remove_dir_if_empty`) have one implementation there.
  Scripts that always run from a clone on disk — `uninstall.sh`,
  `git/git-setup.sh`, `claude/sync-skills.sh`, `claude/unsync-skills.sh` — source
  it (via a `BASH_SOURCE`-relative path) instead of redefining them. `install.sh`
  is the deliberate exception: it must stay fully self-contained for the
  `curl | bash` bootstrap, so it keeps its own copies. Callers must define the
  `echo_*` helpers and `shopt -s nullglob` before calling into the lib (see the
  contract comment at the top of `common.sh`).
- **`utils/` also holds standalone helpers.** `check-repo-freshness.sh` warns at
  shell startup when a local clone is behind upstream (local-only check on the
  hot path; throttled background `git fetch`), and exits silently for every
  not-applicable case. Generic — point it at any clone.
- **Don't commit per-machine / secret files.** These are gitignored and
  bootstrapped from tracked `*.example` files: `zsh/zsh-config`,
  `git/git-identity`, the rendered `git/dqna64-dotfiles.gitconfig` and
  `ssh/dqna64-dotfiles.conf`, and all `*.backup_dqna64.*`. Never write real
  names/emails/keys into tracked files.
- **`*.example` drift.** Configs created once from an example then never
  auto-updated can fall behind when the example gains variables. There are
  startup/preflight checks (`zsh/.zshrc`, `git/git-setup.sh`,
  `utils/shell-var-names.sh`) that compare variable **names** (never values). If
  you add a variable to an `*.example`, keep these checks working.
- **Rendered-template drift.** `git/git-setup.sh` stamps rendered files with the
  template's git object id (`dqna64-template-oid:`), and `zsh/.zshrc` warns when
  a template changes without re-rendering. Preserve this if you touch templating.
- **Adding machines / aliases** is registration-free by design: drop a `.zsh`
  file in an `aliases*/` dir, or a `zsh/.zshrc.<machine>` file, and it's
  auto-sourced. See `README.md` → "Adding a new machine". Keep this property.
- **Shell style.** `install.sh` uses `set -e`; `uninstall.sh` / `git-setup.sh`
  use `set -euo pipefail`. Quote variable expansions, prefer the existing helper
  functions, and keep comments explaining *why* (non-obvious intent), matching
  the existing dense-but-purposeful comment style.

## After changing the install/uninstall scripts

- Re-read the script end to end and confirm the golden rules still hold
  (especially: still idempotent? still backs up instead of clobbering? still
  only removes symlinks that resolve into the repo?).
- There is **no automated test harness yet** (see the `uninstall.sh` review
  TODO in `README.md`) and manual testing has caused real damage before (an
  inherited `ZSH` env var once pointed `rm -rf` at the real `~/.oh-my-zsh`). If
  you test by running the scripts, do it with an **isolated `HOME`**, `env -i`,
  and `ZSH` unset — never against the live home directory.
- Keep `README.md` in sync when you change user-facing behavior or flags.
