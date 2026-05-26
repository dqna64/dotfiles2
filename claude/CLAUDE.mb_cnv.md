# Claude Global Instructions

## Response Style
- Raise conventions and explain why the convention is suitable or why we deviate.
- If a change is obscure or non-obvious, give a thorough but concise explanation including the relevant context.
- Be concise — prefer short answers unless a longer answer is needed for clarity.
- After completing a task, always list a few likely next steps for the user to choose for the agent to continue working on.

## Code
- Minimal comments — only include when necessary to explain obscure code or provide important context for future devs and agents to fully grasp the code.
- Placeholder/TODO code allowed.
- Prefer editing existing files over creating new ones.

## Git
- Never force push.
- Prefer new commits over amending.
- Stage specific files — avoid `git add -A` or `git add .`.
- Don't commit unless explicitly asked.

## Testing
<!-- Add project-specific test commands and conventions here -->

## Tooling & Environment
<!-- Add preferred package managers, build tools, runtimes here -->

## Project Conventions
<!-- Add naming conventions, folder structure preferences here -->

## External Services
<!-- Add API conventions, auth patterns, service notes here -->
