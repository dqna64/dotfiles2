// Autonomous-orchestration Workflow template: guide -> chunked (implement -> review -> fix).
// Generic skeleton for the Workflow tool. Replace the CONFIG block + prompt builders + UNITS for your task.
// Plain JavaScript (NOT TypeScript). No Date.now()/Math.random()/argless new Date() (they throw).
// Pass this via Workflow({script: ...}) or save + Workflow({scriptPath: ...}).

export const meta = {
  name: 'orchestrated-units',
  description: 'Implement N independent units in isolated worktrees, each driven to a green gate + ready-for-review PR, bounded at MAX_CONCURRENT.',
  phases: [
    { title: 'Guide', detail: 'Shared authoring/convention brief read once and handed to all implementers' },
    { title: 'Work', detail: 'implement -> review -> fix per unit, in chunks of MAX_CONCURRENT' },
  ],
}

// ---- CONFIG (edit per task) -------------------------------------------------
const MAX_CONCURRENT = 3 // bound heavy gates; do NOT raise without capacity headroom
const BASE = 'master'
const LIGHT_CHECK = 'the project light check, e.g. pnpm fin --silent / npm test'
const HEAVY_GATE = 'the project final gate, e.g. taz check / make verify (bazel-backed, heavy, shared)'

// One entry per unit of work. wt = pre-created worktree path; branch = pre-created branch off BASE.
const UNITS = [
  // { key: 'unit-a', branch: 'prefix-unit-a', wt: '/abs/path/worktrees/unit-a', title: '...', spec: '...detailed task...' },
]

const RULES = [
  'HARD RULES (never violate):',
  '- Work ONLY in your assigned worktree. Never touch the main checkout, another worktree, or ' + BASE + '.',
  '- No force-push, git reset --hard, rebase, branch deletion, git add -A/git add . (stage specific files), git worktree remove, rm -rf, or history rewriting. New commits only (never amend).',
  '- Do not modify generated/vendored files. Do not request reviewers or @-mention/ping anyone on the PR (that is the human\'s job).',
  '- Stay within the repo and authorized destinations. PR base = ' + BASE + ', ready-for-review (not draft), repo-conventional title/body + required trailers.',
  '',
  'MANDATE: evaluate a couple of approaches and pick the simplest/most idiomatic/convention-matching/complete one. Implement; add tests; iterate with `' + LIGHT_CHECK + '` (cheap); pass `' + HEAVY_GATE + '` as the FINAL gate, calling it as FEW times as possible. Commit specific files, push (no force), open a ready-for-review PR. Only return after the PR exists. If truly blocked after real effort: push what you have, open a DRAFT PR documenting the blocker, set blockers[], return. Never hang.',
].join('\n')

const IMPL_SCHEMA = {
  type: 'object', required: ['branch', 'prCreated', 'gatePassed', 'summary'],
  properties: {
    branch: { type: 'string' }, prCreated: { type: 'boolean' }, prUrl: { type: 'string' },
    gatePassed: { type: 'boolean' }, lightCheckPassed: { type: 'boolean' },
    approachChosen: { type: 'string' }, filesChanged: { type: 'array', items: { type: 'string' } },
    testsAdded: { type: 'boolean' }, commitSha: { type: 'string' },
    blockers: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' },
  },
}
const REVIEW_SCHEMA = {
  type: 'object', required: ['approved', 'blockingIssues'],
  properties: {
    approved: { type: 'boolean' },
    blockingIssues: { type: 'array', items: { type: 'object', required: ['issue'], properties: { issue: { type: 'string' }, file: { type: 'string' }, suggestedFix: { type: 'string' } } } },
    notes: { type: 'array', items: { type: 'string' } },
  },
}
const FIX_SCHEMA = {
  type: 'object', required: ['fixed', 'gatePassed'],
  properties: { fixed: { type: 'boolean' }, gatePassed: { type: 'boolean' }, prUrl: { type: 'string' }, summary: { type: 'string' }, remaining: { type: 'array', items: { type: 'string' } } },
}

