---
name: groom
description: Turn a rough idea into a scoped, labeled GitHub issue ready for the delivery pipeline. Use when the owner wants to capture a todo, feature, or bug as a real backlog item with scope, acceptance criteria, and a priority. First stage of the flow delivery workflow (see docs/workflow.md).
argument-hint: [rough idea — a todo, feature, or bug]
---

# groom — rough idea → scoped GitHub issue

You are the PM/lead in the main session. Turn the owner's rough idea into one well-scoped
GitHub issue, labeled and ready for `/spec-flow:activate`. This is interactive: you draft, the owner
refines. Stay in the foreground — no worktrees, no implementation.

## Steps

1. **Understand the idea.** Read the owner's description. If scope is genuinely ambiguous,
   ask clarifying questions **one at a time** (the owner can't answer batches). Don't
   over-ask — prefer a sensible draft the owner edits.

2. **Delegate the refinement to the `product-manager` agent.** Spawn the `product-manager`
   subagent with the owner's raw idea and any clarifications. It returns a structured refinement —
   problem statement, in/out scope, **testable WHEN/THEN acceptance criteria**, open questions, and
   context (`file:line`, duplicates). Bring that refinement back to the owner, loop on their edits,
   and treat the result as the source for the issue body. (You own the *what/why*; design — the
   *how* — comes later, from the `architect` at `/spec-flow:activate`.)

3. **Draft the issue body** from the refinement, with these sections:
   - **Scope** — what's in, and explicitly what's out.
   - **Acceptance criteria** — a checklist of observable outcomes (these become the spec's
     scenarios later, so make them testable).
   - **Notes / context** — links, constraints, related code (`file:line`), related issues.
   Keep it tight. The full spec comes later in `/spec-flow:activate`; this is the contract for *what*
   and *why*, not *how*.

4. **Set priority.** Propose a priority and confirm with the owner. Exactly one of
   `P0` (drop everything) / `P1` (high) / `P2` (normal) / `P3` (low/someday) — never zero,
   never two.

5. **Create the issue:**
   ```bash
   gh issue create --title "<concise title>" --body "<the drafted body>" \
     --label "<P0|P1|P2|P3>" --label "status:ready"
   ```

6. **Verify and report.** Confirm the created issue carries exactly one `P?` label and
   `status:ready`:
   ```bash
   gh issue view <N> --json number,title,labels
   ```
   Report the issue number and URL. Suggest `/spec-flow:activate <N>` when the owner wants to start it.

## Rules

- Exactly one priority label. If the owner doesn't pick, recommend one and confirm before creating.
- Don't groom the same idea twice — search open issues first (`gh issue list --search`) if it
  might already exist.
- Acceptance criteria are the seed of the spec's `#### Scenario:` blocks — write them as
  observable WHEN/THEN outcomes where you can.
- The slug for later stages is derived from the title (kebab-case); keep titles concrete and short.
- When you cite an issue/PR number, always pair it with a brief `(description)` — the owner does
  not track raw numbers.
