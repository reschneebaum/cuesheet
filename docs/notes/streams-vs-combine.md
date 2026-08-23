# Streams

## What it is

A `Stream<T>` is an asynchronous sequence of values. You get them by
subscribing:

```dart
final sub = repository.watch(query).listen((episodes) => render(episodes));
await sub.cancel();
```

Or by awaiting them one at a time:

```dart
await for (final episodes in repository.watch(query)) { ... }
```

Streams are the reactive spine of a Flutter app. Drift returns one from
`.watch()` on any query, and it re-emits whenever a table the query touched
changes — so "the list updates when the data changes" needs no explicit
invalidation anywhere.

## Closest Swift/iOS analogue

Two, and which one applies depends on the stream:

- **Combine's `Publisher`** — for streams that push whenever something happens,
  regardless of who is listening.
- **`AsyncSequence` / `AsyncStream`** — for the `await for` form, which reads
  almost identically to Swift's `for await`.

Drift's query streams are Publisher-shaped. `Stream.fromIterable` is
AsyncSequence-shaped. Dart does not distinguish them at the type level, which
is the first thing to internalise.

## Where the analogy breaks down

**Single-subscription by default, and this will bite you.** A plain Dart
`Stream` allows exactly one listener, for its whole lifetime. Subscribe twice
and you get a runtime error, not a compile error. Combine publishers are
freely subscribable and Dart's are not. The fix is a *broadcast* stream
(`.asBroadcastStream()`, or a `StreamController.broadcast()`), which then
behaves like Combine — including dropping values emitted while nobody is
listening. Drift's `.watch()` already returns a broadcast-like stream, so
repository consumers are safe; hand-rolled controllers are where this catches
people.

**No backpressure, and no `Demand`.** Combine subscribers request a specific
number of values. Dart has nothing equivalent — you can `pause()` a
subscription, and that is the whole of it. Fast producers buffer.

**Cancellation is a subscription you must actually cancel.** `listen` returns a
`StreamSubscription`, and forgetting to cancel it is the standard Dart memory
leak — the moral equivalent of not storing an `AnyCancellable`, except nothing
goes out of scope to save you. In Flutter this is what `StatefulWidget.dispose`
and Riverpod's `ref.onDispose` are for.

**Errors do not necessarily end the stream.** A Combine publisher completes
permanently on failure. A Dart stream can emit an error and keep going —
whether it does is up to the producer. So an `onError` handler is not
automatically a terminal event, and assuming otherwise leaves subscriptions
alive that you thought were finished.

**`async*` is the generator form**, close to Swift's `AsyncStream` with a
continuation but built into the language:

```dart
Stream<int> countTo(int n) async* {
  for (var i = 1; i <= n; i++) yield i;
}
```

**Transformations are methods, not operators in a chain builder.**
`.map`, `.where`, `.expand`, `.distinct`, `.asyncMap` (for an async transform
that preserves order). No `.sink(receiveValue:)`, no `.eraseToAnyPublisher()` —
`Stream<T>` is already the erased type.

## Minimal example

```dart
final controller = StreamController<int>.broadcast();
final sub = controller.stream
    .where((n) => n.isEven)
    .map((n) => n * 10)
    .listen(print);

controller.add(1);   // filtered out
controller.add(2);   // prints 20
await controller.close();
await sub.cancel();
```

## Where it's used here

- `packages/cuesheet_data/lib/src/repositories.dart` — `watch` on each
  repository returns a drift query stream, so a filtered episode list
  re-emits whenever an episode, a listening row, or a podcast changes.
  `asyncMap` is used rather than `map` because hydrating an episode view
  requires a second query, and order must be preserved.
- `packages/cuesheet_data/test/database_test.dart` — `watch re-emits when the
  underlying data changes` uses `pumpEventQueue()` to let the stream settle
  between assertions, which is the usual shape of a stream test.
