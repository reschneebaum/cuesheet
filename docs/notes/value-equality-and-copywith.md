# Value equality, and the copyWith-null problem

## What it is

Dart gives you **nothing** for free on a class. Two instances with identical
fields are not equal unless you write `operator ==` and `hashCode` yourself,
in agreement with each other:

```dart
@override
bool operator ==(Object other) =>
    other is QueueState &&
    other.active == active &&
    other.position == position &&
    other.source == source;

@override
int get hashCode => Object.hash(active, position, source);
```

The related idiom is `copyWith`, hand-written for the same reason:

```dart
Cuesheet copyWith({List<EpisodeId>? items, ...}) =>
    Cuesheet(id: id, items: items ?? this.items, ...);
```

## Closest Swift/iOS analogue

A `struct` conforming to `Equatable` and `Hashable`. Swift synthesises both
from the stored properties; you write nothing. Value semantics — copy on
assignment, mutate a `var` copy freely — mean Swift has no need for a
`copyWith` idiom at all.

## Where the analogy breaks down

**Equality is opt-in, and easy to get subtly wrong.** Forget `hashCode` and the
class works in `==` comparisons but silently misbehaves in `Set` and as a `Map`
key. Forget to add a newly-added field to `==` and you get a class that
compares equal when it is not. Nothing warns you. This is why the codegen
package `freezed` exists, and why work's `mobile_toolbox_core` uses it — it
generates `==`, `hashCode`, `copyWith`, and `toString` from a declaration.

**Collection fields do not compare by value.** `[a, b] == [a, b]` is `false` in
Dart — `List`'s `==` is identity. Any class with a `List` field needs
`ListEquality` from `package:collection`, or its equality is wrong in a way
that looks right in most tests. Swift's `Array` is `Equatable` when its element
is, so this trap has no Swift counterpart.

**A hand-written `copyWith` cannot express "set this to null".** With
`copyWith({PlaybackSource? source})`, the body reads
`source ?? this.source` — so calling `copyWith(source: null)` means "leave it
alone", and there is no way to say "clear it". The parameter's absence and an
explicit null are indistinguishable.

That is why `applyIntent` constructs `QueueState(...)` directly instead of
using `copyWith` — clearing `source` when the queue empties is exactly the case
a hand-written `copyWith` cannot express, and mixing the two idioms in one
function would be worse than using neither.

`freezed` **does** solve this one, which is a good reason to prefer it over
hand-rolling. Its generated `copyWith` uses a private sentinel as the default
for every nullable parameter, so "absent" and "explicitly null" are genuinely
different values and `copyWith(finishedAt: null)` really does clear the field.
`markUnplayed` in `lib/src/listening.dart` relies on exactly that. See
[freezed and code generation](freezed-and-code-generation.md).

**`@immutable` is a lint, not a guarantee.** It is an annotation from
`package:meta` that asks the analyzer to complain about non-final fields. It
does not make anything actually immutable; `List.unmodifiable` in the
constructor is what does that for the items list.

## Minimal example

```dart
class P {
  P(this.x);
  final int x;
}
print(P(1) == P(1)); // false — identity

class Q {
  Q(this.x);
  final int x;
  @override bool operator ==(Object o) => o is Q && o.x == x;
  @override int get hashCode => x.hashCode;
}
print(Q(1) == Q(1)); // true

print([1, 2] == [1, 2]); // false — the one that will bite you
```

## Where it's used here

- `packages/cuesheet_domain/lib/src/queue_state.dart:85` — `QueueState`'s
  equality. Load-bearing: the undo stack compares snapshots, and
  `_withItems` decides whether an intent was a no-op by comparing the new
  state to the old one.
- `packages/cuesheet_domain/lib/src/cuesheet.dart:57` — uses
  `ListEquality<EpisodeId>` for the items list, per the trap above.
- `packages/cuesheet_domain/lib/src/apply_intent.dart:175` — the deliberate
  avoidance of `copyWith` when clearing `source`.

## Next

`Episode`, `Podcast`, `ListeningState`, and `EpisodeView` use `freezed` rather
than hand-written equality — see
[freezed and code generation](freezed-and-code-generation.md). Writing it by
hand once, here, is what makes the generated code readable rather than magic:
open `lib/src/episode.freezed.dart` and it is doing precisely what
`Cuesheet` does by hand, plus the sentinel trick above.
