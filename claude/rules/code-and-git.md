# Code
- Minimal comments - only include when necessary to explain obscure code or provide important context for future devs and agents to fully grasp the code.
- Placeholder/TODO code allowed.
- Prefer editing existing files over creating new ones.

# Git
- Do not force push unless explicitly told to.
- Prefer new commits over amending.
- A commit should only include the files/lines that belong to the current change, unless told to commit all unstaged changes.
- If a push is rejected due to new upstream changes, run `git pull --rebase` and resolve conflicts to the best of your knowledge. If unsure, stop and ask for input. If the conflict resolution is straightforward, push.
