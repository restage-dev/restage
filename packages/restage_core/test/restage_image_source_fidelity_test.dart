import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readFlutterSource(String relativePath) {
  Directory flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory('${flutterRoot.path}/packages/flutter').existsSync()) {
    final Directory parent = flutterRoot.parent;
    if (parent.path == flutterRoot.path) {
      throw StateError('Could not locate the Flutter SDK source.');
    }
    flutterRoot = parent;
  }
  return File('${flutterRoot.path}/packages/flutter/lib/src/$relativePath')
      .readAsStringSync();
}

String _boundedSource(
  String source, {
  required String start,
  String? end,
  String? after,
}) {
  final int scope = after == null ? 0 : source.indexOf(after);
  if (scope < 0) throw StateError('Missing source scope: $after');
  final int first = source.indexOf(start, scope);
  if (first < 0) throw StateError('Missing source start: $start');
  final int last = end == null ? source.length : source.indexOf(end, first);
  if (last < 0) throw StateError('Missing source end: $end');
  return source.substring(first, last);
}

String _boundedDigest(String source) {
  final List<int> bytes = utf8.encode(source);

  String fnv(Iterable<int> values) {
    int hash = 0x811c9dc5;
    for (final int value in values) {
      hash = ((hash ^ value) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  return '${bytes.length}:${fnv(bytes)}:${fnv(bytes.reversed)}';
}

void main() {
  test('pins the exact native Image and render ownership seams', () {
    final String image = _readFlutterSource('widgets/image.dart');
    expect(
      _boundedDigest(
        _boundedSource(
          image,
          after: 'class _ImageState extends State<Image>',
          start: '  @override\n  Widget build(BuildContext context) {',
          end: '\n  @override\n  void debugFillProperties',
        ),
      ),
      '2422:1d090d63:9d62d0d3',
    );

    final String render = _readFlutterSource('rendering/image.dart');
    expect(
      _boundedDigest(
        _boundedSource(
          render,
          start: '  Size _sizeForConstraints(BoxConstraints constraints) {',
          end: '\n  @override\n  @protected\n  Size computeDryLayout',
        ),
      ),
      '1405:4616b22f:3aa86b8f',
    );

    final String basic = _readFlutterSource('widgets/basic.dart');
    expect(
      _boundedDigest(
        _boundedSource(
          basic,
          after: 'class RawImage extends LeafRenderObjectWidget',
          start:
              '  @override\n  RenderImage createRenderObject(BuildContext context) {',
          end: '\n\n  @override\n  void debugFillProperties',
        ),
      ),
      '2041:2878b395:32300255',
    );
  });

  test('pins the exact private Fade state and animation cluster', () {
    final String fade = _readFlutterSource('widgets/fade_in_image.dart');
    expect(
      _boundedDigest(
        _boundedSource(
          fade,
          start: 'class _FadeInImageState extends State<FadeInImage> {',
        ),
      ),
      '7272:cb20d78c:42bc10be',
    );
  });

  test('pins one native wrapper and the current web-strategy exclusion', () {
    final String bridge = File(
      'lib/src/widgets/restage_image.dart',
    ).readAsStringSync();
    expect(RegExp(r'_replaceNativeLeaf\(').allMatches(bridge), hasLength(2));
    expect(bridge, contains('key: raw.key'));
    expect(
      bridge,
      contains(
        'child: raw is RawImage ? _RestageRawImage.fromRaw(raw) : raw',
      ),
    );

    final String curation =
        File('lib/registry_curation.dart').readAsStringSync();
    expect(curation, contains("'webHtmlElementStrategy',"));
    final String registration =
        File('lib/src/registration.g.dart').readAsStringSync();
    expect(registration, isNot(contains('webHtmlElementStrategy:')));
    expect(registration, contains('return RestageImage.network('));
    expect(registration, contains('return RestageImage.asset('));
    expect(registration, contains('return RestageFadeInImage.assetNetwork('));
  });
}
