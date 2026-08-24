import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'episodes_page.dart';
import 'feeds_page.dart';
import 'providers.dart';
import 'queue_page.dart';
import 'sample_data.dart';

/// The deliberately ugly debug harness.
///
/// No design, no theming, no layout work. It exists so the engine underneath
/// can be driven by hand — the intent algebra, the filter vocabulary and queue
/// persistence from Phase 2, and from Phase 3 the ability to point ingestion
/// at a real feed and read back exactly what it did. Phase 5 replaces this
/// wholesale.
class DebugApp extends StatelessWidget {
  const DebugApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Cuesheet (debug)',
        theme: ThemeData(useMaterial3: true),
        home: const _Home(),
      );
}

class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodeCount =
        ref.watch(episodeIndexProvider).value?.length ?? 0;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Cuesheet debug · $episodeCount episodes'),
          actions: [
            TextButton(
              onPressed: () => insertSampleData(
                podcasts: ref.read(podcastRepositoryProvider),
                episodes: ref.read(episodeRepositoryProvider),
                listening: ref.read(listeningRepositoryProvider),
                now: ref.read(clockProvider)(),
              ),
              child: const Text('Seed data'),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Episodes'),
            Tab(text: 'Queue'),
            Tab(text: 'Saved'),
            Tab(text: 'Feeds'),
          ]),
        ),
        body: const TabBarView(children: [
          EpisodesPage(),
          QueuePage(),
          SavedPage(),
          FeedsPage(),
        ]),
      ),
    );
  }
}
