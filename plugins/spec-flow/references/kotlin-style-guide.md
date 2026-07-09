# Kotlin Style Guide

A guide for writing idiomatic, safe, expressive Kotlin. Each rule is stated
imperatively and backed by a concrete, self-contained example. When in doubt,
prefer the pattern shown here over a more general one.

The overarching philosophy: **lean on the type system and the compiler.** Make
illegal states unrepresentable, push nullability to the edges, and let
exhaustive `when` over sealed hierarchies replace defensive runtime checks.
Clarity comes from immutability, expression-oriented code, and ruthless
consistency; safety comes from the compiler proving things rather than the
programmer hoping for them.

---

## 1. Formatting

Use `ktlint` (and/or the IntelliJ Kotlin formatter configured to the official
style) as the project-wide authority:

```
# .editorconfig
[*.{kt,kts}]
ktlint_code_style = ktlint_official
max_line_length = 120
indent_size = 4
ij_kotlin_allow_trailing_comma = true
ij_kotlin_allow_trailing_comma_on_call_site = true
```

Rules:

- **Never hand-format.** Let `ktlint` decide. Write code, run `ktlintFormat`,
  commit the result. Do not fight it.
- **One statement per line; no semicolons.** Kotlin does not need them — a
  trailing `;` is noise.
- **Trailing commas** on multi-line argument and parameter lists, so adding or
  reordering an entry is a one-line diff.
- **Let long signatures wrap** to one parameter per line, closing paren and
  return type on their own line:

  ```kotlin
  fun interpolate(
      nameToIndex: (String) -> Int?,
      haystack: ByteArray,
      replacement: ByteArray,
      dst: StringBuilder,
  ): Int {
      // ...
  }
  ```

- **Stack call/builder chains vertically** when they exceed the width, each
  `.call()` on its own line:

  ```kotlin
  val client = HttpClient(CIO) {
      install(ContentNegotiation) { json() }
      install(Logging) { level = LogLevel.INFO }
  }
  ```

---

## 2. Naming

| Item | Convention | Example |
|------|------------|---------|
| Classes / interfaces / objects | `PascalCase` | `Searcher`, `Matcher`, `BinaryDetection` |
| Functions / methods | `camelCase` | `findAt`, `isMatch`, `maxContext` |
| Properties / locals / params | `camelCase` | `lastEnd`, `lineTerm` |
| Compile-time constants (`const val`, top-level/`companion`) | `SCREAMING_SNAKE_CASE` | `MAX_LOOK_AHEAD` |
| Type parameters | single uppercase letter | `T`, `R`, `K`, `V` |
| Backing/enum entries | `SCREAMING_SNAKE_CASE` | `UNCLOSED_CLASS` |

Conventions:

- **Predicates start with `is`/`has`/`should`** and return `Boolean`:
  `isPartial()`, `isIo()`, `hasSuffix()`.
- **Factory functions read like constructors.** Prefer a `companion object`
  factory or a same-named top-level function over a telescoping constructor:
  `Match.zero()`, `LineTerminator.crlf()`, `lineTerminator(byte)`.
- **Booleans are positive and unprefixed at the property** (`val hidden:
  Boolean`), but **boolean setters/DSL methods take a named arg**
  (`hidden(yes = true)`) so call sites are self-documenting.
- **Don't encode the type in the name** (no `strName`, no `iCount`). The
  compiler already knows the type; the name should carry meaning.
- **Avoid abbreviations** except established ones (`id`, `url`, `io`). Acronyms
  longer than two letters are `camelCase`: `httpClient`, not `hTTPClient`.

---

## 3. Documentation & Comments

Document the public surface. Treat KDoc as part of the API.

- **KDoc (`/** ... */`) on every public declaration**, in present-tense, active
  voice describing behavior: `/** Returns a new match. */`,
  `/** The full path this entry represents. */`. Use `@param`, `@return`,
  `@throws`, and `@sample` where they add information the signature does not.

  ```kotlin
  /**
   * Offsets both ends of this match by [amount].
   *
   * @throws ArithmeticException if the shift overflows.
   */
  fun offset(amount: Int): Match
  ```

