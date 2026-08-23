import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late CuesheetDatabase db;
  late DriftCuesheetRepository cuesheets;
  late DateTime clock;

  List<EpisodeId> eps(String ids) =>
      ids.split(' ').map((s) => EpisodeId(s)).toList();

  Cuesheet sheet(String id, String items,
          {CuesheetKind kind = CuesheetKind.ephemeral, String? title}) =>
      Cuesheet(
        id: CuesheetId(id),
        kind: kind,
        items: eps(items),
        title: title,
      );

  setUp(() async {
    db = openTestDatabase();
    await seed(db);
    clock = now;
    cuesheets = DriftCuesheetRepository(db, clock: () => clock, keepDisplaced: 3);
  });

  tearDown(() async => db.close());

  group('the queue', () {
    test('is empty before anything has been saved', () async {
      expect(await cuesheets.queue(), QueueState.empty);
    });

    test('round-trips a queue playing from itself', () async {
      final state = QueueState(
        active: sheet('cs1', 'e3 e1 e2'),
        position: 1,
        source: const FromQueue(),
      );
      await cuesheets.saveQueue(state);

      final reloaded = await cuesheets.queue();
      expect(reloaded, state);
      expect(reloaded.active!.items, eps('e3 e1 e2'),
          reason: 'order is the whole point of a cuesheet');
      expect(reloaded.nowPlaying, const EpisodeId('e1'));
    });

    test('round-trips detached playback with the queue intact', () async {
      final state = QueueState(
        active: sheet('cs1', 'e1 e2'),
        position: 1,
        source: const Detached(EpisodeId('e5')),
      );
      await cuesheets.saveQueue(state);

      final reloaded = await cuesheets.queue();
      expect(reloaded.source, const Detached(EpisodeId('e5')));
      expect(reloaded.nowPlaying, const EpisodeId('e5'));
      expect(reloaded.position, 1, reason: 'the queue kept its place');
    });

    test('round-trips a queue with nothing playing', () async {
      final state = QueueState(active: sheet('cs1', 'e1 e2'), source: null);
      await cuesheets.saveQueue(state);

      expect((await cuesheets.queue()).source, isNull);
    });

    test('re-emits when the active cuesheet is reordered', () async {
      await cuesheets.saveQueue(QueueState(
        active: sheet('cs1', 'e1 e2 e3'),
        source: const FromQueue(),
      ));

      final seen = <List<String>>[];
      final sub = cuesheets.watchQueue().listen(
          (q) => seen.add([for (final i in q.active!.items) i.value]));
      await pumpEventQueue();

      // Touches cuesheets and cuesheet_items but not queue_states — the case
      // a plain select on queue_states would miss.
      await cuesheets.save(sheet('cs1', 'e3 e2 e1'));
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, [
        ['e1', 'e2', 'e3'],
        ['e3', 'e2', 'e1'],
      ]);
    });
  });

  group('displacement', () {
    test('keeps a queue that was replaced', () async {
      final first = sheet('cs1', 'e1 e2 e3');
      await cuesheets.saveQueue(
          QueueState(active: first, source: const FromQueue()));

      await cuesheets.saveQueue(
        QueueState(active: sheet('cs2', 'e4 e5'), source: const FromQueue()),
        displaced: first,
      );

      final recovered = await cuesheets.recentlyDisplaced();
      expect(recovered, hasLength(1));
      expect(recovered.single.items, eps('e1 e2 e3'));
    });

    test('lists the most recently displaced first', () async {
      for (final (id, items) in [('cs1', 'e1'), ('cs2', 'e2'), ('cs3', 'e3')]) {
        clock = clock.add(const Duration(minutes: 1));
        await cuesheets.saveQueue(
          QueueState(active: sheet(id, items), source: const FromQueue()),
          displaced: sheet('${id}_old', items),
        );
      }

      final recovered = await cuesheets.recentlyDisplaced();
      expect([for (final c in recovered) c.id.value],
          ['cs3_old', 'cs2_old', 'cs1_old']);
    });

    test('prunes beyond the retention limit', () async {
      for (var i = 0; i < 6; i++) {
        clock = clock.add(const Duration(minutes: 1));
        await cuesheets.saveQueue(
          QueueState(active: sheet('cs$i', 'e1'), source: const FromQueue()),
          displaced: sheet('old$i', 'e2'),
        );
      }

      // keepDisplaced is 3 for these tests.
      final recovered = await cuesheets.recentlyDisplaced(limit: 99);
      expect(recovered, hasLength(3));
      expect([for (final c in recovered) c.id.value], ['old5', 'old4', 'old3']);
    });

    test('recovering a displaced queue un-displaces it', () async {
      final original = sheet('cs1', 'e1 e2');
      await cuesheets.saveQueue(
        QueueState(active: sheet('cs2', 'e3'), source: const FromQueue()),
        displaced: original,
      );

      await cuesheets.saveQueue(
          QueueState(active: original, source: const FromQueue()));

      expect(await cuesheets.recentlyDisplaced(), isEmpty);
      expect((await cuesheets.queue()).active!.id, const CuesheetId('cs1'));
    });
  });

  group('saved cuesheets', () {
    test('promotion is a save with a changed kind and a title', () async {
      final ephemeral = sheet('cs1', 'e1 e2');
      await cuesheets.saveQueue(
          QueueState(active: ephemeral, source: const FromQueue()));

      expect(await cuesheets.watchSaved().first, isEmpty);

      await cuesheets.save(ephemeral.copyWith(
          kind: CuesheetKind.saved, title: 'Monday Morning'));

      final saved = await cuesheets.watchSaved().first;
      expect(saved, hasLength(1));
      expect(saved.single.title, 'Monday Morning');
      expect(saved.single.items, eps('e1 e2'),
          reason: 'the same object, not a copy of it');
      // And it is still the queue: promotion does not detach it.
      expect((await cuesheets.queue()).active!.id, const CuesheetId('cs1'));
    });

    test('re-saving does not reset when the cuesheet was created', () async {
      await cuesheets.save(
          sheet('cs1', 'e1', kind: CuesheetKind.saved, title: 'First'));
      final created = (await db.select(db.cuesheets).getSingle()).createdAt;

      clock = clock.add(const Duration(days: 3));
      await cuesheets.save(
          sheet('cs1', 'e1 e2', kind: CuesheetKind.saved, title: 'Renamed'));

      final row = await db.select(db.cuesheets).getSingle();
      expect(row.createdAt, created);
      expect(row.title, 'Renamed');
    });

    test('removing one takes its items with it', () async {
      await cuesheets.save(
          sheet('cs1', 'e1 e2', kind: CuesheetKind.saved, title: 'Doomed'));
      await cuesheets.remove(const CuesheetId('cs1'));

      expect(await cuesheets.byId(const CuesheetId('cs1')), isNull);
      expect(await db.select(db.cuesheetItems).get(), isEmpty);
    });
  });

  group('domain and database together', () {
    test('an intent round-trips through storage unchanged', () async {
      final visible = eps('e1 e2 e3 e4');
      final result = applyIntent(
        QueueState.empty,
        PlayFromHere(const EpisodeId('e2'), TraversalOrder.ascending),
        visible,
        newCuesheetId: () => const CuesheetId('cs1'),
      );
      await cuesheets.saveQueue(result.state, displaced: result.displaced);

      expect(await cuesheets.queue(), result.state);
    });

    test('a sequence of intents survives reloading between each one', () async {
      final visible = eps('e1 e2 e3 e4');
      var ids = 0;
      CuesheetId nextId() => CuesheetId('cs${++ids}');

      var state = QueueState.empty;
      for (final intent in <PlaybackIntent>[
        PlayFromHere(const EpisodeId('e2'), TraversalOrder.ascending),
        AppendToQueue(const EpisodeId('e1')),
        MoveToEnd(const EpisodeId('e3')),
        PlayJustThis(const EpisodeId('e5')),
      ]) {
        final result =
            applyIntent(state, intent, visible, newCuesheetId: nextId);
        await cuesheets.saveQueue(result.state, displaced: result.displaced);
        // Reload rather than carrying the in-memory value forward, so any
        // lossy round-trip shows up immediately rather than at the end.
        state = await cuesheets.queue();
        expect(state, result.state);
      }

      expect(state.active!.items, eps('e2 e4 e1 e3'));
      expect(state.nowPlaying, const EpisodeId('e5'));
    });
  });

  group('categories', () {
    late DriftCategoryRepository categories;
    late DriftEpisodeRepository episodes;

    setUp(() {
      categories = DriftCategoryRepository(db);
      episodes = DriftEpisodeRepository(db, clock: () => now);
    });

    test('lists alphabetically', () async {
      await categories
          .upsert(const Category(id: CategoryId('z'), name: 'Zoology'));
      await categories
          .upsert(const Category(id: CategoryId('a'), name: 'Archaeology'));

      final all = await categories.watchAll().first;
      expect([for (final c in all) c.name],
          ['Archaeology', 'Fiction', 'News', 'Zoology']);
    });

    test('setting a podcast\'s categories replaces rather than adds', () async {
      const p = PodcastId('p1');
      await categories.setPodcastCategories(p, {const CategoryId('news')});
      await categories.setPodcastCategories(p, {const CategoryId('fiction')});

      expect(await categories.podcastCategories(p), {const CategoryId('fiction')});
    });

    test('episode categories show up on the episode view', () async {
      await categories.setEpisodeCategories(
          const EpisodeId('e2'), {const CategoryId('news')});

      final view = await episodes.byId(const EpisodeId('e2'));
      expect(view!.categories, {const CategoryId('news')});
    });

    test('deleting a category unlinks it everywhere', () async {
      await categories.remove(const CategoryId('news'));

      final view = await episodes.byId(const EpisodeId('e8'));
      expect(view!.categories, {const CategoryId('fiction')});
    });
  });
}
