// Offline check for implement.workflow.js's `closingLines`: the guard on the required `alsoCloses`
// argument and the `Closes #` lines the tech-debt draft PR body starts with. The workflow script
// runs inside the Workflow tool and cannot be imported, so this loads the function's source
// between its BEGIN/END markers and evaluates it alone. Exits non-zero if any check fails.
// Run: node plugins/spec-flow/scripts/test-implement-workflow.mjs
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const workflow = join(here, '..', 'skills', 'implement', 'implement.workflow.js')
const src = readFileSync(workflow, 'utf8')
const match = src.match(/\/\/ BEGIN closingLines[^\n]*\n([\s\S]*?)\/\/ END closingLines/)
if (!match) {
  console.log(`FAIL: no BEGIN/END closingLines markers in ${workflow}`)
  process.exit(1)
}
const closingLines = new Function(`${match[1]}\nreturn closingLines`)()

let pass = 0
let fail = 0
function check(desc, ok, detail) {
  if (ok) {
    console.log(`PASS: ${desc}`)
    pass++
  } else {
    console.log(`FAIL: ${desc}`)
    if (detail) console.log(`      ${detail}`)
    fail++
  }
}

function throws(desc, alsoCloses) {
  try {
    const got = closingLines(971, alsoCloses)
    check(`${desc}: throws`, false, `returned ${JSON.stringify(got)}`)
  } catch (e) {
    check(`${desc}: throws`, true)
    check(`${desc}: the error names alsoCloses`, /alsoCloses/.test(e.message), e.message)
  }
}

throws('missing', undefined)
throws('not an array', 928)
throws('zero', [0])
throws('negative', [-3])
throws('fraction', [1.5])
throws('a string entry', ['928'])
throws('an entry equal to the issue', [971])
throws('one bad entry among good ones', [928, 'x'])

const empty = closingLines(971, [])
check('empty list: only the issue line', JSON.stringify(empty) === JSON.stringify(['Closes #971']), JSON.stringify(empty))

const two = closingLines(971, [928, 930])
check(
  'two entries: the issue line first, then each in order',
  JSON.stringify(two) === JSON.stringify(['Closes #971', 'Closes #928', 'Closes #930']),
  JSON.stringify(two),
)

console.log('')
console.log('----------------------------------------')
console.log(`PASS: ${pass}  FAIL: ${fail}`)
process.exit(fail ? 1 : 0)
