---
name: groom
description: Turn a rough idea into a scoped, labeled GitHub issue with a decided design, ready for the delivery pipeline to run autonomously. Use when the owner wants to capture a todo, feature, or bug as a real backlog item with scope, acceptance criteria, a chosen design, and a priority. Keeps a written question list and works it to zero before filing (one question at a time, stated recommended default, never a guess in place of an answer), runs architect + design-critic read-only and has the owner pick the design here rather than after activation, verifies bug reports read-only before scoping them, and offers a type:docs fast-track label for documentation-only work. This is the stage that spends the owner's attention, so later stages don't have to. First stage of the flow delivery workflow (see docs/workflow.md).
argument-hint: [rough idea — a todo, feature, or bug]
---

# groom — rough idea → scoped GitHub issue

You are the PM/lead in the main session. Turn the owner's rough idea into one well-scoped
GitHub issue, labeled and ready for `/spec-flow:activate`. This is interactive: you draft, the owner
refines. Stay in the foreground — no worktrees, no implementation.

## Steps

1. **Understand the idea — keep a written question list and work it to zero.** Read the owner's
   description. `groom` is where the owner's attention is spent, deliberately. Every question
   answered here is one `issue-manager` never has to stop and ask later. The pipeline downstream is
   only as autonomous as this step is thorough. Treat it as an interview, not a form to fill in
   around.

   **Write the list down. It is an artifact, not a memory.** Before asking anything, draft the
   numbered list of everything you need settled, and print it to the owner. Reprint it each time an
   answer lands, marking each item `answered` or `open`. A list held only in your head erodes turn
   by turn. That erosion is how this step fails: it drifts toward filing, and guesses fill the
   gaps.

   What belongs on the list — anything that changes the *shape* of the work:
   - Scope boundaries, and what is explicitly out.
   - Which of several plausible interpretations is meant.
   - Whether this is really two ideas bundled into one.
   - Priority, when the right one isn't obvious.
   - Anything a later stage would otherwise have to stop and ask the owner about.

   How to ask:
   - **One question at a time** — the owner can't usefully answer a batch.
   - **State your own recommended answer alongside every question** — a default they can accept in
     one word instead of composing an answer from scratch ("I'd scope this to X and leave Y for
     later — sound right?", not just "what should this cover?").
   - **Order dependent questions before the questions that depend on them.** Don't ask a detail
     question whose relevance hinges on an earlier, still-open one.
   - **Follow up on the answer you actually got**, and add what it raises to the list. The list
     grows during the interview; that is the list working, not a failure to plan it.

   **Never guess in place of an answer.** A guessed shape reads exactly like a decided one once it
   is in the issue body, and nothing downstream can tell them apart. If the owner declines to
   answer an item, or defers it, record it in the issue body under **Open questions**, named as
   unanswered. That is honest and it is durable; a silent guess is neither.

   For everything else — a detail a sensible default clearly covers, or a fact you can look up
   yourself (existing code, other issues, prior art) — don't ask; state the default/finding in the
   draft and let the owner redline it. Over-asking is its own failure mode, and a list padded with
   questions you could have answered yourself wastes the same attention it is meant to protect.

2. **For bug reports: verify before you draft.** If the idea describes something not working
   (symptoms, expected vs. actual behavior), don't draft acceptance criteria from an unconfirmed
   report. `groom` stays foreground with no worktree and makes no code changes (see **Rules**), so
   verification here is strictly **read-only** — run the reporter's described repro steps (a
   command, an existing test, a specific input) directly in the primary checkout and observe
   whether the symptom actually occurs:
   - **Reproduces** → note the confirmed repro (command + observed output) in the eventual Notes/
     context section; proceed.
   - **Doesn't reproduce** → say so plainly, with what you tried and what actually happened, and
     ask the owner what's missing (one question — e.g. "what environment/version does this need?")
     before drafting AC from a report you couldn't confirm.
   - **No repro steps given at all** → ask for them (one question, with a guessed default if you
     have one — "I'm guessing this happens when X — is that right, or what actually triggers it?")
     before attempting anything.
   - **Not practically verifiable here** (needs a live external service, specific hardware, a
     production-only condition) → say so, and proceed with the report as given, flagged
     **unverified** in Notes/context — so the step-5 architect consult, and every stage after it,
     treats the premise as unconfirmed, not settled fact.
   Matters most for a report you didn't personally observe — an externally filed bug, or one
   relayed secondhand — where nothing has actually confirmed it's real yet.

