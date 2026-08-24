/// Hosts that exist only to count a download and then hand the listener on.
///
/// Unwrapping is driven by this list of **hosts** rather than by a list of path
/// prefixes, which is what the first draft did and what the real corpus broke.
/// Path prefixes fail two ways: the plumbing between the host and the payload
/// varies (`mgln.ai/e/204/` carries a numeric segment that changes), and — much
/// worse — a prefix like `traffic.megaphone.fm/` matches the *origin* host for
/// every Megaphone show, so stripping it destroyed the URL rather than
/// unwrapping it.
///
/// This list is the maintenance surface. An unknown wrapper is not a
/// correctness problem: the normalized key is merely less stable, so rung 2 of
/// the identity ladder misses and rung 3 catches it. Being wrong in the other
/// direction — re-rooting a URL that was never wrapped — is the dangerous one,
/// which is why nothing is unwrapped unless its host is named here.
const _wrapperHosts = {
  'podtrac.com',          // dts.podtrac.com, www.podtrac.com
  'pdst.fm',
  'chtbl.com',            // Chartable
  'chrt.fm',
  'chartable.com',
  'pscrb.fm',             // Podscribe
  'podscribe.com',        // verifi.podscribe.com
  'clrtpod.com',          // Claritas
  'claritaspod.com',
  'mgln.ai',              // Magellan AI
  'arttrk.com',           // ArtsAI
  'podsights.com',        // pixel.podsights.com
  'prfx.byspotify.com',
  'vpixl.com',            // pfx.vpixl.com
  'op3.dev',
};

/// Query parameters that identify a listener, a campaign, or a moment in time
/// rather than a file.
///
/// Compared lowercased, and written lowercased — the first draft mixed the two
/// and `awCollectionId` therefore never matched anything, which the corpus
/// caught by leaving two per-episode ids in every Simplecast key.
///
/// `updated` is the one worth naming: Megaphone appends the re-upload epoch, so
/// re-cutting an episode changes its URL. Keeping that in the key would defeat
/// rung 2 precisely when a URL has moved, which is the only time rung 2 is
/// doing any work.
const _trackingParams = {
  'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
  'ref', 'source', '_from', 'aid', 'feed', 'updated',
  'awcollectionid', 'awepisodeid',
};

/// Last labels that mean "this segment is a file", not "this segment is a
/// host". Several are also real TLDs (`.mov`, `.dev`), and that ambiguity is
/// resolved in favour of "file" on purpose: guessing "file" stops the unwrap
/// early, which costs stability, while guessing "host" re-roots at the wrong
/// place, which costs correctness.
const _fileExtensions = {
  'mp3', 'm4a', 'm4b', 'mp4', 'm4v', 'aac', 'ogg', 'oga', 'opus', 'wav',
  'flac', 'wma', 'mov', 'webm', 'mpeg', 'mpg',
  'xml', 'rss', 'json', 'html', 'htm', 'php', 'aspx', 'jsp', 'txt',
  'jpg', 'jpeg', 'png', 'webp',
};

final _hostLike = RegExp(r'^[\w-]+(\.[\w-]+)+$');
final _embeddedScheme = RegExp(r'https?://');

/// A stable key for an enclosure URL, for the second rung of the identity
/// ladder (§6).
///
/// Enclosure URLs move: hosts change CDN, add and remove analytics wrappers,
/// and append campaign parameters. Two URLs that fetch the same audio must
/// normalize to the same string, or a feed's routine reshuffle looks like a
/// batch of brand-new episodes.
///
/// Never used for playback — that reads `enclosureUrl` as the feed wrote it,
/// wrappers and signatures intact. This is only ever an identity key, which is
/// what makes dropping parts of the URL safe.
String normalizeEnclosureUrl(Uri url) {
  final unwrapped = _unwrap(url);

  final kept = <String, String>{
    for (final entry in unwrapped.queryParameters.entries)
      if (!_trackingParams.contains(entry.key.toLowerCase()))
        entry.key: entry.value,
  };

  return Uri(
    scheme: unwrapped.scheme.toLowerCase(),
    host: unwrapped.host.toLowerCase(),
    port: unwrapped.hasPort ? unwrapped.port : null,
    path: unwrapped.path,
    queryParameters: kept.isEmpty ? null : kept,
  ).toString();
}

/// Peels wrappers until the host is one that actually serves audio.
///
/// Bounded rather than `while (true)`: the corpus stacks five deep, a malicious
/// or broken feed could stack forever, and there is no sensible URL that needs
/// more than a handful.
Uri _unwrap(Uri url) {
  var current = url;
  for (var depth = 0; depth < 8; depth++) {
    final next = _unwrapOnce(current);
    if (next == null) return current;
    current = next;
  }
  return current;
}

Uri? _unwrapOnce(Uri url) {
  if (!_isWrapperHost(url.host)) return null;

  // Some wrappers embed the whole target URL, scheme and all:
  // `op3.dev/e/https://cdn.example.com/a.mp3`. Searched in the path only —
  // a URL sitting in a *query* parameter is a callback, not a payload.
  final embedded = _embeddedScheme.allMatches(url.path).lastOrNull;
  if (embedded != null && embedded.start > 0) {
    final parsed = Uri.tryParse(url.path.substring(embedded.start));
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.replace(query: url.hasQuery ? url.query : null);
    }
  }

  // Otherwise the inner host is a bare path segment, with the wrapper's own
  // plumbing in front of it.
  final segments = url.pathSegments;
  for (var i = 0; i < segments.length; i++) {
    if (!_looksLikeHost(segments[i])) continue;
    return Uri(
      scheme: url.scheme,
      host: segments[i],
      pathSegments: segments.skip(i + 1),
      query: url.hasQuery ? url.query : null,
    );
  }
  return null;
}

bool _isWrapperHost(String host) {
  final lower = host.toLowerCase();
  return _wrapperHosts
      .any((wrapper) => lower == wrapper || lower.endsWith('.$wrapper'));
}

bool _looksLikeHost(String segment) {
  if (!_hostLike.hasMatch(segment)) return false;
  final lastLabel = segment.substring(segment.lastIndexOf('.') + 1);
  if (lastLabel.length < 2) return false;
  if (!RegExp(r'^[a-zA-Z]+$').hasMatch(lastLabel)) return false;
  return !_fileExtensions.contains(lastLabel.toLowerCase());
}
