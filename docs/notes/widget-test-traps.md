# Widget testing: fake time, and three ways it bites

## What it is

`testWidgets` does not run your widget in real time. It installs
`AutomatedTestWidgetsFlutterBinding`, which replaces the clock, the scheduler,
and `Timer` with fakes you drive by hand:

```dart
await tester.pumpWidget(const MyApp());     // build one frame
await tester.pump(const Duration(seconds: 1));  // advance the clock, build again
await tester.pumpAndSettle();               // pump until no frame is scheduled
```

Nothing moves unless you move it. That makes tests deterministic and
instant — and it is the source of every confusing failure below.

## Closest Swift/iOS analogue

There isn't a close one, which is the point. XCTest runs your `UIView` against
the real run loop and the real clock; you wait on expectations. Flutter's
widget tests are nearer to a SwiftUI snapshot test crossed with a manually
advanced `DispatchQueue` — the framework hands you the clock.

## Where it bites

**1. `pumpAndSettle` never settles if anything animates forever.**
It pumps until no frame is scheduled. A `CircularProgressIndicator` schedules
frames indefinitely, so any test that reaches a loading state hangs until the
ten-minute timeout, then fails with something unrelated-looking. The same is
true of a looping `AnimationController` or a `LinearProgressIndicator`.

Fixes, in order of preference: don't put an indeterminate spinner on a screen
under test; or pump a bounded number of times instead:

```dart
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
```

That drains microtasks, lets stream events land, and covers transitions,
without ever being able to hang.

**2. `pump()` with no argument does not advance the clock.**
It schedules and builds one frame at the *current* fake time. So a
`Timer(Duration.zero)` — very common in library cleanup paths — is created but
never comes due, and the test fails with:

```
A Timer is still pending even after the widget tree was disposed.
```

`await tester.pump(const Duration(milliseconds: 1))` fires it. This one costs
hours if you do not know it, because the error names the symptom and not the
cause.

**3. Teardown registered with `addTearDown` runs too late for that check.**
The binding verifies "no pending timers" at the end of the test *body*, before
any `addTearDown` callback. So cleanup that has to happen before the assertion
must be inside the body:

```dart
void appTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink()); // dispose the tree
    await tester.pump(const Duration(milliseconds: 1)); // let timers fire
  });
}
```

Disposing the tree is what cancels drift's query streams; drift then defers its
bookkeeping with a zero-duration timer; the pump-with-a-duration is what lets
that timer run. All three traps in four lines.

## A non-trap worth recording

The first hypothesis for the pending timer was that Riverpod 3 had made
providers auto-dispose by default, so the database was closing itself whenever
nothing watched it. **It has not.** Riverpod 3 unified the provider types and
made auto-dispose opt-in via `Provider(isAutoDispose: true)`; the default is
still to keep state. Worth checking the changelog before "fixing" a lifetime
problem that is not there — a stray `ref.keepAlive()` would have looked like it
helped, because the real fix landed in the same edit.

## Where it's used here

- `packages/cuesheet_app/test/debug_app_test.dart` — the `appTest` wrapper and
  the `settle` helper, both with the reasoning inline.
- `packages/cuesheet_app/lib/src/episodes_page.dart` — the loading state is
  plain text rather than a spinner, partly for trap 1 and partly because a
  debug harness does not need one.
