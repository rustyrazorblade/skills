# Prose Style Reference

Grading criteria for commit messages, code comments, PR descriptions, release
notes, and API docs. The `prose-review` skill reads this file before grading
anything; it is the one place the rules live. Any skill that authors this
kind of prose can adopt it the same way.

Two independent axes. Grade both — a passage can violate one without the other.

## Axis 1: No intra-implementation commentary

A feature is **in flight** for as long as it lives on a branch that has not
merged. While in flight, no artifact may reference the iteration process:
code comments, docstrings, docs, release notes, commit messages, PR
descriptions.

Do not write:
- References to an earlier attempt on this same branch — "previously", "in
  the first version", "changed from X", "as of v2", "now correct", "per
  review feedback".
- Review-round bookkeeping, or notes addressed to a reviewer of an unmerged
  draft.
- "new" / "updated" / "refactored" / "improved" relative to code that has not
  shipped.

Instead, write every comment and message as though the branch's final state
is the first and only version that ever existed. A fixup to an unmerged
commit is squashed or amended, or authored as if original — never narrated
as a delta against the branch's own earlier commit.

**A fixup commit that exists only to correct an earlier commit on the same
unmerged branch is itself the violation**, independent of its wording — flag
it, then check whether its message also narrates the correction.

Merged history and released behavior *are* legitimate to reference; that is
real shipped context, not in-flight churn. A release note saying "faster than
JDK 21" or a comment saying "matches the behavior shipped in 25.0.3" is fine.

### A squash-target sibling is not "merged" context

A radar or commit describing a bug still open in an unrelated codebase
(upstream OpenJDK, a different product) is legitimately permanent context —
it stays true after this branch's own history is rewritten, so a comment or
message may reference it.

A sibling commit on *this* branch that a `[fix,squash]`-tagged commit is
itself meant to be folded into is not that. Once the squash happens, any
contrast drawn against that sibling's mechanism — "removes the lock", "no
longer synchronizes", "without a lock" — describes a step that no longer
exists in the final history, and the phrase reads as a contrast with
nothing: both the original bug and the final fix can share the very property
being called out (e.g. both are lock-free; only the squashed-away
intermediate commit had a lock). Test before writing such a reference: will
this comparison still make sense once this branch's commits are squashed the
way its tags say they will be? If the fact only makes sense with the
intermediate commit in view, either cut it or replace the sibling-commit
contrast with the permanent, external fact it was standing in for (a
still-open upstream radar, a long-standing design constraint). The two are
easy to conflate — both mention a radar and a mechanism — but only one
survives the squash.

### Regenerate, don't patch

Prose written while code is still moving accumulates residue: self-corrections,
rationale for a design since replaced, alternatives explored and abandoned.
Editing that prose after the fact tends to keep its shape and inherit its
residue, because a patch anchors on what is already there. Once a branch's
code has stabilized, the fix is not to polish existing commit messages and
comments incrementally — it is to rewrite each one fresh, from the current
diff and code plus this reference alone, without rereading the draft being
replaced.

This is why `prose-review` (the skill that uses this reference) proposes
full replacement text for a flagged passage, not a patch to it: a dedicated
review pass that reads the draft and edits around its residue reproduces the
same failure mode this axis exists to catch.

## Axis 2: Simplified Technical English (STE) discipline

Apply ASD-STE100-style discipline to everything written:
- One meaning per word — reuse the same verb for the same action, don't
  rotate synonyms.
- Active voice.
- Simple tenses.
- One instruction per sentence.
- ≤20-word instructions, ≤25-word descriptions.
- ≤3-word noun clusters.
- No ellipsis — keep subject, verb, and article explicit.
- Lists for 3+ steps.

### Comments

State the one fact the code can't say for itself, then stop. Before
finalizing a multi-clause comment, cut:
- The cause, if it's one inference away from the fact plus the surrounding
  code.
- The consequence, if it's already visible in adjacent code.
- Justification for an argument or constant whose name already says what it
  means.
- A guarantee the language construct already enforces — a record's implicit
  final components, a `final` field, a `sealed` hierarchy's exhaustiveness.
  It cannot be violated without abandoning the construct, so restating it as
  an instruction ("the components must stay final") teaches nothing the
  declaration doesn't already show.
- The definition of a named term of art, once the term itself is stated.
  "Safe publication" or "happens-before" is the explanation for a reader who
  knows it; re-deriving what it guarantees is redundant, and a bare spec
  citation (JLS 17.5) adds a reference without adding a fact for a reader who
  doesn't. Name the pattern and stop, unless the citation itself is the
  contract (see the Javadoc Big-O/latency-bound exception below).

Anchor a mechanism-level comment at the operation it protects, not at a
nearby type declaration or an enclosing method. A record or class
declaration states what it holds; the comment explaining why an unlocked
read or write of it is safe belongs at that read or write, because that is
where the guarantee is actually relied on and where a maintainer tempted to
add a lock will be looking. When the same invariant is exercised at more
than one call site, anchor it at each site — consolidating into one comment
elsewhere loses the guarantee exactly where it is needed.

