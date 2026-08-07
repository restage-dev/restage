import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';

class _BadLayoutResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    // References a widget that isn't registered in any library, which causes
    // RFW to throw at build time.
    const source = '''
      import restage.core;
      widget Paywall = NonExistentWidget();
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
    return ResolvedVariant(bytes: bytes, paywallId: id);
  }
}

class _TextResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    const source = '''
      import restage.core;
      widget Paywall = Text(text: "Ready");
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
    return ResolvedVariant(bytes: bytes, paywallId: id);
  }
}

class _ReportOnDispose extends StatefulWidget {
  const _ReportOnDispose({required this.message});

  final String message;

  @override
  State<_ReportOnDispose> createState() => _ReportOnDisposeState();
}

class _ReportOnDisposeState extends State<_ReportOnDispose> {
  @override
  void dispose() {
    _reportTestFlutterError(widget.message);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ThrowOnBuild extends StatelessWidget {
  const _ThrowOnBuild();

  @override
  Widget build(BuildContext context) => throw StateError('same-frame boom');
}

final class _PaintOrderProbe extends LeafRenderObjectWidget {
  const _PaintOrderProbe(this.events);

  final List<String> events;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintOrderProbe(events);
}

final class _RenderPaintOrderProbe extends RenderBox {
  _RenderPaintOrderProbe(this.events);

  final List<String> events;

  @override
  void performLayout() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    events.add('paint');
  }
}

final class _ThrowDuringLayout extends LeafRenderObjectWidget {
  const _ThrowDuringLayout();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ThrowingLayoutRenderBox();
}

final class _ThrowingLayoutRenderBox extends RenderBox {
  @override
  void performLayout() => throw StateError('layout failed');
}

final class _ThrowDuringPaint extends LeafRenderObjectWidget {
  const _ThrowDuringPaint();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ThrowingPaintRenderBox();
}

final class _ThrowingPaintRenderBox extends RenderBox {
  @override
  void performLayout() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    throw StateError('paint failed');
  }
}

enum _StructuralReportPhase { layout, paint }

final class _StructuralReportController extends ChangeNotifier {
  _StructuralReportController({this.revision = 0});

  int revision;

  void trigger() {
    revision += 1;
    notifyListeners();
  }
}

final class _StructuralReportProbe extends LeafRenderObjectWidget {
  const _StructuralReportProbe({
    required this.controller,
    required this.phase,
    this.onPaint,
  });

  final _StructuralReportController controller;
  final _StructuralReportPhase phase;
  final VoidCallback? onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStructuralReportProbe(controller, phase, onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStructuralReportProbe renderObject,
  ) {
    renderObject
      ..controller = controller
      ..phase = phase
      ..onPaint = onPaint;
  }
}

final class _RenderStructuralReportProbe extends RenderBox {
  _RenderStructuralReportProbe(
    _StructuralReportController controller,
    this._phase,
    this.onPaint,
  )   : _controller = controller,
        _reportedRevision = controller.revision == 0 ? 0 : -1;

  _StructuralReportController _controller;
  _StructuralReportPhase _phase;
  int _reportedRevision;
  VoidCallback? onPaint;

  set controller(_StructuralReportController value) {
    if (identical(_controller, value)) return;
    if (attached) _controller.removeListener(_markDirty);
    _controller = value;
    _reportedRevision = value.revision;
    if (attached) _controller.addListener(_markDirty);
  }

  set phase(_StructuralReportPhase value) {
    if (_phase == value) return;
    _phase = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => _phase == _StructuralReportPhase.paint;

  @override
  bool get sizedByParent => _phase == _StructuralReportPhase.layout;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_markDirty);
  }

  @override
  void detach() {
    _controller.removeListener(_markDirty);
    super.detach();
  }

  void _markDirty() {
    switch (_phase) {
      case _StructuralReportPhase.layout:
        markNeedsLayout();
        return;
      case _StructuralReportPhase.paint:
        markNeedsPaint();
        return;
    }
  }

  @override
  void performResize() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void performLayout() {
    if (!sizedByParent) {
      size = constraints.constrain(const Size.square(20));
    }
    if (_phase == _StructuralReportPhase.layout) _reportIfTriggered();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_phase == _StructuralReportPhase.paint) _reportIfTriggered();
    onPaint?.call();
  }

  void _reportIfTriggered() {
    if (_reportedRevision == _controller.revision) return;
    _reportedRevision = _controller.revision;
    FlutterError.reportError(_ownedFlutterErrorDetails(
      this,
      message: '${_phase.name} structurally owned report',
    ));
  }
}

