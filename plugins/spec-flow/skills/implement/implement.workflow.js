export const meta = {
  name: 'flow-implement',
  description: 'Implement an approved OpenSpec change in its worktree: tdd-developer applies tasks test-first, a five-lens review panel (spec, code-review, security-review, test-rigor, observability) reviews in parallel, bounded fix loop, build-engineer gets the build clean, then docs polish.',
  phases: [
    { title: 'Implement', detail: 'tdd-developer applies the OpenSpec tasks test-first' },
    { title: 'Review', detail: 'five-lens panel (spec, code-review, security-review, test-rigor, observability) checks the diff in parallel' },
    { title: 'Fix', detail: 'tdd-developer resolves reviewer findings (bounded loop)' },
    { title: 'Build', detail: 'build-engineer runs the format/lint/build gate' },
    { title: 'Polish', detail: 'docs + final tidy' },
  ],
}

// args: { worktree, repoRoot, change, issue, base, stackUp, buildSystem }
// buildSystem: the project's build tool, used only as a hint for the build phase (e.g. 'cargo',
// 'gradle', 'npm', 'go', 'pytest', or 'auto' to let the agent discover it). NOT an exhaustive
// switch — the agents detect the real runner from the repo.
// Robust to args arriving as a JSON string (some invocations stringify it) or missing.
const _args = typeof args === 'string' ? JSON.parse(args) : (args || {})
const { worktree, change, issue, base = 'origin/main', stackUp = false, buildSystem = 'auto' } = _args
if (!worktree || !change || issue === undefined || issue === null) {
  // Fail fast — never run a review against an empty/clean tree and report a false blocker.
  throw new Error(
    `flow-implement: missing required args (worktree/change/issue). Got: ${JSON.stringify(_args)}`,
  )
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['summary', 'spec_conformance', 'tests_ran', 'findings', 'approve'],
  properties: {
    summary: { type: 'string' },
    spec_conformance: { enum: ['full', 'partial', 'failing'] },
    tests_ran: { enum: ['full', 'degraded', 'none'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'severity', 'location', 'rule', 'problem', 'fix'],
        properties: {
          id: { type: 'string' },
          severity: { enum: ['blocker', 'major', 'minor', 'nit'] },
          location: { type: 'string' },
          rule: { type: 'string' },
          problem: { type: 'string' },
          fix: { type: 'string' },
        },
      },
    },
    approve: { type: 'boolean' },
  },
}

const testInstruction = stackUp
  ? `The repo's external test prerequisites are available — run the FULL test suite as your gate. Discover the runner from the repo (e.g. \`cargo test\`, \`npm test\`, \`./gradlew test\`, \`go test ./...\`, \`pytest\`).`
  : `External test prerequisites (e.g. a docker compose stack or a database) are NOT reachable — DEGRADE to a build + the prerequisite-independent unit tests, and state plainly in your summary that the full suite did not run and why. Never silently skip.`

// Strict guardrail appended to every agent prompt: implement agents must stay inside the
// worktree and never take outward/backlog actions. Prioritization + issue creation are the
// owner's job (a dogfooding finding: agents were auto-creating GitHub issues with self-assigned
// priorities).
const GUARDRAILS = `GUARDRAILS (strict): Operate ONLY inside the worktree. Do NOT create or edit GitHub issues, open or modify PRs, post GitHub comments, push, or take any other outward or destructive action. If you discover follow-up work, related bugs, or candidate new issues, LIST them in your returned summary for the owner to triage — never file them yourself. Backlog creation and prioritization are the owner's job, not yours.`

// Resolve the plugin's agents BARE-FIRST, then fall back to the plugin-namespaced
// id (`spec-flow:<name>`). This preserves the intended override mechanism — a consuming
// repo that defines its own `tdd-developer`/`reviewer`/etc. wins — while still working
// in environments where only the namespaced agent is registered (the common case when the
// plugin is installed). Bare ids containing ':' (already namespaced) and built-ins like
// `general-purpose` resolve on the first try and never hit the fallback.
async function agentNS(prompt, opts = {}) {
  const want = opts.agentType
  try {
    return await agent(prompt, opts)
  } catch (e) {
    const msg = String((e && e.message) || e)
    if (want && !want.includes(':') && /not found/i.test(msg)) {
      return await agent(prompt, { ...opts, agentType: `spec-flow:${want}` })
    }
    throw e
  }
}

