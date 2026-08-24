import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 822 and its descendants', () {
    test('reads the format the spec actually asks for', () {
      expect(parseFeedDate('Tue, 10 Jun 2025 09:00:00 GMT'),
          DateTime.utc(2025, 6, 10, 9));
    });

    test('reads a numeric offset and normalizes to UTC', () {
      expect(parseFeedDate('Mon, 05 May 2025 07:30:00 -0400'),
          DateTime.utc(2025, 5, 5, 11, 30));
      expect(parseFeedDate('Mon, 05 May 2025 07:30:00 +0530'),
          DateTime.utc(2025, 5, 5, 2, 0));
    });

    test('reads a colon in the offset, which RFC 822 does not permit', () {
      expect(parseFeedDate('Mon, 05 May 2025 07:30:00 -04:00'),
          DateTime.utc(2025, 5, 5, 11, 30));
    });

    test('reads the North American zone abbreviations', () {
      expect(parseFeedDate('Mon, 05 May 2025 07:30:00 EDT'),
          DateTime.utc(2025, 5, 5, 11, 30));
      expect(parseFeedDate('Mon, 05 May 2025 07:30:00 PST'),
          DateTime.utc(2025, 5, 5, 15, 30));
    });

    test('survives a missing day of week', () {
      expect(parseFeedDate('10 Jun 2025 09:00:00 GMT'),
          DateTime.utc(2025, 6, 10, 9));
    });

    test('ignores a day of week that disagrees with the date', () {
      // 10 June 2025 was a Tuesday. The feed says Friday. The numbers win.
      expect(parseFeedDate('Fri, 10 Jun 2025 09:00:00 GMT'),
          DateTime.utc(2025, 6, 10, 9));
    });

    test('survives a single-digit day', () {
      expect(parseFeedDate('Tue, 3 Jun 2025 09:00:00 GMT'),
          DateTime.utc(2025, 6, 3, 9));
    });

    test('survives omitted seconds', () {
      expect(parseFeedDate('Tue, 10 Jun 2025 09:00 GMT'),
          DateTime.utc(2025, 6, 10, 9));
    });

    test('survives an omitted time entirely', () {
      expect(parseFeedDate('10 Jun 2025'), DateTime.utc(2025, 6, 10));
    });

    test('expands a two-digit year the way RFC 2822 says to', () {
      expect(parseFeedDate('Tue, 10 Jun 25 09:00:00 GMT'),
          DateTime.utc(2025, 6, 10, 9));
      expect(parseFeedDate('Sat, 10 Jun 95 09:00:00 GMT'),
          DateTime.utc(1995, 6, 10, 9));
    });

    test('reads a parenthesised zone', () {
      expect(parseFeedDate('Tue, 10 Jun 2025 09:00:00 (GMT)'),
          DateTime.utc(2025, 6, 10, 9));
    });

    test('treats an unrecognised zone name as UTC rather than failing', () {
      // An hour wrong beats no date at all: §6's third rung compares to day
      // resolution, and the alternative is losing the rung entirely.
      expect(parseFeedDate('Tue, 10 Jun 2025 09:00:00 CET'),
          DateTime.utc(2025, 6, 10, 9));
    });

    test('reads a full month name', () {
      expect(parseFeedDate('Tue, 10 June 2025 09:00:00 GMT'),
          DateTime.utc(2025, 6, 10, 9));
    });
  });

  group('ISO 8601', () {
    test('reads a zoned timestamp', () {
      expect(parseFeedDate('2025-06-10T09:00:00Z'),
          DateTime.utc(2025, 6, 10, 9));
      expect(parseFeedDate('2025-06-10T05:00:00-04:00'),
          DateTime.utc(2025, 6, 10, 9));
    });

    test('reads a zone-less timestamp as UTC, not as device-local', () {
      // The whole point: the same feed must produce the same publishedAt in
      // Chicago and in Berlin.
      expect(parseFeedDate('2025-06-10T09:00:00'),
          DateTime.utc(2025, 6, 10, 9));
      expect(parseFeedDate('2025-06-10T09:00:00')!.isUtc, isTrue);
    });

    test('reads a bare date as UTC midnight', () {
      expect(parseFeedDate('2025-06-10'), DateTime.utc(2025, 6, 10));
    });

    test('reads a space in place of the T', () {
      expect(parseFeedDate('2025-06-10 09:00:00'),
          DateTime.utc(2025, 6, 10, 9));
    });

    test('keeps sub-second precision', () {
      expect(parseFeedDate('2025-06-10T09:00:00.250Z'),
          DateTime.utc(2025, 6, 10, 9, 0, 0, 250));
    });
  });

  group('nothing usable', () {
    test('returns null for null, empty and whitespace', () {
      expect(parseFeedDate(null), isNull);
      expect(parseFeedDate(''), isNull);
      expect(parseFeedDate('   '), isNull);
    });

    test('returns null for prose', () {
      expect(parseFeedDate('whenever we got round to it'), isNull);
      expect(parseFeedDate('Unknown'), isNull);
    });

    test('returns null for an impossible day', () {
      expect(parseFeedDate('Tue, 45 Jun 2025 09:00:00 GMT'), isNull);
    });

    test('returns null for a month that is not a month', () {
      expect(parseFeedDate('Tue, 10 Xyz 2025 09:00:00 GMT'), isNull);
    });
  });

  test('always returns UTC', () {
    for (final raw in [
      'Tue, 10 Jun 2025 09:00:00 -0700',
      '2025-06-10T09:00:00+02:00',
      '2025-06-10',
      '10 Jun 2025',
    ]) {
      expect(parseFeedDate(raw)!.isUtc, isTrue, reason: raw);
    }
  });
}
