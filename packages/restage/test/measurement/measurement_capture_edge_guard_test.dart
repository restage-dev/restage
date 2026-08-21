import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ownedEdgeSourcePaths = <String>[
  'lib/src/measurement/measurement_capture_edge.dart',
  'lib/src/measurement/measurement_rfw_presentation.dart',
  'lib/src/measurement/presentation_commit.dart',
  'lib/src/measurement/presentation_commit_hook.dart',
];

const _prohibitedEdgeWork = <String>[
  'MeasurementPublicationRouteCarrierV1.parse',
  'MeasurementPublicationRouteCarrierV1(',
  'CanonicalJsonCodec',
  'CanonicalJson',
  'sha256',
  'hashCode',
  'MeasurementFactFrame',
  'MeasurementIngest',
  'MeasurementRuntimeCaptureSession',
  'MeasurementEventSanitizer',
  'MeasurementOutbox',
  'MeasurementUpload',
  'MeasurementTransport',
  'HttpClient',
  'Socket',
  'Dio',
  'Network',
  'MethodChannel',
  'SharedPreferences',
  'File(',
  'Directory(',
  'dart:async',
  'dart:convert',
  'dart:io',
  'dart:isolate',
  'Future<',
  'Future.',
  'FutureOr',
  'Completer',
  ' async ',
  'async {',
  'async*',
  'await ',
  'Isolate.spawn',
  'Isolate.run',
  'Timer',
  'Stopwatch',
  'DateTime.now',
  'DateTime(',
  'millisecondsSinceEpoch',
  'addPostFrameCallback',
  'Map<',
  'Map.',
  'MapEntry',
  'as Map',
  'jsonEncode',
  'jsonDecode',
  'base64',
];

void main() {
  test('owned capture edge sources stay primitive-only and synchronous', () {
    for (final path in _ownedEdgeSourcePaths) {
      _expectBoundedEdgeSource(path, File(path).readAsStringSync());
    }
  });

  test('RFW presentation resolves compact tokens without the raw sink path',
      () {
    final source = File(
      'lib/src/measurement/measurement_rfw_presentation.dart',
    ).readAsStringSync();
    final start = source.indexOf('Widget _buildMeasurementPresented(');
    final end = source.indexOf(
      'final class _MeasurementRfwPresentationPaintBoundary',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final runtimeCapture = source.substring(start, end);

    expect(runtimeCapture, contains('_validPointTokens(source)'));
    expect(
      runtimeCapture,
      contains('MeasurementRfwPresentationCaptureScope.maybeOf(context)'),
    );
    expect(
      runtimeCapture,
      contains('MeasurementRfwPresentationBinderScope.maybeOf(context)'),
    );
    expect(runtimeCapture, contains('?.bindPresentation('));
    expect(
      runtimeCapture,
      contains('edge.appendPresentationToken(pointToken)'),
    );
    for (final prohibited in <String>[
      'MeasurementRfwPresentationScope.maybeOf',
      'recordPresentedCarrier',
      'MeasurementPublicationRouteCarrierV1',
      'OpaqueMeasurementRouteTokenV1',
      'CanonicalJsonCodec',
      'hashCode',
    ]) {
      expect(
        runtimeCapture,
        isNot(contains(prohibited)),
        reason: 'RFW runtime capture must not reach $prohibited',
      );
    }
  });

  test('the edge constructs a primitive worker record and no legacy session',
      () {
    final source = File(
      'lib/src/measurement/measurement_capture_edge.dart',
    ).readAsStringSync();

    expect(source, contains('MeasurementWorkerAppendRecord('));
    expect(source, contains('routeIndex: identity.routeIndex'));
    expect(source, contains('monotonicTimestampMicros:'));
    expect(source, contains('_monotonicClock.readMicros()'));
    expect(source, contains('value: value'));
    expect(source, contains('_workerSession.append('));
    expect(source, isNot(contains('MeasurementRuntimeCaptureSession')));
    expect(source, isNot(contains('MeasurementWorkerSession.internal')));
    expect(source, isNot(contains('.checkpoint(')));
    expect(source, isNot(contains('.teardown(')));
  });

  test(
      'static controls reject raw, hash, async, wall-clock, and post-frame mutations',
      () {
    final edgePath = 'lib/src/measurement/measurement_capture_edge.dart';
    final edgeSource = File(edgePath).readAsStringSync();
    final presentationPath =
        'lib/src/measurement/measurement_rfw_presentation.dart';
    final presentationSource = File(presentationPath).readAsStringSync();

    for (final mutation in <String>[
      'MeasurementPublicationRouteCarrierV1.parse(compactToken);',
      'identity.hashCode;',
      'await workerSession.checkpoint();',
      'DateTime.now();',
    ]) {
      expect(
        () => _expectBoundedEdgeSource(edgePath, '$edgeSource\n$mutation'),
        throwsA(isA<TestFailure>()),
        reason: 'The guard must reject $mutation',
      );
    }

    expect(
      () => _expectBoundedEdgeSource(
        presentationPath,
        '$presentationSource\nWidgetsBinding.instance.addPostFrameCallback((_) {});',
      ),
      throwsA(isA<TestFailure>()),
      reason: 'The guard must reject post-frame acceptance',
    );
  });

  test('worker-owned interaction lookup never reparses a carrier on the edge',
      () {
    final source = File(
      'lib/src/measurement/measurement_host_construction_owner.dart',
    ).readAsStringSync();
    final start = source.indexOf('void recordInteractionCarrier(');
    final end = source.indexOf(
      '  @override\n  void recordSuccessfulPresentation',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final callbackEdge = source.substring(start, end);
    expect(callbackEdge, contains('_routesByCarrier[rawCarrier]'));
    expect(callbackEdge, contains('appendInteractionIdentity(route.identity)'));
    for (final prohibited in <String>[
      'resolveOpaqueRoute',
      'MeasurementPublicationRouteCarrierV1',
      'MeasurementEventSanitizer',
      'CanonicalJson',
      'sha256',
      'Map<',
      'await ',
      'Http',
      'File(',
      'Directory(',
    ]) {
      expect(callbackEdge, isNot(contains(prohibited)));
    }
  });

  test('capture and binder scope shapes stay fail-closed in product builds',
      () {
    final source = File(
      'lib/src/measurement/measurement_rfw_presentation.dart',
    ).readAsStringSync();
    final captureStart = source.indexOf(
      'final class MeasurementRfwPresentationCaptureScope',
    );
    final binderStart = source.indexOf(
      'final class MeasurementRfwPresentationBinderScope',
    );
    final libraryStart = source.indexOf(
      'LocalWidgetLibrary buildMeasurementRfwPresentationLocalWidgetLibrary',
    );

    expect(captureStart, greaterThanOrEqualTo(0));
    expect(binderStart, greaterThan(captureStart));
    expect(libraryStart, greaterThan(binderStart));
    final captureScope = source.substring(captureStart, binderStart);
    final binderScope = source.substring(binderStart, libraryStart);

    expect(captureScope, contains('required this.edge'));
    expect(captureScope, isNot(contains('this.binder')));
    expect(binderScope, contains('required this.binder'));
    expect(binderScope, isNot(contains('this.edge')));
    expect(source, isNot(contains('assert((edge == null)')));
  });
}

void _expectBoundedEdgeSource(String path, String source) {
  for (final prohibited in _prohibitedEdgeWork) {
    expect(
      source,
      isNot(contains(prohibited)),
      reason: '$path must not reach $prohibited',
    );
  }
}