3. **Docs-only? Offer the fast track.** If the idea is purely documentation — README, a docs/
   mdBook tree, comments, no behavior change — say so and offer to label it `type:docs` (recommend
   yes; a low-stakes default the owner can accept in one word). `activate` and `implement` both
   skip most of their heavyweight machinery for a `type:docs` issue — no architect design consult,
   no design-choice stop, no review panel, and (for most content-only docs work — the label
   alone doesn't decide this; `activate` step 5 judges it from the issue's own scope) no OpenSpec
   spec generated at all — while still stopping at both owner seams as normal; see **Docs fast
   path** in `docs/workflow.md`. Not sure it's docs-only, or it touches behavior at all (even
   indirectly — e.g. a config example that has to stay in sync with real defaults)? Leave it
   unlabeled; the full pipeline is the safe default.

4. **Delegate the refinement to the `product-manager` agent.** Spawn the `product-manager`
   subagent with the owner's raw idea, any clarifications from step 1, and the verification verdict
   from step 2 if this is a bug. It returns a structured refinement —
   problem statement, in/out scope, **testable WHEN/THEN acceptance criteria**, open questions, and
   context (`file:line`, duplicates). Bring that refinement back to the owner, loop on their edits,
   and treat the result as the source for the issue body.

   **Every open question it returns goes onto step 1's list and gets asked.** Do not answer one on
   the owner's behalf, and do not let it dissolve into the draft as a settled statement. The
   subagent surfaced it precisely because it could not resolve it; resolving it silently here
   throws away the finding.

5. **Decide the design here — `architect`, then `design-critic`, then the owner picks.** This is
   the decision that used to happen at `/spec-flow:activate`, after the issue was already claimed
   and a worker was already running. It happens here instead, so the filed issue carries a decided
   design and `issue-manager` can proceed without stopping to ask. **Skip this step entirely for a
   `type:docs` issue** (step 3) — documentation content has no design to choose.

   Both agents are read-only, so this runs in the primary checkout; `groom` still creates no
   worktree and writes no code.
   - Spawn `architect` with the refined scope and acceptance criteria. It returns options —
     structure, module boundaries, data model, key interfaces — with the trade-offs behind each.
     Spawn a domain-expert agent concurrently when the repo has one that fits the subject.
   - Then spawn `design-critic` with the architect's output plus the same scope and acceptance
     criteria. It attacks the plan: unstated assumptions, missing edge cases, failure modes, and
     acceptance criteria no option actually satisfies. The architect grades its own work; this is
     what stops that from being the last word.
   - **Present the options to the owner and let them choose.** One decision at a time, with your
     recommended option named. Significant design decisions are the owner's — you advise, they
     decide. Never pick for them and never fold the choice into the draft as though it were
     settled.

6. **Draft the issue body** from the refinement, with these sections:
   - **Scope** — what's in, and explicitly what's out.
   - **Acceptance criteria** — a checklist of observable outcomes (these become the spec's
     scenarios later, when a spec gets generated at all — see the Docs fast path exception below —
     so make them testable).
   - **Direction** — the design the owner chose at step 5: what it is, then each rejected
     alternative with the reason it lost, then `design-critic`'s surviving concerns. Omit this
     section entirely for a `type:docs` issue, which never runs step 5. This section is the
     contract `issue-manager` starts from, so write it to be read by an agent that has no access
     to this conversation.
   - **Open questions** — anything on step 1's list the owner declined or deferred, stated as
     unanswered. Omit the section when the list closed clean.
   - **Notes / context** — links, constraints, related code (`file:line`), related issues, and —
     for a bug — the step-2 verification verdict (confirmed repro, or flagged unverified/couldn't
     reproduce).
   Keep it tight. A full spec usually comes later in `/spec-flow:activate` (a content-only
   `type:docs` issue skips that artifact — see **Docs fast path** in `docs/workflow.md` — but still
   reviews this same scope + acceptance criteria at Seam 1). Either way, this body is the contract
   the pipeline starts from: **Scope** and **Acceptance criteria** state the *what* and *why*, and
   **Direction** states the *how* the owner chose at step 5.

