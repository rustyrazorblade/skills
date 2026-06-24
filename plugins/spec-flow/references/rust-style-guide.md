# Rust Style Guide

A guide for writing idiomatic, high-performance Rust. Each rule is stated
imperatively and backed by a concrete, self-contained example. When in doubt,
prefer the pattern shown here over a more general one.

The overarching philosophy: **each component solves exactly one problem well.**
No defensive over-engineering, no speculative abstraction. Clarity comes from
documentation and ruthless consistency; performance comes from zero-cost
abstractions (newtypes, monomorphized generics, enum dispatch) rather than
runtime machinery.

---

## 1. Formatting

Use `rustfmt` with a strict, project-wide config:

```toml
max_width = 79
use_small_heuristics = "max"
edition = "2024"
```

Rules:

- **79-column limit.** Code should be readable in a narrow terminal pane and in
  side-by-side diffs. This is the single most visible constraint — it forces
  signatures, builder chains, and match arms onto multiple lines.
- **Never hand-format.** Let `rustfmt` decide. Write code, run the formatter,
  commit the result. Do not fight it.
- **Let long signatures wrap.** A function with several parameters becomes one
  parameter per line, with the `where` clause on its own lines:

  ```rust
  fn interpolate<F>(
      &self,
      name_to_index: F,
      haystack: &[u8],
      replacement: &[u8],
      dst: &mut Vec<u8>,
  ) where
      F: FnMut(&str) -> Option<usize>,
  ```

- **Stack builder/method chains vertically** when they exceed the width:

  ```rust
  builder
      .line_terminator(self.line_term.as_byte())
      .binary_detection(self.binary.0);
  ```

---

## 2. Naming

| Item | Convention | Example |
|------|------------|---------|
| Types (struct/enum/trait) | `PascalCase` | `Match`, `Matcher`, `BinaryDetection` |
| Functions / methods | `snake_case` | `find_at`, `is_match`, `max_context` |
| Variables / fields | `snake_case` | `last_end`, `line_term` |
| Constants / statics | `SCREAMING_SNAKE_CASE` | `MAX_LOOK_AHEAD` |
| Lifetimes | single lowercase letter | `'a` |
| Generic params | single uppercase letter | `P`, `M`, `S`, `F` |

Conventions:

- **Builders are named `<Type>Builder`** and produce `<Type>` from `build()`:
  `SearcherBuilder` → `Searcher`, `MatcherBuilder` → `Matcher`.
- **Predicates start with `is_`/`has_`** and return `bool`: `is_partial()`,
  `is_io()`, `is_suffix()`.
- **Constructors are `new()`**, with named variants for alternatives:
  `Match::new()`, `Match::zero()`, `LineTerminator::byte()`,
  `LineTerminator::crlf()`.
- **Generic parameter letters are semantic by convention:** `M: Matcher`,
  `S: Sink`, `P: AsRef<Path>`, `F: FnMut(...)`. Use them consistently.

---

## 3. Documentation & Comments

Documentation is mandatory, not optional. Enable enforcement at the crate root:

```rust
#![deny(missing_docs)]
```

- **Module docs (`//!` or `/*! ... */`)** open every crate's `lib.rs`. Write
  rich markdown: explain the crate's purpose, design rationale, and include a
  runnable example. Use headings (`# Brief overview`, `# Example`) for longer
  modules.
- **Item docs (`///`)** on every public item, in **present-tense, active
  voice** describing behavior: `/// Create a new match.`,
  `/// The full path that this entry represents.`
- **Use doc sections** where relevant:
  - `# Examples` with a triple-backtick code block that compiles (doctests).
  - `# Panics` whenever a function can panic:

    ```rust
    /// # Panics
    ///
    /// This panics if adding the given amount to either the start or end
    /// offset would result in an overflow.
    pub fn offset(&self, amount: usize) -> Match { /* ... */ }
    ```
- **Inline comments (`//`) explain *why*, never *what*.** Reserve them for
  non-obvious logic, edge cases, and invariants:

  ```rust
  // This is an empty match. To ensure we make progress, start the next
  // search at the smallest possible starting position of the next match.
  last_end = m.end + 1;
  ```
