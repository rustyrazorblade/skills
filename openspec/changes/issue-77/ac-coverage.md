# Acceptance criteria coverage

| Source | Requirement | Covering scenario(s) | Status |
|--------|-------------|----------------------|--------|
| AC | More than one round unless round 1 already meets the readiness bar | `idea-refinement: An idea with unresolved detail runs more than one round`; `A small idea converges in one round` | ✅ Covered |
| AC | The next round receives the answers and the previous refinement, and digs further | `idea-refinement: A later round receives what came before`; `A bare answer retains its question` | ✅ Covered |
| AC | `groom` runs another round unless every criterion is testable, unhappy paths covered, no behavioural assumption left | `idea-refinement: The agent claims completeness but the bar is unmet`; `Design assumptions do not hold the loop open` | ✅ Covered |
| AC | A criterion testable only via an unsourced specific value is not ready | `idea-refinement: An unsourced specific value does not satisfy the bar` | ✅ Covered |
| AC | Questions reach the owner one at a time, ≤3 per round, each with a recommended default | `idea-refinement: A round asks three questions`; `A round produces more candidate questions than the cap`; `A question arrives without a recommended default` | ✅ Covered |
| AC | An owner hand edit is binding, and the agent does not re-propose what was cut | `idea-refinement: The owner rewrites a scope line`; `The owner deletes a criterion without comment` | ✅ Covered |
| AC | When two record entries contradict, the later wins | `idea-refinement: A later answer contradicts an earlier one` | ✅ Covered |
| AC | Owner technical direction is recorded verbatim, never reworded, and appears in the issue | `idea-refinement: The owner states a constraint mid-loop`; `The agent tries to restate direction as behaviour` | ✅ Covered |
| AC | An issue with technical direction reaches `architect` with that section verbatim | `idea-refinement: activate hands technical direction to architect`; `An issue without technical direction is unaffected` | ✅ Covered |
| AC | Ending the loop runs a closing pass with the last answers that asks nothing | `idea-refinement: The closing pass asks nothing`; `The owner's final answers reach the agent`; `The owner ends the loop` | ✅ Covered |
| AC | Traceable assumptions are bulk-confirmable and promote; unraised ones need explicit yes/no | `idea-refinement: A traceable assumption is bulk-confirmed`; `An agent-authored assumption cannot ride along` | ✅ Covered |
| AC | A round whose questions are all already answered ends the loop | `idea-refinement: A round produces nothing new` | ✅ Covered |
| AC | Unresolved assumptions appear in a dedicated issue-body section | `idea-refinement: An unresolved assumption is recorded, not dropped` | ✅ Covered |
| Risk | Owner fatigue — the loop asks more than the owner will sit through | `idea-refinement: A round produces more candidate questions than the cap`; `A round produces nothing new`; `A small idea converges in one round` | ✅ Covered |
| Risk | The readiness bar applied loosely lets a vague criterion through | `idea-refinement: The agent claims completeness but the bar is unmet` | ✅ Covered |
| Risk | The readiness bar applied strictly chases detail owned by the architect | `idea-refinement: Design assumptions do not hold the loop open` | ✅ Covered |
| Risk | More rounds multiply the chance of agent-invented scope | `idea-refinement: A repo finding suggests unrequested scope`; `Invention does not accumulate across rounds`; `An agent-authored assumption cannot ride along` | ✅ Covered |
| Risk | Conversation compaction silently degrades the record to a paraphrase | `idea-refinement: The record survives a compacted conversation` | ✅ Covered |
| Risk | A longer, code-denser issue body fires the existing shell-interpolation bug | `idea-refinement: A body citing related code` | ✅ Covered |
| Risk | The agent driving `groom` follows its own stale single-pass instruction | `idea-refinement: The driving agent's instructions match the skill` | ✅ Covered |
| Risk | The no-new-questions stop is unreachable because a fresh agent paraphrases | `idea-refinement: A bare answer retains its question` | ⚠️ Partial — recording each answer with its question makes recognizing a paraphrase tractable, but the judgement is `groom`'s and is not mechanically verifiable. Accepted: the owner is present every round and can end the loop. |
| Risk | Cost and latency — several subagent rounds, each re-reading the repo | — | ⚠️ Excluded — inherent to the change the owner asked for; no scenario can assert an acceptable cost, and no round cap was chosen. |
