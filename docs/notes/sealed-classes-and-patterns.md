# Sealed classes, exhaustive switch, and destructuring patterns

## What it is

`sealed class Foo` declares a class that can only be extended within the same
library. Because the compiler knows the complete set of subtypes, a `switch`
over a `Foo` is checked for exhaustiveness: miss a case and it fails to
compile.

Dart 3 patterns then let a `case` both test the runtime type and pull fields
out in one step:

```dart
case PlayJustThis(:final episode):   // matches the type, binds `episode`
```

`switch` also exists as an *expression*, which returns a value:

```dart
final items = switch (order) {
  TraversalOrder.ascending  => visibleList.sublist(start),
  TraversalOrder.descending => visibleList.sublist(0, start + 1).reversed.toList(),
};
```

## Closest Swift/iOS analogue

A Swift `enum` with associated values, matched with `switch` and `case let`:

```swift
enum PlaybackIntent {
    case playJustThis(EpisodeID)
    case playFromHere(EpisodeID, TraversalOrder)
}

switch intent {
case .playJustThis(let episode): …
}
```

Same guarantee, same reason to want it: a closed set of cases, exhaustively
handled, so adding a case breaks every site that must learn about it.

## Where the analogy breaks down

**They are classes, not enum cases.** Each variant is a real class with its own
fields, methods, and possible further subtypes. `PlayFromHere` could gain a
method; a Swift enum case cannot. This also means variants can share behaviour
through the base class, which a Swift enum can only fake with a computed
property and a `switch`.

**Exhaustiveness comes from the library boundary, not the declaration.** Swift's
enum is closed because it is an enum. Dart's is closed because `sealed` forbids
subtypes outside the declaring library. Move `ReorderQueue` into another file
in the same package and it still compiles — same library. Move it into another
*package* and the seal breaks.

**A non-exhaustive switch statement is not always an error.** `switch` used as
an *expression* must be exhaustive. A `switch` *statement* over a sealed type is
also checked — but a statement over a non-sealed type is not, and quietly falls
through. The safety is a property of the sealed type, not of `switch` itself.

**`:final episode` is object destructuring, not case matching.** It calls the
`episode` getter on the matched object. It works on any class with that getter,
sealed or not — which is more general than Swift's `case let`, and slightly
more dangerous, because the property being read is not necessarily part of a
declared variant shape.

**No `where`-less binding shorthand.** Swift's `if case let` has no direct
equivalent; Dart uses `if (x case Pattern(...))`, which reads backwards at
first:

```dart
if (current.source case Detached(episode: final playing)) { … }
```

## Minimal example

```dart
sealed class Shape {}
final class Circle extends Shape { Circle(this.r); final double r; }
final class Square extends Shape { Square(this.side); final double side; }

double area(Shape s) => switch (s) {
      Circle(:final r) => 3.14159 * r * r,
      Square(:final side) => side * side,
    };
// Add `final class Triangle extends Shape {}` and `area` stops compiling.
```

## Where it's used here

- `packages/cuesheet_domain/lib/src/playback_intent.dart:15` — the sealed
  `PlaybackIntent` hierarchy, the closed set the whole app is built around.
- `packages/cuesheet_domain/lib/src/apply_intent.dart:52` — the exhaustive
  `switch` that is the only thing allowed to produce a new `QueueState`.
  Adding an intent breaks this function, by design.
- `packages/cuesheet_domain/lib/src/apply_intent.dart:76` — `switch` as an
  expression over `TraversalOrder`.
- `packages/cuesheet_domain/lib/src/queue_state.dart:72` — pattern matching
  over `PlaybackSource` including the `null` case, which is a real pattern in
  Dart rather than a separate check.
