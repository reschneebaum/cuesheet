import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'episodes_page.dart';
import 'feeds_page.dart';
import 'playback_controller.dart';
import 'providers.dart';
import 'queue_page.dart';
import 'sample_data.dart';
import 'transport_bar.dart';

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
        title: 'Cuesheet',
        theme: cuesheetThemeData(CuesheetColors.light, Brightness.light),
        darkTheme: cuesheetThemeData(CuesheetColors.dark, Brightness.dark),
        // Resolved below MaterialApp so the palette follows whichever theme
        // Material settled on, rather than re-deriving it from the platform and
        // risking the two disagreeing.
        builder: (context, child) => CuesheetTheme(
          colors: Theme.of(context).brightness == Brightness.dark
              ? CuesheetColors.dark
              : CuesheetColors.light,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const _Home(),
      );
}

class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // §9 lists backgrounding among the events that force a write, and it is
    // the one no tick can report: the app is told it is going away, the engine
    // is not. Nothing here relies on a clean termination, which is the point.
    _lifecycle = AppLifecycleListener(
      onInactive: () => ref.read(playbackControllerProvider).flush(),
      onPause: () => ref.read(playbackControllerProvider).flush(),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episodeCount =
        ref.watch(episodeIndexProvider).value?.length ?? 0;

    // Read eagerly so the controller is listening to ticks before the first
    // one arrives. A provider nobody reads is a provider that was never built.
    ref.watch(playbackControllerProvider);

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
        body: const Column(
          children: [
            Expanded(
              child: TabBarView(children: [
                EpisodesPage(),
                QueuePage(),
                SavedPage(),
                FeedsPage(),
              ]),
            ),
            TransportBar(),
          ],
        ),
      ),
    );
  }
}
