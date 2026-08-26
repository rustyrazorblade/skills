---
name: prose-review
description: >
  Grade the prose in a patch against prose-style.md and report the findings; apply them with --fix.
  Covers code comments and javadoc by default, and commit messages, the PR description, or release
  notes when asked.  Use this skill when the user asks to review, audit, grade, clean up, fix, tidy,
  or restyle comments, javadoc, commit messages, a PR description, or release notes, says "the
  comments need work", "check the prose on this branch", "do a comment pass", or asks for
  prose-style.md to be applied to anything.  It reports by default and edits only with --fix.  It
  never reviews code correctness; /code-review does that.
argument-hint: "[path | commit range | --staged | --working] [--commits] [--pr] [--notes] [--all] [--fix]"
---

# Prose review

Grade every in-scope passage against `prose-style.md`.  Report the findings.  Apply them only when
Jon passes `--fix`.

You judge words.  You never judge code, and you never edit code.

## 1. Read the style reference first

`prose-style.md` is the authority.  Read the whole file before you grade a single passage.  Do not
work from memory of it.

Find it in this order:

1. `prose-style.md` at the current repo root.
2. `prose-style.md` in a parent directory, walking up.
3. `${CLAUDE_PLUGIN_ROOT}/references/prose-style.md`, this plugin's bundled copy.

A repo's own copy always wins; the bundled copy is the fallback, so the skill works in a repo that
has no copy of its own.  Never hardcode a path to a copy in some other repo.  If you find no copy
at all, stop and say so.  Do not substitute general style knowledge.

Every rule below is a pointer into that file, not a replacement for it.  When the two disagree,
`prose-style.md` wins.

## 2. Resolve the artifacts

Two dimensions: which prose, and which change.  Resolve the prose first.

| Flag | Adds |
|---|---|
| *(none)* | Code comments and javadoc / API docs.  The default. |
| `--commits` | The commit messages in the resolved range. |
| `--pr` | The pull request description for the branch. |
| `--notes` | Release notes the patch touches. |
| `--all` | All of the above. |

Comments are the default because they are the only artifact that ships inside the code and the only
one every patch has.  Everything else is opt in.  Never widen past what Jon asked for.  If you see a
violation in an artifact he did not select, name it in **Left alone** and leave it.

## 3. Resolve the scope

Use the argument if Jon gave one:

- A path: every artifact in that file or directory.
- A commit range or a single revision: every artifact the range touches.
- `--staged` or `--working`: the staged or unstaged diff.

With no argument, review the current branch's patch.  Get its base from the tracked upstream:

```
git merge-base HEAD @{upstream}
```

If the branch tracks nothing, ask Jon for the base branch.  Do not guess it, and do not assume
`trunk` or `main`.

Print the resolved artifacts, the resolved scope, and the file count before you start.

### What a patch scope includes

- Every passage on a line the patch adds or modifies.
- Every pre-existing passage the patch made wrong.

A pre-existing passage that is merely nearby stays out of scope.  Say so in the report if you see a
bad one, and leave it alone.

## 4. Run the Axis 1 pre-pass

Axis 1 violations are the highest severity and the cheapest to find.  Grep the in-scope files for
the tells:

```
grep -nEi '(previously|formerly|used to|originally|in the first version|as of v|now correct|changed from|per review|review feedback|no longer|refactored|improved|new implementation|updated to)' <files>
```

Run the same grep over `git log` output when `--commits` is in play.

Treat every hit as a candidate, not a verdict.  "No longer" and "instead of" have honest uses.  A
hit is a violation only when it references this branch's own unmerged history.  A reference to
merged history, a shipped release, or an open upstream bug is legitimate permanent context.

Read `prose-style.md`'s squash-target section before you judge a contrast drawn against a sibling
commit.  A fixup commit that exists only to correct an earlier commit on the same unmerged branch is
itself an Axis 1 violation, whatever its wording.  Report it and point at `/squash`.  Never rewrite
history to fix it yourself; see the guardrails.

## 5. Grade each passage

Follow this order.  It exists because `prose-style.md` says to regenerate, not to patch; a rewrite
that starts from the old wording inherits the old residue.

1. Read the context the passage describes — the whole method or declaration for a comment, the diff
   for a commit message, the branch's diff for a PR description.
2. List the facts the reader needs that the artifact's own context cannot state for itself.
3. Cut from that list every fact `prose-style.md` says to cut for this artifact.
4. Write the replacement from the surviving list alone.  Do not reread the old text yet.
5. Now read the old text once.  Look only for a load-bearing fact you missed.  If you find one, add
   it to the list and write again from the list.  Never paste the old phrasing back.
6. Check the anchor.  A mechanism-level comment belongs at the operation it protects, not at a type
   declaration or an enclosing method.  If the same invariant is relied on at several sites, anchor
   a comment at each site.
7. Check the referents.  If you cut a sentence, no surviving sentence may point at it.

Apply the STE mechanics to the result: active voice, simple tense, one meaning per word, one
instruction per sentence, 20 words or fewer for an instruction, 25 or fewer for a description, three
words or fewer in a noun cluster, no ellipsis, a list for three or more steps.