Length tracks the count of independent, non-inferable facts, not an
arbitrary line cap. A comment with four non-inferable facts (e.g., "this call
resets state X; that makes value Y unreliable for case Z; the obvious
alternative source for Y doesn't work either, because W") earns four
clauses. Cutting a comment to one line when it carries three non-inferable
facts loses information; padding a one-fact comment to five lines buries it.
Judge each clause on its own, not the comment's total length.

### Match the focus to the artifact

Each has a different reader with different context.

**Commit messages** — what changed, not how it works internally. The reader
has the diff open, so codebase vocabulary is free to use. Name a mechanism
only when the mechanism's name is the smallest correct description of the
change itself.

The subject states the outcome or capability — a fix, a user-visible
behavior, a flag — not the internal method, class, or register that
implements it. A subject naming the implementation reads as a diff summary,
not a changelog entry a reader scanning `git log --oneline` can act on. The
mechanism name does not disappear — it moves to the body's opening sentence.
`Add Rdtsc::elapsed_counter to Runtime1::name_for_address` describes the
diff; `Fix hotspot fastdebug assert on x86` describes what a reader needs
from the subject. Flag a subject that names a method/field/register when the
commit fixes a bug or ships a capability: the fix or capability belongs in
the subject, the mechanism in the body.

State the change and the one or two facts that make it non-obvious, then
stop — a commit message is not a design-rationale essay. Cut:
- Alternatives considered and rejected.
- Defense of a sub-decision a reviewer would not question.
- Process or tooling footnotes (a lint rule satisfied, an include re-sorted)
  unless the reviewer needs them to judge correctness.

A paragraph that would not survive as a comment under the cutting rule above
does not survive here either.

**PR descriptions** — what changed, and why this approach: enough rationale
for a reviewer to evaluate the approach before reading every commit. Broader
in scope than any single commit message; still assumes a reader who can open
the diff.

**Release notes** — the observable, user-facing effect, for a reader with no
codebase context. A term earns a place here only if it also appears on some
other user-visible surface the product already exposes — a flag name, a
log/JFR output, an existing public doc. If it appears nowhere a user would
see it, translate it to plain observable language, no matter how standard
the term is inside the codebase. Cover known user-visible residual
limitations here too, not just completed fixes — if a number can still come
out wrong in a documented way, a reader relying on that number needs to
know, not just the engineers reading the commit message.

A release note answers one question: what does a reader of *this specific
release* observe as different from the one before it? Subsequent releases
do not carry this note forward, so it is the only place this question gets
answered for this delta. If the underlying defect or API already shipped a
user-visible fix in an earlier release — even under a different radar, even
for the same bug — restating that fix here is not this release's news: it
already happened, and a reader comparing this release to the last one finds
nothing new where the note describes it. A prior fix may still belong in
the note as background, to explain why a mechanism existed before this
release removed or changed it, but only in service of the delta this
release actually carries, never as the note's own subject.

**Javadoc and other API docs** — the contract: inputs, outputs, guarantees,
and when a value is meaningless or unavailable. Not the implementation
behind it.

A per-platform or per-backend enumeration of *how* a value is produced
(which register, which syscall, which counter, which flag) is
implementation, even when each clause is true and phrased as "on X it is A,
on Y it is B" — that shape is the tell. State the one platform-invariant
guarantee instead.

Name a specific mechanism only when it is itself part of the contract the
caller depends on (a flag they can set, a unit that differs by platform) —
never as background explaining where a number comes from.

A `public static final` field initialized from a method call names that
method and stops; the algorithm's guarantees (bounds, exactness,
monotonicity) belong on the method that owns them, stated once — not copied
onto the field, and not onto an unrelated sibling merely because it is
declared nearby.

A performance caveat tied to implementation mechanics (JIT tier,
intrinsification, which instruction) is implementation too, even when it
reads as something a caller "should know" — put it in a plain code comment,
not a Javadoc block. Anchor that comment at the exact operation whose cost
it describes, not at a caller of it: a caller several frames up (a flag
check, a dispatching method) is the wrong home even when it feels like the
natural "decision point," because the mechanism the comment explains isn't
visible there.

A Javadoc block earns a performance fact only when the number itself is the
contract (Big-O, a documented latency bound).

### Proposed cuts must not orphan a referent

When a finding proposes cutting a sentence — whether the padded-past-its-facts
case above or any other — check the rest of the passage for a pronoun or
phrase ("that range", "this value", "the flag") that only resolves through
the sentence being cut. Cutting the sentence that defines "the 1 MHz-100 GHz
range" while leaving a later sentence's "outside that range" is not a smaller
message, it is a broken one. Either cut both sentences together, reword the
survivor to stand alone, or don't propose the cut — never propose a cut that
leaves a dangling referent for someone else to notice.

## Severity

- **[H]** — Axis 1 violation (in-flight commentary of any kind), or a
  Javadoc/release-note passage that states something false or something the
  reader cannot act on.
- **[M]** — Axis 2 violation that changes what a reader takes away: a
  commit-message design-rationale essay, an artifact-focus mismatch (e.g.
  implementation mechanism in a Javadoc contract), a comment padded past its
  fact count, a subject naming implementation where the fix/capability
  belongs, a dangling referent left by a trim.
- **[L]** — Pure STE mechanics on an otherwise sound passage: sentence
  length, passive voice, a rotated synonym.

## Non-goals

This reference does not cover code correctness, API design, test coverage,
or naming. `prose-review` and this file are about the words, not the code
they describe — a comment can be perfectly styled and still describe a bug,
and that bug is out of scope here.
