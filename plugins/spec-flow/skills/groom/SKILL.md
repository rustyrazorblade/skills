---
name: groom
description: Turn a rough idea into a scoped, labeled GitHub issue ready for the delivery pipeline. Use when the owner wants to capture a todo, feature, or bug as a real backlog item with scope, acceptance criteria, and a priority. Grills shape-defining ambiguity (one question at a time, stated recommended default) rather than just drafting around it, verifies bug reports read-only before scoping them, and offers a type:docs fast-track label for documentation-only work. First stage of the flow delivery workflow (see docs/workflow.md).
argument-hint: [rough idea — a todo, feature, or bug]
---

# groom — rough idea → scoped GitHub issue

You are the PM/lead in the main session. Turn the owner's rough idea into one well-scoped
GitHub issue, labeled and ready for `/spec-flow:activate`. This is interactive: you draft, the owner
refines. Stay in the foreground — no worktrees, no implementation.

## Steps

1. **Understand the idea — grill shape-defining ambiguity, don't just draft around it.** Read the
   owner's description. For anything that changes the *shape* of the work (scope boundaries, which
   of several plausible interpretations is meant, whether this is really two ideas bundled into
   one), treat it as a short interview, not a form to fill in around:
   - **One question at a time** — the owner can't usefully answer a batch.
   - **State your own recommended answer alongside every question** — a default they can accept in
     one word instead of composing an answer from scratch ("I'd scope this to X and leave Y for
     later — sound right?", not just "what should this cover?").
   - **Order dependent questions before the questions that depend on them.** Don't ask a detail
     question whose relevance hinges on an earlier, still-open one.
   - **Don't draft the issue until shape-defining ambiguity is actually resolved.** This is the one
     place `groom` diverges from "prefer a sensible draft the owner edits," below: get confirmation
     on what the work *is* before writing it up, not after.
   For everything else — a detail a sensible default clearly covers, or a fact you can look up
   yourself (existing code, other issues, prior art) — don't ask; state the default/finding in the
   draft and let the owner redline it. Over-asking is its own failure mode.

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
     **unverified** in Notes/context — so the architect consult at `activate` treats the premise as
     unconfirmed, not settled fact.
   Matters most for a report you didn't personally observe — an externally filed bug, or one
   relayed secondhand — where nothing has actually confirmed it's real yet.

3. **Docs-only? Offer the fast track.** If the idea is purely documentation — README, a docs/
   mdBook tree, comments, no behavior change — say so and offer to label it `type:docs` (recommend
   yes; a low-stakes default the owner can accept in one word). `activate` and `implement` both
   skip most of their heavyweight machinery for a `type:docs` issue — no architect design consult,
   no design-choice stop, no 5-lens review panel, and (for most content-only docs work — the label
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
   and treat the result as the source for the issue body. (You own the *what/why*; design — the
   *how* — comes later, from the `architect` at `/spec-flow:activate`.)

5. **Draft the issue body** from the refinement, with these sections:
   - **Scope** — what's in, and explicitly what's out.
   - **Acceptance criteria** — a checklist of observable outcomes (these become the spec's
     scenarios later, when a spec gets generated at all — see the Docs fast path exception below —
     so make them testable).
   - **Notes / context** — links, constraints, related code (`file:line`), related issues, and —
     for a bug — the step-2 verification verdict (confirmed repro, or flagged unverified/couldn't
     reproduce).
   Keep it tight. A full spec usually comes later in `/spec-flow:activate` (a content-only
   `type:docs` issue skips that artifact — see **Docs fast path** in `docs/workflow.md` — but still
   reviews this same scope + acceptance criteria at Seam 1); either way, this is the contract for
   *what* and *why*, not *how*.

6. **Set priority.** Propose a priority and confirm with the owner. Exactly one of
   `P0` (drop everything) / `P1` (high) / `P2` (normal) / `P3` (low/someday) — never zero,
   never two.

7. **Create the issue:**
   ```bash
   gh issue create --title "<concise title>" --body "<the drafted body>" \
     --label "<P0|P1|P2|P3>" --label "status:ready"
   ```
   If the owner accepted the docs-fast-track offer at step 3, add `--label "type:docs"` too.

8. **Verify and report.** Confirm the created issue carries exactly one `P?` label and
   `status:ready` (plus `type:docs` if applicable):
   ```bash
   gh issue view <N> --json number,title,labels
   ```
   Report the issue number and URL. Suggest `/spec-flow:activate <N>` when the owner wants to start it.

## Rules

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
