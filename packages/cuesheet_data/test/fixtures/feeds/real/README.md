# Real feeds

Captured verbatim from live subscriptions on 2026-08-24. **Do not tidy these.**
Everything wrong with them is the point — §13 wants the corpus to be feeds that
exist, not feeds we would have written.

Each file carries a comment recording its source URL, capture date, response
headers, and original size. Three of the four are trimmed to the newest twelve
and oldest twelve items, because the originals total 9 MB; the elision is marked
in the file. The oldest items are kept deliberately, and are the more valuable
half — see below.

| Fixture | Host | Items | Notes |
|---|---|---|---|
| `last_podcast_on_the_left.xml` | Simplecast, behind pdst.fm + podtrac | 1196 → 24 | Migrated off SoundCloud; old guids are `tag:soundcloud,2010:tracks/…` |
| `rotten_mango.xml` | Simplecast, behind podtrac | 557 → 24 | Migrated off Buzzsprout; old guids are `Buzzsprout-…` |
| `black_girl_gone.xml` | Megaphone, behind five stacked wrappers | 319 → 24 | `podtrac → pdst.fm → pscrb.fm → clrtpod.com → mgln.ai → traffic.megaphone.fm` |
| `epstein_files_book_club.xml` | Megaphone, direct | 36 | Committed whole |

## What this corpus caught

It paid for itself on the first run, which is the argument for having it:

1. **`traffic.megaphone.fm/` was in the redirect-marker list.** It is the origin
   host for every Megaphone show, not a wrapper. Stripping it turned
   `https://traffic.megaphone.fm/CFQ4592230655.mp3` into
   `https://cfq4592230655.mp3` — a bogus host, no path. Every Megaphone episode
   in the library had a garbage identity key.

2. **The tracking-parameter denylist was compared lowercased against entries
   that were not lowercase**, so `awCollectionId` and `awEpisodeId` never
   matched. Both are per-episode ids, and both were sitting in the identity key
   of every Simplecast episode.

3. **Megaphone appends `?updated=<epoch>`**, which changes when an episode is
   re-cut — 24 distinct values across 36 items here. Keeping it in the key would
   defeat rung 2 of the identity ladder at exactly the moment rung 2 exists for.

Fixing 1 and 2 meant replacing prefix-matching with host-matching in
`normalize_url.dart`; the reasoning is written down there.

## Other things worth knowing that these feeds established

- Duration format is per-host, not per-spec: Megaphone emits bare seconds
  (`2760`), Simplecast emits `hh:mm:ss` (`01:53:56`).
- Timezone offsets vary within a single feed: `-0000` and `+0000` both appear.
- Megaphone sends **no ETag at all**, only `Last-Modified`, so conditional
  refresh cannot assume both.
- Simplecast serves `Content-Type: application/xml` with **no charset**, which
  is the case `decode_body.dart` exists for: `package:http` would read that as
  Latin-1.
- guids arrive wrapped in CDATA on Megaphone and bare on Simplecast.

## Provenance

Podcast feeds are published metadata, fetched here with an ordinary GET and
kept only as test fixtures. Nothing in this directory is redistributed and the
audio is not touched.
