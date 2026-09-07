---
name: groom
description: Turn a rough idea into a scoped, labeled GitHub issue ready for the delivery pipeline. Use when the owner wants to capture a todo, feature, or bug as a real backlog item with scope, acceptance criteria, and a priority. Refines the idea over as many rounds as it takes — each round a fresh `product-manager` that has read the code, asking at most three questions, one at a time, each with a stated recommended default — and ends the loop only when every acceptance criterion is testable as written. Verifies bug reports read-only before scoping them, and offers a type:docs fast-track label for documentation-only work. First stage of the flow delivery workflow (see docs/workflow.md).
argument-hint: [rough idea — a todo, feature, or bug]
---

# groom — rough idea → scoped GitHub issue

You are the PM/lead in the main session. Turn the owner's rough idea into one well-scoped
GitHub issue, labeled and ready for `/spec-flow:activate`. This is interactive: you draft, the owner
refines. Stay in the foreground — no worktrees, no implementation.

## Steps

1. **Read the idea — ask only what round 1 can't start without.** Two things, at most:
   - **What is this?** Only if the description is genuinely unreadable as a unit of work. A rough,
     under-specified idea is the normal input here, not a problem to solve before proceeding.
   - **Is this one piece of work or several?** A bundle of two ideas becomes two issues, and the
     refinement loop can't sharpen both at once.
   Ask them one at a time, each with your own recommended answer stated alongside it — a default
   they can accept in one word ("this reads like two issues to me: X, and Y for later — split it?").
   **Everything else waits for step 4.** The deep interview happens there, asked by an agent that
   has read the code, which is most of what makes a question worth asking. Don't resolve
   shape-defining ambiguity here and don't hold the refinement back for it: that's what the loop is
   for, and asking here as well puts the owner through two interviews with two different bars.

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
   no design-choice stop, no review panel, and (for most content-only docs work — the label
   alone doesn't decide this; `activate` step 5 judges it from the issue's own scope) no OpenSpec
   spec generated at all — while still stopping at both owner seams as normal; see **Docs fast
   path** in `docs/workflow.md`. Not sure it's docs-only, or it touches behavior at all (even
   indirectly — e.g. a config example that has to stay in sync with real defaults)? Leave it
   unlabeled; the full pipeline is the safe default.