- **Tone is professional and complete-sentence.** Never terse to the point of
  ambiguity, never chatty.

---

## 4. Module & Crate Organization

### Crate layout

Decompose by *responsibility*, sliced vertically, with dependencies flowing
**downward only**. For a multi-crate workspace, define a low-level interface
crate, implement it in sibling crates, and layer higher-level crates on top:

```
interface  →  defines the core trait(s). No internal deps.
impl-a     →  implements the interface.   ┐ depend on interface
impl-b     →  implements the interface.   ┘
engine     →  orchestration built on the interface.
output     →  formats and writes results. (interface + engine)
facade     →  thin crate re-exporting the public API.
app        →  the binary; wires everything together.
```

This enables swappable implementations (anything implementing the interface
trait), independent evolution (the output layer changes without touching the
engine), and reusable components. Apply the same principle within a single crate
using modules instead of crates.

### `lib.rs` structure

1. Module-level doc comment.
2. `#![deny(missing_docs)]` and other crate attributes.
3. Grouped public re-exports via `pub use`.
4. `mod` declarations (private by default).

```rust
/*! Module documentation ... */
#![deny(missing_docs)]

pub use crate::{
    lines::{LineIter, LineStep},
    searcher::{
        BinaryDetection, ConfigError, Encoding, MmapChoice, Searcher,
        SearcherBuilder,
    },
    sink::{Sink, SinkContext, SinkMatch},
};

mod lines;
mod searcher;
mod sink;
```

### File organization

- Give each major type/concept its own file (`sink.rs`, `lines.rs`).
- A complex type gets a directory module: `searcher/mod.rs` for the public type
  plus `searcher/core.rs`, `searcher/glue.rs`, `searcher/mmap.rs` for private
  internals.

### Visibility

- `pub` — the crate's public API.
- `pub(crate)` — internal helpers shared across modules. Prefer over
  `pub(super)`.
- (no modifier) — private, the default. Most items.
- **`pub` struct with private fields** is a deliberate pattern: the type is
  documented and namable, but only its builder/constructors can create it (see
  §6 `Config`).

---

## 5. Types: structs, enums, impls

### Derive order

Use a consistent alphabetical-ish order:
`#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]`. Add `Default` where a
sensible zero value exists. Feature-gate optional derives with `cfg_attr`:

```rust
#[derive(Clone, Eq)]
#[cfg_attr(feature = "arbitrary", derive(arbitrary::Arbitrary))]
pub struct Glob { /* ... */ }
```

### Struct layout

Doc comment → derives → declaration → fields (each public field documented).

```rust
/// The type of a match.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct Match {
    start: usize,
    end: usize,
}
```

### Impl block ordering

Group methods by role, and put **each trait impl in its own block**:

1. Constructors (`new`, named variants).
2. Accessors / getters.
3. Mutators / builder-style methods.
4. Complex behavior.
5. Trait impls — one `impl Trait for Type` block each (`Index`, `Display`,
   `FromStr`, ... never merged).

### Enums

- Use struct-like variants when a variant carries named context; tuple variants
  for one or two unnamed values.
- Mark public error/extensible enums `#[non_exhaustive]` so variants can be
  added without a breaking change.
- Document every variant.

