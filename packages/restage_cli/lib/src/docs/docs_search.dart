import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/backend_sites.dart';

/// One page of the documentation.
class DocsPage {
  /// Construct a page.
  const DocsPage({
    required this.path,
    required this.title,
    required this.description,
    required this.group,
    required this.url,
    required this.markdownUrl,
  });

  /// Reads a page from the docs index.
  factory DocsPage.fromJson(Map<String, Object?> json) => DocsPage(
    path: json['path']! as String,
    title: json['title']! as String,
    description: json['description']! as String,
    group: json['group']! as String,
    url: json['url']! as String,
    markdownUrl: json['markdownUrl']! as String,
  );

  /// Site path, such as `/delivery/hosted-delivery`.
  final String path;

  /// Page title.
  final String title;

  /// One-line description.
  final String description;

  /// Sidebar group.
  final String group;

  /// Page URL.
  final String url;

  /// URL of the page as Markdown.
  final String markdownUrl;
}

/// One section of a page: the unit search ranks and returns.
class DocsSection {
  /// Construct a section.
  const DocsSection({
    required this.page,
    required this.title,
    required this.headings,
    required this.anchor,
    required this.url,
    required this.markdownUrl,
    required this.markdown,
    required this.hash,
  });

  /// Reads a section from the docs index.
  factory DocsSection.fromJson(Map<String, Object?> json) => DocsSection(
    page: json['page']! as String,
    title: json['title']! as String,
    headings: (json['headings']! as List).cast<String>(),
    anchor: json['anchor'] as String?,
    url: json['url']! as String,
    markdownUrl: json['markdownUrl']! as String,
    markdown: json['markdown']! as String,
    hash: json['hash']! as String,
  );

  /// Path of the page the section belongs to.
  final String page;

  /// Title of that page.
  final String title;

  /// Headings from the page title down to this section; empty for the
  /// page's opening text.
  final List<String> headings;

  /// Heading anchor, or null for the opening text.
  final String? anchor;

  /// URL of the section.
  final String url;

  /// URL of the page as Markdown.
  final String markdownUrl;

  /// The section's Markdown.
  final String markdown;

  /// Content hash of [markdown].
  final String hash;
}

/// The section index the docs site publishes at `/docs-index.json`.
class DocsIndex {
  /// Construct an index.
  const DocsIndex({required this.pages, required this.sections});

  /// Parses the published index.
  factory DocsIndex.parse(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    return DocsIndex(
      pages: [
        for (final page
            in (json['pages']! as List).cast<Map<String, Object?>>())
          DocsPage.fromJson(page),
      ],
      sections: [
        for (final chunk
            in (json['chunks']! as List).cast<Map<String, Object?>>())
          DocsSection.fromJson(chunk),
      ],
    );
  }

  /// Every page in sidebar order.
  final List<DocsPage> pages;

  /// Every section in page order.
  final List<DocsSection> sections;
}

/// A ranked search result.
class DocsHit {
  /// Construct a hit.
  const DocsHit({
    required this.section,
    required this.score,
    required this.snippet,
  });

  /// The matching section.
  final DocsSection section;

  /// Relevance; higher ranks first.
  final int score;

  /// A short excerpt around the first match.
  final String snippet;

  /// Structured form for tools and `--json` output.
  Map<String, Object?> toJson() => {
    'title': section.title,
    'section': section.headings.isEmpty ? null : section.headings.last,
    'headings': section.headings,
    'url': section.url,
    'markdownUrl': section.markdownUrl,
    'snippet': snippet,
    'score': score,
  };
}

