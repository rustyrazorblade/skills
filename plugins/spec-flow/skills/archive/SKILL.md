---
name: archive
description: Check the buildup of un-archived OpenSpec changes waiting on the default branch (one per merged-and-finalized issue) against a threshold (default 5, overridable), and — once confirmed with the owner — spawn a dedicated background worker to sync and archive them all in one pass and land one PR. Owner-invoked or offered by project-manager when it notices the buildup; never automatic. Part of the flow delivery workflow (see docs/workflow.md).
---

# archive — batch-archive the piled-up OpenSpec changes

You are the central `project-manager` (this isn't tied to any one issue, so it's yours to run, the
same way `board`/`groom`/`setup` are — no `issue-manager` involved). Every finalized issue leaves its
`openspec/changes/issue-<N>` change sitting on the default branch, unarchived, until this runs.
You **watch for the buildup and check in with the owner** — you never archive on your own
initiative, and you never do the archiving work yourself; once the owner confirms, you delegate it
to a dedicated background worker, the same way you delegate an issue to `issue-manager`.

## Steps

1. **Count the buildup.** List every top-level `openspec/changes/*` directory except `archive/` on
   the default branch — each one is a finalized-but-unarchived issue. Use the `<ref>:<path>` form,
   not a plain pathspec — `git ls-tree -- openspec/changes` (no trailing slash) lists the directory
   itself, not its children (confirmed live); `<ref>:<path>` lists bare child names directly, and
   `2>/dev/null` covers the case where `openspec/changes` doesn't exist in this tree at all
   (nothing pending, not an error):
   ```bash
   DEFAULT_BR=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   git fetch origin "$DEFAULT_BR"
   git ls-tree --name-only "origin/$DEFAULT_BR:openspec/changes" 2>/dev/null | grep -v '^archive$'
   ```
   Each entry is `issue-<N>` — extract `<N>`. Empty output means nothing's pending; say so and
   stop.

2. **Resolve the threshold.** Default **5**. Check for a standing override the owner has stated —
   in this conversation already, or written as a preference in this repo's (or their global)
   `CLAUDE.md` — before falling back to the default. This is the same kind of "check CLAUDE.md for
   a stated preference" `project-manager` already does for spawn instructions; don't invent a
   number that wasn't actually stated anywhere.

3. **Below threshold?** Report the count against the threshold ("3 of 5 — not archiving yet") and
   stop, **unless the owner explicitly asks you to archive now regardless of count** (an ad hoc
   override for this run only — doesn't change the standing threshold for next time). Never treat
   silence as permission to lower the bar.

4. **At or above threshold (or overridden) — list the batch and confirm before doing anything.**
   Show the owner exactly which issues are about to be archived (`#A`, `#B`, ... — always paired
   with a brief description) and ask before proceeding. This is real confirmation, not a
   formality — archiving lands a real PR, and the owner should see the batch before it's built,
   the same way they see a design before it's implemented.

5. **Confirmed — spawn the worker, don't do the work yourself.** This is the only *upfront* owner
   check-in — once you spawn, the worker builds the batch, commits, opens the PR, **and merges it,
   fully on its own**, no further confirmation needed for any of that. The one exception is a
   genuine content conflict while reconciling delta specs (two changes touching the same
   requirement incompatibly) — the worker doesn't guess a resolution or stop-and-exit for that; it
   posts a comment on the conflicting issues and **pauses to work it out with the owner
   interactively**, in that same session, then continues the batch from where it left off once
   resolved — see `agents/archive-batch.md` step 3. A blocked merge (required checks, branch
   protection) also stops the worker, but that's mechanical, not a judgment call, and it does end
   the run rather than pausing it — relay whatever it reports.
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/spawn-archive-batch.sh
   ```
   Report its one-line output — the session id — and tell the owner they can attach via
   `claude agents` (select it from the list) to watch it work, same as an `issue-manager`. **Don't create the worktree,
   run `openspec-sync-specs`/`openspec-archive-change`, or open the PR yourself** — if you catch
   yourself about to do any of that inline, stop; that's `agents/archive-batch.md`'s job, running
   as its own process specifically so this doesn't become work in your own context. If the script
   fails, relay its error verbatim rather than hand-rolling a replacement spawn — same rule as
   `spawn-issue-manager.sh`.

## Rules

- **Never invent a schedule.** Don't suggest running this "every night" or wire it to anything
  automatic — the threshold check happens when you're asked, or when you naturally notice the
  count while doing something else (e.g. `board`); it's never a background timer.
- **Always confirm before spawning**, even when the threshold is clearly met — see step 4. The one
  exception is the owner's own ad hoc "archive now" — that IS the confirmation.
- **You delegate this, you don't do it.** Steps 1-4 are checks and a conversation; step 5 is a
  spawn, not an implementation. If you're editing OpenSpec files, running `git worktree add`, or
  calling `gh pr create` from here, you've drifted into `archive-batch`'s job.
- **This never touches any issue's own feature branch or PR.** It only ever operates on the
  default branch's already-merged `openspec/changes/` content — a completely separate, code-free
  bookkeeping lane.
- When you cite an issue or PR, always write it as `<number>: <title>`, on its own line with a `-`
  prefix — never a bare number, and never several run together inline in a sentence. The batch
  confirmation list in step 4 follows this format too.
