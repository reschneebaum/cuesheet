import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:test/test.dart';

void main() {
  test('reads a plain count of seconds', () {
    expect(parseFeedDuration('3600'), const Duration(hours: 1));
    expect(parseFeedDuration('2715'), const Duration(minutes: 45, seconds: 15));
  });

  test('reads hh:mm:ss', () {
    expect(parseFeedDuration('01:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(parseFeedDuration('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
  });

  test('reads two parts as mm:ss, never as hh:mm', () {
    // The error this test exists to prevent is a sixty-fold one.
    expect(parseFeedDuration('14:30'), const Duration(minutes: 14, seconds: 30));
    expect(parseFeedDuration('90:00'), const Duration(minutes: 90));
    expect(parseFeedDuration('62:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
  });

  test('reads sloppy single-digit parts', () {
    expect(parseFeedDuration('1:2:3'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
  });

  test('reads fractional seconds', () {
    expect(parseFeedDuration('3600.5'),
        const Duration(hours: 1, milliseconds: 500));
    expect(parseFeedDuration('00:00:01.250'),
        const Duration(seconds: 1, milliseconds: 250));
  });

  test('tolerates surrounding whitespace', () {
    expect(parseFeedDuration('  01:02:03 '),
        const Duration(hours: 1, minutes: 2, seconds: 3));
  });

  test('reports zero as unknown rather than as an empty episode', () {
    expect(parseFeedDuration('0'), isNull);
    expect(parseFeedDuration('00:00'), isNull);
    expect(parseFeedDuration('00:00:00'), isNull);
  });

  test('returns null for anything that is not a duration', () {
    for (final raw in [null, '', '   ', '--:--', 'n/a', 'PT1H', '1:2:3:4',
                       '1::02', '-300', '1:-2']) {
      expect(parseFeedDuration(raw), isNull, reason: '"$raw"');
    }
  });
}