/// Ranks [index] sections for [query]. Every query word must appear; title
/// matches outrank heading matches, which outrank body matches.
List<DocsHit> searchDocs(DocsIndex index, String query, {int limit = 8}) {
  final terms = _tokens(query);
  if (terms.isEmpty) return const [];
  final phrase = terms.join(' ');
  final hits = <DocsHit>[];
  for (final section in index.sections) {
    final title = section.title.toLowerCase();
    final headings = section.headings.join(' ').toLowerCase();
    final body = searchableText(section.markdown);
    var score = 0;
    var matched = true;
    for (final term in terms) {
      final inTitle = _count(title, term);
      final inHeadings = _count(headings, term);
      final inBody = _count(body, term);
      if (inTitle == 0 && inHeadings == 0 && inBody == 0) {
        matched = false;
        break;
      }
      score +=
          (inTitle > 0 ? 12 : 0) +
          (inHeadings > 0 ? 8 : 0) +
          (inBody < 5 ? inBody : 5);
    }
    if (!matched) continue;
    if (terms.length > 1) {
      if (headings.contains(phrase)) score += 10;
      if (body.contains(phrase)) score += 4;
    }
    if (section.anchor == null) score += title.contains(phrase) ? 15 : 2;
    hits.add(
      DocsHit(
        section: section,
        score: score,
        snippet: _excerpt(proseText(section.markdown), terms),
      ),
    );
  }
  // A stable sort keeps page order among equal scores.
  final ranked = [for (var i = 0; i < hits.length; i++) (i, hits[i])]
    ..sort((a, b) {
      final byScore = b.$2.score.compareTo(a.$2.score);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
  return [for (final (_, hit) in ranked.take(limit)) hit];
}

/// Lowercased text a section is matched against, code included.
String searchableText(String markdown) => markdown
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'[`*>#|]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// Readable prose for snippets: no headings or code blocks, table rows as
/// sentences, inline code kept in backticks.
String proseText(String markdown) {
  final out = <String>[];
  var inFence = false;
  for (var line in markdown.split('\n')) {
    if (RegExp(r'^\s*(```|~~~)').hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence ||
        RegExp(r'^#{1,6}\s').hasMatch(line) ||
        RegExp(r'^\s*\|?\s*:?-{3,}').hasMatch(line)) {
      continue;
    }
    if (RegExp(r'^\s*\|').hasMatch(line)) {
      line = line
          .trim()
          .replaceAll(RegExp(r'^\||\|$'), '')
          .split('|')
          .map((cell) => cell.trim())
          .where((cell) => cell.isNotEmpty)
          .join(', ');
      if (line.isNotEmpty && !RegExp(r'[.!?:]$').hasMatch(line)) line += '.';
    }
    out.add(
      line
          .replaceFirst(RegExp(r'^\s*(?:[-*+]|\d+\.)\s+'), '')
          .replaceFirst(RegExp(r'^\s*>\s?'), ''),
    );
  }
  return out
      .join(' ')
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'\*\*|__'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> _tokens(String query) => query
    .toLowerCase()
    .split(RegExp('[^a-z0-9_]+'))
    .where((t) => t.isNotEmpty)
    .toList();

int _count(String text, String term) =>
    RegExp('(^|[^a-z0-9_])${RegExp.escape(term)}').allMatches(text).length;

String _excerpt(String text, List<String> terms) {
  final lower = text.toLowerCase();
  var at = -1;
  for (final term in terms) {
    at = lower.indexOf(term);
    if (at >= 0) break;
  }
  var start = at < 60 ? 0 : text.lastIndexOf(' ', at - 50) + 1;
  if ('`'.allMatches(text.substring(0, start)).length.isOdd) {
    start = text.lastIndexOf('`', start - 1);
  }
  var end = start + 200 < text.length ? start + 200 : text.length;
  if (end < text.length) {
    final space = text.lastIndexOf(' ', end);
    end = space > start + 120 ? space : end;
  }
  var excerpt = text.substring(start, end);
  if ('`'.allMatches(excerpt).length.isOdd) excerpt += '`';
  return '${start > 0 ? '…' : ''}$excerpt${end < text.length ? '…' : ''}';
}

/// A docs request that failed.
class DocsException implements Exception {
  /// Construct an exception.
  const DocsException(this.message);

  /// What went wrong, as a sentence.
  final String message;

  @override
  String toString() => message;
}

/// Reads the published docs: the section index and each page's Markdown.
class DocsClient {
  /// Construct a client for [origin], or the published docs by default.
  DocsClient({http.Client? httpClient, String? origin})
    : _client = httpClient ?? http.Client(),
      _ownsClient = httpClient == null,
      origin = (origin ?? defaultDocsOrigin).replaceFirst(RegExp(r'/+$'), '');

  /// Builds a client for the docs of the backend at [endpoint].
  factory DocsClient.forBackend(Uri endpoint, {http.Client? httpClient}) =>
      DocsClient(httpClient: httpClient, origin: backendSites(endpoint).docs);

  /// The docs origin, without a trailing slash.
  final String origin;
  final http.Client _client;
  final bool _ownsClient;
  DocsIndex? _index;

  /// The section index, fetched once per client.
  Future<DocsIndex> index() async =>
      _index ??= DocsIndex.parse(await _get('/docs-index.json'));

  /// Ranked sections for [query].
  Future<List<DocsHit>> search(String query, {int limit = 8}) async =>
      searchDocs(await index(), query, limit: limit);

  /// The Markdown for [location]: a site path, a `.md` path or a docs URL.
  /// With a `#anchor`, only that section.
  Future<String> read(String location) async {
    final (path, anchor) = docsPathOf(location, origin: origin);
    if (anchor == null) return _get(path == '/' ? '/index.md' : '$path.md');
    final docs = await index();
    for (final section in docs.sections) {
      if (section.page == path && section.anchor == anchor) {
        return section.markdown;
      }
    }
    throw DocsException('No section #$anchor on $path.');
  }

  Future<String> _get(String path) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$origin$path'),
        headers: const {'Accept': 'text/markdown, application/json'},
      );
    } on Exception catch (error) {
      throw DocsException('Could not reach $origin: ${error.runtimeType}.');
    }
    final status = response.statusCode;
    if (status == 404) {
      throw DocsException(
        'No docs page at $path. Search with `restage docs search`.',
      );
    }
    if (status != 200) throw DocsException('$origin$path returned $status.');
    return utf8.decode(response.bodyBytes);
  }

  /// Releases the HTTP client when this client created it.
  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Normalizes a docs location to a site path and optional anchor:
/// `delivery/hosted-delivery.md`, `/delivery/hosted-delivery#push` and full
/// docs URLs all name the same page.
(String, String?) docsPathOf(
  String location, {
  String origin = defaultDocsOrigin,
}) {
  var value = location.trim();
  for (final prefix in [origin, defaultDocsOrigin]) {
    if (value.startsWith(prefix)) value = value.substring(prefix.length);
  }
  if (RegExp('^[a-z]+://').hasMatch(value)) {
    throw DocsException('$location is not a Restage docs URL.');
  }
  String? anchor;
  final hash = value.indexOf('#');
  if (hash >= 0) {
    anchor = value.substring(hash + 1);
    value = value.substring(0, hash);
    if (anchor.isEmpty) anchor = null;
  }
  value = value.replaceFirst(RegExp(r'\?.*$'), '');
  if (!value.startsWith('/')) value = '/$value';
  value = value
      .replaceFirst(RegExp(r'\.md$'), '')
      .replaceFirst(RegExp(r'/+$'), '');
  if (value.isEmpty || value == '/index') value = '/';
  return (value, anchor);
}