// ── Phase: Implement ───────────────────────────────────────────────────────
phase('Implement')
await agentNS(
  `You are implementing an approved OpenSpec change in an existing git worktree.
WORKTREE (run everything here, cwd): ${worktree}
CHANGE: ${change}  — tasks at openspec/changes/${change}/tasks.md, spec at openspec/changes/${change}/specs/**/spec.md
ISSUE: #${issue}

Work the tasks in tasks.md test-first (RED→GREEN→REFACTOR), honoring the repo's documented
conventions (its CLAUDE.md / CONTRIBUTING / style guide — TDD, SOLID, and whatever hard rules the
repo documents). Mark each task '- [x]' as you complete it and commit your work on the current
branch with focused messages. Do NOT push and do NOT touch main.
${testInstruction}
Return a short summary of what you implemented and the test outcome.

${GUARDRAILS}`,
  { agentType: 'tdd-developer', label: `implement:${change}`, phase: 'Implement' },
)

// ── Phases: Review → Fix (bounded loop) ──────────────────────────────────────
const MAX_ROUNDS = 3
let review = null
let round = 0
const residual = []

// Review is a PANEL of FIVE lenses, run in parallel each round:
//   1. spec            — the project reviewer (spec-conformance + the repo's documented rules +
//                        scenario→test traceability).
//   2. code-review     — correctness-bug hunt (logic errors, edge cases, panics, concurrency/error
//                        handling), via the built-in /code-review skill.
//   3. security-review — security pass (input validation, auth/tenant isolation, injection,
//                        secret/data exposure, external-surface hardening), via /security-review;
//                        SELF-GATES (approve+empty) on changes touching no relevant surface.
//   4. test-rigor      — TEST-rigor (test-rigor-reviewer): bidirectional. Does the diff's touched
//                        public surface + observable side effects have ANTAGONISTIC, regression-
//                        exposing tests (happy-path-only / no side-effect assertion = a gap)? AND
//                        the brake: over-built tests (fakes reconstructing a dependency, library
//                        re-verification) + test churn (per-test container restarts) = minor unless
//                        egregious. No-ops off any public surface, side effect, or added tests.
//   5. observability   — OBSERVABILITY (observability-reviewer): are the diff's new code paths +
//                        failure modes diagnosable in prod? Logging at the right level w/ structured
//                        context, metrics on ops + errors (bounded label cardinality), tracing/spans
//                        around new I/O, no silently-swallowed failures, no secrets in telemetry.
//                        SELF-GATES (approve+empty) on changes introducing no new path/I/O/failure.
// Findings from all five merge; a fix round addresses blocker/major from ANY lens; approval requires
// every lens to approve with no must-fix findings. The merge/approval logic generalizes over N
// lenses — adding or removing a lens needs NO change to the loop below.
// The code-review/security-review lenses INVOKE the built-in skills, so they need Skill-tool access:
// they use `general-purpose` (tools: *), NOT the `reviewer` agent (Read/Bash/Grep/Glob only).
const reviewLenses = [
  {
    label: 'spec',
    agentType: 'reviewer',
    prompt: `Review the implementation of OpenSpec change "${change}" for issue #${issue}.
worktree: ${worktree}
base: ${base}
change: ${change}
Diff is ${base}...HEAD in that worktree. Follow your output contract exactly (JSON only).
ALSO enforce spec-scenario → test traceability: enumerate every "#### Scenario:" in the change's
specs/**/spec.md, map each to the diff's test(s), and emit a "major" finding (rule
"scenario→test traceability", location = the spec file + scenario name) for EVERY scenario with no
backing test — one finding per uncovered scenario, no nitpick spray. A "major" finding withholds
approval and feeds the fix loop, so an uncovered scenario blocks approval until a test is added.
You MAY add a one-line scenario-coverage summary to "summary".`,
  },
  {
    label: 'code-review',
    agentType: 'general-purpose',
    prompt: `Run a CORRECTNESS review of the diff ${base}...HEAD in the git worktree at ${worktree}.
Invoke the built-in \`/code-review\` skill on that diff (cwd ${worktree}) and have it hunt correctness
defects ONLY: logic errors, off-by-one / boundary / edge-case mistakes, unhandled error paths,
panics / unwrap on fallible values, incorrect concurrency or async ordering, resource leaks, and
contract violations between caller and callee. Do NOT re-review spec conformance or style — the
other lenses own those. If you find no correctness defect, return approve=true with an empty
findings array.
Then MAP the skill's result into EXACTLY this JSON contract and output nothing else:
{"summary":"…","spec_conformance":"full","tests_ran":"full","findings":[{"id":"…","severity":"blocker|major|minor|nit","location":"file:line","rule":"correctness","problem":"…","fix":"…"}],"approve":true|false}.
(spec_conformance/tests_ran are owned by the spec reviewer — leave them "full". A blocker/major
finding MUST set approve=false.)
If \`/code-review\` is not invokable here, perform the same correctness pass yourself by reading the
diff and emit the identical contract — same outcome.`,
  },
  {
    label: 'security-review',
    agentType: 'general-purpose',
    prompt: `Run a SECURITY review of the diff ${base}...HEAD in the git worktree at ${worktree}.
Invoke the built-in \`/security-review\` skill on that diff (cwd ${worktree}).
This lens SELF-GATES. First enumerate whether the change touches ANY of these security-relevant
surfaces: (1) input parsing / untrusted-input handling, (2) multi-tenant isolation / cross-tenant
data access, (3) authentication or authorization, (4) external endpoints / network surfaces, (5)
secrets, credentials, or sensitive-data exposure. If the change touches NONE of them, return
approve=true with an EMPTY findings array (state in the summary that no security-relevant surface
was found). If it touches one or more, review them for: missing/weak input validation, injection
(SQL/CQL/command/log), tenant-isolation bypass, broken authz, unsafe external calls, and leaked
secrets/data. Emit a blocker/major finding for any real exposure.
MAP the result into EXACTLY this JSON contract and output nothing else:
{"summary":"…","spec_conformance":"full","tests_ran":"full","findings":[{"id":"…","severity":"blocker|major|minor|nit","location":"file:line","rule":"security","problem":"…","fix":"…"}],"approve":true|false}.
(spec_conformance/tests_ran are owned by the spec reviewer — leave them "full". A blocker/major
finding MUST set approve=false.)
If \`/security-review\` is not invokable here, perform the same security pass yourself by reading the
diff and emit the identical contract — same outcome.`,
  },
  {
    label: 'test-rigor',
    agentType: 'test-rigor-reviewer',
    prompt: `Audit TEST RIGOR for the diff ${base}...HEAD in the git worktree at ${worktree} (change "${change}", issue #${issue}).
Scope to the public surface the diff adds/changes (HTTP/gRPC API, CLI, library/public API) and any
observable side effects it causes (emitted events, DB writes, published messages, files). For each,
judge whether the tests would FAIL on a regression — not merely exercise the happy path. Flag (rule
"test-rigor") any missing antagonistic case the surface can exhibit: malformed/oversized/wrong-type
input, boundary/limit, error-contract honesty (the right error type/code/message, not a blurred
one), concurrency conflicts, auth/tenant isolation where applicable, already-exists/not-found,
idempotency/replay. And flag (rule "side-effect-coverage") any write/op whose tests assert the
direct result but NOT its observable side effect (the emitted event/message/row is never asserted),
judged surface → state → side-effect. A happy-path-only surface, or one with no side-effect
assertion, is a "major" gap (withholds approval, feeds the fix loop).
ALSO run the brake (the other direction). Flag (rule "over-testing") tests the diff adds that are
over-built: a fake reconstructing a well-tested dependency to test the dependency rather than this
change (a hand-built fake SSH/DB/HTTP server where a boundary stub would do), a test that only
re-verifies a library/framework, a trivial-glue test with no nameable regression, or a pure
duplicate. And flag (rule "test-practicality") avoidable test-infrastructure churn — most importantly
a Testcontainers test that restarts a container per test where a shared/reused container would give
the same coverage far faster. These default to "minor" (surfaced, non-blocking); escalate to "major"
only for egregious, objective waste. The brake is for high-confidence waste, not taste.
If the diff touches NO public surface, observable side effect, OR tests, return approve=true with
empty findings. Follow your output contract exactly (JSON only); leave spec_conformance/tests_ran
"full" (the spec reviewer owns them).`,
  },
  {
    label: 'observability',
    agentType: 'observability-reviewer',
    prompt: `Audit OBSERVABILITY for the diff ${base}...HEAD in the git worktree at ${worktree} (change "${change}", issue #${issue}).
First learn the repo's existing observability stack (its logging/metrics/tracing conventions) and
judge against THAT, not a foreign one. Scope to the new code paths and failure modes the diff
introduces — new operations, new I/O (network/DB/external calls), new error/Result/exception
branches, new async/concurrent work. For each, judge whether an operator could SEE and DIAGNOSE it
in production. Flag (rule "observability") any: significant path/transition with no log at an
appropriate level; a log missing the structured context (id/operation/outcome) needed to act; a new
failure branch that is swallowed/mapped-away with NO telemetry (a silent failure — lean blocker); a
new SLI-relevant operation or failure class with no metric, or a metric with unbounded label
cardinality (raw ids/user input/paths as labels); new I/O with no span/trace coverage or dropped
context propagation across new async boundaries; and any secret/credential/PII emitted to
logs/spans/metrics (blocker). A silently-swallowed failure or a logged secret is a "blocker"; a new
operation/error path with no telemetry where the repo's conventions expect one is "major" (both
withhold approval and feed the fix loop). If the diff introduces NO new code path, I/O, or failure
mode, return approve=true with empty findings. Follow your output contract exactly (JSON only);
leave spec_conformance/tests_ran "full" (the spec reviewer owns them).`,
  },
]

