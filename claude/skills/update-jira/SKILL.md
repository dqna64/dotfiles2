---
name: update-jira
description: "Create or update a Jira ticket description. MUST be invoked proactively any time you are about to call mcp__otter__jira_create or mcp__otter__jira_update with a description field. Triggers on: create ticket, create a ticket, update jira, update ticket, jira description, write ticket, fix jira formatting, subtask, sub-task."
user-invocable: true
---

# Create or Update Jira Ticket

## When to Use

- When the user asks to create a new ticket
- When the user asks to update a ticket description
- After committing changes for a Jira ticket

## Creation Flow

### 1. Check for duplicates

Search Jira for existing tickets covering the same work. If a match exists, update it instead.

### 2. Determine project and parent

- Default project: **ACD**
- Ask for parent ticket if not provided

### 3. Write the description

**Formatting rules:**
- Use Markdown (Jira Cloud renders it natively): `##` headings, `-` bullets, backticks, `1.` numbered lists, `**bold**`
- Do NOT use Jira wiki markup (`h2.`, `*bold*`, `#` for ordered lists)
- Do NOT use Markdown tables (400 errors on create, renders poorly on update). Use bullet lists instead.
- No hard line wrapping. Jira handles soft wrapping. Break on sentence boundaries, not character limits.
- URLs must use explicit Markdown link syntax to render as clickable: `[link text](url)`. Bare URLs do not auto-link in Jira.
- Write descriptions in present tense, not past tense. Describe what the ticket does, not what was done.

**Content rules:**
- Present tense ("Remove the flag" not "Removed the flag")
- Lead with a one-line summary of the purpose
- Bullet points for changes or acceptance criteria
- Focus on "what" and "why", not file-level changelogs

### 4. Create the ticket

```
mcp__otter__jira_create project_key="ACD" issue_type="Task" summary="..." description="..." labels="agent-created" parent_key="..."
```

Always include `labels="agent-created"`.

### 5. Post-creation setup

**Default (non-backlog) tickets** — do all of:
1. Assign to current user (use `mcp__otter__whoami` to get email if needed)
2. Move to current sprint (see "Sprint Assignment" below)
3. Transition to Ready: `transition_id="81"`

**Backlog tickets** (user explicitly says "backlog") — skip all three. The `agent-created` label is already set at creation.

### 6. Verify

Confirm success and share the ticket URL.

## Update Flow

- Extract ticket key from CONTEXT.md, branch name, or ask the user
- Gather content from CONTEXT.md, git diff, or conversation
- `mcp__otter__jira_update ticket_id="<key>" fields='description="..."'`

## Sprint Assignment

1. Find a ticket already in the active sprint:
   ```
   mcp__otter__jira_search jql="project = ACD AND sprint in openSprints()" limit=1
   ```
2. Get the numeric sprint ID via Bash:
   ```
   otter mcp exec claude_ai_atlassian_getJiraIssue --cloudId="canva.atlassian.net" --issueIdOrKey="<ticket>" --fields='["customfield_10020"]'
   ```
   Sprint ID is at `fields.customfield_10020[0].id`.
3. Set sprint on target ticket:
   ```
   mcp__otter__jira_update ticket_id="<ticket>" fields='customfield_10020="<sprint_id>"'
   ```

## Quick Reference: JQL Queries

- **My sprint tasks**: `project = ACD AND sprint in openSprints() AND assignee = currentUser()`
- **All sprint tasks**: `project = ACD AND sprint in openSprints()`
- **My backlog**: `project = ACD AND sprint is EMPTY AND assignee = currentUser() AND status != Done`
- **Unassigned in sprint**: `project = ACD AND sprint in openSprints() AND assignee is EMPTY`
- **Done this sprint**: `project = ACD AND sprint in openSprints() AND status = Done`

## Reference

- **Board ID**: 914 (ACD Scrum Board)
- **Cloud ID**: canva.atlassian.net (for Atlassian Claude AI tools)
- **Sprint field**: `customfield_10020` (array of sprint objects with `id`, `name`, `state`)
- **Transition IDs** (ACD project):
  - 71: Backlog
  - 81: Ready
  - 31: In Progress
  - 111: Blocked
  - 61: Testing
  - 51: Review
  - 91: Delivered
  - 101: Cancelled