- **Document every checked precondition.** If a function calls `require`,
  `check`, or `requireNotNull`, state the contract in KDoc — the `@throws
  IllegalArgumentException` is part of the API.
- **Inline comments (`//`) explain *why*, never *what*.** Reserve them for
  non-obvious logic, edge cases, and invariants:

  ```kotlin
  // Empty match: bump the start so the next search makes progress and we
  // don't spin on a zero-width match forever.
  lastEnd = m.end + 1
  ```

- **Tone is professional and complete-sentence.** Never terse to the point of
  ambiguity, never chatty. Let the example carry the weight where prose would
  just restate the code.

---

## 4. Package & Module Organization

Decompose by *responsibility*, sliced vertically, with dependencies flowing
**downward only**. In a Gradle multi-module build, define a low-level
interface/contract module, implement it in sibling modules, and layer
higher-level modules on top:

```
:core      → core domain types + interfaces. No internal deps.
:impl-a    → implements the core interfaces.   ┐ depend on :core
:impl-b    → implements the core interfaces.   ┘
:engine    → orchestration built on the interfaces.
:output    → formats and writes results.       (:core + :engine)
:app       → the entry point; wires everything together (Koin/manual DI).
```

This enables swappable implementations, independent evolution, and reuse. Apply
the same principle within a single module using packages instead of modules.

- **Package by feature, not by layer.** Prefer `search/`, `walk/`, `output/`
  over `controllers/`, `services/`, `models/`. A feature's types live together.
- **One top-level public type per file**, named after the type
  (`Searcher.kt`). Small, tightly-related types (a sealed hierarchy and its
  variants, a value class and its factory) may share a file.
- **Visibility is `internal` by default for module-internal helpers**, `public`
  (the Kotlin default — write it explicitly only on API surface) for the
  module's API, `private` for file/class-local. Prefer `internal` over leaking
  a helper as `public`.
- **No `Utils`/`Helpers` dumping grounds.** A behavior that operates on a type
  belongs as an extension function near that type, in that type's file or a
  cohesive `<Type>Extensions.kt`.

---

## 5. Types: classes, data classes, sealed hierarchies, enums

### Prefer immutable data classes for values

A type that is "just data" is a `data class` with `val` properties. You get
`equals`/`hashCode`/`toString`/`copy`/destructuring for free.

```kotlin
/** The span of a match, as half-open byte offsets `[start, end)`. */
data class Match(val start: Int, val end: Int) {
    init {
        require(start <= end) { "start ($start) must be <= end ($end)" }
    }

    companion object {
        val ZERO = Match(0, 0)
    }
}
```

- **Validate invariants in `init`** so an instance can never exist in an illegal
  state. This is the Kotlin equivalent of enforcing invariants in a constructor.
- **Evolve values with `copy`, never by mutation:**
  `match.copy(end = match.end + 1)`.

### Use `value class` for zero-cost newtypes

Wrap a raw type to add meaning and invariants without an allocation:

```kotlin
@JvmInline
value class CollectionId(val raw: String) {
    init { require(raw.isNotBlank()) { "collection id must not be blank" } }
}
```

A `CollectionId` cannot be confused with a `TenantId` or a bare `String` at a
call site, but compiles down to the underlying `String`.

### Make illegal states unrepresentable with `sealed`

A closed set of variants is a `sealed interface`/`sealed class`. Each variant
carries exactly the data that variant needs — this is Kotlin's answer to a
tagged union, and it pairs with exhaustive `when` (§7).

```kotlin
sealed interface LineTerminator {
    data class Byte(val value: kotlin.Byte) : LineTerminator
    data object CrLf : LineTerminator
}
```

- Use `data object` for variants with no payload, `data class` for variants
  that carry context.
