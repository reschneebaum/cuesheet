# Records

## What it is

An anonymous, immutable, structurally-typed group of values. Fields can be
positional, named, or both, and the type is written inline:

```dart
({String verb, String? detail}) describe() => (verb: 'Move to end', detail: null);

final d = describe();
print(d.verb);

// Destructuring, including in a pattern:
final (verb: v, detail: _) = describe();
```

Records get `==`, `hashCode`, and `toString` for free, structurally — no
declaration required.

## Closest Swift/iOS analogue

Swift tuples, including labelled ones:

```swift
func describe() -> (verb: String, detail: String?) { ... }
```

Same use: return two things without inventing a type for them.

## Where the analogy breaks down

**They are `Equatable` for free, which Swift tuples are not.** Two records with
equal fields are `==`, and they work as `Map` keys and `Set` members. Swift
tuples cannot conform to protocols at all, so they are not `Equatable`,
`Hashable`, or usable as dictionary keys. This is the biggest practical
difference and it makes Dart records useful in places Swift tuples cannot go.

**Named and positional fields are different fields.** `(1, 2)` and
`(a: 1, b: 2)` are unrelated types. Positional fields are accessed as `$1`,
`$2` — one-based, and easy to misread as string interpolation.

**Structural typing, so no name to hang documentation on.** Any
`({String verb, String? detail})` is interchangeable with any other, which is
the convenience and also the cost — there is nowhere to write down what the
fields mean. That is the line for reaching for a real class instead.

**No mutation, no `copyWith`.** Build a new one.

## Minimal example

```dart
(int, int) divmod(int a, int b) => (a ~/ b, a % b);

final (q, r) = divmod(17, 5);   // 3, 2
print(divmod(17, 5) == (3, 2)); // true — structural equality
```

## Where it's used here

- `packages/cuesheet_domain/lib/src/preview_intent.dart` — `_describe` returns
  `({String verb, String? detail})`. Two strings for one statement; naming a
  type would have been ceremony.
- `packages/cuesheet_domain/lib/src/sort_spec.dart` — `_Ordering` is a
  `typedef` for a record, carrying a comparison result plus whether it came
  from a null-ordering decision (which must survive the descending flip).
