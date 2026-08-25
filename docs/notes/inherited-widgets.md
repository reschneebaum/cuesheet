# InheritedWidget

## What it is

The mechanism by which a value reaches every widget below a point in the tree
without being passed through each one. A widget subclasses `InheritedWidget`,
holds a value, and descendants read it through a static `of(context)` that calls
`context.dependOnInheritedWidgetOfExactType<T>()`.

The second thing it does is the important one: reading it **registers a
dependency**. When the inherited widget is rebuilt with a different value, every
widget that read it rebuilds too. It is a lookup and a subscription in one call.

## Closest Swift/iOS analogue

SwiftUI's `@Environment` / `.environment(…)`. Very close in spirit: a value
injected at one point in a view hierarchy, read implicitly further down, with
reads driving invalidation.

## Where the analogy breaks down

**`BuildContext` is a position, not a value.** `context` is the element's own
slot in the tree, so `of(context)` means "look upward from *here*". A context
from the wrong place finds the wrong answer — the classic case being a `context`
captured before a widget was inserted under the provider it needs. SwiftUI has
no equivalent footgun because the environment is resolved by the framework, not
by a handle you hold.

**Reading it in `initState` throws.** Dependencies cannot be registered before
the element is mounted. The workaround — `didChangeDependencies` — has no
SwiftUI counterpart, and the error message is not obviously about timing.

**Type identity is exact, not a subtype match.** `dependOnInheritedWidgetOfExactType<CuesheetTheme>()`
finds a `CuesheetTheme` and nothing else, including subclasses. Two themes of
different types nested in the same tree do not shadow each other.

**Rebuilds are on the whole value, not the field you read.** A widget that reads
one colour rebuilds when *any* field of the inherited value changes, because the
dependency is on the widget, not the property. SwiftUI's `@Environment(\.foo)`
tracks the key path. Splitting an inherited widget into several is the usual fix
and is a real design decision, not a micro-optimisation.

**Nothing enforces that it is there.** `of(context)` returning null at runtime is
the normal failure. The convention is an `assert` with a message naming the
widget you forgot, because the framework's own error is a null dereference three
frames away.

## Minimal example

```dart
class CuesheetTheme extends InheritedWidget {
  const CuesheetTheme({required this.colors, required super.child, super.key});

  final CuesheetColors colors;

  static CuesheetColors of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<CuesheetTheme>();
    assert(theme != null, 'No CuesheetTheme found. Wrap the app in one.');
    return theme!.colors;
  }

  // Called on rebuild: return false and dependents will not be notified.
  @override
  bool updateShouldNotify(CuesheetTheme old) => old.colors != colors;
}
```

`updateShouldNotify` has no SwiftUI analogue at all — it is a manual equality
check that decides whether the subscription fires. Returning `true`
unconditionally is a common and invisible performance bug.

## Where it's used here

- `packages/cuesheet_ui/lib/src/theme/cuesheet_theme.dart` — the whole reason
  the palette is inherited rather than static. A widget test wraps one component
  in either theme and asserts what it renders, with no app around it, which is
  what makes "renders in both themes" a one-line test on every component.