### Match the focus to the artifact

Each artifact has a different reader.  `prose-style.md` states each one in full; these are the tells
to grade against.

- **Comments** — the one fact the code cannot say, then stop.  Length tracks the count of
  independent, non-inferable facts, not a line cap.
- **Javadoc and API docs** — the contract: inputs, outputs, guarantees, and when a value is
  meaningless.  A per-platform enumeration of how a value is produced is implementation, not
  contract.  A performance caveat earns a place only when the number itself is the contract.
- **Commit messages** — what changed, not how it works.  The subject states the outcome or
  capability; a subject naming a method, field, or register belongs in the body instead.  No
  design-rationale essay.
- **PR descriptions** — what changed, and why this approach.  Enough for a reviewer to judge the
  approach before reading every commit.
- **Release notes** — the observable, user-facing effect, for a reader with no codebase context, and
  only the delta this release carries.  Cover known user-visible residual limitations too.

### The verdicts

- **keep** — the passage already complies.  Change nothing.
- **rewrite** — replace the text.
- **cut** — the surviving fact list is empty.  Delete the passage.
- **relocate** — the text is sound but sits at the wrong anchor.  Move it, and reword it for its new
  home if the new position changes what needs saying.
- **flag** — you cannot verify the fact the passage encodes.  Leave it exactly as it is and report
  it.

Give every verdict except **keep** its full replacement text in the report, even without `--fix`.
The replacement is the finding.  A finding that only names the problem makes Jon do the regeneration
this skill exists to do.

### Two rules that override the cutting instinct

**Never cut a passage whose fact you cannot verify.**  It may record a decision the code does not
show.  Deleting it destroys the only copy.  Flag it instead.

**Never invent a fact.**  If a replacement would assert something you have not read in the code, do
not assert it.

## 6. Never touch these

- The Apache licence header.
- Generated files, and vendored or third-party source.
- A JIRA identifier, an issue number, a URL, or a `@param`/`@return`/`@throws` tag name.  You may
  restyle the prose beside them.
- A tool pragma: `// CHECKSTYLE`, `// NOSONAR`, `//$NON-NLS-1$`, and similar.
- Commented-out code.  That is a code question, not a prose question.  Report it and move on.
- Any line of code, in any way, for any reason.

## 7. Report

Without `--fix`, stop here.  Group by file, then by artifact:

```
src/java/org/apache/cassandra/db/compaction/CursorCompaction.java
  :412  [H] cut       in-flight commentary: contrast with a squashed-away commit
  :455  [M] rewrite   three clauses of consequence already visible below
  :488  [M] relocate  -> :503, the unlocked read it describes

commit 4f21ac9
  [M] rewrite   subject names the method; the fix belongs there instead
```

Print the full replacement text under each finding.

Report the severity per `prose-style.md`: `[H]` for an Axis 1 violation, or a javadoc or
release-note passage that is false or unactionable; `[M]` for a change in what the reader takes
away; `[L]` for pure STE mechanics.  Do not rank the findings by urgency and do not recommend an
order; Jon decides that.

Then list separately, under a **Left alone** heading:

- Every **flag** verdict, with the reason you could not verify it.
- Every commented-out block you found.
- Every out-of-scope bad passage you noticed, including one in an artifact Jon did not select.

## 8. Apply, with `--fix` only

Apply what you reported, artifact by artifact.  Report first, then edit — never edit a passage you
did not report.

**Comments, javadoc, and release notes.**  Edit one file at a time.  Match the exact existing text
and replace it; do not edit by line number, because a cut shifts every line below it.  Match the
surrounding comment conventions — capitalisation, `//` against `/* */`, indentation.  House
convention wins over personal preference.

**The PR description.**  Outward-facing.  Show the replacement body and get Jon's word before you
run `gh pr edit <n> --body`.

**Commit messages.**  Report only.  Rewriting them rewrites history, which is Jon's call and needs a
force-push he has not asked for.  Hand him the replacement text and point at `/squash`.  Never run
`git rebase`, `git commit --amend`, or `git push` to land a message fix.

### Verify the diff

After every file is done, prove that you changed comments only:

```
git diff -U0 | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*(//|/\*|\*|$)'
```

Empty output means every changed line is a comment line or blank.  Any output needs your eyes: an
interior line of a block comment can legitimately appear here, and a release note is prose in a
file, not a comment.  Investigate each one.  Revert anything that turns out to be code.

If you changed a `/*` or `*/` delimiter anywhere, compile the affected files as well.  A mangled
delimiter is the one way a comment edit breaks a build.

Close with a one-line tally: `Applied 3 changes across 1 file.  Diff verified: comment lines only.`

## Guardrails

- Judge words.  Never edit code.
- Report by default.  Edit only with `--fix`.
- Never commit and never push.  Jon reviews with `git diff` and commits himself.
- Never rewrite git history, even with `--fix`.
- Never widen the scope, or the artifact set, past what Jon named.
- If the review would change more than roughly 40 passages, say so and confirm the scope before you
  start editing.