class _FlutterErrorRecorder {
  _FlutterErrorRecorder() : _originalOnError = FlutterError.onError {
    FlutterError.onError = reports.add;
  }

  final void Function(FlutterErrorDetails details)? _originalOnError;
  final List<FlutterErrorDetails> reports = <FlutterErrorDetails>[];

  void restore() {
    FlutterError.onError = _originalOnError;
  }
}

FlutterErrorDetails _testFlutterErrorDetails(String message) =>
    FlutterErrorDetails(
      exception: StateError(message),
      stack: StackTrace.current,
      library: 'restage_flutter_sdk_test',
    );

FlutterErrorDetails _ownedFlutterErrorDetails(
  RenderObject renderObject, {
  required String message,
  InformationCollector? informationCollector,
}) =>
    FlutterErrorDetails(
      exception: StateError(message),
      stack: StackTrace.current,
      library: 'restage_flutter_sdk_test',
      informationCollector: informationCollector ??
          () => <DiagnosticsNode>[
                DiagnosticsProperty<RenderObject>('renderObject', renderObject),
              ],
    );

FlutterErrorDetails _reportTestFlutterError(String message) {
  final details = _testFlutterErrorDetails(message);
  FlutterError.reportError(details);
  return details;
}

Future<void> _pumpReadyPaywall(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RestagePaywall(
        id: 'ok',
        resolver: _TextResolver(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Restage.debugReset());

  testWidgets(
      'a same-frame descendant throw reports once and never acknowledges '
      'first-build success', (tester) async {
    var successes = 0;
    var paintSuccesses = 0;
    var errors = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstBuildSuccess: () => successes += 1,
        onFirstPaintSuccess: () => paintSuccesses += 1,
        onError: (_, __) => errors += 1,
        errorReplacement: (_, __, ___) => const SizedBox.shrink(),
        child: const _ThrowOnBuild(),
      ),
    ));
    await tester.pump();

    final escaped = tester.takeException();
    final observed = (
      successes: successes,
      paintSuccesses: paintSuccesses,
      errors: errors,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(escaped, isNull);
    expect(observed, (successes: 0, paintSuccesses: 0, errors: 1));
  });

  testWidgets('first-paint success runs after descendant paint exactly once',
      (tester) async {
    final events = <String>[];

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstBuildSuccess: () => events.add('buildSuccess'),
        onFirstPaintSuccess: () => events.add('paintSuccess'),
        onError: (_, __) => events.add('error'),
        errorReplacement: (_, __, ___) => const SizedBox.shrink(),
        child: _PaintOrderProbe(events),
      ),
    ));
    await tester.pump();

    expect(events, containsAllInOrder(<String>['paint', 'paintSuccess']));
    expect(events.where((event) => event == 'buildSuccess'), hasLength(1));
    expect(events.where((event) => event == 'paintSuccess'), hasLength(1));
    expect(events, isNot(contains('error')));
  });

  testWidgets('existing first-build success remains independent and unchanged',
      (tester) async {
    var buildSuccesses = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstBuildSuccess: () => buildSuccesses += 1,
        onError: (_, __) {},
        errorReplacement: (_, __, ___) => const SizedBox.shrink(),
        child: const SizedBox.square(dimension: 20),
      ),
    ));
    await tester.pump();

    expect(buildSuccesses, 1);
  });

  testWidgets('stale queued paint callback is suppressed after widget update',
      (tester) async {
    final callbacks = <String>[];
    final paints = <String>[];

    Widget buildBoundary(VoidCallback onFirstPaintSuccess) => Directionality(
          textDirection: TextDirection.ltr,
          child: Offstage(
            child: RuntimeErrorBoundary(
              onFirstPaintSuccess: onFirstPaintSuccess,
              onError: (_, __) {},
              errorReplacement: (_, __, ___) => const SizedBox.shrink(),
              child: _PaintOrderProbe(paints),
            ),
          ),
        );

    await tester.pumpWidget(
      buildBoundary(() => callbacks.add('stale')),
    );
    _paintBoundaryProbe(tester);
    await tester.pumpWidget(
      buildBoundary(() => callbacks.add('current')),
    );
    await tester.pump();

    final observed = List<String>.of(callbacks);
    final observedPaints = List<String>.of(paints);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed, isEmpty);
    expect(observedPaints, <String>['paint']);
  });

  testWidgets('disposed boundary suppresses a queued paint callback',
      (tester) async {
    var callbacks = 0;
    final paints = <String>[];

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Offstage(
        child: RuntimeErrorBoundary(
          onFirstPaintSuccess: () => callbacks += 1,
          onError: (_, __) {},
          errorReplacement: (_, __, ___) => const SizedBox.shrink(),
          child: _PaintOrderProbe(paints),
        ),
      ),
    ));
    _paintBoundaryProbe(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(callbacks, 0);
  });

  testWidgets('layout failure reports once and never reports paint success',
      (tester) async {
    var paintSuccesses = 0;
    var errors = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () => paintSuccesses += 1,
        onError: (_, __) => errors += 1,
        errorReplacement: (_, __, ___) => const SizedBox.shrink(),
        child: const _ThrowDuringLayout(),
      ),
    ));
    await tester.pump();
    await tester.pump();

    final escaped = tester.takeException();
    final observed = (errors: errors, paintSuccesses: paintSuccesses);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(escaped, isNull);
    expect(observed, (errors: 1, paintSuccesses: 0));
  });

  testWidgets('paint failure reports once and never reports paint success',
      (tester) async {
    var paintSuccesses = 0;
    var errors = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () => paintSuccesses += 1,
        onError: (_, __) => errors += 1,
        errorReplacement: (_, __, ___) => const SizedBox.shrink(),
        child: const _ThrowDuringPaint(),
      ),
    ));
    await tester.pump();
    await tester.pump();

    final escaped = tester.takeException();
    final observed = (errors: errors, paintSuccesses: paintSuccesses);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(escaped, isNull);
    expect(observed, (errors: 1, paintSuccesses: 0));
  });

  testWidgets(
      'owned recoverable paint report draws but fails closed exactly once',
      (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);
    final controller = _StructuralReportController(revision: 1);
    addTearDown(controller.dispose);
    var paints = 0;
    var errors = 0;
    var paintSuccesses = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () => paintSuccesses += 1,
        onError: (_, __) => errors += 1,
        errorReplacement: (_, __, ___) => const Text('owned fallback'),
        child: _StructuralReportProbe(
          controller: controller,
          phase: _StructuralReportPhase.paint,
          onPaint: () => paints += 1,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    final fallbackFound = find.text('owned fallback').evaluate().length;
    final delegated = List<FlutterErrorDetails>.of(flutterErrors.reports);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    flutterErrors.restore();

    expect(paints, 1);
    expect(errors, 1);
    expect(paintSuccesses, 0);
    expect(delegated, isEmpty);
    expect(fallbackFound, 1);
  });

  testWidgets('genuine RenderFlex overflow fails closed exactly once',
      (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);
    var errors = 0;
    var paintSuccesses = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: RuntimeErrorBoundary(
            onFirstPaintSuccess: () => paintSuccesses += 1,
            onError: (_, __) => errors += 1,
            errorReplacement: (_, __, ___) => const Text('overflow fallback'),
            child: const Row(
              children: <Widget>[
                SizedBox(width: 200, height: 20),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    final escaped = tester.takeException();
    final fallbackFound = find.text('overflow fallback').evaluate().length;
    final delegated = List<FlutterErrorDetails>.of(flutterErrors.reports);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    flutterErrors.restore();

    expect(escaped, isNull);
    expect(errors, 1);
    expect(paintSuccesses, 0);
    expect(delegated, isEmpty);
    expect(fallbackFound, 1);
  });

  testWidgets(
      'unowned report delegates once with the identical details while preview '
      'is mounted', (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () {},
        onError: (_, __) {},
        errorReplacement: (_, __, ___) => const SizedBox.shrink(),
        child: const SizedBox.square(dimension: 20),
      ),
    ));
    final details = _reportTestFlutterError('outside mounted preview');
    await tester.pump();

    final delegated = List<FlutterErrorDetails>.of(flutterErrors.reports);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    flutterErrors.restore();

    expect(delegated, hasLength(1));
    expect(delegated.single, same(details));
  });

  testWidgets(
      'layout-time inner build claim prevents the outer paint boundary from '
      'stealing ownership', (tester) async {
    var outerErrors = 0;
    var innerErrors = 0;
    var outerPaintSuccesses = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () => outerPaintSuccesses += 1,
        onError: (_, __) => outerErrors += 1,
        errorReplacement: (_, __, ___) => const Text('outer fallback'),
        child: RuntimeErrorBoundary(
          onError: (_, __) => innerErrors += 1,
          errorReplacement: (_, __, ___) => const Text('inner fallback'),
          child: LayoutBuilder(
            builder: (_, __) => throw StateError('layout-time build failure'),
          ),
        ),
      ),
    ));
    await tester.pump();

    final escaped = tester.takeException();
    final innerFallbacks = find.text('inner fallback').evaluate().length;
    final outerFallbacks = find.text('outer fallback').evaluate().length;
    final observed = (
      innerErrors: innerErrors,
      outerErrors: outerErrors,
      outerPaintSuccesses: outerPaintSuccesses,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(escaped, isNull);
    expect(
      observed,
      (innerErrors: 1, outerErrors: 0, outerPaintSuccesses: 1),
    );
    expect(innerFallbacks, 1);
    expect(outerFallbacks, 0);
  });

  testWidgets('late independent repaint report terminates the owning boundary',
      (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);
    final controller = _StructuralReportController();
    addTearDown(controller.dispose);
    var errors = 0;
    var paintSuccesses = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () => paintSuccesses += 1,
        onError: (_, __) => errors += 1,
        errorReplacement: (_, __, ___) => const Text('repaint fallback'),
        child: _StructuralReportProbe(
          controller: controller,
          phase: _StructuralReportPhase.paint,
        ),
      ),
    ));
    await tester.pump();
    expect(paintSuccesses, 1);

    controller.trigger();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final fallbackFound = find.text('repaint fallback').evaluate().length;
    final delegated = List<FlutterErrorDetails>.of(flutterErrors.reports);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    flutterErrors.restore();

    expect(errors, 1);
    expect(paintSuccesses, 1);
    expect(delegated, isEmpty);
    expect(fallbackFound, 1);
  });

  testWidgets('late independent relayout report terminates the owning boundary',
      (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);
    final controller = _StructuralReportController();
    addTearDown(controller.dispose);
    var errors = 0;
    var paintSuccesses = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () => paintSuccesses += 1,
        onError: (_, __) => errors += 1,
        errorReplacement: (_, __, ___) => const Text('relayout fallback'),
        child: _StructuralReportProbe(
          controller: controller,
          phase: _StructuralReportPhase.layout,
        ),
      ),
    ));
    await tester.pump();
    expect(paintSuccesses, 1);

    controller.trigger();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final fallbackFound = find.text('relayout fallback').evaluate().length;
    final delegated = List<FlutterErrorDetails>.of(flutterErrors.reports);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    flutterErrors.restore();

    expect(errors, 1);
    expect(paintSuccesses, 1);
    expect(delegated, isEmpty);
    expect(fallbackFound, 1);
  });

  testWidgets('nested paint boundaries attribute a late report to nearest only',
      (tester) async {
    final controller = _StructuralReportController();
    addTearDown(controller.dispose);
    var outerErrors = 0;
    var innerErrors = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () {},
        onError: (_, __) => outerErrors += 1,
        errorReplacement: (_, __, ___) => const Text('outer fallback'),
        child: RuntimeErrorBoundary(
          onFirstPaintSuccess: () {},
          onError: (_, __) => innerErrors += 1,
          errorReplacement: (_, __, ___) => const Text('inner fallback'),
          child: _StructuralReportProbe(
            controller: controller,
            phase: _StructuralReportPhase.paint,
          ),
        ),
      ),
    ));
    await tester.pump();

    controller.trigger();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final innerFallbacks = find.text('inner fallback').evaluate().length;
    final outerFallbacks = find.text('outer fallback').evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(innerErrors, 1);
    expect(outerErrors, 0);
    expect(innerFallbacks, 1);
    expect(outerFallbacks, 0);
  });

  testWidgets(
      'stale structural report callback is suppressed after replacement and '
      'dispose', (tester) async {
    final staleErrors = <String>[];
    final controller = _StructuralReportController();
    addTearDown(controller.dispose);

    Widget boundary(ValueChanged<String> onError) => Directionality(
          textDirection: TextDirection.ltr,
          child: RuntimeErrorBoundary(
            onFirstPaintSuccess: () {},
            onError: (error, _) => onError(error.toString()),
            errorReplacement: (_, __, ___) => const SizedBox.shrink(),
            child: _StructuralReportProbe(
              controller: controller,
              phase: _StructuralReportPhase.paint,
            ),
          ),
        );

    await tester.pumpWidget(boundary((_) => staleErrors.add('stale')));
    await tester.pump();
    final firstRenderObject = tester.renderObject<RenderObject>(
      find.byType(_StructuralReportProbe),
    );
    FlutterError.reportError(_ownedFlutterErrorDetails(
      firstRenderObject,
      message: 'stale replacement report',
    ));
    await tester.pumpWidget(boundary((_) => staleErrors.add('current')));
    await tester.pump();
    expect(staleErrors, isEmpty);

    final currentRenderObject = tester.renderObject<RenderObject>(
      find.byType(_StructuralReportProbe),
    );
    FlutterError.reportError(_ownedFlutterErrorDetails(
      currentRenderObject,
      message: 'stale dispose report',
    ));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(staleErrors, isEmpty);
  });

  testWidgets(
      'duplicate typed evidence owns once while ambiguous unrelated markers '
      'delegate', (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);
    var leftErrors = 0;
    var rightErrors = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: <Widget>[
          RuntimeErrorBoundary(
            key: const ValueKey<String>('left-boundary'),
            onFirstPaintSuccess: () {},
            onError: (_, __) => leftErrors += 1,
            errorReplacement: (_, __, ___) => const SizedBox.shrink(),
            child: const SizedBox.square(
              key: ValueKey<String>('left'),
              dimension: 20,
            ),
          ),
          RuntimeErrorBoundary(
            key: const ValueKey<String>('right-boundary'),
            onFirstPaintSuccess: () {},
            onError: (_, __) => rightErrors += 1,
            errorReplacement: (_, __, ___) => const SizedBox.shrink(),
            child: const SizedBox.square(
              key: ValueKey<String>('right'),
              dimension: 20,
            ),
          ),
        ],
      ),
    ));
    await tester.pump();
    final left = tester.renderObject<RenderObject>(
      find.byKey(const ValueKey<String>('left')),
    );
    final duplicate = _ownedFlutterErrorDetails(
      left,
      message: 'duplicate structural evidence',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<RenderObject>('first', left),
        DiagnosticsProperty<RenderObject>('duplicate', left),
      ],
    );
    FlutterError.reportError(duplicate);
    await tester.pump();
    await tester.pump();

    final duplicateObserved = (
      leftErrors: leftErrors,
      rightErrors: rightErrors,
      delegated: List<FlutterErrorDetails>.of(flutterErrors.reports),
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: <Widget>[
          RuntimeErrorBoundary(
            key: const ValueKey<String>('left-current-boundary'),
            onFirstPaintSuccess: () {},
            onError: (_, __) => leftErrors += 1,
            errorReplacement: (_, __, ___) => const SizedBox.shrink(),
            child: const SizedBox.square(
              key: ValueKey<String>('left-current'),
              dimension: 20,
            ),
          ),
          RuntimeErrorBoundary(
            key: const ValueKey<String>('right-current-boundary'),
            onFirstPaintSuccess: () {},
            onError: (_, __) => rightErrors += 1,
            errorReplacement: (_, __, ___) => const SizedBox.shrink(),
            child: const SizedBox.square(
              key: ValueKey<String>('right-current'),
              dimension: 20,
            ),
          ),
        ],
      ),
    ));
    await tester.pump();
    final leftCurrent = tester.renderObject<RenderObject>(
      find.byKey(const ValueKey<String>('left-current')),
    );
    final rightCurrent = tester.renderObject<RenderObject>(
      find.byKey(const ValueKey<String>('right-current')),
    );
    final ambiguous = _ownedFlutterErrorDetails(
      leftCurrent,
      message: 'ambiguous structural evidence',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<RenderObject>('left', leftCurrent),
        DiagnosticsProperty<RenderObject>('right', rightCurrent),
      ],
    );
    FlutterError.reportError(ambiguous);
    await tester.pump();

    final delegated = List<FlutterErrorDetails>.of(flutterErrors.reports);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    flutterErrors.restore();

    expect(duplicateObserved.leftErrors, 1);
    expect(duplicateObserved.rightErrors, 0);
    expect(duplicateObserved.delegated, isEmpty);
    expect(leftErrors, 1);
    expect(rightErrors, 0);
    expect(delegated, hasLength(1));
    expect(delegated.single, same(ambiguous));
  });

  testWidgets(
      'throwing and recursive collectors delegate originals without partial '
      'ownership', (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);
    var errors = 0;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onFirstPaintSuccess: () {},
        onError: (_, __) => errors += 1,
        errorReplacement: (_, __, ___) => const SizedBox.shrink(),
        child: const SizedBox.square(
          key: ValueKey<String>('collector-child'),
          dimension: 20,
        ),
      ),
    ));
    await tester.pump();
    final renderObject = tester.renderObject<RenderObject>(
      find.byKey(const ValueKey<String>('collector-child')),
    );
    final throwing = _ownedFlutterErrorDetails(
      renderObject,
      message: 'throwing collector',
      informationCollector: () => throw StateError('collector failed'),
    );
    FlutterError.reportError(throwing);
    await tester.pump();

    final recursive = _testFlutterErrorDetails('recursive collector report');
    final outer = _ownedFlutterErrorDetails(
      renderObject,
      message: 'outer recursive collector',
      informationCollector: () {
        FlutterError.reportError(recursive);
        return <DiagnosticsNode>[
          DiagnosticsProperty<RenderObject>('renderObject', renderObject),
        ];
      },
    );
    FlutterError.reportError(outer);
    await tester.pump();

    final delegated = List<FlutterErrorDetails>.of(flutterErrors.reports);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    flutterErrors.restore();

    expect(errors, 0);
    expect(delegated.length, 3);
    expect(
      (
        throwing: identical(delegated[0], throwing),
        recursive: identical(delegated[1], recursive),
        outer: identical(delegated[2], outer),
      ),
      (throwing: true, recursive: true, outer: true),
    );
  });

  testWidgets(
      'global handlers remain installed until the last boundary unmounts',
      (tester) async {
    final originalOnError = FlutterError.onError;
    final originalBuilder = ErrorWidget.builder;
    void previousOnError(FlutterErrorDetails details) {}
    Widget previousBuilder(FlutterErrorDetails details) =>
        const SizedBox.shrink();
    FlutterError.onError = previousOnError;
    ErrorWidget.builder = previousBuilder;
    addTearDown(() {
      FlutterError.onError = originalOnError;
      ErrorWidget.builder = originalBuilder;
    });

    Widget boundaries(List<String> ids) => Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: <Widget>[
              for (final id in ids)
                RuntimeErrorBoundary(
                  key: ValueKey<String>(id),
                  onError: (_, __) {},
                  errorReplacement: (_, __, ___) => const SizedBox.shrink(),
                  child: const SizedBox.square(dimension: 20),
                ),
            ],
          ),
        );

    await tester.pumpWidget(boundaries(<String>['left', 'right']));
    final installedOnError = FlutterError.onError;
    final installedBuilder = ErrorWidget.builder;

    await tester.pumpWidget(boundaries(<String>['left']));
    final afterFirstUnmount = (
      onError: FlutterError.onError,
      builder: ErrorWidget.builder,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final afterLastUnmount = (
      onError: FlutterError.onError,
      builder: ErrorWidget.builder,
    );
    FlutterError.onError = originalOnError;
    ErrorWidget.builder = originalBuilder;

    expect(identical(installedOnError, previousOnError), isFalse);
    expect(identical(installedBuilder, previousBuilder), isFalse);
    expect(identical(afterFirstUnmount.onError, installedOnError), isTrue);
    expect(identical(afterFirstUnmount.builder, installedBuilder), isTrue);
    expect(identical(afterLastUnmount.onError, previousOnError), isTrue);
    expect(identical(afterLastUnmount.builder, previousBuilder), isTrue);
  });

  testWidgets('teardown preserves externally replaced global handlers',
      (tester) async {
    final originalOnError = FlutterError.onError;
    final originalBuilder = ErrorWidget.builder;
    void previousOnError(FlutterErrorDetails details) {}
    Widget previousBuilder(FlutterErrorDetails details) =>
        const SizedBox.shrink();
    void externalOnError(FlutterErrorDetails details) {}
    Widget externalBuilder(FlutterErrorDetails details) =>
        const SizedBox.shrink();
    FlutterError.onError = previousOnError;
    ErrorWidget.builder = previousBuilder;
    addTearDown(() {
      FlutterError.onError = originalOnError;
      ErrorWidget.builder = originalBuilder;
    });

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RuntimeErrorBoundary(
        onError: (_, __) {},
        errorReplacement: (_, __, ___) => const SizedBox.shrink(),
        child: const SizedBox.square(dimension: 20),
      ),
    ));
    FlutterError.onError = externalOnError;
    ErrorWidget.builder = externalBuilder;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final afterUnmount = (
      onError: FlutterError.onError,
      builder: ErrorWidget.builder,
    );
    FlutterError.onError = originalOnError;
    ErrorWidget.builder = originalBuilder;

    expect(identical(afterUnmount.onError, externalOnError), isTrue);
    expect(identical(afterUnmount.builder, externalBuilder), isTrue);
  });

  testWidgets('subtree exceptions are caught; errorBuilder is invoked',
      (tester) async {
    var errorBuilderHit = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'ouch',
          resolver: _BadLayoutResolver(),
          errorBuilder: (_, __) {
            errorBuilderHit = true;
            return const Text('Caught');
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // No FlutterError should escape:
    expect(tester.takeException(), isNull);
    expect(errorBuilderHit, isTrue);
  });

  testWidgets(
      'unrelated Flutter errors are delegated while boundary is mounted',
      (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);

    await _pumpReadyPaywall(tester);

    _reportTestFlutterError('outside runtime boundary');
    await tester.pump();
    final reportedCount = flutterErrors.reports.length;
    final reportedException = flutterErrors.reports.isEmpty
        ? null
        : flutterErrors.reports.single.exception;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    flutterErrors.restore();

    expect(reportedCount, 1);
    expect(reportedException, isA<StateError>());
  });

  testWidgets('unrelated Flutter errors delegate after boundary teardown',
      (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);

    await _pumpReadyPaywall(tester);

    _reportTestFlutterError('outside runtime boundary before teardown');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    flutterErrors.restore();

    expect(flutterErrors.reports.length, 1);
    expect(flutterErrors.reports.single.exception, isA<StateError>());
  });

  testWidgets('unrelated dispose-time errors delegate during boundary teardown',
      (tester) async {
    final flutterErrors = _FlutterErrorRecorder();
    addTearDown(flutterErrors.restore);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const _ReportOnDispose(message: 'outside boundary during teardown'),
            RestagePaywall(
              id: 'ok',
              resolver: _TextResolver(),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    flutterErrors.restore();

    expect(flutterErrors.reports.length, 1);
    expect(flutterErrors.reports.single.exception, isA<StateError>());
  });
}

void _paintBoundaryProbe(WidgetTester tester) {
  final leaf = tester.renderObject<RenderBox>(
    find.byType(_PaintOrderProbe, skipOffstage: false),
  );
  final probe = leaf.parent! as RenderBox;
  final context = PaintingContext(ContainerLayer(), probe.paintBounds);
  probe.paint(context, Offset.zero);
}