- Keep the hierarchy in one file so the compiler (and the reader) sees the whole
  closed set at once.

### Reserve `enum class` for a fixed set of constants

Use an `enum` when the variants are simple, payload-free named constants
(possibly with shared properties/behavior). Reach for `sealed` the moment a
variant needs its own distinct data.

```kotlin
enum class Severity(val rank: Int) {
    DEBUG(0), INFO(1), WARN(2), ERROR(3);
    fun atLeast(other: Severity) = rank >= other.rank
}
```

### Class member order

Within a class, order members predictably: properties → `init` →
secondary constructors → public functions (constructors-as-factories first,
then accessors, then behavior) → internal/private helpers → `companion object`.

---

## 6. Null Safety — non-null by default, never `!!`

This is the heart of writing safe Kotlin. The type system distinguishes `T`
from `T?`; honor that distinction instead of defeating it. The failure mode this
section corrects is **"Java with a Kotlin accent"** — code that compiles as
Kotlin but carries Java's defensive habits, the most common being nullable types
scattered everywhere "just in case."

### Default to non-nullable types

**A nullable type is a design decision, not a default.** Declare `T`, not `T?`,
unless absence is a real, meaningful state the caller must handle. Most
properties, parameters, and return types should be non-null. If you cannot say
in one sentence what null *means* at this site, do not write `?`.

```kotlin
// Good: the type guarantees a value exists.
class Searcher(private val config: Config, private val matcher: Matcher)

// Bad: nullable with no reason — every use now needs a null check.
class Searcher(private val config: Config?, private val matcher: Matcher?)
```

Push nullability to the **edges** (parsing input, external I/O, optional config)
and resolve it there. Internal code should work with non-null types.

### Decision procedure — run before adding any `?`

Walk these in order. The first one that applies gives a non-null solution; only
if you fall through all of them is `?` the right answer.

1. **Set at construction time?** Make it a non-null constructor `val`. No `?`.
2. **Set once shortly after construction** by a framework, DI, or test setup?
   Use `lateinit var` (non-null, set-once). No `?`.
3. **Computed once on first access?** Use `by lazy` (non-null). No `?`.
4. **Does "absent" really mean an empty collection?** Hold/return an empty
   `List`/`Set`/`Map`, never `List<T>?`.
5. **Is "absent" a distinct domain state with its own behavior?** Model it with
   a `sealed` type (§5), not null.
6. **Optional function parameter?** Use a default argument (§9), not a nullable
   param.
7. **Does null genuinely mean "this value may legitimately not exist"** — a
   lookup that found nothing, an optional field in external data, a Java interop
   boundary? *Now* `?` is correct. Use it.

### When nullable IS correct — don't over-correct

The goal is not *zero* nullable types; it's that every `?` is intentional.
Over-correcting is its own defect — do **not** rewrite these into `Optional<T>`,
a throw on an expected miss, or a contortion to avoid the `?`:

- **"Find one" lookups** that can miss: `fun findByExternalId(id: String):
  Payment?` returning `null` for not-found. This is idiomatic, and better than
  both `Optional<T>` and throwing for an expected absence.
- **Genuinely optional fields** parsed from external/untrusted data (JSON, user
  input) where the field may legitimately be absent.
- **Java interop boundaries** where a Java API can return `null`.

Here `?` is the honest type. Keep it, and handle it at the call site (below).

### Never use `!!`

The not-null assertion operator `!!` throws `NullPointerException` and discards
every guarantee the type system gave you. **It is banned on production paths.**
`detekt`'s `UnsafeCallOnNullableType` rule flags it; treat a flagged `!!` as a
defect to redesign, not a wart to suppress.

Replace `!!` with one of these, in order of preference:

1. **Don't have a nullable in the first place** — restructure so the value is
   non-null by construction (the best fix).
2. **Safe call `?.`** to operate only when present:
   ```kotlin
   val length = name?.length            // Int?, no throw
   user?.profile?.email?.let(::notify)  // runs only if the whole chain is non-null
   ```
