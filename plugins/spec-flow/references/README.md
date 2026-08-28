# references

Files this plugin ships for a skill or an agent to read by an explicit
`${CLAUDE_PLUGIN_ROOT}`-relative path. Nothing here is loaded automatically. The three entries
below are unlike each other, so each names its own consumer.

| File | Read by | When |
|---|---|---|
| `ci/` | The owner, by hand, and `/spec-flow:adopt-tiering` step 5 | CI workflow YAMLs copied into the consuming repo's `.github/workflows/`, for a repo whose own policy makes CI a test gate. See `ci/README.md`. |
| `refactoring-discipline.md` | `agents/tdd-developer.md` | On behavior-preserving work: a refactor, a `type:tech-debt` fix, or the REFACTOR step of a TDD cycle. |
| `TESTING.md.template` | `skills/setup/SKILL.md`, during seeding only | **Read only while a repo is being seeded, with the owner present. Never at runtime.** `setup` opens it only where it has already read the repo and found the tiered shape. |

**A template is named for what it becomes.** A template this plugin ships whose destination is a
single named file carries that filename plus a `.template` suffix, so a reader can pair it with the
file it seeds without opening either one. `TESTING.md.template` becomes the consuming repo's
`spec-flow/TESTING.md`. The workflow YAMLs in `ci/` are named for the runner they wire, not for a
destination, because the owner picks one of several and names the copied file themselves.

**The seeding template is not a fallback.** The pipeline reads the consuming repo's own
`spec-flow/TESTING.md` and nothing else; when that file is absent the check exits non-zero and the
run stops. `scripts/repo-config.sh` composes the policy path from the **consuming repo's** root,
which it gets from `git rev-parse --show-toplevel`; it never knows the plugin's root. The template
sits inside the plugin, so it is outside the tree any resolution searches, and reaching it would
take a literal path written by hand. Containment, not the name, is what keeps it unreachable —
the `.template` suffix is for the reader, and carries no weight in that guarantee.
