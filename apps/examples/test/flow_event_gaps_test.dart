import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/restage_shared.dart';

const _bundleRoot = 'assets/restage/bundles';

/// Every compiled flow outside a paywall, with its screens: a flow's own
/// bundle first, then the bundles that carry its screens.
Map<String, FlowSurfacePayload> _compiledFlows() {
  final bundles = [
    for (final file in Directory(_bundleRoot).listSync(recursive: true))
      if (file is File && file.path.endsWith('.rsbundle'))
        RestageBundleCodec.decode(file.readAsBytesSync()),
  ];
  final shared = <String, Uint8List>{
    for (final bundle in bundles)
      for (final entry in bundle.entries) entry.logicalPath: entry.bytes,
  };
  final flows = <String, FlowSurfacePayload>{};
  for (final bundle in bundles) {
    final own = {
      for (final entry in bundle.entries) entry.logicalPath: entry.bytes,
    };
    for (final MapEntry(key: path, value: bytes) in own.entries) {
      final match =
          RegExp(r'^assets/(\w+)/flows/[^/]+\.flow\.json$').firstMatch(path);
      if (match == null) continue;
      final document = FlowDocumentCodec.decodeJson(utf8.decode(bytes));
      final screens = <String, Uint8List>{};
      for (final MapEntry(key: id, value: artifact)
          in document.screenArtifacts.entries) {
        final screenPath = isPaywallScreenArtifact(artifact.path)
            ? '$kPaywallScreensAssetDir/${artifact.path}'
            : 'assets/${match.group(1)}/screens/${artifact.path}';
        final blob = own[screenPath] ?? shared[screenPath];
        if (blob == null) fail('$path: no compiled screen at $screenPath');
        screens[id] = blob;
      }
      flows[path] = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: screens,
      );
    }
  }
  return flows;
}

void main() {
  test('every example flow handles every event its screens emit', () {
    final flows = _compiledFlows();
    expect(flows, isNotEmpty);
    final gaps = {
      for (final MapEntry(key: path, value: payload) in flows.entries)
        if (flowScreenEventGaps(payload) case final found when found.isNotEmpty)
          path: [for (final gap in found) '$gap'],
    };
    expect(gaps, isEmpty);
  });
}
