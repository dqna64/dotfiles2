# Story Format and Narrative Rules

Use this reference after gathering PR context and before creating `story.json`.

## Narrative Ordering

Build the shortest sequence that explains why each important change exists.
Prefer these story shapes:

| Change shape | Useful order |
| --- | --- |
| New behavior | Trigger -> core decision/state -> collaborators -> result -> tests |
| Refactor | Old responsibility -> new boundary -> migrated callers -> preserved behavior |
| State machine | Initiating action -> states/transitions -> race/failure handling -> projections -> tests |
| Data flow | Source -> transformation -> storage/transport -> consumer -> validation |
| API change | Contract -> implementation -> callers -> compatibility -> tests |
| Removal | Previous owner -> removed path -> surviving path -> cleanup -> tests |

Do not follow file order or commit order unless it happens to match the final
causal structure.

## Evidence Rules

- Use exact base/head SHA links.
- Explain final behavior, not abandoned intermediate commits.
- Use PR body and human discussion to recover rationale, never to override code.
- Place tests next to the behavior they establish, then summarize them in the
  tests section.
- Mark unsupported architectural relationships as `inference`.
- Mark missing, omitted, binary, contradictory, or inaccessible evidence as
  `unknown`.
- Do not create a watchout merely to fill the section.

## File Classification

Use these defaults, then correct them when the PR proves otherwise:

- `core`: runtime implementation or public contract central to the change.
- `supporting`: changed caller, adapter, helper, documentation, or integration.
- `test`: behavioral test code or fixtures.
- `mechanical`: build metadata, project config, lockfiles, snapshots, or wiring
  whose contents do not need a narrative chapter.
- `generated`: generated source or generated API/config output.

Every changed file must appear exactly once in `files`. A file can be
mechanical and still link to a chapter if it materially explains dependency
wiring.

## Story JSON Schema

Write UTF-8 JSON with this top-level shape:

```json
{
  "meta": {
    "owner": "Canva",
    "repo": "canva",
    "number": 123,
    "title": "PR title",
    "url": "https://github.com/Canva/canva/pull/123",
    "author": "octocat",
    "state": "OPEN",
    "is_draft": false,
    "base_ref": "master",
    "base_sha": "40-character SHA",
    "head_ref": "feature-branch",
    "head_sha": "40-character SHA",
    "additions": 10,
    "deletions": 3,
    "changed_files": 2
  },
  "overview": {
    "one_minute_summary": "Two or three concise sentences.",
    "why": "The problem or responsibility this PR addresses.",
    "scope": ["Included behavior"],
    "not_in_scope": ["Explicitly deferred behavior"]
  },
  "flow": [
    {
      "label": "1. Initiate",
      "description": "What begins the behavior.",
      "source_urls": ["https://github.com/..."]
    }
  ],
  "chapters": [
    {
      "title": "The core responsibility moves",
      "summary": "The chapter thesis.",
      "confidence": "fact",
      "evidence": [
        {
          "label": "Changed implementation",
          "url": "https://github.com/..."
        }
      ],
      "steps": [
        {
          "title": "A focused step",
          "explanation": "Why this step follows from the previous one.",
          "code": {
            "language": "typescript",
            "label": "Final implementation",
            "content": "const example = true;",
            "source_url": "https://github.com/..."
          }
        }
      ]
    }
  ],
  "tests": [
    {
      "behavior": "Concurrent starts share one attempt.",
      "evidence": "The test issues two calls before resolving auth.",
      "source_url": "https://github.com/..."
    }
  ],
  "watchouts": [
    {
      "kind": "risk",
      "title": "A concrete risk",
      "detail": "Evidence-backed explanation.",
      "source_urls": ["https://github.com/..."]
    }
  ],
  "files": [
    {
      "path": "src/example.ts",
      "status": "modified",
      "category": "core",
      "role": "Owns the new behavior.",
      "treatment": "Chapter 1",
      "additions": 8,
      "deletions": 2,
      "url": "https://github.com/..."
    }
  ]
}
```

## Schema Constraints

- Use only plain text in narrative fields. Do not include Markdown or HTML.
- Use `fact`, `inference`, or `unknown` for chapter confidence.
- Use `risk`, `assumption`, or `unknown` for watchout kind.
- Keep `flow`, `chapters`, and `files` non-empty.
- Keep file paths unique and make their count equal `meta.changed_files`.
- Keep every URL absolute and use HTTPS.
- Omit `code` when no excerpt helps. When present, include all four code fields.
- Use empty arrays for absent scope, deferred scope, tests, or watchouts.
- Keep excerpts small enough to scan. Prefer one semantic unit, not a whole
  file or large diff hunk.

## Artifact Voice

- Write for an experienced engineer who may not know this exact subsystem.
- Define only concepts needed to connect the changed pieces.
- Prefer direct sentences and concrete verbs.
- Avoid changelog narration such as "then the author added".
- Avoid praise, review theater, and severity labels.
- Avoid em dashes.
- Separate known behavior from interpretation.
