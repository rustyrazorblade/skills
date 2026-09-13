# Acceptance-criteria coverage — issue 82

| Source | Requirement | Covering scenario(s) | Status |
|--------|-------------|----------------------|--------|
| AC | A finding is stated in plain terms before any identifier; the identifier is optional trailing context | `owner-presentation: Relaying a review-panel finding` | ✅ Covered |
| AC | Several findings/decisions are presented one at a time by default, waiting before the next | `owner-presentation: Several findings after a review round` | ✅ Covered |
| AC | The owner may ask for the whole set at once; the override applies to that request only | `owner-presentation: The owner asks for the whole set` | ✅ Covered |
| AC | A cited file, line, scenario, or task number says what is there, not just names it | `owner-presentation: Citing a file and line` | ✅ Covered |
| AC | Each option states its cost as well as its effect; the recommended one is marked | `owner-presentation: Options with a recommendation`; `owner-presentation: A decision the agent must not steer` | ✅ Covered |
| AC | A relayed finding is not presented in the author's vocabulary without translation | `owner-presentation: Relaying a review-panel finding` | ✅ Covered |
| Risk | A pointer alone would not change behavior; the emitting instruction must be fixed in place | tasks 2.1–2.7 fix each site in place, not only via a pointer | ✅ Covered |
| Risk | The contract must not forbid deliberate batch presentations (board, coverage tables, PR residual lists) | `owner-presentation: The board renders many items`; `owner-presentation: A finding written into a PR body` | ✅ Covered |
| Risk | The contract must not falsify groom's "the only exception" claim | `owner-presentation: groom's bulk assumption confirm` | ✅ Covered |
| Risk | The 0.46.0 sentence must not contradict AC1's trailing-tag allowance | `owner-presentation: The 0.46.0 spec-identifier sentence` | ✅ Covered |
| Risk | One-at-a-time cannot apply to one-shot written artifacts (PR body, comment) | `owner-presentation: A finding written into a PR body` | ✅ Covered |
| Risk | "Every agent" must not bind review subagents that never present to the owner | `owner-presentation: A review subagent returns findings to its lead` | ✅ Covered |