while (round < MAX_ROUNDS) {
  round++
  phase('Review')
  const lensResults = await parallel(
    reviewLenses.map(l => () =>
      agentNS(`${l.prompt}\n\n${GUARDRAILS}`, {
        agentType: l.agentType,
        label: `review:${l.label}:${change}#${round}`,
        phase: 'Review',
        schema: REVIEW_SCHEMA,
      })),
  )
  const reviews = lensResults.filter(Boolean)
  if (reviews.length === 0) { residual.push('all review lenses returned no result'); break }

  const findings = reviews.flatMap(r => r.findings || [])
  const mustFix = findings.filter(f => f.severity === 'blocker' || f.severity === 'major')
  const specLens = lensResults[0] // aligned with reviewLenses[0] (the spec reviewer)
  review = {
    summary: lensResults
      .map((r, i) => `[${reviewLenses[i].label}] ${r ? r.summary : '(no result)'}`)
      .join('\n\n'),
    spec_conformance: specLens ? specLens.spec_conformance : 'unknown',
    tests_ran: specLens ? specLens.tests_ran : (stackUp ? 'full' : 'degraded'),
    findings,
    approve: reviews.every(r => r.approve) && mustFix.length === 0,
  }

  if (review.approve) break
  if (round >= MAX_ROUNDS) {
    residual.push(...mustFix.map(f => `[${f.severity}] ${f.location}: ${f.problem}`))
    break
  }

  phase('Fix')
  const fixList = mustFix.map(f => `- [${f.severity}] ${f.location} (${f.rule}): ${f.problem}\n  suggested: ${f.fix}`).join('\n')
  await agentNS(
    `Resolve these review findings in the worktree, test-first where behavior changes.
WORKTREE (cwd): ${worktree}
CHANGE: ${change}
FINDINGS:
${fixList}
Fix each, keep the full suite (or degraded subset) green, commit with focused messages.
Do NOT push and do NOT touch main. Return what you changed.

${GUARDRAILS}`,
    { agentType: 'tdd-developer', label: `fix:${change}#${round}`, phase: 'Fix' },
  )
}