3. **Elvis `?:`** to supply a default or fail loudly with a *meaningful* error:
   ```kotlin
   val port = config.port ?: DEFAULT_PORT
   val id = lookup(key)
       ?: error("no entry for $key")    // intentional, message-carrying failure
   ```
4. **`requireNotNull` / `checkNotNull`** at a boundary to convert "should never
   be null here" into a documented, message-carrying check:
   ```kotlin
   val token = requireNotNull(headers["Authorization"]) {
       "request reached handler without an auth token"
   }
   // `token` is smart-cast to non-null below.
   ```
5. **Smart casts** — once you've checked, the compiler narrows the type; use it:
   ```kotlin
   if (node == null) return
   // node is smart-cast to non-null from here.
   process(node.children)
   ```
   A **mutable property (`var`) cannot be smart-cast** — it could change between
   the check and the use — so bind a local `val` first and let the smart cast
   hold on that:
   ```kotlin
   val repo = repository ?: return   // local val; smart-cast below
   repo.findById(id)
   ```

The difference between `requireNotNull(x) { "..." }` and `x!!` is that the
former documents the invariant and produces a diagnosable message; the latter
produces a bare `NPE` with no context. Always choose the former.

**`T?` means "absent," never "errored."** Null cannot carry a reason, so don't
use a nullable return to signal *why* an operation failed — model that with a
`sealed` result or an exception (§10). Reserve `?` for a value that may
legitimately not exist, not for a failure.

### Initialize instead of nulling

Prefer a real initial value, `lateinit` for genuinely-deferred non-null deps
(DI/test setup), or a lazy property — over a `var x: T? = null` you later
assert:

```kotlin
private val cache: MutableMap<String, Entry> = mutableMapOf()   // not null + later
private val parser by lazy { Parser(config) }                   // computed once, non-null
@Inject lateinit var repository: UserRepository                 // set once by DI, non-null
```

`lateinit` is non-null and set-once: it throws a clear error if accessed before
assignment — the correct loud failure, not a silent null. It can't be used with
primitive types (`Int`, `Boolean`, ...) or with `val`; use a default or `by
lazy` there.

---

## 7. Prefer `when` over `if`/`else` chains

`when` is the default branching construct. Use it instead of an `if`/`else if`
ladder whenever you branch three or more ways, match on a value, or branch on a
type.

### `when` as an expression

A `when` used as an expression must be exhaustive, so the compiler forces you to
handle every case — this is where it earns its keep.

```kotlin
// Good: exhaustive, expression-bodied, no else needed.
fun describe(term: LineTerminator): String = when (term) {
    is LineTerminator.Byte -> "byte 0x${term.value.toString(16)}"
    LineTerminator.CrLf    -> "CRLF"
}

// Bad: if/else ladder, easy to forget a case, no exhaustiveness check.
fun describe(term: LineTerminator): String {
    if (term is LineTerminator.Byte) return "byte ..."
    else if (term == LineTerminator.CrLf) return "CRLF"
    else throw IllegalStateException()   // unreachable noise
}
```

### Exhaustiveness over `else`

For a sealed hierarchy or enum, **omit `else`** and enumerate every branch. Then
when someone adds a variant, the compiler flags every `when` that needs
updating. An `else -> throw ...` silently swallows that signal — avoid it on
closed sets. Reserve `else` for genuinely open domains (arbitrary `Int`,
`String`).

### `when` with no subject for conditions

Use subjectless `when` to replace an `if`/`else if` chain of unrelated
conditions:

```kotlin
val category = when {
    score >= 90 -> Grade.A
    score >= 80 -> Grade.B
    score >= 70 -> Grade.C
    else        -> Grade.F
}
```

Keep a plain `if` only for a single binary branch, and prefer it as an
expression (`val x = if (cond) a else b`) over a statement that assigns in both
arms. Kotlin has no ternary operator — `if`-as-expression is it.

---

## 8. Immutability & Collections

