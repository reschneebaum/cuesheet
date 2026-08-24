import 'dart:convert';

import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:test/test.dart';

List<int> latin1Bytes(String s) => [for (final r in s.runes) r];

void main() {
  test('reads UTF-8 when nothing says otherwise', () {
    expect(decodeFeedBody(utf8.encode('Piñata 👍')), 'Piñata 👍');
  });

  test('strips a UTF-8 byte-order mark', () {
    final bytes = [0xef, 0xbb, 0xbf, ...utf8.encode('<?xml version="1.0"?>')];
    expect(decodeFeedBody(bytes), '<?xml version="1.0"?>');
  });

  test('reads UTF-16 in both byte orders', () {
    expect(decodeFeedBody([0xff, 0xfe, 0x41, 0x00, 0x42, 0x00]), 'AB');
    expect(decodeFeedBody([0xfe, 0xff, 0x00, 0x41, 0x00, 0x42]), 'AB');
  });

  test('obeys the XML declaration over the transport header', () {
    // HTTP normally makes Content-Type authoritative. XML inverts that,
    // because a document is meant to stay self-describing once the headers
    // are gone.
    final bytes = latin1Bytes('<?xml version="1.0" encoding="ISO-8859-1"?>'
        '<rss><channel><title>Café</title></channel></rss>');
    expect(
      decodeFeedBody(bytes, contentType: 'text/xml; charset=utf-8'),
      contains('Café'),
    );
  });

  test('obeys the Content-Type charset when the declaration is silent', () {
    final bytes = latin1Bytes('<?xml version="1.0"?><t>Café</t>');
    expect(decodeFeedBody(bytes, contentType: 'text/xml; charset=iso-8859-1'),
        contains('Café'));
  });

  test('decodes the Windows-1252 range rather than reading it as controls', () {
    // 0x92 is a right single quote in cp1252 and an invisible control in
    // Latin-1. Every apostrophe in the feed rides on this.
    final bytes = [
      ...latin1Bytes('<?xml version="1.0" encoding="windows-1252"?><t>Don'),
      0x92,
      ...latin1Bytes('t</t>'),
    ];
    expect(decodeFeedBody(bytes), contains('Don’t'));
  });

  test('defaults to UTF-8 for a charset it has never heard of', () {
    final bytes = utf8.encode('<?xml version="1.0" encoding="x-weird"?><t>é</t>');
    expect(decodeFeedBody(bytes), contains('é'));
  });

  test('substitutes rather than throwing on malformed UTF-8', () {
    // One mangled character must not cost the user a whole subscription.
    expect(() => decodeFeedBody([0x3c, 0x74, 0x3e, 0xff, 0xfe0 & 0xff]),
        returnsNormally);
  });

  test('ignores an encoding attribute that is not in the XML declaration', () {
    final bytes =
        utf8.encode('<rss><item encoding="iso-8859-1">é</item></rss>');
    expect(decodeFeedBody(bytes), contains('é'));
  });
}
