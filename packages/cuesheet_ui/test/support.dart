import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:cuesheet_ui/cuesheet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 8, 25, 12);

EpisodeId eid(String id) => EpisodeId(id);

EpisodeView viewOf({
  String id = 'e1',
  String title = 'The Mercator Problem',
  String podcast = 'The Cartographers',
  Duration? duration = const Duration(hours: 1),
  DateTime? publishedAt,
  bool orphaned = false,
  ListeningState? listening,
}) =>
    EpisodeView(
      episode: Episode(
        id: eid(id),
        podcastId: const PodcastId('p1'),
        title: title,
        enclosureUrl: Uri.parse('https://cdn.example.com/$id.mp3'),
        duration: duration,
        publishedAt: publishedAt,
        isOrphaned: orphaned,
      ),
      listening: listening ?? ListeningState(episodeId: eid(id)),
      podcastTitle: podcast,
    );

Cuesheet sheetOf(List<String> ids) => Cuesheet(
      id: const CuesheetId('cs'),
      kind: CuesheetKind.ephemeral,
      items: [for (final id in ids) eid(id)],
    );

QueueState queueOf(
  List<String> ids, {
  int position = 0,
  PlaybackSource? source = const FromQueue(),
}) =>
    QueueState(active: sheetOf(ids), position: position, source: source);

/// Components are built without an app around them wherever possible — that is
/// the payoff for them taking plain values.
extension Pump on WidgetTester {
  Future<void> pumpComponent(
    Widget child, {
    Brightness brightness = Brightness.light,
  }) async {
    final colors = brightness == Brightness.dark
        ? CuesheetColors.dark
        : CuesheetColors.light;
    await pumpWidget(CuesheetTheme(
      colors: colors,
      child: MaterialApp(
        theme: cuesheetThemeData(colors, brightness),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    ));
    await pump();
  }
}
