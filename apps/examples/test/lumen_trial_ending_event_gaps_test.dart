import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('every trial-ending screen event is handled by its flow', () {
    final entries = [
      for (final bundle in const [
        'surfaces/lumen_trial_ending_flow',
        'surfaces/lumen_trial_ending',
        'paywalls/lumen_welcome_offer',
      ])
        ...RestageBundleCodec.decode(
          File('assets/restage/bundles/lib/$bundle.rsbundle').readAsBytesSync(),
        ).entries,
    ];
    Uint8List bytes(String suffix) => Uint8List.fromList(
          entries
              .singleWhere((entry) => entry.logicalPath.endsWith(suffix))
              .bytes,
        );
    final document = FlowDocumentCodec.decodeJson(
      utf8.decode(bytes('/lumen_trial_offer.flow.json')),
    );
    final payload = FlowSurfacePayload(
      flowDocument: document,
      screenBlobs: {
        for (final MapEntry(:key, :value) in document.screenArtifacts.entries)
          key: bytes('/${value.path}'),
      },
    );

    expect(
      document.outbound.customEvents.keys,
      unorderedEquals(['privacy', 'terms', 'restore_purchases']),
    );
    expect(flowScreenEventGaps(payload), isEmpty);
  });
}
