---
name: update-jira
description: "Create or update a Jira ticket description. MUST be invoked proactively any time you are about to create or edit a Jira issue that has a description field - via mcp__claude_ai_Atlassian__createJiraIssue / editJiraIssue, or the otter jira_mcp_* fallbacks. Triggers on: create ticket, create a ticket, update jira, update ticket, jira description, write ticket, fix jira formatting, subtask, sub-task."
user-invocable: true
---

# Create or Update Jira Ticket

## Tools

**Primary** - the claude.ai Atlassian connector:

| Purpose | Tool |
|---|---|
| Create | `mcp__claude_ai_Atlassian__createJiraIssue` |
| Update fields | `mcp__claude_ai_Atlassian__editJiraIssue` |
| Read | `mcp__claude_ai_Atlassian__getJiraIssue` |
| Search | `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` |
| List transitions | `mcp__claude_ai_Atlassian__getTransitionsForJiraIssue` |
| Apply transition | `mcp__claude_ai_Atlassian__transitionJiraIssue` |
| Who am I | `mcp__claude_ai_Atlassian__atlassianUserInfo` |

**Fallback** - if the connector is unavailable, otter serves the same API. Swap the prefix:
`mcp__plugin_otter-tools_otter__jira_mcp_<sameToolName>` (e.g. `..._jira_mcp_createJiraIssue`).
Requires `otter login atlassian`; check with `otter status atlassian --json`.
Last resort from Bash: `otter mcp exec jira_mcp_getJiraIssue --cloudId=... --issueIdOrKey=...`

**`cloudId` is required on every call**: `d3a6b95b-bc47-4f92-b865-3ec7796e70f5` (the site URL `canva.atlassian.net` also works).

## Never hardcode project-specific values

Project key, transition IDs, and the sprint field differ per project and go stale. Derive them:

- **Project**: from the ticket key in the branch name, `CONTEXT.md`, or the plan doc. Ask if it cannot be inferred. Do not assume a default.
- **Transition ID**: call `getTransitionsForJiraIssue` on the issue and match the target status by name. Canva's workflow transitions are marked `isGlobal: true` and the IDs below have been verified identical across ACD and CLB, so they usually transfer - but derive rather than assume, since a project on a custom workflow will differ.
- **Sprint field**: read an issue already in the active sprint and find the field holding an array of objects with `id`/`name`/`state`. It is usually `customfield_10020`, but confirm rather than assume.

## Creation Flow

### 1. Check for duplicates

Search for existing tickets covering the same work. If a match exists, update it instead.

### 2. Determine project and parent

Derive the project as above. Ask for the parent ticket if not provided.

### 3. Write the description

**Formatting rules:**
- Use Markdown (Jira Cloud renders it natively): `##` headings, `-` bullets, backticks, `1.` numbered lists, `**bold**`
- Do NOT use Jira wiki markup (`h2.`, `*bold*`, `#` for ordered lists)
- Do NOT use Markdown tables (400 errors on create, renders poorly on update). Use bullet lists instead.
- No hard line wrapping. Jira handles soft wrapping. Break on sentence boundaries, not character limits.
- URLs must use explicit Markdown link syntax to render as clickable: `[link text](url)`. Bare URLs do not auto-link in Jira.
- Write descriptions in present tense, not past tense. Describe what the ticket does, not what was done.
- Descriptions are capped at 32000 characters.

**Content rules:**
- Present tense ("Remove the flag" not "Removed the flag")
- Lead with a one-line summary of the purpose
- Bullet points for changes or acceptance criteria
- Focus on "what" and "why", not file-level changelogs

### 4. Create the ticket

```
mcp__claude_ai_Atlassian__createJiraIssue
  cloudId="d3a6b95b-bc47-4f92-b865-3ec7796e70f5"
  projectKey="<derived>"
  issueTypeName="Task"
  summary="..."
  description="..."
  parent="<parent key, for subtasks>"
  additional_fields={"labels": ["agent-created"]}
```

`labels` has no top-level parameter - it MUST go inside `additional_fields`, as must priority, components, and any `customfield_*`.

Always include the `agent-created` label.

### 5. Post-creation setup

**Default (non-backlog) tickets** - do all three:
1. Assign to current user. Get the account ID from `atlassianUserInfo`, then set `assignee_account_id` at creation or via `editJiraIssue` with `fields={"assignee": {"id": "<accountId>"}}`.
2. Move to the current sprint (see below).
3. Transition to Ready - look up the ID via `getTransitionsForJiraIssue`, then `transitionJiraIssue` with `transition={"id": "<id>"}`.

**Backlog tickets** (user explicitly says "backlog") - skip all three. The `agent-created` label is already set at creation.

### 6. Verify

Confirm success and share the ticket URL.

## Update Flow

- Extract the ticket key from `CONTEXT.md`, the branch name, or ask the user
- Gather content from `CONTEXT.md`, the git diff, or the conversation
- ```
  mcp__claude_ai_Atlassian__editJiraIssue
    cloudId="d3a6b95b-bc47-4f92-b865-3ec7796e70f5"
    issueIdOrKey="<key>"
    fields={"description": "..."}
  ```

## Sprint Assignment

1. Find a ticket already in the active sprint:
   ```
   searchJiraIssuesUsingJql jql="project = <KEY> AND sprint in openSprints()" maxResults=1
   ```
2. Read its sprint field to get the numeric sprint ID:
   ```
   getJiraIssue cloudId="..." issueIdOrKey="<ticket>" fields=["customfield_10020"]
   ```
   The active sprint is the entry whose `state` is `active`; take its `id`.
3. Set it on the target ticket:
   ```
   editJiraIssue cloudId="..." issueIdOrKey="<ticket>" fields={"customfield_10020": <sprint_id>}
   ```

## Quick Reference: JQL Queries

Substitute the derived project key for `<KEY>`.

- **My sprint tasks**: `project = <KEY> AND sprint in openSprints() AND assignee = currentUser()`
- **All sprint tasks**: `project = <KEY> AND sprint in openSprints()`
- **My backlog**: `project = <KEY> AND sprint is EMPTY AND assignee = currentUser() AND status != Done`
- **Unassigned in sprint**: `project = <KEY> AND sprint in openSprints() AND assignee is EMPTY`
- **Done this sprint**: `project = <KEY> AND sprint in openSprints() AND status = Done`
- **Recently touched by me**: `assignee = currentUser() AND updated >= -30d ORDER BY updated DESC`

## Reference

- **Cloud ID**: `d3a6b95b-bc47-4f92-b865-3ec7796e70f5` (site: `canva.atlassian.net`)
- **Sprint field**: usually `customfield_10020` (array of sprint objects with `id`, `name`, `state`) - confirm per project

### Transition IDs - verified for ACD and CLB (2026-09-10)

These come from a shared global workflow (`isGlobal: true`), so they are likely correct for other Canva projects too. Confirm with `getTransitionsForJiraIssue` before relying on one for a project not listed here.

- 71: Backlog
- 81: Ready
- 31: In Progress
- 111: Blocked
- 61: Testing
- 51: Review
- 91: Delivered
- 101: Cancelled

Board IDs: ACD 914 (ACD Scrum Board), CLB 110.

Sprint field `customfield_10020` confirmed on CLB; the active sprint entry is the one with `state: "active"`.
