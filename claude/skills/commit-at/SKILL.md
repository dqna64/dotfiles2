---
name: commit-at
description: Commit staged changes with a specified commit timestamp. Useful for backdated commits, scheduled commits, or marking when work was actually completed. Parses the time from the user's request; if none specified, uses current time.
---

# Commit with Specified Timestamp

Commit staged changes and set the commit timestamp to a specific time (past, present, or future). The timestamp affects the commit date/time metadata, not the commit message.

## Workflow

```
- [ ] 1. Verify staged changes exist
- [ ] 2. Parse and validate timestamp from user request (or use current time)
- [ ] 3. Ask for commit message
- [ ] 4. Create commit with --date flag
- [ ] 5. Verify success
```

### 1. Verify staged changes

Check that there are staged changes ready to commit:

```bash
git status
git diff --cached --stat
```

If nothing is staged, tell the user and stop.

### 2. Parse and validate timestamp

Extract the desired timestamp from the user's request. **Use the system's configured timezone** (check `TZ` environment variable or system settings). Common formats:

| User says | Interpretation (system timezone) |
|---|---|
| `commit-at 3pm` | Today at 3:00 PM in local time |
| `commit-at 2026-06-15 14:30` | June 15, 2026 at 2:30 PM in local time |
| `commit-at yesterday 10am` | Yesterday at 10:00 AM in local time |
| `commit-at 1 hour ago` | 1 hour before now (local time) |
| *(no time specified)* | Current time (omit env vars, use git's default) |

Convert the user's input to a git-accepted format, **including the system timezone offset**. Use one of these formats:

- ISO 8601 with timezone: `2026-06-15T15:00:00+10:00`
- RFC 2822 with timezone: `Mon, 15 Jun 2026 15:00:00 +1000`
- Unix timestamp: `1750245000` (timezone-agnostic)

To get the current timezone offset, run:
```bash
date +%z    # returns e.g., +1000 or -0800
```

If the user provides a relative time like "1 hour ago", calculate the actual datetime in the system's local time before setting the env vars.

**Validate against the previous commit:** After parsing, check the timestamp of the current HEAD:

```bash
git log -1 --format="%ai"    # returns the previous commit's timestamp
```

If the requested timestamp is **earlier than the previous commit**, warn the user:

```
⚠️  You're backdating this commit before the previous commit (which was at <PREVIOUS_TIME>).
This will make the commit history out of chronological order. Continue? [y/N]
```

Only proceed if the user confirms. If you can't parse the user's time request, ask for clarification.

### 3. Ask for commit message

Ask the user for the commit message if you don't have one already. This should be clear and concise.

### 4. Create commit with --date

Use `git commit` with both `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` environment variables set to the same timestamp to ensure both dates are identical:

```bash
GIT_AUTHOR_DATE="<parsed-date>" GIT_COMMITTER_DATE="<parsed-date>" git commit -m "$(cat <<'EOF'
<commit message>
EOF
)"
```

Both dates must be in the same format and include the system's timezone offset. Use ISO 8601 format for consistency: `2026-06-15T15:00:00+10:00` (where `+10:00` is your local offset).

### 5. Verify

Show the user the commit that was created with its timestamp:

```bash
git log -1 --format="%H %ai %s" --no-decorate
git log -1 --format="%B"
```

Display the commit hash, timestamp, and message so they can confirm it's correct.

## Notes

- **System timezone.** All times are interpreted in the system's configured timezone. Include the system's timezone offset in the timestamp (run `date +%z` to check your offset).
- If the user doesn't specify a time, just use the current time (omit the date environment variables and let git use defaults).
- Both the **author date** and **committer date** must be set to the same timestamp using `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` environment variables. This ensures the commit appears to have been created at the specified time.
- Timestamps are commit metadata, not part of the message body.
- Never force push; this is a straightforward commit.
- Always confirm the message with the user before committing.
