---
name: machine-logs
description: Read and maintain this machine's log of software installed outside the dotfiles repo ($MACHINE_LOG_FILE). Trigger this before installing anything system-wide (brew/apt/npm -g/pip/manual installs, toolchains, GUI apps, OS permissions), when diagnosing "is X installed / where did X come from / what version" questions, or right after any such install completes.
version: 1.0.0
---

# Machine logs

A running log of software installed or configured outside the user's dotfiles
repo on this machine.

**Its path is `$MACHINE_LOG_FILE`**, exported by the user's `zsh/zsh-config`.
Use that variable; don't derive a filename or assume a location.

If it is unset, no log is configured on this machine - say so and carry on. If
it is set but the file isn't there, mention it and ask before creating anything.

## Read it when

- You are about to install a system-wide dependency - the answer may already be
  there (already installed, installed a different way, or previously tried and
  abandoned).
- You need machine context: which toolchain/version manager is in use, where a
  binary came from, what PATH/env additions exist, what OS permissions were
  granted.
- The user asks "how did I install X", "what version of X do I have", "why is X
  set up this way".

Grep it first (`grep -in '<tool>' "$MACHINE_LOG_FILE"`) rather than reading the
whole file - it grows without bound.

## Append to it when

Any of these happen, whether you ran the command or the user did:

- A package manager install that changes the machine, not a project:
  `brew install`, `apt install`, `npm i -g`, `pipx install`, `cargo install`,
  `gem install`, `pyenv install`, `nvm install`, SDKMAN, etc.
- A manual install: downloaded binary, `.pkg`/`.dmg`, something dropped into
  `/usr/local`, `/Library`, `~/.local/bin`.
- A toolchain or runtime made default (JDK switch, python/node version pin).
- GUI app configuration worth remembering (editor `settings.json` edits, app
  preferences) or an OS permission granted (Screen Recording, Accessibility,
  Full Disk Access).
- PATH/env changes made outside the dotfiles repo.

Do **not** log project-local work: `npm install` into a project, a venv, a
lockfile change, or anything already tracked in the dotfiles repo itself.

## How to append

Append at the **bottom** of the file (newest last). Match the surrounding style;
do not restructure or reformat existing entries.

````markdown
## <what was installed> [YY/MM/DD]

```sh
$ <the exact command(s) run>
```

- Where it landed (install path, binary path) and anything non-obvious.
- Why it was needed - the project or task that prompted it.
- Follow-up config: PATH/env changes, app settings, OS permissions granted.
````

Keep it short - a few lines. Paste real output only when it carries information
worth keeping (an install path, a resolved version); trim the noise. Use the
machine's real date (`date +%y/%m/%d`), never a guessed one.

**Never** put secrets, tokens, API keys, or licence keys in this file. If a step involved one, write "(configured a token - not
recorded here)".

## Committing

The log may sit in a repo of its own, in which case an edit leaves **that** repo
dirty - not whatever project you are working in. Check with
`git -C "$(dirname "$MACHINE_LOG_FILE")" status`. Mention the pending change and
offer to commit it there; do not commit without being asked, and never stage it
into an unrelated repo's commit.