```rust
#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum ErrorKind {
    /// Occurs when a character class is not closed, e.g., `[abc`.
    UnclosedClass,
    /// Occurs when a range is invalid, e.g., `[z-a]`.
    InvalidRange(char, char),
}
```

---

## 6. The Builder Pattern (the dominant composition tool)

Every type that needs more than trivial configuration gets a builder. Builders
**separate configuration from execution** — this is the central architectural
principle.

### Anatomy

1. A `Builder` struct that wraps a private `Config` struct.
2. A `Config` with **private fields** and a `Default` impl holding all defaults.
3. Setter methods that take `&mut self`, mutate one config field, and return
   `&mut Self` for chaining.
4. **No validation in setters** — validate once, in `build()`.
5. `build()` clones/freezes the config into an immutable working type.

```rust
#[derive(Clone, Debug)]
pub struct SearcherBuilder {
    config: Config,
}

impl SearcherBuilder {
    pub fn new() -> SearcherBuilder {
        SearcherBuilder { config: Config::default() }
    }

    pub fn build(&self) -> Searcher {
        let mut config = self.config.clone();
        // ... validation / derived setup happens here, once ...
        Searcher { config, /* runtime state */ }
    }

    pub fn after_context(&mut self, n: usize) -> &mut SearcherBuilder {
        self.config.after_context = n;
        self
    }

    pub fn invert_match(&mut self, yes: bool) -> &mut SearcherBuilder {
        self.config.invert_match = yes;
        self
    }
}

impl Default for SearcherBuilder {
    fn default() -> SearcherBuilder { SearcherBuilder::new() }
}
```

The internal `Config` is `pub` (for docs) but every field is private and only
the builder writes to it:

```rust
/// The internal configuration of a searcher. Only ever written to by the
/// SearcherBuilder.
#[derive(Clone, Debug)]
pub struct Config {
    line_term: LineTerminator,
    invert_match: bool,
    after_context: usize,
    // ...
}
```

### Conventions

- **Boolean setters take `yes: bool`** (not a bare flag): `hidden(yes)`,
  `multi_line(yes)`. This makes call sites self-documenting and toggleable.
- **A builder may have multiple `build*` targets** when it produces related
  types: e.g. `build()` → sequential walker, `build_parallel()` → parallel
  walker; `build()` → colored output, `build_no_color()` → plain.
- **Compose builders inside builders.** A higher-level builder can own a
  lower-level one and forward to it; convenience methods bundle several
  settings:

  ```rust
  pub fn standard_filters(&mut self, yes: bool) -> &mut WalkBuilder {
      self.hidden(yes)
          .parents(yes)
          .ignore(yes)
          .git_ignore(yes)
          .git_global(yes)
          .git_exclude(yes)
  }
  ```
- **Required construction args go in `new()`**; values needed only at build time
  go on `build()` (e.g. `WalkBuilder::new(path)`, but `build(pattern)` takes the
  pattern when building).

The payoff: a configured working type is reusable across many operations,
configuration logic never clutters execution, and the working type is
effectively immutable.

---

## 7. Trait Design (abstraction boundaries)

Traits are the primary abstraction mechanism — use them where you'd reach for
inheritance in another language.

### Keep required methods minimal; build with defaults

Define the smallest set of primitive methods as required, then layer rich
convenience methods as **default methods** on top of them. For example, a
`Matcher` trait might require only `find_at` and `new_captures`, and express
everything else (`find`, `find_iter`, `captures_iter`, `replace`, ...) as
default methods in terms of those primitives.

```rust
pub trait Matcher {
    type Captures: Captures;
    type Error: std::fmt::Display;

    // Required primitives:
    fn find_at(
        &self,
        haystack: &[u8],
        at: usize,
    ) -> Result<Option<Match>, Self::Error>;

    fn new_captures(&self) -> Result<Self::Captures, Self::Error>;

    // Default method built on the primitive:
    fn find_iter<F>(
        &self,
        haystack: &[u8],
        matched: F,
    ) -> Result<(), Self::Error>
    where
        F: FnMut(Match) -> bool,
    {
        self.find_iter_at(haystack, 0, matched)
    }
}
```

Implementors get a large, correct API for free and can override hot paths.

### Use associated types for per-impl concrete types

When each implementation needs its *own* error or output type, use associated
types (not generics, not boxing): `type Captures` and `type Error`. This lets a
simple implementation pick zero-cost types (e.g. an empty `NoCaptures`, an
uninhabited-style `NoError`) while a richer one picks real ones — with no vtable
and no allocation.

### Provide default methods with `#[inline]`

Mark small trait methods and forwarding methods `#[inline]` so monomorphization
can erase the abstraction entirely.

### Implement traits for references and boxes

So callers can pass `&M`, `&mut S`, or `Box<S>` wherever the trait is expected,
add forwarding impls:

```rust
impl<'a, M: Matcher> Matcher for &'a M {
    type Captures = M::Captures;
    type Error = M::Error;
    fn find_at(&self, h: &[u8], at: usize)
        -> Result<Option<Match>, Self::Error>
    { (*self).find_at(h, at) }
}

impl<S: Sink + ?Sized> Sink for Box<S> { /* forwards to (**self) */ }
```

This makes dynamic dispatch *opt-in* (`Box<dyn ...>`) without penalizing the
common static case.

### Offer closure-based facade impls

Wrap the trait around a closure for ergonomic call sites. For example, a newtype
over an `FnMut(u64, &str) -> Result<bool, io::Error>` can implement a `Sink`
trait, so users write `|lnum, line| { ... }` instead of a full `impl Sink`:

```rust
pub struct UTF8<F>(pub F)
where
    F: FnMut(u64, &str) -> Result<bool, io::Error>;

impl<F> Sink for UTF8<F>
where
    F: FnMut(u64, &str) -> Result<bool, io::Error>,
{
    type Error = io::Error;
    fn matched(&mut self, _: &Searcher, mat: &SinkMatch<'_>)
        -> Result<bool, io::Error>
    { /* decode, then call (self.0)(line_number, line) */ }
}
```

---

## 8. Generics vs. Trait Objects

- **Default to generics with trait bounds** (`M: Matcher`, `S: Sink`).
  Monomorphization gives full inlining and no vtable cost, and associated types
  (`Self::Error`) only work cleanly through generics.

  ```rust
  pub fn search_path<P, M, S>(&mut self, matcher: M, path: P, write_to: S)
      -> Result<(), S::Error>
  where P: AsRef<Path>, M: Matcher, S: Sink { /* ... */ }
  ```

- **Reach for trait objects (`Box<dyn Trait>`) only when you must** store
  heterogeneous implementations together or need a stable ABI. The forwarding
  impls in §7 keep this available as an explicit choice.

- **Prefer enum dispatch over `dyn` for a closed set of variants.** When all
  implementations are known at compile time, an enum + a `match` is faster and
  keeps everything monomorphized. Select the strategy once up front, then
  dispatch with a single `match`:

  ```rust
  enum MatchStrategy {
      Literal(LiteralStrategy),
      Extension(ExtensionStrategy),
      Prefix(PrefixStrategy),
      Regex(RegexStrategy),
      // ...
  }

  impl MatchStrategy {
      fn is_match(&self, c: &Candidate<'_>) -> bool {
          match *self {
              MatchStrategy::Literal(ref s) => s.is_match(c),
              MatchStrategy::Extension(ref s) => s.is_match(c),
              MatchStrategy::Prefix(ref s) => s.is_match(c),
              MatchStrategy::Regex(ref s) => s.is_match(c),
          }
      }
  }
  ```

---

## 9. Newtypes & Zero-Cost Abstractions

Wrap raw types to add invariants, methods, and semantic meaning at no runtime
cost.

- **Enforce invariants in the constructor:**

  ```rust
  pub struct Match { start: usize, end: usize }

  impl Match {
      pub fn new(start: usize, end: usize) -> Match {
          assert!(start <= end);
          Match { start, end }
      }
  }
  ```

- **Hide the representation behind a newtype over a private enum**, exposing
  only controlled constructors and accessors:

  ```rust
  pub struct LineTerminator(LineTerminatorImp);

  enum LineTerminatorImp { Byte(u8), CRLF }

  impl LineTerminator {
      pub fn byte(byte: u8) -> LineTerminator { /* ... */ }
      pub fn crlf() -> LineTerminator { /* ... */ }
      pub fn as_bytes(&self) -> &[u8] { /* ... */ }
  }
  ```

- **Add domain operations to the wrapper**, e.g. implement
  `Index<Match> for [u8]` so a match can slice a haystack directly:
  `&haystack[m]`.

- **Use compact bitset newtypes** (e.g. `ByteSet(BitSet([u64; 4]))` = 256 bits)
  for O(1) set membership with a clean API over raw bit twiddling.

---

## 10. Error Handling

### Libraries: hand-written error types. Binaries: `anyhow`.

This split is deliberate. **Library crates should not depend on `anyhow`** —
define concrete error types with hand-written `std::error::Error` impls.
Reserve `anyhow` for the binary at the top level.

- **Library error types** give callers something precise to match on and are
  part of the stable API.
- **The binary** uses `anyhow::Result<T>` at the top level to avoid defining
  yet another error enum where it only needs to report-and-exit.

### Two library error shapes

1. **Rich enum that accumulates context** — variants wrap a `Box<Error>` to
   build error chains (path → line number → cause), so the user gets
   "line 42 in .gitignore: invalid glob":

   ```rust
   pub enum Error {
       Partial(Vec<Error>),
       WithLineNumber { line: u64, err: Box<Error> },
       WithPath { path: PathBuf, err: Box<Error> },
       WithDepth { depth: usize, err: Box<Error> },
       Io(std::io::Error),
       Glob { glob: Option<String>, err: String },
       // ...
   }
   ```

   Context is attached by *consuming* and *wrapping*, never mutating:

   ```rust
   fn with_path<P: AsRef<Path>>(self, path: P) -> Error {
       Error::WithPath { path: path.as_ref().to_path_buf(), err: Box::new(self) }
   }
   ```

   Provide predicate helpers (`is_partial()`, `is_io()`) that recurse through
   the wrappers.

2. **Opaque struct wrapping a `#[non_exhaustive]` `ErrorKind` enum** — for a
   clean API surface where construction logic should be hidden behind factory
   methods:

   ```rust
   #[derive(Clone, Debug)]
   pub struct Error { kind: ErrorKind }

   impl Error {
       pub(crate) fn new(kind: ErrorKind) -> Error { Error { kind } }
       pub fn kind(&self) -> &ErrorKind { &self.kind }
   }

   #[derive(Clone, Debug)]
   #[non_exhaustive]
   pub enum ErrorKind { Regex(String), InvalidLineTerminator(u8), /* ... */ }
   ```

### Enable `?` with `From` impls

```rust
impl From<std::io::Error> for Error {
    fn from(err: std::io::Error) -> Error { Error::Io(err) }
}
```

### The `NoError` pattern for infallible implementations

When a trait has an associated `Error` type but a given impl can never fail, use
a zero-size `NoError` whose `Display` panics — it satisfies the bound at no cost
and the panic is unreachable by construction. (Use the never type `!` once it
stabilizes.)

```rust
pub struct NoError(());
impl std::fmt::Display for NoError {
    fn fmt(&self, _: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        panic!("BUG for NoError: an impossible error occurred")
    }
}
```

### Propagate, handle, and report at the right layers

- **Propagate** with `?` throughout library internals.
- **Handle** specific cases with `match` near where the decision is local — e.g.
  treat a broken pipe as graceful termination, log other per-item errors and
  continue:

  ```rust
  let result = match searcher.search(&haystack) {
      Ok(r) => r,
      Err(err) if err.kind() == std::io::ErrorKind::BrokenPipe => break,
      Err(err) => {
          eprintln!("{}: {}", haystack.path().display(), err);
          continue;
      }
  };
  ```

- **Report** once, at `main`, formatting the whole `anyhow` chain with `{:#}`
  and choosing the process exit code. Inspect the chain with `downcast_ref` for
  special-casing:

  ```rust
  fn main() -> ExitCode {
      match run() {
          Ok(code) => code,
          Err(err) => {
              for cause in err.chain() {
                  if let Some(io) = cause.downcast_ref::<std::io::Error>() {
                      if io.kind() == std::io::ErrorKind::BrokenPipe {
                          return ExitCode::from(0);
                      }
                  }
              }
              eprintln!("{:#}", err);
              ExitCode::from(2)
          }
      }
  }
  ```

### `panic` / `unwrap` / `expect` policy

- User-facing failures **always** return `Result`; never panic on bad input.
- `unwrap()`/`expect()` are acceptable **only when an invariant guarantees
  success**, and that reasoning must be documented:

  ```rust
  /// This returns the match for index `0` ... equivalent to `get(0).unwrap()`.
  fn as_match(&self) -> Match { self.get(0).unwrap() }
  ```

- Use checked arithmetic for values that *could* overflow, treating overflow as
  a programming bug and documenting it with a `# Panics` section:

  ```rust
  Match {
      start: self.start.checked_add(amount).unwrap(),
      end: self.end.checked_add(amount).unwrap(),
  }
  ```

---

## 11. Functional Patterns & Composition

### Internal vs. external iteration

- **Use internal iteration (callbacks) when the producer needs control** over
  the loop — empty-match handling, error short-circuiting, progress invariants.
  Push values into an `FnMut(T) -> bool` (return `false` to stop) rather than
  returning an `Iterator` when converting the internal loop to an external
  iterator would cost performance or ergonomics:

  ```rust
  fn find_iter<F>(&self, haystack: &[u8], matched: F)
      -> Result<(), Self::Error>
  where F: FnMut(Match) -> bool;
  ```

- **Use external iteration (`for`) when the caller drives the loop** and needs
  to `break`/`continue` on its own conditions.

### Closures as the unit of behavior

- Accept `FnMut(...)` for callbacks that mutate captured state.
- Provide a **fallible variant** that returns `Result<bool, E>` so callers can
  abort with their own error, threaded back out through a nested `Result`:

  ```rust
  fn try_find_iter<F, E>(&self, haystack: &[u8], matched: F)
      -> Result<Result<(), E>, Self::Error>
  where F: FnMut(Match) -> Result<bool, E>;
  ```

### Combinators vs. `match`

- **Combinators for simple, linear transforms:** `map`, `map_or`, `and_then`,
  `unwrap_or`.

  ```rust
  slice.last().map_or(false, |&b| b == self.as_byte())
  Ok(self.find_at(haystack, at)?.map(|m| m.end))
  ```

- **`match` (or `if let ... else if let`) for multi-way branching** where each
  arm does something distinct — it stays readable where chained combinators
  would not:

  ```rust
  if let Some(lit) = pat.basename_literal() {
      MatchStrategy::BasenameLiteral(lit)
  } else if let Some(ext) = pat.ext() {
      MatchStrategy::Extension(ext)
  } else {
      MatchStrategy::Regex
  }
  ```

### Avoid allocation; favor borrowing & immutability

- **Use `Cow<'a, [u8]>`** for data that is usually borrowed but occasionally
  owned, so the common path allocates nothing:

  ```rust
  pub struct Candidate<'a> {
      path: Cow<'a, [u8]>,
      basename: Cow<'a, [u8]>,
      ext: Cow<'a, [u8]>,
  }
  ```

- **Accept `impl AsRef<...>`** (`P: AsRef<Path>`, `AsRef<str>`,
  `AsRef<[u8]>`) at API boundaries so callers pass borrowed or owned data
  without forcing a conversion.
- **Build new values instead of mutating in place** (the error-wrapping methods
  in §10 consume `self` and return a new error). Working types are immutable
  after `build()`; confine interior mutability for buffers behind `RefCell`.

---

## 12. Tests

- **Unit tests** live next to the code in a `#[cfg(test)] mod tests` block; mark
  test-only helper types `#[cfg(test)]`.
- **Integration tests** live in the crate's `tests/` directory and exercise the
  public API. Rename the binary in `Cargo.toml` when useful:

  ```toml
  [[test]]
  name = "integration"
  path = "tests/tests.rs"
  ```

- **Extract terse helpers** to keep tests focused on the case, not the setup:

  ```rust
  fn matcher(pattern: &str) -> RegexMatcher {
      RegexMatcher::new(Regex::new(pattern).unwrap())
  }
  fn m(start: usize, end: usize) -> Match { Match::new(start, end) }
  ```

- **Name tests after the behavior** (`find`, `try_find_iter`,
  `skip_bom`) and structure each as **arrange → act → assert**.
- Doctests in `///` `# Examples` blocks double as compile-checked documentation
  — keep them runnable.

---

## 13. Observability

Observability is a first-class diagnostic tool, not an afterthought — weak observability
costs project velocity (a can't-reproduce-in-CI bug is unblocked by *adding logging and
reading what the system actually saw*, never by blind fixes). Log, meter, and trace so that
a failure is diagnosable from the telemetry alone. The `observability-reviewer` lens checks
new code against these rules; the existing primitives live in `crates/server/src/telemetry.rs`
(the OTLP trace/metric/log pipeline) and `metrics.rs` (the instrument handles).

### Logging: `tracing`, never `print!`

- Use the `tracing` macros (`error!`/`warn!`/`info!`/`debug!`/`trace!`) for **all** diagnostic
  output. **Never `print!`/`println!`/`eprint!`/`eprintln!`** on a production path — they bypass
  levels, structured fields, and the OTLP export. Route **test** diagnostics through a `tracing`
  test-subscriber (e.g. `tracing_subscriber::fmt().with_test_writer()`), not `println!`.
- **When/what/level:**
  - `error!` — a request/operation failed and is surfaced to the caller; an invariant broke.
  - `warn!` — a recoverable anomaly, a fallback taken, a retryable failure.
  - `info!` — significant lifecycle events (startup, config resolved, a tenant provisioned).
  - `debug!`/`trace!` — per-request / hot-path detail, off by default in production.
- **Log the diagnostic artifact on error, not just the error string.** When a call fails,
  capture the *thing you would need to reproduce it* — the offending value, the live state
  (e.g. the actual index mapping on a search failure, the rejected document, the resolved
  collection id), not merely `error = %e`. The error string alone is rarely enough to diagnose.
- **Structured fields over interpolation.** Prefer `warn!(collection_id = %id, "drop skipped")`
  to `warn!("drop skipped for {id}")` — fields are queryable and don't bloat the message. Use
  `%` for `Display`, `?` for `Debug`.

### Metrics: low-cardinality attributes only

- Add counters/histograms on **new and hot paths** (request counts, row/batch counts, backend
  query latency) via the `metrics.rs` instrument handles.
- **Metric attribute keys MUST be low-cardinality** — `method`/`outcome`/`op`/`table`/`record`,
  not unbounded values. **Ids (entity/edge/tenant/txn ids, collection names) go on spans, never
  on metric attributes** — a high-cardinality attribute explodes the time-series and is a defect.

### Tracing / spans

- Cover request, CDC, and write paths with spans; attach the **useful fields** (ids, tenant,
  collection, op) to the span — this is where high-cardinality context belongs.
- **Propagate** context across boundaries: extract the inbound W3C context on the gRPC edge
  (`telemetry.rs`) and stamp it onto outbound work so a trace stays connected end-to-end.

---

## Quick Checklist

When writing or reviewing Rust in this style, confirm:

- [ ] Formatted with `rustfmt`, fits in 79 columns.
- [ ] `#![deny(missing_docs)]`; every public item documented in active voice.
- [ ] `# Panics` documented wherever a function can panic.
- [ ] Complex configuration goes through a `<Type>Builder` with a private
      `Config`, `&mut Self`-returning setters, and validation in `build()`.
- [ ] Abstractions are traits with minimal required methods + default methods;
      per-impl types use associated types.
- [ ] Generics + monomorphization by default; `dyn`/enum-dispatch only when
      justified.
- [ ] Newtypes enforce invariants in their constructors at zero runtime cost.
- [ ] Library errors are hand-written concrete types; the binary uses `anyhow`.
- [ ] `?` to propagate, `match` to handle locally, single report at `main`.
- [ ] `unwrap`/`expect` only on documented invariants; user input never panics.
- [ ] Borrow over allocate (`Cow`, `AsRef`); build new values over mutating.
- [ ] Tests: unit beside code, integration in `tests/`, behavioral names,
      arrange/act/assert.
- [ ] Observability: `tracing` not `print!`; error paths log the diagnostic
      artifact (not just the error string); metric attributes are
      low-cardinality (ids on spans, never on metrics); hot paths are spanned
      with useful fields + propagated context.
