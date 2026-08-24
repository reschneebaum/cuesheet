import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'format.dart';
import 'providers.dart';

/// Subscribe, search, refresh — the Phase 3 half of the debug harness.
///
/// Still no design. It exists so that ingestion can be pointed at a real feed
/// by hand, and so that what a refresh actually did — how each episode
/// matched, what was orphaned, what the parser complained about — is readable
/// without a breakpoint.
class FeedsPage extends ConsumerStatefulWidget {
  const FeedsPage({super.key});

  @override
  ConsumerState<FeedsPage> createState() => _FeedsPageState();
}

class _FeedsPageState extends ConsumerState<FeedsPage> {
  final _searchField = TextEditingController();
  final _urlField = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _searchField.dispose();
    _urlField.dispose();
    super.dispose();
  }

  /// Runs one ingestion and writes what happened to the log.
  ///
  /// Every failure path ends up here as a line rather than as a thrown error
  /// nobody sees: a feed that 404s, a URL that is not a feed, and a feed that
  /// is merely ugly all have to be distinguishable from the outside.
  Future<void> _run(String label, Future<IngestionReport> Function() work) async {
    final log = ref.read(ingestionLogProvider.notifier);
    setState(() => _busy = true);
    try {
      final report = await work();
      log.add('$label — ${_describe(report)}');
      for (final warning in report.warnings) {
        log.add('    ⚠ $warning');
      }
    } on FeedFormatException catch (e) {
      log.add('$label — not a feed: ${e.message}');
    } on FeedTransportException catch (e) {
      log.add('$label — ${e.isPermanent ? 'gone' : 'unreachable'}: '
          '${e.statusCode ?? '—'} ${e.message}');
    } on Object catch (e) {
      log.add('$label — failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(IngestionReport report) {
    if (report.notModified) return 'not modified (304)';
    final rungs = report.rungs.entries
        .where((e) => e.key != MatchRung.firstSighting)
        .map((e) => '${e.value} by ${e.key.name}')
        .join(', ');
    return [
      '+${report.added} new',
      '${report.matched} matched${rungs.isEmpty ? '' : ' ($rungs)'}',
      if (report.unorphaned > 0) '${report.unorphaned} un-orphaned',
      if (report.orphaned > 0) '${report.orphaned} orphaned',
      if (report.deleted > 0) '${report.deleted} deleted',
    ].join(', ');
  }

  Future<void> _subscribe(Uri feedUrl, String label) => _run(
      label, () => ref.read(feedIngestionProvider).subscribe(feedUrl));

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(directoryResultsProvider);
    final podcasts = ref.watch(podcastsProvider).value ?? const <Podcast>[];
    final episodes = ref.watch(episodeIndexProvider).value ?? const {};
    final log = ref.watch(ingestionLogProvider);

    final counts = <String, int>{};
    var orphans = 0;
    for (final view in episodes.values) {
      final key = view.episode.podcastId.value;
      counts[key] = (counts[key] ?? 0) + 1;
      if (view.episode.isOrphaned) orphans++;
    }

    return ListView(
      children: [
        if (_busy) const LinearProgressIndicator(),
        _heading('Subscribe by feed URL'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _urlField,
                decoration: const InputDecoration(hintText: 'https://…/rss'),
                onSubmitted: (_) => _subscribeTyped(),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _subscribeTyped,
              child: const Text('Subscribe'),
            ),
          ]),
        ),
        _heading('Search the directory'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchField,
                decoration: const InputDecoration(hintText: 'podcast name'),
                onSubmitted: (q) =>
                    ref.read(directoryQueryProvider.notifier).submit(q),
              ),
            ),
            TextButton(
              onPressed: () => ref
                  .read(directoryQueryProvider.notifier)
                  .submit(_searchField.text),
              child: const Text('Search'),
            ),
          ]),
        ),
        switch (results) {
          AsyncError(:final error) =>
            ListTile(title: Text('Search failed: $error')),
          AsyncLoading() => const ListTile(title: Text('Searching…')),
          AsyncValue(value: final found?)
              when found.isEmpty && ref.watch(directoryQueryProvider).isEmpty =>
            const SizedBox.shrink(),
          AsyncValue(value: final found?) when found.isEmpty =>
            const ListTile(dense: true, title: Text('No results.')),
          AsyncValue(value: final found?) => Column(
              children: [
                for (final result in found)
                  ListTile(
                    dense: true,
                    title: Text(result.title),
                    subtitle: Text([
                      result.author ?? 'unknown author',
                      result.primaryGenre,
                      if (result.episodeCount != null)
                        '${result.episodeCount} episodes',
                    ].whereType<String>().join(' · ')),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _subscribe(result.feedUrl, result.title),
                      child: const Text('Subscribe'),
                    ),
                  ),
              ],
            ),
        },
        _heading('Subscriptions'
            '${orphans == 0 ? '' : ' · $orphans orphaned episodes'}'),
        if (podcasts.isEmpty)
          const ListTile(title: Text('Nothing subscribed yet.'))
        else
          for (final podcast in podcasts)
            ListTile(
              dense: true,
              title: Text(podcast.title),
              subtitle: Text([
                '${counts[podcast.id.value] ?? 0} episodes',
                podcast.lastFetchedAt == null
                    ? 'never fetched'
                    : 'fetched ${formatTimestamp(podcast.lastFetchedAt!)}',
                podcast.feedUrl.host,
              ].join(' · ')),
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                          podcast.title,
                          () => ref
                              .read(feedIngestionProvider)
                              .refresh(podcast.id),
                        ),
                child: const Text('Refresh'),
              ),
            ),
        if (podcasts.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: _busy ? null : () => _refreshAll(podcasts),
              child: const Text('Refresh all'),
            ),
          ),
        _heading('Ingestion log'),
        if (log.isEmpty)
          const ListTile(dense: true, title: Text('Nothing yet.'))
        else
          for (final line in log)
            ListTile(dense: true, title: Text(line)),
      ],
    );
  }

  void _subscribeTyped() {
    final url = Uri.tryParse(_urlField.text.trim());
    if (url == null || !url.hasScheme || url.host.isEmpty) {
      ref
          .read(ingestionLogProvider.notifier)
          .add('"${_urlField.text.trim()}" is not a URL');
      return;
    }
    _subscribe(url, url.host);
  }

  /// One at a time, deliberately.
  ///
  /// `Future.wait` would be the obvious move and is the wrong one here: it
  /// would open every feed at once against a shared database, and there is no
  /// way to cancel any of them once started.
  Future<void> _refreshAll(List<Podcast> podcasts) async {
    for (final podcast in podcasts) {
      await _run(
        podcast.title,
        () => ref.read(feedIngestionProvider).refresh(podcast.id),
      );
    }
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge),
      );
}
