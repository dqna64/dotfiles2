# dotfiles

Gordon's cross-machine dotfiles. Includes shared and machine-specific
configurations for tools like zsh, git, ssh, vscode, claude, tmux, etc

The install script will create symlinks on your machine for files that are
consumed by tools. Examples:
- `~/.zshrc`
- `~/.gitignore_global`
- `~/.config/karabiner/karabiner.json`
- `~/.tmux.conf`
So changes to the original files for those symlinks will take effect
without re-running the installer.

`.zshrc` will source lots of other dotfiles, so remember remember to
re-source `.zshrc` after making changes to those files.

## First-time setup on a new machine

1. **Bootstrap.** Clones this repo to `$HOME/dotfiles_dqna64`, installs
   oh-my-zsh + plugins, and symlinks the zsh / karabiner / tmux / yabai
   entry points. Existing files are backed up to
   `<file>.backup_dqna64.<timestamp>`.

   ```bash
   curl -fsSL https://raw.githubusercontent.com/dqna64/dotfiles2/main/install.sh | bash
   ```

   Or, if you'd rather inspect first, clone the repo manually and run
   `install.sh` from it:

   ```bash
   git clone https://github.com/dqna64/dotfiles2.git ~/dotfiles_dqna64
   ~/dotfiles_dqna64/install.sh
   ```

   **Custom install path.** The default is `$HOME/dotfiles_dqna64`, but
   you can install anywhere by setting the `DOTFILES_DIR=<path>` env var:

   ```bash
   # curl form — put the var before the receiving `bash`:
   curl -fsSL https://raw.githubusercontent.com/dqna64/dotfiles2/main/install.sh | DOTFILES_DIR=~/code/dotfiles bash


   `install.sh` clones into that path and symlinks `~/.zshenv` to it;
   `zsh/.zshenv` auto-derives `DOTFILES_DIR` from that symlink on every
   shell startup, so no shell-rc edit is needed to remember the
   non-default location. `.zshrc` warns at startup if `DOTFILES_DIR`
   doesn't resolve to a real clone.

2. **Edit `zsh/zsh-config`** (bootstrapped from `zsh-config.example` by
   `install.sh`). Set `DQNA64_MACHINE` (any identifier; it selects the
   `*.<machine>` files and `zshrc.d.<machine>/` dirs), list any extension
   repos in `DOTFILES_OVERLAYS` (see "Extension repos" below), and toggle
   the per-machine flags (`ENABLE_YABAI_DQNA64`, `ZSH_THEME_MY`, etc.).
   This file is gitignored. Re-run `install.sh` after editing it: it clones
   listed overlays and re-resolves the single files.

3. **(Optional) Configure git identities + SSH host aliases.** Edit
   `git/git-identity` with your real values (it's bootstrapped from
   `git-identity.example`, also gitignored), then run
   `./git/git-setup.sh`. The script renders:

   - `git/dqna64-dotfiles.gitconfig` — gitconfig snippet (gitignored,
     next to its template)
   - `~/.gitignore_global` — symlink to `git/.gitignore_global`
   - `ssh/dqna64-dotfiles.conf` — SSH host-alias snippet (gitignored,
     next to its template)

   Overlays (see "Extension repos") may carry their own
   `git/gitconfig.template` and `ssh/config.template`; the same run
   renders them with the same identity values and includes them from
   the two files above, so nothing else changes on the machine.

   `~/.gitconfig` and `~/.ssh/config` are user-owned and never modified
   by the script. To pull in the rendered files, `git-setup.sh` prints
   the exact one-time blocks to add:

   ```ini
   # in ~/.gitconfig (path printed by git-setup.sh based on $DOTFILES_DIR)
   # --- START DQNA64 DOTFILES ... --- #
   [include]
       path = ~/dotfiles_dqna64/git/dqna64-dotfiles.gitconfig
   # --- END DQNA64 DOTFILES --- #
   ```

   ```
   # in ~/.ssh/config (path printed by git-setup.sh based on $DOTFILES_DIR)
   # --- START DQNA64 DOTFILES ... --- #
   Include ~/dotfiles_dqna64/ssh/dqna64-dotfiles.conf
   # --- END DQNA64 DOTFILES --- #
   ```

4. **(Optional) Agent config.** `claude/sync-agent-links.sh` links skills,
   output styles, rules and settings from this repo and every overlay
   (`claude/README.md`). VS Code: `vscode/README.md`.

## Shell config: `zsh/zshrc.d`

`zsh/.zshrc` sources, from this repo and then from each overlay in order:
every `zsh/zshrc.d/*.zsh` (all machines using that repo), then every
`zsh/zshrc.d.<machine>/*.zsh` where `<machine>` is `$DQNA64_MACHINE`
lowercased. Files load in filename order inside a directory, so prefix with
a number when order matters (`10-general.zsh`, `20-git.zsh`). Aliases,
functions, exports and tool init all go in these files; missing dirs are
skipped. Drop a file in - no registration anywhere.

## Adding a new machine

1. Pick an identifier (e.g. `MB_2026`) and set `DQNA64_MACHINE` to it in
   `zsh/zsh-config`.
2. Machine-specific shell config: create `zsh/zshrc.d.mb_2026/` (the id
   lowercased, `_` not `-`) in whichever repo should own it and drop `.zsh`
   files in. Machine-specific single files: `claude/settings.mb_2026.json`,
   `tmux/.tmux.mb_2026.conf`, `karabiner/karabiner.mb_2026.json`, `yabai/yabairc.mb_2026`
   in any repo (the id goes before the last extension, or at the end if none).
3. Nothing to edit in `.zshrc`, `.zshenv` or `install.sh`.

## Extension repos (overlays)

This repo is the base: it works on its own and defines the places an
extension repo can add to. An overlay is a second git repo with the same
layout, holding what does not belong in a public base: work tooling, private
machine configs, a team's skills. A machine can use several; an overlay can
serve many machines. The base stores nothing about which overlays exist;
each machine lists its own in `zsh/zsh-config`:

```sh
DOTFILES_OVERLAYS=(
  "https://github.com/<you>/dotfiles-work.git"                 # cloned to ~/dotfiles-work
  "git@github.com-personal:<you>/dotfiles-home.git=$HOME/home"  # cloned to an explicit path
  "$HOME/some-local-dir"                                       # existing dir, nothing cloned
)
```

`install.sh` clones missing overlays, runs each overlay's `install.d/*.sh` (every run, so keep them
idempotent), and resolves the single files. Use whatever URL form
authenticates on that machine (HTTPS app, SSH host alias).

What an overlay may contain, and how it combines with the base:

| Path | Kind | Rule |
|---|---|---|
| `bin/` | collection | every repo's `bin/` is prepended to `PATH` by `.zshenv`, base first (a later repo's same-named script wins; `dotdoctor` reports these) |
| `zsh/zshrc.d/`, `zsh/zshrc.d.<machine>/` | collection | all repos' files are sourced, base first |
| `claude/skills/`, `claude/output-styles/`, `claude/rules/` | collection | all repos' items are linked; a duplicate name is an error |
| `claude/settings.json`, `tmux/.tmux.conf`, `karabiner/karabiner.json`, `yabai/yabairc` (+ machine variants: `settings.<machine>.json`, `.tmux.<machine>.conf`, `yabairc.<machine>`) | single file | most specific wins: the machine variant in any repo, else an overlay's file, else the base's; a tie is an error |
| `install.d/*.sh` | hooks | run by `install.sh` after its own steps |
| `git/gitconfig.template`, `ssh/config.template` | templates | rendered by `git/git-setup.sh` with the base's `git-identity` values (the only identity source), written next to the template (each overlay's own `.gitignore` must cover them; `new-overlay.sh` writes that and `git-setup.sh` warns if missing), and included from the base's rendered gitconfig (last, so overlay values win) and ssh snippet (first, so overlay Hosts are global); unknown placeholders are an error |
| `zsh/.zshrc`, `zsh/.zshenv`, `install.sh`, `uninstall.sh`, `utils/` | reserved | read only from the base; ignored in an overlay, with a warning |

Collections never override, single files never tie silently, and an overlay's
files are self-contained (a rule file does not import a base file).
Overlays are for private or work-specific config, not secrets: keys and
identities stay in the gitignored `zsh/zsh-config` and `git/git-identity`.

`dotpull` pulls every repo; `dotdoctor` prints the machine id, each repo's
state, which repo won each single file, every agent link, collisions, and any
overlay file the base does not read (a typo or an unsupported directory).

### Create an extension repo

```bash
~/dotfiles_dqna64/new-overlay.sh ~/dotfiles-work --remote git@github.com-work:<you>/dotfiles-work.git
git -C ~/dotfiles-work push -u origin main
```

It scaffolds the layout above with a README that states the rules, commits
it, and prints the `zsh-config` line to add on each machine. Then on each of
those machines: add the line, run
`install.sh` and `claude/sync-agent-links.sh`.

Moving an existing machine onto this layout: follow `OVERLAY-MIGRATION.md`.

## Machine logs

Log of software installed **outside** this repo (brew formulae, manual installs,
toolchains, OS permissions, PATH/env changes made elsewhere), so you can answer
"how did I install this" months later.

The log lives wherever you put it - any path, any repo. These dotfiles only need
its path, and nothing here creates, clones, or validates it.

| Where | Does what |
|---|---|
| `zsh/zsh-config` | `MACHINE_LOG_FILE` - the log's path. Exported, so agents read it from the environment |
| `install.sh` | reports that path (or says it's unset). Creates nothing |
| `claude/rules/skills.md` | the trigger: before/after a system-wide install, claude will know to use the `machine-logs` skill. Linked into `~/.claude/rules/` |
| `claude/skills/machine-logs/SKILL.md` | the detail: what counts as loggable, the entry format, the header for a new log, where to commit. Synced to `~/.claude/skills` by `claude/sync-agent-links.sh` |

To set one up: create the log wherever you want it (the skill has the header to
start it with), then in `zsh/zsh-config`:

```sh
export MACHINE_LOG_FILE="$HOME/machine-logs/this-machine.md"
```

Agents pick it up from there - no other registration.

## Agent activity logs

A per-project record of what agent sessions actually **changed**, written
automatically by Claude Code / Cursor hooks (nothing to set up). Only turns that
change something are logged, summarised by a small model call; reads, searches
and test runs add nothing.

```sh
agentlog            # this project, all sessions merged
agentlog -n 20      # recent entries only
agentlog -s <id>    # one session, by id prefix
agentlog -a         # every project under the global logs root
```

Where they live, same hierarchy as branch plans: `<git root>/.agent_dqna64/logs/`
when the project has a `.agent_dqna64/` (committed with the project, like plans -
never gitignored; use the fallback if a repo must not carry them), else
`$AGENT_LOGS/<project slug>/`, else `~/.agent/logs/<project slug>/`. One JSONL
file per agent session, `<start>_<machine>_<agent>_<session id>.jsonl`, the id
being the agent's own (`claude --resume <id>`), so no two writers ever share a
file and git never merges two sessions.

Know before trusting one: `summary` is the agent's own unverified account of its
turn; `files`, `commit`, `branch`, `ts` are recorded mechanically. Only the shape
of tool calls is captured and credentials are redacted before anything is
written. Cursor is covered by the same hook entries (it reads
`~/.claude/settings.json` as a third-party source; `agent-log.sh` detects the
agent from the payload).

Code: `utils/agent-log/` (`agent-log.sh` hook entry, `mutation-gate.sh`,
`summarise.sh`, `log-path.sh`, `render.sh`); hooks in `claude/settings.*.json`;
reader guidance in `claude/skills/agent-logs/SKILL.md`; design notes in `CLAUDE.md`.

## Gitignored, per-machine files (do not commit)

- `zsh/zsh-config` — machine identifier + flags.
- `git/git-identity` — real name/email/SSH key paths/SSH host alias labels.
- `*.backup_dqna64.*` — created by `install.sh` and `git-setup.sh` when
  an existing file is moved aside before being replaced. The marker
  keeps these distinct from any other `.backup` files you might have.

## Brittleness

- **`zsh/.zshenv` depth is baked into `DOTFILES_DIR` derivation.**
  `.zshenv` uses `${_zshenv_self:A:h:h}` to walk two levels up to the
  repo root. If `.zshenv` moves to a different depth, update the `:h`
  count (`<repo>/.zshenv` → `:A:h`; `<repo>/zsh/sub/.zshenv` →
  `:A:h:h:h`). Dir name doesn't matter, only depth.

## Uninstall

`uninstall.sh` reverses `install.sh`: it removes the symlinks it created
(`~/.zshenv`, `~/.zshrc`, `~/.tmux.conf`, etc, plus the
`~/.gitignore_global`, any `~/.claude/*` links, and the optional
`~/.cursor/rules/claude.mdc` link) and restores the most
recent `<file>.backup_dqna64.<timestamp>` for each path. It also delegates to
`claude/unsync-agent-links.sh` to drop any per-item links under `~/.claude/skills`,
`~/.cursor/skills`, and `~/.claude/output-styles` you opted into via
`claude/sync-agent-links.sh`. It only ever
deletes symlinks that resolve back into `$DOTFILES_DIR`, so unrelated user
config is never touched. It's idempotent.

```bash
~/dotfiles_dqna64/uninstall.sh --dry-run            # preview, change nothing
~/dotfiles_dqna64/uninstall.sh                      # interactive (prompts)
~/dotfiles_dqna64/uninstall.sh -y                   # auto-confirm the core removal (symlinks + backups); repo still prompted/kept
~/dotfiles_dqna64/uninstall.sh -y --remove-repo     # also delete the cloned $DOTFILES_DIR
~/dotfiles_dqna64/uninstall.sh --help               # list every flag
```

Flags can be combined; `--dry-run` (`-n`) can be added to any of the above to
preview it. `--yes` (`-y`) and `--no` are mutually exclusive, and `--yes` never
removes the repo on its own — pair it with `--remove-repo` (or use `--keep-repo`
to suppress the repo prompt in an interactive run).

Prompt model (all default to "no" non-interactively):

- **Core dotfiles removal** (the symlinks + backup restore) is prompted, and
  `-y` / `--yes` auto-confirms *only* this part.
- **Out-of-tree dependencies** (`~/.oh-my-zsh`, TPM) are **not** removed —
  they're shared tools you may use outside these dotfiles. The script just
  reports what's present and prints by-hand removal commands.
- **The cloned `$DOTFILES_DIR`** is **never** removed by `-y` — it requires an
  explicit `--remove-repo`.

User-owned files aren't edited: the script prints the `[include]` / `Include`
lines to remove from `~/.gitconfig` / `~/.ssh/config` and a reminder to revert
your login shell. Run `uninstall.sh --help` for all options.

## TODO

- [ ] Test out installing in a different directory than default, via
   `./install.sh` and via curl -fsSL
- [x] tmux session saving (via TPM + tmux-resurrect; see `tmux/.tmux.conf`)
- [ ] Duplicated contants prone to drift due to not using a single source between install.sh
    and everything else. Includes:
  - `DOTFILES_DIR`
  - `dotfiles_backup_path` (`backup_dqna64`)

### `uninstall.sh` review (issues + improvements)

Found during a review of `uninstall.sh`. Roughly highest-impact first.
Completed items have been moved to the review plan in `$AGENT_PLANS`
(`dotfiles-repo-review.md`, "Jun 6 — uninstall.sh hardening"). Remaining:

- [ ] **No end-of-run summary.** Consider printing a tally (symlinks removed,
  backups restored, things kept/removed) so the user can see at a glance what
  changed.
- [ ] **Add a safe test harness.** Manual testing already caused real damage
  once (an inherited `ZSH` env var pointed `rm -rf` at the real `~/.oh-my-zsh`).
  Add a scripted test that runs with an isolated `HOME`, `env -i`, and `ZSH`
  unset, exercising: symlink-into-repo removal + restore, foreign-symlink
  skip, real-file skip, empty-parent-dir cleanup, and the `--remove-repo` path.
- [ ] **`-y` + repo removal ordering note.** Self-deleting `$DOTFILES_DIR`
  while running from inside it works because the block is last and `cd`s out
  first, but it's fragile — worth a comment/guard (already partially there)
  and a test.

## Migrating from the bare git repo dotfiles

- [ ] clean up redundant bits in `~/.gitconfig`
- [ ] Clean up previous symlink ~/.gitignore_global → /Users/gordonh/.config/git/gitignore_global 
