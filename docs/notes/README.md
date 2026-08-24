# Teaching notes

Cuesheet doubles as a Flutter/Dart case study, written by someone whose
expertise is native iOS. These notes are the durable output of that.

They are **curated per concept, not per session.** A conversation log is long,
repetitive, and effectively write-only. A note keyed to a concept is something
you actually return to.

## The habit

Whenever work touches a Dart or Flutter construct that would not be obvious
coming from Swift/iOS, the note is written or extended **in the same commit as
the code that motivated it.** Not batched, not deferred. If the note is missing,
the commit is incomplete.

## Format

Every note follows the same five sections:

```markdown
# <construct>

## What it is
Plain description, no analogies yet.

## Closest Swift/iOS analogue
The thing you already know that this most resembles.

## Where the analogy breaks down
The most important section. An unqualified analogy is worse than none —
it produces confident wrong predictions about behaviour.

## Minimal example
Smallest runnable snippet that demonstrates the point.

## Where it's used here
Links into this repo — `packages/…/foo.dart:42` — so the note is a jumping-off
point into real code rather than an isolated snippet.
```

## Index

Grouped by theme; populated as notes are written.

### Language
- [Sealed classes, exhaustive switch, and destructuring patterns](sealed-classes-and-patterns.md)
  — Swift enums with associated values, except they are real classes and the
  seal is a library boundary.
- [Extension types](extension-types.md) — typed IDs that cost nothing at
  runtime, because at runtime they are not there.
- [Value equality, and the copyWith-null problem](value-equality-and-copywith.md)
  — why Dart needs `freezed`, and the collection-equality trap.
- [Records](records.md) — Swift tuples, except they are `Equatable` for free.
- [Strings: code units, runes, and characters](strings-and-runes.md) — the same
  three views Swift has, with the safe one and the unsafe one swapped round.

### Concurrency
- [Streams](streams-vs-combine.md) — Combine and AsyncSequence rolled into one
  type, with single-subscription as the trap.
- [Generators: `sync*` and `async*`](generators-sync-and-async.md) — writing a
  sequence as a normal loop, which Swift cannot do.
- [Futures and `async`/`await`](futures-and-async.md) — the same keywords, with
  no cancellation, no structured concurrency, and no actors underneath them.

### State management
_(nothing yet)_

### Persistence
_(nothing yet)_

### Testing
- [Widget testing: fake time, and three ways it bites](widget-test-traps.md) —
  `pumpAndSettle` vs infinite animations, `pump()` not advancing the clock, and
  teardown ordering.

### Tooling and build
- [freezed and code generation](freezed-and-code-generation.md) — `part` files,
  `build_runner`, and what the generated code actually contains.