Immutability is the default; mutability is a local, justified exception.

- **`val` over `var`, always, unless reassignment is genuinely required.** A
  `var` is a small claim that the value changes over time — make the reader
  believe it. Most locals and nearly all properties are `val`.
- **Read-only collection types in signatures.** Expose `List`, `Map`, `Set`
  (read-only interfaces), not `MutableList`/`ArrayList`. Build with a mutable
  local and return the read-only view, or use `buildList { }`:

  ```kotlin
  fun parseRules(lines: List<String>): List<Rule> = buildList {
      for (line in lines) {
          parseRule(line)?.let(::add)
      }
  }
  ```

- **Keep mutable state private and narrow.** A mutable collection is an
  implementation detail; never return it where a caller could mutate your
  internals. Expose `Map<K, V>`, back it with a private `MutableMap<K, V>`.
- **Prefer transformation over mutation.** `map`/`filter`/`associateBy`/`fold`
  produce new collections; reach for them before a manual loop that mutates an
  accumulator. Use a `for` loop when you need early `break`/`continue` or the
  body has side effects.

---

## 9. Functions, Expressions & Scope Functions

### Expression bodies for single-expression functions

```kotlin
fun isMatch(haystack: ByteArray): Boolean = findAt(haystack, 0) != null
```

Prefer an expression body (`= ...`) over a block body with a single `return`.
Let the return type be inferred for `private`/`internal` functions; **state it
explicitly on public API** for readability and binary stability.

### Default arguments over overloads

Kotlin has default and named arguments — use them instead of telescoping
overloads:

```kotlin
fun search(
    haystack: ByteArray,
    startAt: Int = 0,
    invertMatch: Boolean = false,
): Result
```

Call with named args at the site for clarity: `search(data, invertMatch = true)`.

### Extension functions to add behavior without inheritance

Add domain operations to existing types as extensions, scoped `internal`/
`private` when they're not API:

```kotlin
internal fun ByteArray.sliceOf(match: Match): ByteArray =
    copyOfRange(match.start, match.end)
```

### Scope functions — pick the right one, don't nest them

Use `let`/`run`/`apply`/`also`/`with` deliberately:

- **`?.let { }`** — run a block only when a nullable is present (§6).
- **`apply { }`** — configure a freshly-built object, return it: `Foo().apply { bar = 1 }`.
- **`also { }`** — a side effect (logging, validation) that returns the receiver unchanged.
- **`run { }` / `with(x) { }`** — compute a result from a receiver's members.

Avoid deeply nested or chained scope functions — if a `let` inside an `apply`
inside a `run` appears, extract a named function instead. Readability beats
cleverness.

---

## 10. Error Handling

### Exceptions for truly exceptional, `sealed` results for expected outcomes

- **Throw for programmer errors and unrecoverable conditions.** Validate
  preconditions with `require` (caller's fault → `IllegalArgumentException`) and
  invariants with `check` (our fault → `IllegalStateException`), each with a
  message that names the offending value:

  ```kotlin
  fun connect(config: Config) {
      require(config.port in 1..65535) { "port out of range: ${config.port}" }
      check(state == State.READY) { "connect() called while $state" }
  }
  ```

- **Model expected, recoverable outcomes as data**, not exceptions. A parse that
  can fail, a lookup that can miss, a validation that can reject — return a
  `sealed` result the caller must handle via exhaustive `when`:

  ```kotlin
  sealed interface ParseResult {
      data class Ok(val rule: Rule) : ParseResult
      data class Invalid(val line: Int, val reason: String) : ParseResult
  }
  ```

  This puts the failure in the type system (the caller cannot forget it) instead
  of relying on documentation and `catch`.

### `Result<T>` and nullable returns at boundaries

- A nullable return (`fun find(key: K): V?`) is the right shape for a simple
  "found / not found". Don't wrap that in an exception or a `Result`.
- Use `runCatching` / `Result<T>` to bridge a throwing API into a value at a
  boundary, then fold it — but don't let `Result` leak deep into domain logic
  where a `sealed` type models the outcomes more precisely.

  ```kotlin
  val outcome = runCatching { client.fetch(url) }
      .map(::parse)
      .getOrElse { return Failure(it.toDiagnostic()) }
  ```

### Catch narrowly; never swallow

- **Catch the most specific exception you can handle**, and handle it — convert,
  retry, or log-and-continue with a real decision. Never `catch (e: Exception)`
  to silence it.
- **Never catch and discard.** An empty `catch` block, or one that logs nothing,
  hides the very information needed to diagnose the failure.
- **Don't catch `CancellationException`** in coroutine code (or rethrow it
  immediately if you catch broadly) — swallowing it breaks structured
  concurrency cancellation (§11).

