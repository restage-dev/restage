import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui/src/a2ui_payload_scan.dart';

void main() {
  const message = {
    'version': '1.0',
    'createSurface': {'surfaceId': 's'},
  };
  test('parses a single v1 message and a flat bundle', () {
    expect(
      parseA2uiV1Messages(message).messages.single,
      isA<CreateSurfaceMessage>(),
    );
    expect(parseA2uiV1Messages([message]).messages, hasLength(1));
    expect(
      parseA2uiV1Messages({
        'messages': [message],
      }).messages,
      hasLength(1),
    );
  });
  test('rejects malformed containers and legacy versions', () {
    for (final payload in <Object?>[
      null,
      'text',
      [null],
      [
        [message],
      ],
      {1: 'value'},
      {'messages': 'not a list'},
      {
        'messages': [message],
        'extra': 1,
      },
      {...message, 'version': 'v0.9'},
    ]) {
      expect(
        () => parseA2uiV1Messages(payload),
        throwsA(anything),
        reason: '$payload',
      );
    }
  });
  test('preserves arbitrary business data without recursive scanning', () {
    final parsed = parseA2uiV1Messages({
      'version': '1.0',
      'updateDataModel': {
        'surfaceId': 's',
        'path': '/data',
        'value': {'id': 'x', 'component': 'NotAWidget', 'path': 'business'},
      },
    });
    expect((parsed.messages.single as UpdateDataModelMessage).value, {
      'id': 'x',
      'component': 'NotAWidget',
      'path': 'business',
    });
  });
}
