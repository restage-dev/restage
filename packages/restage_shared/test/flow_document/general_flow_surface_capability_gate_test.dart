import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

/// B0 proof slice (restage_shared half): the delivery-mode marker rides the
/// full delivery envelope, and general-mode is gated as a forward-contract
/// capability requirement — a decoder that does not recognize the marker fails
/// closed rather than mis-rendering a general document.
void main() {
  group('deliveryMode rides the delivery envelope', () {
    test('a general marker survives the SurfaceDocument round-trip', () {
      final screenBytes = Uint8List.fromList([1, 2, 3]);
      final payload = FlowSurfacePayload(
        flowDocument: _generalDoc(screenBytes: screenBytes),
        screenBlobs: {'start': screenBytes},
      );
      final surface = SurfaceDocument(
        surfaceType: Surface.onboarding,
        surfaceSlug: 'welcome',
        version: 1,
        minClient: payload.minClient,
        payload: payload,
        publishedAt: DateTime.utc(2026),
      );

      final decoded =
          SurfaceDocumentCodec.decode(SurfaceDocumentCodec.encode(surface));
      final decodedPayload = decoded.payload as FlowSurfacePayload;

      expect(
        decodedPayload.flowDocument.deliveryMode,
        FlowDeliveryMode.general,
      );
    });
  });

  group('general-mode is a forward-contract capability gate', () {
    // general-mode is gated by the deliveryMode marker as a declared capability
    // requirement. A client that does not implement general-mode fails closed
    // on the marker — this is BY DESIGN (the marker names the capability), not
    // "old clients can't parse the key". These prove the two forward-contract
    // fail-closed paths a current client honors.

    test('an unrecognized deliveryMode value fails closed (capability gate)',
        () {
      // A future delivery mode a current client does not implement: it must
      // fail closed, not silently degrade to a known mode.
      final json = _docJson(_generalDoc(screenBytes: _bytes))
        ..['deliveryMode'] = 'a_future_mode';

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsFormatException,
      );
    });

    test(
        'an unrecognized capability marker key fails closed at decode '
        '(the mechanism that gates a pre-general-mode client)', () {
      // A pre-general-mode decoder's allowed-key set predates the deliveryMode
      // capability marker, so it rejects a document carrying that marker rather
      // than rendering it. The current decoder rejects any unrecognized
      // top-level capability marker the same way — the forward contract.
      final json = _docJson(_generalDoc(screenBytes: _bytes))
        ..['aFutureCapabilityMarker'] = 'x';

      expect(
        () => FlowDocumentCodec.decodeJson(jsonEncode(json)),
        throwsFormatException,
      );
    });
  });
}

final Uint8List _bytes = Uint8List.fromList([1, 2, 3]);

Map<String, Object?> _docJson(FlowDocument document) =>
    jsonDecode(FlowDocumentCodec.encodePrettyJson(document))
        as Map<String, Object?>;

FlowDocument _generalDoc({required Uint8List screenBytes}) {
  return FlowDocument(
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
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: const {
      'start': ScreenFlowState(
        screen: 'start',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
    deliveryMode: FlowDeliveryMode.general,
  );
}