7. **Set priority.** Propose a priority and confirm with the owner. Exactly one of
   `P0` (drop everything) / `P1` (high) / `P2` (normal) / `P3` (low/someday) — never zero,
   never two.

8. **Check the question list, then create the issue.** Reprint step 1's list one last time. Every
   item must be `answered`, or recorded under **Open questions** in the body because the owner
   deferred it. **If anything is still open and unrecorded, stop and ask it — do not file.** This
   is the gate: an issue filed over an open question ships a guess into a pipeline that cannot
   tell it from a decision.
   ```bash
   gh issue create --title "<concise title>" --body "<the drafted body>" \
     --label "<P0|P1|P2|P3>" --label "status:ready" --label "design:decided"
   ```
   If the owner accepted the docs-fast-track offer at step 3, add `--label "type:docs"` too.

   **`design:decided` goes on only when step 5 actually produced a chosen design.** Drop it for a
   `type:docs` issue, which skips step 5 and writes no `## Direction`, and drop it when the owner
   deferred the design to **Open questions**. `activate` reads that label as permission to skip its
   own design stop and `design-critic`, so applying it to an undecided issue sends a guess through
   the pipeline as though the owner had settled it. The label is the claim; the section is only the
   text.

9. **Verify and report.** Confirm the created issue carries exactly one `P?` label and
   `status:ready` (plus `type:docs` or `design:decided` where each applies):
   ```bash
   gh issue view <N> --json number,title,labels
   ```
   Report the issue number and URL. Suggest `/spec-flow:activate <N>` when the owner wants to start it.

## Rules

- **A guess is never a default.** Where a sensible default covers a detail, state it in the draft
  and let the owner redline it — that is a default. Where the answer changes the shape of the work
  or the design, invent nothing: ask, or record it as an open question. Filing fast is worth
  nothing if the issue says something the owner never agreed to.
- **The question list is worked to zero before filing** (step 8). Deferred is a valid outcome and
  gets written down; unasked is not.
- **This is where the owner's attention gets spent.** A question answered here costs one exchange.
  The same question reaching `issue-manager` costs a stop, a spawn, and a context switch. If no
  human is present, an agent that was never authorized to decide it answers it instead.
- Exactly one priority label. If the owner doesn't pick, recommend one and confirm before creating.
- Don't groom the same idea twice — search open issues first (`gh issue list --search`) if it
  might already exist.
- Acceptance criteria are the seed of the spec's `#### Scenario:` blocks (when a spec gets
  generated at all — see the Docs fast path exception above) — write them as observable WHEN/THEN
  outcomes where you can.
- Keep titles concrete and short — the OpenSpec change name is `issue-<N>` (deterministic, not
  derived from the title), so the title only has to be a good title, not double as a slug source.
- When you cite an issue or PR, always write it as `<number>: <title>`, on its own line with a `-`
  prefix — the owner does not track raw numbers. Never run several together inline in a sentence.
- **Bug verification (step 2) is read-only, always.** No worktree, no file writes, no commits —
  run existing commands/tests and observe; if verifying would require changing anything, that's
  past `groom`'s scope, not a reason to skip verification (fall back to "not practically verifiable
  here" instead).
- **`type:docs` is conservative by default.** Only offer it when the idea is unambiguously
  documentation-only; when genuinely unsure, don't offer it — the full pipeline (architect consult,
  full review panel) is always safe to run on a docs change, just slower. The fast path is an
  opt-in speedup, never something inferred without asking.
