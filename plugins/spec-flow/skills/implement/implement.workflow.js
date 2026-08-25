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

// args: { worktree, change, issue, base, buildSystem, breaker }
// buildSystem: the project's build tool, used only as a hint for the build phase (e.g. 'cargo',
// 'gradle', 'npm', 'go', 'pytest', or 'auto' to let the agent discover it). NOT an exhaustive
// switch — the agents detect the real runner from the repo.
// change: normally 'issue-<N>' (a real OpenSpec change). For a type:tech-debt issue (no spec —
// see "Tech-debt fast path" in docs/workflow.md), SKILL.md passes the literal sentinel
// 'none — type:tech-debt fast path' instead — see TECH_DEBT_CHANGE below.
// Robust to args arriving as a JSON string (some invocations stringify it) or missing.
const _args = typeof args === 'string' ? JSON.parse(args) : (args || {})
// base should always be passed explicitly (SKILL.md resolves the repo's actual default branch
// and passes it) — 'origin/main' here is only a last-resort fallback if it's ever omitted, not
// an assumption this repo uses `main`.
const { worktree, change, issue, base = 'origin/main', buildSystem = 'auto', breaker = 'ask' } = _args
if (!worktree || !change || issue === undefined || issue === null) {
  // Fail fast — never run a review against an empty/clean tree and report a false blocker.
  throw new Error(
    `flow-implement: missing required args (worktree/change/issue). Got: ${JSON.stringify(_args)}`,
  )
}

