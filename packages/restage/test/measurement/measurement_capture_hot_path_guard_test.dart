import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the admitted capture sub-entry stays handle-only and O(1)', () {
    final source = File(
      'lib/src/measurement/measurement_runtime_capture.dart',
    ).readAsStringSync();
    final start = source.indexOf('MeasurementCaptureWriteDisposition _record(');
    final end = source.indexOf('MeasurementMissingnessWriteDisposition', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final hotPath = source.substring(start, end);

    expect(source, contains('Uint32List? _slotStates'));
    expect(
      source,
      contains('_slotStates = Uint32List(routeTable._routeCount)'),
    );
    expect(source, isNot(contains('final class _MeasurementFactSlot')));
    expect(hotPath, contains('identical(route._owner, routeTable._owner)'));
    expect(hotPath, contains('final originalSlotState = slotStates[index]'));
    expect(hotPath, contains('_measurementSlotPresentedFlag'));
    expect(hotPath, contains('_measurementSlotHasInteractionCounterFlag'));
    expect(hotPath, contains('_measurementSlotInteractionCountMask'));
    expect(hotPath, contains('bounds.maximumPresentedPoints'));
    expect(hotPath, contains('bounds.maximumInteractionCounters'));

    for (final prohibited in <String>[
      'CanonicalJsonCodec',
      'Map<',
      'Timer',
      'async',
      'await',
      'dart:io',
      'sha256',
      'scheduleMicrotask',
      'eventName',
      'arguments',
      'measurement_capture_capability',
      'legacy',
      'dualWrite',
    ]) {
      expect(
        hotPath,
        isNot(contains(prohibited)),
        reason: 'The capture sub-entry must not reach $prohibited',
      );
    }
  });
}