---

## 11. Coroutines & Concurrency

Concurrency in Kotlin is **structured**: every coroutine has a parent scope, and
the scope doesn't complete until its children do. Honor that structure.

- **Never `GlobalScope`.** It detaches a coroutine from all lifecycle and
  cancellation. Launch into a real `CoroutineScope` tied to a lifecycle, or use
  `coroutineScope { }` / `supervisorScope { }` to bound concurrent work.

  ```kotlin
  suspend fun fetchAll(urls: List<String>): List<Page> = coroutineScope {
      urls.map { url -> async { fetch(url) } }.awaitAll()
  }
  ```

- **`suspend` functions must be main-safe.** A `suspend` function should be
  callable from any dispatcher without blocking it. Wrap blocking I/O or CPU work
  in `withContext(Dispatchers.IO)` / `Dispatchers.Default` *inside* the function,
  rather than forcing callers to remember.
- **Inject the dispatcher**, don't hard-code it — so tests can substitute a test
  dispatcher: `class Repo(private val io: CoroutineDispatcher = Dispatchers.IO)`.
- **Propagate cancellation.** Don't swallow `CancellationException`; check
  `isActive` / call `ensureActive()` in long loops; prefer cancellable
  suspending calls (`delay`) over blocking sleeps.
- **Prefer `Flow` for streams** of values; keep flows cold and collect them in a
  structured scope. Use `StateFlow`/`SharedFlow` for hot state, and confine
  mutable shared state behind a `Mutex` or a single-owner coroutine rather than
  sharing it across threads.

---

## 12. Tests

- **Framework: JUnit 5 + AssertJ** (or Kotest if the project uses it). Assert
  with AssertJ's fluent, descriptive assertions:

  ```kotlin
  assertThat(result.matches).hasSize(2)
  assertThat(result.first().start).isEqualTo(4)
  assertThatThrownBy { Match(5, 2) }
      .isInstanceOf(IllegalArgumentException::class.java)
      .hasMessageContaining("must be <= end")
  ```

- **Name tests after behavior**, using backtick method names for readability:

  ```kotlin
  @Test
  fun `offset shifts both ends and rejects overflow`() { /* ... */ }
  ```

- **Structure each test arrange → act → assert.** Extract terse helpers/builders
  so the test reads as the case, not the setup:

  ```kotlin
  private fun matcher(pattern: String) = RegexMatcher(Regex(pattern))
  private fun m(start: Int, end: Int) = Match(start, end)
  ```

- **Test behavior through public APIs**, not private internals. Use real objects
  for collaborators you own; mock only at architectural boundaries (network,
  clock, filesystem). Prefer **TestContainers** over mocks for real
  infrastructure (databases, brokers) where the project does.
- **Keep tests deterministic and isolated.** Inject the clock and the dispatcher;
  never depend on wall-clock timing or test ordering. For coroutines, use
  `runTest` and a `TestDispatcher` so virtual time is controlled.

---

## 13. Observability

Observability is a first-class diagnostic tool, not an afterthought — weak
observability costs project velocity (a can't-reproduce-in-CI bug is unblocked
by *adding logging and reading what the system actually saw*, never by blind
fixes). Log, meter, and trace so a failure is diagnosable from the telemetry
alone. The `observability-reviewer` lens checks new code against these rules.

