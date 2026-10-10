import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_capture_edge.dart';
import 'package:restage/src/measurement/measurement_point_identity.dart';
import 'package:restage/src/measurement/measurement_rfw_presentation.dart';
import 'package:restage/src/measurement/measurement_runtime_capture.dart';
import 'package:restage/src/measurement/measurement_worker.dart';
import 'package:restage_core/library_registration.dart' as restage_core;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _library = LibraryName(<String>['test', 'layout']);

const _tokens = <String>[
  'column',
  'spacerTop',
  'title',
  'expanded',
  'expandedChild',
  'flexible',
  'spacerBottom',
  'button',
  'stack',
  'positioned',
  'positionedChild',
];

void main() {
  testWidgets('presented Flex children keep Spacer, Expanded and Flexible',
      (tester) async {
    final vanilla = await _vanillaFlexRects(tester);
    final harness = _Harness();
    await harness.pump(tester, _flexSource(presentColumn: true));
    expect(tester.takeException(), isNull);

    expect(_rect(tester, 'title'), vanilla['title']);
    expect(_rect(tester, 'expandedChild'), vanilla['expandedChild']);
    expect(_rect(tester, 'flexibleChild'), vanilla['flexibleChild']);
    expect(_rect(tester, 'button'), vanilla['button']);
    expect(_rect(tester, 'button').bottom, _surfaceSize.height);
  });

  testWidgets('presented Stack children keep Positioned', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, _stackSource);

    expect(tester.takeException(), isNull);
    expect(
      _rect(tester, 'positionedChild'),
      const Rect.fromLTWH(10, 20, 30, 40),
    );
  });

  testWidgets('parent-data children report through the enclosing paint',
      (tester) async {
    final harness = _Harness();
    await harness.pump(tester, _flexSource(presentColumn: true));
    await harness.pump(tester, _stackSource);

    expect(tester.takeException(), isNull);
    expect(harness.presentedTokens, containsAll(_tokens));
    expect(harness.presentedTokens,
        hasLength(harness.presentedTokens.toSet().length));
  });

  testWidgets('parent-data children report through the surface root',
      (tester) async {
    final harness = _Harness();
    await harness.pump(tester, _flexSource(presentColumn: false));

    expect(tester.takeException(), isNull);
    expect(_rect(tester, 'button').bottom, _surfaceSize.height);
    expect(
      harness.presentedTokens.toSet(),
      {
        'spacerTop',
        'title',
        'expanded',
        'expandedChild',
        'flexible',
        'spacerBottom',
        'button',
      },
    );
    expect(harness.presentedTokens, hasLength(7));
  });
}

const _surfaceSize = Size(200, 400);

String _compact(String token) => token.padRight(32, '_');

Rect _rect(WidgetTester tester, String label) =>
    tester.getRect(find.text(label));

String _presented(String token, String child) =>
    'MeasurementPresented(carriers: ["$token"], '
    'pointTokens: ["${_compact(token)}"], '
    'child: $child)';

String _box(String label, {double? height}) => 'SizedBox('
    '${height == null ? '' : 'height: $height, '}child: Text(text: "$label"))';

String _flexSource({required bool presentColumn}) {
  final column = '''
Column(crossAxisAlignment: "stretch", children: [
  ${_presented('spacerTop', 'Spacer()')},
  ${_presented('title', _box('title', height: 20))},
  ${_presented('expanded', 'Expanded(flex: 2, child: ${_presented('expandedChild', _box('expandedChild'))})')},
  ${_presented('flexible', 'Flexible(fit: "tight", child: ${_box('flexibleChild', height: 30)})')},
  ${_presented('spacerBottom', 'Spacer()')},
  ${_presented('button', _box('button', height: 48))},
])''';
  return '''
import restage.core;
import restage.measurement;
widget Root = ${presentColumn ? _presented('column', column) : column};
''';
}

final _stackSource = '''
import restage.core;
import restage.measurement;
widget Root = ${_presented('stack', 'Stack(children: [${_presented('positioned', 'Positioned(left: 10.0, top: 20.0, width: 30.0, height: 40.0, child: ${_presented('positionedChild', _box('positionedChild'))})')}])')};
''';

