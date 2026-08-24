import 'package:cuesheet_data/cuesheet_data.dart';
import 'package:test/test.dart';

void main() {
  test('leaves plain text alone', () {
    expect(plainText('The Mercator Problem'), 'The Mercator Problem');
  });

  test('strips tags', () {
    expect(plainText('<b>Episode 1:</b> Don’t Panic'),
        'Episode 1: Don’t Panic');
    expect(plainText('<a href="https://x.example">Jo &amp; Ray</a>'),
        'Jo & Ray');
  });

  test('turns line-break and block-end tags into newlines', () {
    expect(plainText('one<br>two'), 'one\ntwo');
    expect(plainText('one<br />two'), 'one\ntwo');
    expect(plainText('<p>Line one.</p><p>Line two.</p>'),
        'Line one.\nLine two.');
  });

  test('decodes the named entities feeds actually use', () {
    expect(plainText('Ampersand &amp; Co&nbsp;&mdash; The Show'),
        'Ampersand & Co — The Show');
    expect(plainText('Don&rsquo;t Panic'), 'Don’t Panic');
  });

  test('decodes numeric entities in both bases', () {
    expect(plainText('Don&#8217;t &#x2019;'), 'Don’t ’');
  });

  test('leaves an entity it does not know as written', () {
    expect(plainText('&zwnj;marker'), '&zwnj;marker');
  });

  test('decodes entities after stripping tags, not before', () {
    // The feed wrote `&lt;b&gt;`, meaning the reader should see the characters
    // `<b>`. Decoding first would turn it into a tag and strip it.
    expect(plainText('Episode 2: &lt;b&gt;not actually bold&lt;/b&gt;'),
        'Episode 2: <b>not actually bold</b>');
  });

  test('collapses runs of horizontal space and trims', () {
    expect(plainText('  too    many\tspaces  '), 'too many spaces');
  });

  test('collapses a run of blank lines to one', () {
    expect(plainText('a<br><br><br><br>b'), 'a\n\nb');
  });

  test('is null-in, null-out, and null for anything that reduces to nothing',
      () {
    expect(plainText(null), isNull);
    expect(plainText(''), isNull);
    expect(plainText('   '), isNull);
    expect(plainText('<p></p>'), isNull);
  });
}