// A type:tech-debt issue has no OpenSpec change — activate skipped generation entirely (see
// "Tech-debt fast path" in docs/workflow.md) — so SKILL.md passes this exact sentinel as `change`
// instead of a real change name. Every reviewLens prompt below just interpolates ${change} as
// informational text either way, and agents/reviewer.md itself is what switches to
// behavior-preservation mode on seeing this string — only the Implement phase needs its own branch
// here, since the normal prompt assumes tasks.md exists.
const TECH_DEBT_CHANGE = 'none — type:tech-debt fast path'
const isTechDebt = change === TECH_DEBT_CHANGE

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['summary', 'spec_conformance', 'tests_ran', 'findings', 'approve'],
  properties: {
    summary: { type: 'string' },
    spec_conformance: { enum: ['full', 'partial', 'failing'] },
    tests_ran: { enum: ['full', 'unit', 'degraded', 'none'] },
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

// Local gate = the UNIT tier + the branch's flagged set (docs/workflow.md, "Test tiering"). The
// full/integration suite is CI's gate and is never run locally.
const testInstruction = `Run the UNIT tier locally as your gate — the repo's fast, no-container / no-I/O unit tests, i.e. the runner's default fast selection (e.g. \`cargo nextest run\`, \`./gradlew test\`, \`npm test\`, \`go test -short ./...\`, \`pytest -m 'not integration'\`). ALSO run any tests listed in \`.spec-flow/flagged-tests\` at the worktree root if that file exists (one runner-selectable test id per line; '#' and blank lines ignored) — these are tests CI flagged on this branch, guarded locally. Do NOT run the full/integration suite locally — that is CI's gate. State plainly in your summary that the unit tier (plus any flagged tests) ran locally and the full suite runs in CI. If the repo has not split its tests into unit/integration tiers yet, run its default test command and say so.`

// Refactor circuit breaker — set per repo by SPEC_FLOW_REFACTOR_BREAKER (docs/workflow.md,
// "Refactor circuit breaker"). SKILL.md resolves it and passes it as `breaker`; this script cannot
// read env itself.
//
// SCOPE: behavior-preserving runs ONLY — the tech-debt Implement spawn and its fix rounds. Under
// ordinary feature TDD, editing one test file three times is routine (several tests for one
// module), so appending this to the normal path would stall almost every run. The non-configurable
// triage gate in agents/tdd-developer.md still applies everywhere; only this mechanical backstop
// is scoped.
//
// Both modes ask the agent to prefix its summary with BREAKER_STOP_TOKEN when it trips, because
// this script has no hook back out to the lead mid-run: the token is the only way a stop can
// reach the owner. On seeing it the script returns immediately (below) rather than running the
// panel — a fix round would spawn a FRESH agent whose "in this run" edit counter resets, which
// would let it resume editing the very file the breaker just stopped.
const BREAKER_STOP_TOKEN = 'BREAKER-STOP:'
const BREAKER_SENTENCES = {
  ask: ` If you have edited the same test file more than twice in this run, STOP: leave the tree exactly as it is, do NOT revert, and return a summary whose FIRST characters are the exact token \`${BREAKER_STOP_TOKEN}\` followed by the blocker and the classification you could not make. Do not keep editing that file.`,
  revert: ` If you have edited the same test file more than twice in this run, STOP: revert to the last green commit (\`git reset --hard <sha>\`, on the issue branch only) and return a summary whose FIRST characters are the exact token \`${BREAKER_STOP_TOKEN}\` followed by the blocker and the classification you could not make. Do not keep editing that file.`,
  off: ``,
}
// Own-property lookup only: an inherited key ('constructor', 'toString', ...) would otherwise
// resolve to a function and interpolate into every prompt instead of falling back to 'ask'.
const BREAKER = Object.prototype.hasOwnProperty.call(BREAKER_SENTENCES, breaker)
  ? BREAKER_SENTENCES[breaker]
  : BREAKER_SENTENCES.ask

// Strict guardrail appended to every agent prompt: implement agents must stay inside the
// worktree and never take outward/backlog actions. Prioritization + issue creation are the
// owner's job (a dogfooding finding: agents were auto-creating GitHub issues with self-assigned
// priorities).
const GUARDRAILS = `GUARDRAILS (strict): Operate ONLY inside the worktree, on the issue branch. You MAY \`git push\` the issue branch to its own remote at checkpoints so CI runs the full suite on the already-open draft PR (push somewhat frequently — after a completed task or a few green cycles — not on every commit). Do NOT create or edit GitHub issues, do NOT create/modify/mark-ready any PR (it is already open as a draft — leave it draft), do NOT post GitHub comments, do NOT push to \`main\` or any branch other than the issue branch, and do NOT take any other outward or destructive action. If you discover follow-up work, related bugs, or candidate new issues, LIST them in your returned summary for the owner to triage — never file them yourself. Backlog creation and prioritization are the owner's job, not yours.`

// Review lenses are critics, not implementers — they must never commit or push (unlike
// GUARDRAILS above, which permits checkpoint pushes for the tdd-developer/build-engineer phases),
// but they DO need to run the repo's own build/lint/test commands to honestly report tests_ran.
const REVIEW_GUARDRAILS = `GUARDRAILS (strict): You are reviewing, not implementing. Operate ONLY inside the worktree. Running the repo's own format/lint/build/test commands to verify your findings is fine — you need that to honestly report tests_ran — but you may not change the tree: do NOT commit, do NOT \`git push\`, do NOT create or edit GitHub issues, do NOT create/modify/mark-ready any PR, do NOT post GitHub comments, and do NOT take any other outward or destructive action — your output is the JSON review contract, nothing else. If you discover follow-up work, related bugs, or candidate new issues, LIST them in your findings/summary for the owner to triage — never file them yourself.`

// Resolve the plugin's agents BARE-FIRST, then fall back to the plugin-namespaced
// id (`spec-flow:<name>`). This preserves the intended override mechanism — a consuming
// repo that defines its own `tdd-developer`/`reviewer`/etc. wins — while still working
// in environments where only the namespaced agent is registered (the common case when the
// plugin is installed). A bare id already containing ':' (already namespaced), or a built-in
// agent type not defined by this plugin, resolves on the first try and never hits the fallback.
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
// Tech-debt mode permits ONE exception to GUARDRAILS: opening the draft PR itself. Normally
// SKILL.md's step 2 (the lead, outside this script) opens it before this phase ever runs — but a
// tech-debt issue commits no spec, so there's nothing to push until THIS agent's first commit
// lands, and nothing outside this script regains control mid-run to open it the way the docs fast
// path's lead does. This agent is the first (and only) actor with a commit to push.
const GUARDRAILS_TECH_DEBT_IMPLEMENT = `GUARDRAILS (strict): Operate ONLY inside the worktree, on the issue branch. You MAY \`git push\` the issue branch to its own remote at checkpoints. Because no PR exists yet for this branch (no spec was committed for this type:tech-debt issue), you MAY also open ONE draft PR for it — after your first commit, check for an existing one first (\`gh pr list --head <branch> --json number\`); if none exists, open it (mechanics in the prompt above). This is the one exception to "don't touch PRs," specific to this no-spec case — do NOT mark it ready or edit it again after opening it. Do NOT create or edit GitHub issues, do NOT post GitHub comments, do NOT push to \`main\` or any branch other than the issue branch, and do NOT take any other outward or destructive action. If you discover follow-up work, related bugs, or candidate new issues, LIST them in your returned summary for the owner to triage — never file them yourself. Backlog creation and prioritization are the owner's job, not yours.${BREAKER}`

phase('Implement')
let implementReturn = null
if (isTechDebt) {
  implementReturn = await agentNS(
    `You are implementing a BEHAVIOR-PRESERVING structural fix in an existing git worktree. This is a type:tech-debt fast path issue — no OpenSpec change exists, so there is no tasks.md to follow.
WORKTREE (run everything here, cwd): ${worktree}
ISSUE: #${issue} — read its body for the plan: \`gh issue view ${issue} --json title,body\`. Its '## Direction' section is the shape of the fix; '## Acceptance criteria' states the behavior-preservation bar explicitly; '## Adjacent specified behavior (must be preserved)' (if present) names existing openspec/specs/ requirements this surface touches — do not contradict them.

Implement exactly that Direction, test-first (RED→GREEN→REFACTOR) wherever you touch anything non-trivial, honoring the repo's documented conventions (CLAUDE.md / CONTRIBUTING / style guide). This is BEHAVIOR-PRESERVING: if achieving the Direction cleanly would require changing any observable behavior (a public signature, an error contract, CLI/config/serialized output, or an existing test's asserted behavior), STOP and report the specific behavior delta instead of implementing it — do not silently make the change. Commit with focused messages.

After your first commit, push the branch (\`git push -u origin <branch>\`) and open a DRAFT PR — title "<issue title>", body "Closes #${issue}\\n\\nDraft — tech-debt fix in progress. Behavior-preserving — see issue body for Direction. The unit tier runs locally; the full suite runs in CI on each push.", base = the repo's actual default branch (resolve via \`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name\`, never assume main).
${testInstruction}
Return a short summary of what you implemented (or the behavior-delta question, if you stopped for one) and the test outcome.

${GUARDRAILS_TECH_DEBT_IMPLEMENT}`,
    { agentType: 'tdd-developer', label: `implement:${change}`, phase: 'Implement' },
  )
  // Only the behavior-preserving path carries the breaker, so only it can trip one.
  if (typeof implementReturn === 'string' && implementReturn.trim().startsWith(BREAKER_STOP_TOKEN)) {
    log('Refactor circuit breaker tripped during Implement — returning to the owner without running the panel.')
    return {
      change,
      issue,
      tests_ran: 'unit',
      spec_conformance: 'unknown',
      approved: false,
      review_rounds: 0,
      residual_findings: [`refactor circuit breaker (${breaker}) stopped the implement phase: ${implementReturn.trim()}`],
      non_blocking_findings: [],
      review_summary: 'stopped by the refactor circuit breaker before review — see residual_findings',
      polish: 'n/a',
    }
  }
} else {
  await agentNS(
    `You are implementing an approved OpenSpec change in an existing git worktree.
WORKTREE (run everything here, cwd): ${worktree}
CHANGE: ${change}  — tasks at openspec/changes/${change}/tasks.md, spec at openspec/changes/${change}/specs/**/spec.md
ISSUE: #${issue}

Work the tasks in tasks.md test-first (RED→GREEN→REFACTOR), honoring the repo's documented
conventions (its CLAUDE.md / CONTRIBUTING / style guide — TDD, SOLID, and whatever hard rules the
repo documents). Mark each task '- [x]' as you complete it and commit your work on the current
branch with focused messages. PUSH the branch at checkpoints — after a completed task or a few green cycles, somewhat frequently, not on every commit — so CI runs the full suite on the open draft PR while you keep working locally. Never touch main; leave the PR a draft.
${testInstruction}
Return a short summary of what you implemented and the test outcome.

${GUARDRAILS}`,
    { agentType: 'tdd-developer', label: `implement:${change}`, phase: 'Implement' },
  )
}

// ── Phases: Review → Fix (bounded loop) ──────────────────────────────────────
const MAX_ROUNDS = 3
let review = null
let round = 0
const residual = []

// Review is a PANEL of FIVE lenses (spec, code-review, security-review, test-rigor,
// observability), run in parallel each round. Findings merge; a fix round addresses blocker/major
// from ANY lens; approval requires every lens to approve with no must-fix findings. The
// merge/approval logic generalizes over N lenses — adding or removing a lens needs NO change to
// the loop below. Full per-lens mandate: docs/workflow.md's "Review panel" section, or each
// lens's own agents/<name>.md — not restated here. Every lens is backed by its own agent
// definition, which already carries the full mandate/process/output-contract as its own system
// prompt when spawned by agentType, so each prompt below sends only the runtime values, never a
// restatement (that restatement is exactly what used to drift between here, SKILL.md, the agent
// file, and workflow.md).
const reviewLenses = [
  {
    label: 'spec',
    agentType: 'reviewer',
    prompt: `Panel mode. worktree: ${worktree}. base: ${base}. change: "${change}". issue: #${issue}.
Follow your agent definition's process and output contract exactly (JSON only).`,
  },
  {
    label: 'code-review',
    agentType: 'code-reviewer',
    prompt: `Panel mode. worktree: ${worktree}. base: ${base}. change: "${change}". issue: #${issue}.
Follow your agent definition's process and output contract exactly (JSON only).`,
  },
  {
    label: 'security-review',
    agentType: 'security-reviewer',
    prompt: `Panel mode. worktree: ${worktree}. base: ${base}. change: "${change}". issue: #${issue}.
Follow your agent definition's process and output contract exactly (JSON only).`,
  },
  {
    label: 'test-rigor',
    agentType: 'test-rigor-reviewer',
    prompt: `Panel mode. worktree: ${worktree}. base: ${base}. change: "${change}". issue: #${issue}.
Follow your agent definition's process and output contract exactly (JSON only).`,
  },
  {
    label: 'observability',
    agentType: 'observability-reviewer',
    prompt: `Panel mode. worktree: ${worktree}. base: ${base}. change: "${change}". issue: #${issue}.
Follow your agent definition's process and output contract exactly (JSON only).`,
  },
]

while (round < MAX_ROUNDS) {
  round++
  phase('Review')
  const lensResults = await parallel(
    reviewLenses.map(l => () =>
      agentNS(`${l.prompt}\n\n${REVIEW_GUARDRAILS}`, {
        agentType: l.agentType,
        label: `review:${l.label}:${change}#${round}`,
        phase: 'Review',
        schema: REVIEW_SCHEMA,
      })),
  )
  const reviews = lensResults.filter(Boolean)
  if (reviews.length === 0) { residual.push('all review lenses returned no result'); break }
  const missingLenses = reviewLenses.filter((l, i) => !lensResults[i]).map(l => l.label)

  const findings = reviews.flatMap(r => r.findings || [])
  // A lens can decline without pointing at anything ACTIONABLE — e.g. the spec lens requires
  // spec_conformance:"full" to approve, so a "partial" verdict alone sets approve=false with no
  // discrete finding; or a lens reports approve=false but only minor/nit findings, which don't
  // enter mustFix on their own. Left alone that either wastes a Fix round on nothing (empty
  // fixList) or survives silently to the round cap with no must-fix findings to explain it — the
  // owner sees "not approved," no reason why. Synthesize one so it flows through the same mustFix
  // pipeline as everything else, same as a real finding would. Condition is "no blocker/major
  // finding", not "no findings at all" — a lens with only minor findings is just as unexplained.
  lensResults.forEach((r, i) => {
    const hasMustFix = (r && r.findings || []).some(f => f.severity === 'blocker' || f.severity === 'major')
    if (r && r.approve === false && !hasMustFix) {
      findings.push({
        id: `unexplained-${reviewLenses[i].label}`,
        severity: 'major',
        location: `(${reviewLenses[i].label} lens report)`,
        rule: 'unexplained-non-approval',
        problem: `${reviewLenses[i].label} lens returned approve=false with no findings (summary: ${r.summary || 'none given'})`,
        fix: 'Re-review and either approve, or report a specific blocking finding.',
      })
    }
  })
  const mustFix = findings.filter(f => f.severity === 'blocker' || f.severity === 'major')
  const specLens = lensResults[0] // aligned with reviewLenses[0] (the spec reviewer)
  review = {
    summary: lensResults
      .map((r, i) => `[${reviewLenses[i].label}] ${r ? r.summary : '(no result)'}`)
      .join('\n\n'),
    spec_conformance: specLens ? specLens.spec_conformance : 'unknown',
    tests_ran: specLens ? specLens.tests_ran : 'unit',
    findings,
    // Approval requires EVERY lens to have reported AND approved — a lens that returns no
    // result must never be silently dropped from the vote.
    approve: missingLenses.length === 0 && reviews.every(r => r.approve) && mustFix.length === 0,
  }

  if (review.approve) break
  if (round >= MAX_ROUNDS) {
    residual.push(...mustFix.map(f => `[${f.severity}] ${f.location}: ${f.problem}`))
    if (missingLenses.length) residual.push(`lens(es) did not report: ${missingLenses.join(', ')}`)
    break
  }

  if (mustFix.length === 0 && missingLenses.length > 0) {
    // Nothing actionable to fix — only missing lenses withheld approval. Re-run the panel
    // next round instead of dispatching an empty Fix pass.
    continue
  }

  phase('Fix')
  const fixList = mustFix.map(f => `- [${f.severity}] ${f.location} (${f.rule}): ${f.problem}\n  suggested: ${f.fix}`).join('\n')
  await agentNS(
    `Resolve these review findings in the worktree, test-first where behavior changes.
WORKTREE (cwd): ${worktree}
CHANGE: ${change}
FINDINGS:
${fixList}
Fix each, keep the unit tier (plus the branch's \`.spec-flow/flagged-tests\`) green, commit with focused messages.
Push the branch at checkpoints so CI keeps running the full suite on the draft PR. Never touch main; leave the PR a draft. Return what you changed.

${GUARDRAILS}${isTechDebt ? BREAKER : ''}`,
    { agentType: 'tdd-developer', label: `fix:${change}#${round}`, phase: 'Fix' },
  )
}

// ── Phases: Build → Polish (skipped if the panel never approved) ─────────────
// A tree with unresolved blocker/major findings is going back through another `implement` round
// regardless — that round's own Build phase runs again once it's actually approved, so running
// Build/Polish now is pure waste: extra agent runs and commits on a tree already known to change.
let polish = 'n/a'
if (review && review.approve) {
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
changing behavior, and commit the result, then push the branch. Never touch main; leave the PR a draft. Return the final
format/lint/build status.

${GUARDRAILS}`,
    { agentType: 'build-engineer', label: `build:${change}`, phase: 'Build' },
  )

  phase('Polish')
  polish = await agentNS(
    `Final documentation polish for OpenSpec change "${change}" in worktree ${worktree}.
Ensure any new modules/behaviors are documented consistently with the repo's conventions
(module/responsibility comments, any architecture/index docs the repo keeps, doc comments on
public items). ALSO: if this change alters user-facing behavior (a public API, CLI, config, or
how the service is run), update the repo's user-facing docs accordingly (e.g. README, a docs/
tree, an mdBook under book/, or a docs site) — keep its pages and examples current. If the repo
has no user-facing docs or the change has no user-facing surface, skip this and say so.
Make only documentation/comment edits; commit them and push the branch. Never touch main; leave the PR a draft.
Return a one-line note on what you documented (including whether user docs changed).

${GUARDRAILS}`,
    { agentType: 'tdd-developer', label: `polish:${change}`, phase: 'Polish' },
  )
} else {
  log('Review panel did not approve within the bounded fix loop — skipping Build/Polish; residual findings are for the owner.')
}

return {
  change,
  issue,
  tests_ran: review ? review.tests_ran : 'unit',
  spec_conformance: review ? review.spec_conformance : 'unknown',
  approved: !!(review && review.approve && residual.length === 0),
  review_rounds: round,
  residual_findings: residual,
  // Deliberately non-blocking findings (e.g. test-rigor's over-testing/test-practicality flags)
  // from an approving round — computed above in `findings` but otherwise never returned, so they
  // silently vanished before reaching the owner at Seam 2.
  non_blocking_findings: review
    ? review.findings
        .filter(f => f.severity === 'minor' || f.severity === 'nit')
        .map(f => `[${f.severity}] ${f.location} (${f.rule}): ${f.problem}`)
    : [],
  review_summary: review ? review.summary : 'no review captured',
  polish: polish || 'n/a',
}