const GUIDE_PROMPT = [
  'Read the project conventions/API/patterns relevant to this task (name the exact files to read) and produce ONE concrete, copy-pasteable authoring guide an implementer can follow end-to-end.',
  'Cover: the canonical pattern + exact import paths, success/error/edge handling, any manifest/registration step, the test style (with a sketch), and how to run ' + LIGHT_CHECK + ' / ' + HEAVY_GATE + '. Be self-contained; this is handed verbatim to every implementer.',
].join('\n')

function implPrompt(u, guide) {
  return [
    'Implement ONE unit in your own pre-created git worktree and take it to a ready-for-review PR.',
    'WORKTREE (cd here): ' + u.wt, 'BRANCH (off ' + BASE + '): ' + u.branch, 'UNIT: ' + u.key + ' - ' + u.title,
    '', '=== SPEC ===', u.spec, '', '=== GUIDE ===', guide || '(read the convention files yourself)', '', '=== RULES & MANDATE ===', RULES,
    '', 'Begin by cd-ing in, confirming branch/status, and locating exact sites with grep (spec line numbers are approximate). Return the structured result.',
  ].join('\n')
}
function reviewPrompt(p) {
  return [
    'STRICT read-only reviewer. Do NOT edit. Inspect the real branch diff: git -C ' + p.u.wt + ' diff ' + BASE + '...HEAD and the changed files.',
    'Implementer report: ' + JSON.stringify(p.impl),
    'Verify the change matches existing conventions/patterns, is correct + complete, has meaningful tests, edits no generated files, is not a draft, and the gate genuinely passes. Flag only BLOCKING issues with concrete fixes. approved=true only if none.',
  ].join('\n')
}
function fixPrompt(p) {
  return [
    'Fix BLOCKING review issues in the worktree and restore a green, ready-for-review PR.',
    'WORKTREE: ' + p.u.wt, 'BRANCH: ' + p.u.branch, 'Issues: ' + JSON.stringify(p.review.blockingIssues), '', RULES,
    '', 'Fix every issue, re-pass ' + LIGHT_CHECK + ' then ' + HEAVY_GATE + ', commit (new commit, specific files), push (no force), keep the PR ready-for-review. Return the structured result.',
  ].join('\n')
}

function chunk(a, n) { const o = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o }

phase('Guide')
log('Building shared authoring guide...')
const guide = await agent(GUIDE_PROMPT, { agentType: 'Explore', effort: 'high', label: 'guide', phase: 'Guide' })

phase('Work')
const all = []
const chunks = chunk(UNITS, MAX_CONCURRENT)
for (let i = 0; i < chunks.length; i++) {
  log('Chunk ' + (i + 1) + '/' + chunks.length + ' (<=' + MAX_CONCURRENT + ' concurrent): ' + chunks[i].map(u => u.key).join(', '))
  const res = await pipeline(
    chunks[i],
    (u) => agent(implPrompt(u, guide), { agentType: 'general-purpose', effort: 'high', label: 'impl:' + u.key, phase: 'Work', schema: IMPL_SCHEMA }).then((impl) => ({ u, impl })),
    (p) => agent(reviewPrompt(p), { agentType: 'Explore', effort: 'high', label: 'review:' + p.u.key, phase: 'Work', schema: REVIEW_SCHEMA }).then((review) => ({ ...p, review })),
    (p) => (p.review && p.review.approved === true)
      ? Promise.resolve({ ...p, fix: { skipped: true } })
      : agent(fixPrompt(p), { agentType: 'general-purpose', effort: 'high', label: 'fix:' + p.u.key, phase: 'Work', schema: FIX_SCHEMA }).then((fix) => ({ ...p, fix })),
  )
  all.push(...res)
}

const results = all.filter(Boolean).map((e) => ({
  key: e.u && e.u.key, branch: e.u && e.u.branch,
  prUrl: (e.fix && e.fix.prUrl) || (e.impl && e.impl.prUrl),
  gatePassed: (e.fix && e.fix.gatePassed === true) ? true : !!(e.impl && e.impl.gatePassed),
  approved: !!(e.review && e.review.approved), blockers: e.impl && e.impl.blockers,
}))
log('Done. ' + results.filter((r) => r.prUrl).length + '/' + results.length + ' PRs created.')
return { results }