### Logging: a real logger, never `println`

- Use a structured logger (`kotlin-logging`/`KotlinLogging`, or SLF4J directly),
  **never `println`/`print`** on a production path — they bypass levels,
  structured context, and any export pipeline. Route **test** diagnostics
  through the logger too, not `println`.

  ```kotlin
  private val log = KotlinLogging.logger {}
  ```

- **Use lazy lambda logging** so message construction is skipped when the level
  is disabled: `log.debug { "resolved $count rules for $tenant" }`.
- **When/what/level:**
  - `error` — an operation failed and is surfaced to the caller; an invariant broke.
  - `warn` — a recoverable anomaly, a fallback taken, a retryable failure.
  - `info` — significant lifecycle events (startup, config resolved, tenant provisioned).
  - `debug`/`trace` — per-request / hot-path detail, off by default in production.
- **Log the diagnostic artifact on error, not just the message.** Capture the
  *thing you'd need to reproduce it* — the offending value, the live state, the
  rejected input — not merely `e.message`. Pass the exception as the cause so the
  stack trace is preserved: `log.error(e) { "drop failed for collection=$id" }`.
- **Structured context over interpolation** where the backend supports it (MDC /
  key-value): put `collectionId`, `tenant`, `op` in context so logs are
  queryable, not buried in a formatted string.

### Metrics: low-cardinality attributes only

- Add counters/timers on **new and hot paths** (request counts, batch sizes,
  backend latency) via the project's meter (Micrometer/OTel).
- **Metric tag keys MUST be low-cardinality** — `method`/`outcome`/`op`/`table`,
  not unbounded values. **Ids (entity/tenant/txn ids, collection names) go on
  spans, never on metric tags** — a high-cardinality tag explodes the
  time-series and is a defect.

### Tracing / spans

- Cover request and write paths with spans; attach the **useful fields** (ids,
  tenant, collection, op) to the span — this is where high-cardinality context
  belongs.
- **Propagate** context across coroutine and service boundaries (W3C
  traceparent) so a trace stays connected end-to-end; coroutine context
  elements carry the active span across `suspend` calls.

---

## Quick Checklist

When writing or reviewing Kotlin in this style, confirm:

- [ ] Formatted with `ktlint` (official style), trailing commas, no semicolons.
- [ ] Public API has KDoc in active voice; checked preconditions documented.
- [ ] Values are immutable `data class`/`value class`; invariants enforced in `init`.
- [ ] Closed variant sets are `sealed`; fixed constants are `enum`.
- [ ] **Every `?` is intentional** — it survives the decision procedure (not deferred init, empty collection, optional param, or a domain state better modeled `sealed`) — and legitimate nullables (find-one lookups, optional external fields, Java interop) are *not* over-corrected into `Optional`/throws.
- [ ] **No `!!` anywhere** — use `?.`, `?:`, `requireNotNull`/`checkNotNull` with a message, smart casts (local `val` for a `var`), or a redesign. `T?` means absent, never errored.
- [ ] **`when` (exhaustive, no `else` on sealed/enum) replaces `if`/`else if` ladders.**
- [ ] `val` over `var`; read-only collection types in signatures; mutable state private.
- [ ] Expression bodies, default/named args, extension functions; scope functions chosen deliberately, not nested.
- [ ] `require`/`check` for programmer errors; `sealed` results for expected outcomes; catches are narrow and never swallow.
- [ ] Structured concurrency: no `GlobalScope`; `suspend` is main-safe; dispatcher injected; cancellation propagated.
- [ ] Tests: JUnit5 + AssertJ, behavioral backtick names, arrange/act/assert, deterministic (injected clock/dispatcher, `runTest`).
- [ ] Observability: a logger not `println`; error paths log the diagnostic artifact + cause; metric tags low-cardinality (ids on spans); hot paths spanned with propagated context.
