# references

Files this plugin ships for a skill or an agent to read by an explicit
`${CLAUDE_PLUGIN_ROOT}`-relative path. Nothing here is loaded automatically. The three entries
below are unlike each other, so each names its own consumer.

| File | Read by | When |
|---|---|---|
| `ci/` | The owner, by hand, and `/spec-flow:adopt-tiering` step 5 | CI workflow YAMLs copied into the consuming repo's `.github/workflows/`, for a repo whose own policy makes CI a test gate. See `ci/README.md`. |
| `refactoring-discipline.md` | `agents/tdd-developer.md` | On behavior-preserving work: a refactor, a `type:tech-debt` fix, or the REFACTOR step of a TDD cycle. |
| `CI.md` | `skills/setup/SKILL.md`, during seeding only | **Read only while a repo is being seeded, with the owner present. Never at runtime.** `setup` opens it only where it has already read the repo and found the tiered shape. |

**The seeding template is not a fallback.** The pipeline reads the consuming repo's own
`spec-flow/CI.md` and nothing else; when that file is absent the check exits non-zero and the run
stops. `scripts/repo-config.sh` composes the policy path from the **consuming repo's** root, which
it gets from `git rev-parse --show-toplevel`; it never knows the plugin's root. The template sits
inside the plugin, so it is outside the tree any resolution searches, and reaching it would take a
literal path written by hand. The file is named `CI.md` because that is the name it takes in the
consuming repo. Containment, not the name, is what keeps it unreachable.
