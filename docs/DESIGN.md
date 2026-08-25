# Cuesheet — Design

Status: Phase 5, in progress. Last revised 2026-08-25.

Companion to [ARCHITECTURE.md](ARCHITECTURE.md), which owns everything
structural. This owns what the app looks like and why, and it exists because
`cuesheet_ui` needs a single place those decisions are written down rather than
inferred from whichever component was built first.

## 1. The direction

**Quiet, and close to the platform.** The chrome gets out of the way; the intent
sheet is the one place with real personality.

That follows from the thesis rather than from taste. This app's argument is that
other podcast apps surprise you — they mutate your queue as a side effect of
tapping things. An app making that argument cannot itself be full of surprises,
and a strong visual identity competing for attention on every screen is a kind
of surprise. So the interface is deliberately unremarkable everywhere except the
one surface where the argument is actually made: the sheet that names, in
advance, exactly what a tap will do (§5.5).

Three rules follow:

1. **Nothing decorative gets the accent.** It marks what the user authored or is
   about to — the playhead, a queue position, an available intent — and nothing
   the app decided on its own. An accent spent on section headers stops meaning
   anything.
2. **State is on the row, never behind a tap.** Whether an episode is queued,
   where, whether it is playing, whether it fell out of its feed. Learning the
   state of your own queue should not require opening anything.
3. **Material is the widget kit, not the look.** Elevation, ripples, filled
   surfaces and the 56-pixel app bar are all turned off once in
   `cuesheetThemeData`, so no component has to remember to.

## 2. Type

Two families, and one rule about which is which.

| Role | Face | Used for |
|---|---|---|
| Display | Newsreader (bundled, 400/600) | Screen titles, section headings, the now-playing episode |
| Text | The platform face | Everything else |

Display is spent only on things a person came to *read*. Controls, metadata,
list rows and counts are the platform face, because a control that announces
itself in a serif is announcing the wrong thing.

The platform face is requested as `fontFamily: null`, never by name. Naming
`.SF Pro Text` would pin the app to one OS and fall back silently to something
wrong everywhere else; `null` asks each platform for its own, which is the whole
point of the direction.

Every number that sits in a column — durations, positions, counts, queue
indices — uses `FontFeature.tabularFigures()`. A timecode whose digits change
width as the seconds tick is the single most distracting thing a player can do.

## 3. Colour

One accent, two neutral ramps, and a muted tone for orphans. Defined in
`CuesheetColors`, as a plain class rather than a Material `ColorScheme`, because
most of these have no Material equivalent — "the colour a queued badge is" is
not a primary or a tertiary, and forcing it into that vocabulary would make
every use site a small act of translation.

The accent is a deep teal (`#0E6F66` light, `#5CC8BC` dark). It is not the
platform blue, so the app does not read as stock; it is not a warm accent on a
cream ground, which is the look every AI-designed page currently arrives
wearing.

Orphans get a muted ochre rather than a warning red. An episode that fell out of
its feed is a fact about the feed, not a problem the user caused (§6).

## 4. Both themes, always

Every component is tested in both. `CuesheetTheme` is an `InheritedWidget` so a
test can wrap a single component in either and assert what it renders, without
an app around it — see [inherited-widgets](notes/inherited-widgets.md).

## 5. Components take values, not providers

`cuesheet_ui` depends on `cuesheet_domain` and nothing else: no database, no
audio, no Riverpod. Every component takes plain values and callbacks.

This is what makes them testable in milliseconds, and it is also what stops the
UI growing rules of its own. `IntentSheet` is the clearest case — it takes a
`QueueState` and a list of intents and asks `previewIntent` what each one should
say. It is structurally incapable of inventing a label, which is exactly the
guarantee §5.5 asks for.

## 6. Open

- **A display face on list rows?** Currently platform-only there. Worth trying
  Newsreader at row-title size once there is a real library to look at.
- **Artwork.** No component shows any yet. Episode and podcast art exists in the
  schema and will change row density when it lands.
- **Density.** Row padding is set for a phone. A macOS window at full width
  currently gets phone-sized rows, which is fine for the harness and not for
  long.
