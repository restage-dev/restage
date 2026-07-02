import 'dart:convert';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

FlowDocument _doc({FlowDeliveryMode? mode}) => FlowDocument(
      flow: 'welcome',
      version: 1,
      schemaVersion: 1,
      minClient: 1,
      initial: 'start',
      screenArtifacts: {
        'start': ScreenArtifact(
          path: 'start.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          contentHash: FlowContentHash.compute(<int>[1, 2, 3]),
        ),
      },
      states: const {
        'start': ScreenFlowState(screen: 'start', on: {}),
      },
      deliveryMode: mode ?? FlowDeliveryMode.typed,
    );

void main() {
  group('FlowDocument.deliveryMode', () {
    test('defaults to typed when constructed without the field', () {
      expect(
        FlowDocument(
          flow: 'welcome',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          initial: 'start',
          screenArtifacts: _doc().screenArtifacts,
          states: _doc().states,
        ).deliveryMode,
        FlowDeliveryMode.typed,
      );
    });

    test('a general-marked document round-trips through the codec', () {
      final general = _doc(mode: FlowDeliveryMode.general);
      final json = FlowDocumentCodec.encodePrettyJson(general);

      expect(json, contains('"deliveryMode": "general"'));
      expect(
        FlowDocumentCodec.decodeJson(json).deliveryMode,
        FlowDeliveryMode.general,
      );
    });

    test('a typed document OMITS the marker (byte-stable with pre-marker docs)',
        () {
      final typed = _doc();
      final json = FlowDocumentCodec.encodePrettyJson(typed);

      expect(json, isNot(contains('deliveryMode')));
      expect(
        FlowDocumentCodec.decodeJson(json).deliveryMode,
        FlowDeliveryMode.typed,
      );
    });

    test('an absent marker decodes to typed (default-safe forward contract)',
        () {
      final withMarker = jsonDecode(
        FlowDocumentCodec.encodePrettyJson(
          _doc(mode: FlowDeliveryMode.general),
        ),
      ) as Map<String, Object?>;
      expect(withMarker.remove('deliveryMode'), 'general');
      final legacy = const JsonEncoder.withIndent('  ').convert(withMarker);

      expect(
        FlowDocumentCodec.decodeJson('$legacy\n').deliveryMode,
        FlowDeliveryMode.typed,
      );
    });
  });
}
