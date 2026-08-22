# Extension types (typed IDs with no runtime cost)

## What it is

```dart
extension type const EpisodeId(String value) {}
```

A compile-time-only wrapper. `EpisodeId` and `CuesheetId` are different types
to the analyzer, so passing one where the other is expected is an error — but
at runtime there is no wrapper object at all. An `EpisodeId` *is* a `String`
once the program is running, and a `List<EpisodeId>` costs exactly what a
`List<String>` costs.

## Closest Swift/iOS analogue

A `struct` wrapping a raw value, which is the standard Swift newtype move:

```swift
struct EpisodeID: Hashable, RawRepresentable {
    let rawValue: String
}
```

Same intent: stop `String` from being interchangeable with every other
`String` in the codebase.

## Where the analogy breaks down

**There is no object.** Swift's wrapper struct is a real value with a real
layout (usually optimised, but real). Dart's extension type is erased entirely.
This is what makes it free — and also what makes it leaky.

**Erasure means it does not survive `dynamic` or `is`.** At runtime,
`episodeId is String` is `true`, and `episodeId.runtimeType` is `String`. The
guarantee is purely static. A JSON decode returning `dynamic` will happily hand
you a `String` where an `EpisodeId` is expected, and nothing will complain
until the analyzer sees a type it can check. Swift's struct would fail at the
cast.

**Members are not inherited unless you ask.** Written as above, `EpisodeId` has
no `String` methods — no `.length`, no `.toUpperCase()`. Only `.value` and
`Object`'s members. Writing `extension type const EpisodeId(String value)
implements String {}` would expose all of `String`, which also makes it
assignable *back* to `String` and throws away most of the safety. The opaque
form is the useful one.

**Equality comes from the representation, for free.** No `Hashable`
conformance to declare, no `==` to write: `EpisodeId('a') == EpisodeId('a')` is
true, and it works as a `Map` key or `Set` member, because at runtime those
*are* two equal Strings. This is one of the rare places Dart needs less
ceremony than Swift.

**`toString()` gives you the raw value, not a wrapper description.** String
interpolation of an `EpisodeId` prints the bare id. Convenient in test output;
occasionally surprising in logs, where you might have wanted the type name.

## Minimal example

```dart
extension type const Meters(double value) {}
extension type const Feet(double value) {}

void travel(Meters d) {}

travel(Meters(5));        // fine
travel(Feet(5));          // compile error — the entire point
print(Meters(5));         // 5.0   (erased: it really is a double)
print(Meters(5) is double); // true
```

## Where it's used here

- `packages/cuesheet_domain/lib/src/ids.dart:7` — `EpisodeId`, `CuesheetId`,
  `PodcastId`, `CategoryId`. Keeping these distinct matters most in
  `applyIntent`, which juggles episode ids and cuesheet ids in the same
  expressions.