4. **Refine in rounds.** One `product-manager` pass produces whatever depth a single reading
   reaches; everything it couldn't settle becomes a guess made later, by `architect` or
   `tdd-developer`, without the owner in the room. So run it as a loop. **You drive the loop and
   you decide when it ends** — the agent never decides that for you.

   **A round.** Spawn a **fresh** `product-manager` subagent. Its prompt carries three runtime
   values and nothing else:
   - the owner's **raw idea, verbatim** — plus the step-2 verification verdict if this is a bug;
   - the **refinement record** in full (below);
   - the **previous round's refinement** — the owner's edited copy wherever they edited it, not the
     agent's original. Round 1 has none.

   Don't restate the agent's mandate in the prompt; it has its own definition, and a restatement
   there only competes with it. Send runtime values, the way `implement` does.

   The round returns a refinement — problem statement, in/out scope, testable WHEN/THEN acceptance
   criteria, open questions, context — and up to three questions. Show the refinement to the owner,
   relay the questions (below), append everything to the record, then judge the refinement against
   the readiness bar. Bar met → step 5. Bar unmet → run another round.

   **The refinement record.** Keep it in a file, `.spec-flow/groom-<slug>.md` in the primary
   checkout, where `<slug>` is a short kebab-case name for the idea (`.spec-flow/` is already
   gitignored; if this repo's isn't, add it). Not in your conversation. You run inside
   `project-manager`'s session, which compacts; a record held in context degrades to a paraphrase,
   and a later round would receive softened owner constraints while you still believed you had
   passed on their exact words. Append to it as the round happens, one entry per thing the owner
   did:

   ```markdown
   ## Round 2
   - **Q:** <the question exactly as you asked it>
     **A:** <the owner's answer, verbatim>
   - **Edit:** <the scope line or criterion the owner rewrote, in the owner's wording>
   - **Deletion:** <the line the owner removed>
   - **Direction:** <owner technical direction, verbatim — see below>
   ```

   Four properties make the record worth keeping:
   - **Verbatim.** Copy what the owner wrote. Don't tidy it, summarize it, or turn it into a
     criterion — that's the next round's job, in the open.
   - **Append-only.** Never rewrite an earlier entry. Where two entries contradict, **the later
     one wins**: an answer given in round 2 and reversed in round 4 is settled by round 4.
   - **Every answer keeps its question.** "No" and "the second one" mean nothing on their own, and
     a later round can't resolve the referent from the answer alone.
   - **Edits and deletions are entries too.** An owner who deletes an acceptance criterion and says
     nothing has said something. Record the deletion, so the next round doesn't re-add the line.

   **The readiness bar — yours to apply, not the agent's.** A round is ready when all three hold:
   - **(a)** every acceptance criterion is testable as written;
   - **(b)** the unhappy paths are covered — errors, limits, empty or oversized input, conflicts;
   - **(c)** no **behavioral** assumption is left for a downstream agent to guess at.

   Item (c) is scoped to behavior deliberately. **Design assumptions don't hold the loop open** —
   data models, interfaces, algorithms, libraries all belong to `architect` at the design stop, and
   chasing them here both duplicates that work and gives the loop no fixed point.

   A round that asks no questions has not thereby met the bar, and a round that asks three has not
   thereby failed it. Read the refinement and judge it. **A small idea meeting the bar in round 1
   is a normal, expected outcome** — converging fast isn't a sign you applied the bar too loosely.

   **Unsourced concreteness is not readiness.** A criterion that is testable *only* because it
   names a value nobody gave — a size limit, a timeout, a retry count, a specific error code — is
   not ready. Rewarding it would make inventing a number the cheapest route to convergence. Treat
   that value as the next round's question, with your recommended default.

   **Relaying questions.** One at a time, at most three per round.
   - **One at a time** — the owner can't usefully answer a batch. Ask the second only after the
     first is answered.
   - **Each question states your own recommended answer**, so the owner can accept in one word. A
     question that arrives without a default doesn't go to the owner as-is: supply the default
     yourself if you have one, otherwise drop it and treat the round as not having asked it.
   - **Order dependent questions before what depends on them.**
   - **More than three candidates?** Relay the three that most change the shape of the work. The
     rest stay in the record's open questions and are available to a later round.

   **The loop ends** when any one of these is true:
   - the **readiness bar is met**;
   - the **owner ends it** — "that's enough", "just file it", or anything else that plainly means
     stop;
   - **a round has nothing new to ask** — every question it would ask is already answered in the
     record. A further round has the same inputs and returns the same thing.

   There's no round cap. The owner is present at every round, so a long loop is visible and one
   word ends it.

   **The closing pass.** When the loop ends for any reason *other* than the bar being met, run one
   more round, and only one. Honour "stop" immediately — the closing pass is what you do next, not
   another round of questions. Its prompt is the usual three values, including the owner's final
   answers, plus the instruction that it asks **nothing**: it returns a refinement, and it converts
   everything still open into explicitly stated assumptions, each marked as traceable to the record
   or as the agent's own.

   **Confirming the assumptions — one screen, split by provenance.** Present the closing pass's
   assumptions to the owner in a single pass, in two groups:
   - **Traceable to something the owner said** — confirmable in **bulk**, one answer for the group.
     Each confirmed item becomes an ordinary Scope or Acceptance criteria line.
   - **Never raised by the owner** — each needs its own explicit yes or no. **A bulk yes never
     promotes one of these.** Promotion makes an agent-authored line indistinguishable from one the
     owner wrote, and the moment of least attention is the wrong moment to grant that.

   This bulk confirmation is a **deliberate, scoped exception** to the one-question-at-a-time rule
   above, and the only one. It applies to the traceable group at the closing pass, nowhere else:
   the loop's questions each shape the work, while these are already-stated positions being
   confirmed as a set at the end.

   Anything the owner leaves unresolved is neither promoted nor dropped — it goes into the issue's
   own assumptions section (step 5).

   **Owner technical direction.** The owner may state technical direction at any round —
   architecture, performance characteristics, implementation guidelines, constraints. Record it
   **verbatim**, under `**Direction:**` in the record, and carry it into the drafted issue
   unchanged. Never reword it into a behavioral criterion, and never drop it for being design:
   `product-manager`'s "stay out of design" rule binds the agent, not the owner. If a round returns
   owner direction restated as an acceptance criterion, don't accept the rewording — the direction
   stands as the owner wrote it.

5. **Draft the issue body** from the final refinement, with these sections:
   - **Scope** — what's in, and explicitly what's out.
   - **Acceptance criteria** — a checklist of observable outcomes (these become the spec's
     scenarios later, when a spec gets generated at all — see the Docs fast path exception below —
     so make them testable).
   - **Technical direction** — the owner's own words, verbatim, exactly as recorded. Include this
     section only if the owner stated any; `activate` passes it to the `architect`.
   - **Assumptions** — the closing pass's items the owner left unresolved. Include this section
     only if there are any.
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

7. **Create the issue.** Write the drafted body to a file and pass it by path. Never interpolate
   it into a double-quoted argument: the body cites related code in backticks, and the shell runs
   backticks inside double quotes as command substitution.
   ```bash
   gh issue create --title "<concise title>" --body-file .spec-flow/groom-<slug>-body.md \
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
- **Every line traces back to the owner.** A scope boundary or acceptance criterion goes in the
  issue only if the owner said it, or you showed it to them and they kept it. Reading the code
  tells you what a criterion *could* be; it never authorises adding one. When your repo reading
  turns up something the owner did not raise — a config path to honour, a test harness to extend,
  a concrete example value — name it as a proposal in the draft review and mark it as yours, so
  they can cut it in one word. Silence is not agreement. An issue that carries rules nobody asked
  for sends the whole pipeline off building them. **Running more rounds never relaxes this**: four
  rounds of refinement must leave no scope line or criterion without an antecedent in the record
  or an explicit confirmation from the owner.
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
