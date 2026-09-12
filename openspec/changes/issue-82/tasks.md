# Tasks — issue 82: owner presentation contract

## 1. The canonical contract

- [x] 1.1 Add a "Presenting to the owner" section to `docs/workflow.md` with the four rules: plain
      terms before any identifier; one decision at a time by default; the owner may override to a
      batch; every option states its cost and marks the recommended one where one exists.
- [x] 1.2 In that section, split the rules by kind: plain terms and translate-the-words apply to
      every presentation including PR bodies and comments; one-at-a-time and its wait apply to
      interactive decision points.
- [x] 1.3 In that section, name the deliberate batch presentations the contract does not govern:
      status summaries (the board), read-only check batches (`setup` step 1), whole-artifact reviews
      (Seam 1 coverage tables, `implement`'s residual findings list).

## 2. Fix each owner-facing presenter in place

- [ ] 2.1 `agents/issue-manager.md`: reword the 0.46.0 sentence to forbid an identifier only as
      subject or sole referent, allow it as a trailing tag; add the panel-finding relay rule and the
      one-at-a-time default to the relay path; reference the contract.
- [ ] 2.2 `skills/implement/SKILL.md`: fix the fix-round and gate-failure emitting instructions so
      residual findings are stated in plain terms with the identifier as a trailing tag; reference
      the contract.
- [ ] 2.3 `skills/address/SKILL.md`: fix the report path so findings are stated in plain terms;
      reference the contract.
- [ ] 2.4 `skills/activate/SKILL.md`: add the missing recommended-default half to step 1 ("with a
      recommended answer where you have one"); reference the contract.
- [ ] 2.5 `skills/groom/SKILL.md`: reword step 4's "the only exception" line to point at the
      contract's list of exempt batches.
- [ ] 2.6 `skills/setup/SKILL.md`: reference the contract alongside its existing interview-discipline
      reference.
- [ ] 2.7 `agents/project-manager.md`: add a compliant pointer to the contract for its owner-facing
      presentations (board, next-decision, archive confirmations).

## 3. Verification

- [ ] 3.1 Write `verification.md` with a worked before/after example per acceptance criterion.
- [ ] 3.2 Write the coverage checklist mapping each acceptance criterion to the file and line that
      satisfies it.
- [ ] 3.3 Scan every bound file and confirm no instruction tells an agent to present the owner a bare
      identifier as a referent.