Future<Map<String, Rect>> _vanillaFlexRects(WidgetTester tester) async {
  Widget box(String label, {double? height}) => SizedBox(
        height: height,
        child: Text(label),
      );
  await tester.pumpWidget(
    _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          box('title', height: 20),
          Expanded(flex: 2, child: box('expandedChild')),
          Flexible(fit: FlexFit.tight, child: box('flexibleChild', height: 30)),
          const Spacer(),
          box('button', height: 48),
        ],
      ),
    ),
  );
  return {
    for (final label in ['title', 'expandedChild', 'flexibleChild', 'button'])
      label: _rect(tester, label),
  };
}

Widget _frame(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: _surfaceSize, child: child),
      ),
    );

final class _Harness {
  _Harness() {
    final context = MeasurementMountedArtifactContext(
      artifactGraphHash: CanonicalDigest('a' * 64),
      artifactId: ArtifactId('artifact.layout'),
      artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.layout'),
      measurementManifestHash: CanonicalDigest('b' * 64),
      surfaceRevisionId: SurfaceRevisionId('surface.layout.v1'),
    );
    final table = MeasurementRuntimeRouteTable(
      mountedArtifactContext: context,
      routes: const [],
      presentationRoutes: [
        for (final (index, token) in _tokens.indexed)
          MeasurementRuntimePresentationRouteDeclaration(
            token: OpaqueMeasurementEventSlotToken(token),
            occurrenceId: CanonicalDigest(
              (index + 1).toRadixString(16).padLeft(64, '0'),
            ),
            lineageId: PointLineageId('lineage.layout.${token.toLowerCase()}'),
          ),
      ],
    );
    final identities = MeasurementPointIdentityTable.fromPreboundTokens(
      tokens: [
        for (final token in _tokens)
          MeasurementPreboundPointToken(
            compactToken: _compact(token),
            route: table.resolveOpaqueRoute(
              context: context,
              token: OpaqueMeasurementEventSlotToken(token),
            )!,
          ),
      ],
    );
    _routeTokens = {
      for (final token in _tokens)
        identities.resolve(_compact(token))!.routeIndex: token,
    };
    edge = MeasurementCaptureEdge(
      pointIdentityTable: identities,
      workerSession: MeasurementWorkerSession.internal(
        _RecordingSession(_appended),
        'session.layout',
      ),
      monotonicClock: _Clock(),
    );
  }

  late final MeasurementCaptureEdge edge;
  late final Map<int, String> _routeTokens;
  final _appended = <MeasurementWorkerAppendRecord>[];

  List<String> get presentedTokens => [
        for (final record in _appended)
          if (record.value == MeasurementWorkerAppendValue.presentation)
            _routeTokens[record.routeIndex]!,
      ];

  Future<void> pump(WidgetTester tester, String source) async {
    final runtime = Runtime()
      ..update(
        const LibraryName(<String>['restage', 'core']),
        restage_core.buildCoreWidgetLibrary(),
      )
      ..update(
        kMeasurementRfwPresentationLibrary,
        buildMeasurementRfwPresentationLocalWidgetLibrary(),
      )
      ..update(_library, parseLibraryFile(source));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(
      _frame(
        MeasurementRfwPresentationBinderScope(
          binder: _Binder(edge),
          child: RemoteWidget(
            key: UniqueKey(),
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_library, 'Root'),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

final class _Binder implements MeasurementRfwPresentationCaptureBinder {
  const _Binder(this._edge);

  final MeasurementCaptureEdge _edge;

  @override
  MeasurementCaptureEdge? bindPresentation({
    required List<String> pointTokens,
    required List<String> routeCarriers,
  }) =>
      _edge;
}

final class _RecordingSession implements MeasurementWorkerSessionState {
  _RecordingSession(this._records);

  final List<MeasurementWorkerAppendRecord> _records;

  @override
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) {
    _records.add(record);
    return MeasurementWorkerAppendOutcome.accepted;
  }

  @override
  Future<MeasurementWorkerBatchResult> checkpoint({int? frameElapsedMicros}) =>
      throw UnimplementedError();

  @override
  Future<MeasurementWorkerBatchResult> teardown({int? frameElapsedMicros}) =>
      throw UnimplementedError();
}

final class _Clock implements MeasurementCaptureMonotonicClock {
  var _micros = 0;

  @override
  int readMicros() => _micros++;
}