// ── Phase: Build ─────────────────────────────────────────────────────────────
phase('Build')
const buildHint = buildSystem && buildSystem !== 'auto' ? ` (build system: ${buildSystem})` : ''
await agentNS(
  `In the worktree at ${worktree}, get the build clean for review${buildHint}.
Discover and run the repo's format, lint, and build steps — examples by ecosystem:
  - Rust:   \`cargo fmt\`, then \`cargo clippy --all-targets -- -D warnings\`, then \`cargo build\`
  - Node:   the repo's lint + build scripts (e.g. \`npm run lint && npm run build\`)
  - Gradle: \`./gradlew spotlessApply build\` (or the project's check task)
  - Go:     \`gofmt -l .\`, \`go vet ./...\`, \`go build ./...\`
Use whatever the repo actually configures. Resolve any formatting/lint/build issues WITHOUT
changing behavior, and commit the result. Do NOT push and do NOT touch main. Return the final
format/lint/build status.

${GUARDRAILS}`,
  { agentType: 'build-engineer', label: `build:${change}`, phase: 'Build' },
)

// ── Phase: Polish ────────────────────────────────────────────────────────────
phase('Polish')
const polish = await agentNS(
  `Final documentation polish for OpenSpec change "${change}" in worktree ${worktree}.
Ensure any new modules/behaviors are documented consistently with the repo's conventions
(module/responsibility comments, any architecture/index docs the repo keeps, doc comments on
public items). ALSO: if this change alters user-facing behavior (a public API, CLI, config, or
how the service is run), update the repo's user-facing docs accordingly (e.g. README, a docs/
tree, an mdBook under book/, or a docs site) — keep its pages and examples current. If the repo
has no user-facing docs or the change has no user-facing surface, skip this and say so.
Make only documentation/comment edits; commit them. Do NOT push, do NOT touch main.
Return a one-line note on what you documented (including whether user docs changed).

${GUARDRAILS}`,
  { agentType: 'tdd-developer', label: `polish:${change}`, phase: 'Polish' },
)

return {
  change,
  issue,
  tests_ran: review ? review.tests_ran : (stackUp ? 'full' : 'degraded'),
  spec_conformance: review ? review.spec_conformance : 'unknown',
  approved: !!(review && review.approve && residual.length === 0),
  review_rounds: round,
  residual_findings: residual,
  review_summary: review ? review.summary : 'no review captured',
  polish: polish || 'n/a',
}
