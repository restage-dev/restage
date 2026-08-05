import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/error_boundary.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';

void main() {
  testWidgets(
      'a descendant paint exception does not register the transaction '
      'afterCommit callback', (tester) async {
    var committed = false;
    var painted = false;
    var ready = false;
    var errors = 0;
    var afterCommit = false;
    final transaction = FirstPaintLeaseTransaction(
      canCommit: () => true,
      commit: () => committed = true,
      onPainted: () => painted = true,
      afterCommit: () => afterCommit = true,
      afterRejection: () {},
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FirstPaintLeaseScope(
          transaction: transaction,
          child: FirstPaintLeaseGuard(
            transaction: transaction,
            armed: true,
            child: RuntimeErrorBoundary(
              onFirstPaintSuccess: () => ready = true,
              onError: (_, __) => errors += 1,
              errorReplacement: (_, __, ___) => const SizedBox.shrink(),
              child: const _ThrowDuringPaint(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final paintError = tester.takeException();
    final observed = (
      committed: committed,
      painted: painted,
      ready: ready,
      errors: errors,
      afterCommit: afterCommit,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed.committed, isTrue);
    expect(transaction.isCommitted, isTrue);
    expect(transaction.isPaintAcknowledged, isFalse);
    expect(paintError, isNull);
    expect(observed.painted, isFalse);
    expect(observed.ready, isFalse);
    expect(observed.errors, 1);
    expect(observed.afterCommit, isFalse);
  });

  testWidgets(
    'an unowned report during preview paint delegates without blocking the '
    'lease',
    (tester) async {
      final originalOnError = FlutterError.onError;
      final delegated = <FlutterErrorDetails>[];
      FlutterError.onError = delegated.add;
      addTearDown(() => FlutterError.onError = originalOnError);
      FlutterErrorDetails? reported;
      var committed = false;
      var painted = false;
      var ready = false;
      var afterCommit = false;
      var boundaryErrors = 0;
      final transaction = FirstPaintLeaseTransaction(
        canCommit: () => true,
        commit: () => committed = true,
        onPainted: () => painted = true,
        afterCommit: () => afterCommit = true,
        afterRejection: () {},
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FirstPaintLeaseScope(
            transaction: transaction,
            child: FirstPaintLeaseGuard(
              transaction: transaction,
              armed: true,
              child: RuntimeErrorBoundary(
                onFirstPaintSuccess: () => ready = true,
                onError: (_, __) => boundaryErrors += 1,
                errorReplacement: (_, __, ___) => const SizedBox.shrink(),
                child: _ReportDuringPaint(
                  structurallyOwned: false,
                  onReport: (details) => reported = details,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final observedDelegation = List<FlutterErrorDetails>.of(delegated);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      FlutterError.onError = originalOnError;

      expect(committed, isTrue);
      expect(transaction.isCommitted, isTrue);
      expect(transaction.isPaintAcknowledged, isTrue);
      expect(painted, isTrue);
      expect(ready, isTrue);
      expect(afterCommit, isTrue);
      expect(boundaryErrors, 0);
      expect(observedDelegation, hasLength(1));
      expect(observedDelegation.single, same(reported));
    },
  );

  testWidgets(
    'positive render ownership survives a later lazy diagnostic failure',
    (tester) async {
      final originalOnError = FlutterError.onError;
      final delegated = <FlutterErrorDetails>[];
      FlutterError.onError = delegated.add;
      addTearDown(() => FlutterError.onError = originalOnError);
      var committed = false;
      var painted = false;
      var ready = false;
      var afterCommit = false;
      var boundaryErrors = 0;
      final transaction = FirstPaintLeaseTransaction(
        canCommit: () => true,
        commit: () => committed = true,
        onPainted: () => painted = true,
        afterCommit: () => afterCommit = true,
        afterRejection: () {},
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FirstPaintLeaseScope(
            transaction: transaction,
            child: FirstPaintLeaseGuard(
              transaction: transaction,
              armed: true,
              child: RuntimeErrorBoundary(
                onFirstPaintSuccess: () => ready = true,
                onError: (_, __) => boundaryErrors += 1,
                errorReplacement: (_, __, ___) =>
                    const Text('lazy diagnostic fallback'),
                child: const _ReportDuringPaint(
                  structurallyOwned: true,
                  lazyDiagnosticFailure: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final observedDelegation = List<FlutterErrorDetails>.of(delegated);
      final fallbackCount =
          find.text('lazy diagnostic fallback').evaluate().length;
      await tester.pump();
      expect(boundaryErrors, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      FlutterError.onError = originalOnError;

      expect(committed, isTrue);
      expect(transaction.isCommitted, isTrue);
      expect(painted, isFalse);
      expect(ready, isFalse);
      expect(afterCommit, isFalse);
      expect(boundaryErrors, 1);
      expect(fallbackCount, 1);
      expect(observedDelegation, isEmpty);
    },
  );

  testWidgets(
    'definitive layout report permanently blocks lease success while a '
    'fresh transaction readies',
    (tester) async {
      var committed = false;
      var painted = false;
      var ready = false;
      var afterCommit = false;
      var boundaryErrors = 0;
      final transaction = FirstPaintLeaseTransaction(
        canCommit: () => true,
        commit: () => committed = true,
        onPainted: () => painted = true,
        afterCommit: () => afterCommit = true,
        afterRejection: () {},
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FirstPaintLeaseScope(
            transaction: transaction,
            child: FirstPaintLeaseGuard(
              transaction: transaction,
              armed: true,
              child: RuntimeErrorBoundary(
                key: const ValueKey<String>('failed-boundary'),
                onFirstPaintSuccess: () => ready = true,
                onError: (_, __) => boundaryErrors += 1,
                errorReplacement: (_, __, ___) =>
                    const Text('layout report fallback'),
                child: const _ReportDuringPaint(
                  structurallyOwned: true,
                  phase: _FrameworkReportPhase.layout,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final escaped = tester.takeException();
      final failedObserved = (
        committed: committed,
        painted: painted,
        ready: ready,
        afterCommit: afterCommit,
        boundaryErrors: boundaryErrors,
        fallbacks: find.text('layout report fallback').evaluate().length,
      );

      var freshCommitted = false;
      var freshPainted = 0;
      var freshReady = 0;
      var freshAfterCommit = 0;
      var freshErrors = 0;
      final freshTransaction = FirstPaintLeaseTransaction(
        canCommit: () => true,
        commit: () => freshCommitted = true,
        onPainted: () => freshPainted += 1,
        afterCommit: () => freshAfterCommit += 1,
        afterRejection: () {},
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FirstPaintLeaseScope(
            transaction: freshTransaction,
            child: FirstPaintLeaseGuard(
              transaction: freshTransaction,
              armed: true,
              child: RuntimeErrorBoundary(
                key: const ValueKey<String>('fresh-boundary'),
                onFirstPaintSuccess: () => freshReady += 1,
                onError: (_, __) => freshErrors += 1,
                errorReplacement: (_, __, ___) => const SizedBox.shrink(),
                child: const SizedBox.square(dimension: 20),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final freshObserved = (
        committed: freshCommitted,
        painted: freshPainted,
        ready: freshReady,
        afterCommit: freshAfterCommit,
        errors: freshErrors,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(escaped, isNull);
      expect(failedObserved.committed, isTrue);
      expect(transaction.isCommitted, isTrue);
      expect(failedObserved.painted, isFalse);
      expect(failedObserved.ready, isFalse);
      expect(failedObserved.afterCommit, isFalse);
      expect(failedObserved.boundaryErrors, 1);
      expect(failedObserved.fallbacks, 1);
      expect(freshTransaction.isCommitted, isTrue);
      expect(freshObserved, (
        committed: true,
        painted: 1,
        ready: 1,
        afterCommit: 1,
        errors: 0,
      ));
    },
  );

  testWidgets(
    'identical ErrorWidget claim releases the outer provisional lease token',
    (tester) async {
      final observed = await _runIdentityClaimScenario(
        tester,
        useIdenticalBuilderDetails: true,
      );

      expect(observed, (
        outerCommitted: true,
        outerPainted: true,
        outerReady: true,
        outerAfterCommit: true,
        outerErrors: 0,
        innerErrors: 1,
        outerIsCommitted: true,
        innerIsCommitted: false,
        outerFallbacks: 0,
        innerFallbacks: 1,
        escaped: null,
      ));
    },
  );

  testWidgets(
    'non-identical ErrorWidget claim cannot release the outer provisional '
    'lease token',
    (tester) async {
      final observed = await _runIdentityClaimScenario(
        tester,
        useIdenticalBuilderDetails: false,
      );

      expect(observed, (
        outerCommitted: true,
        outerPainted: false,
        outerReady: false,
        outerAfterCommit: false,
        outerErrors: 1,
        innerErrors: 1,
        outerIsCommitted: true,
        innerIsCommitted: false,
        outerFallbacks: 1,
        innerFallbacks: 0,
        escaped: null,
      ));
    },
  );

  testWidgets(
    'stale structural ownership releases its lease token without poisoning '
    'it',
    (tester) async {
      var committed = false;
      var painted = false;
      var ready = false;
      var afterCommit = false;
      var staleErrors = 0;
      var currentErrors = 0;
      final transaction = FirstPaintLeaseTransaction(
        canCommit: () => true,
        commit: () => committed = true,
        onPainted: () => painted = true,
        afterCommit: () => afterCommit = true,
        afterRejection: () {},
      );

      void staleOnError(Object _, StackTrace __) => staleErrors += 1;
      void currentOnError(Object _, StackTrace __) => currentErrors += 1;

      var current = false;
      FlutterErrorDetails? reportDuringBuild;
      StateSetter? rebuildParent;
      Widget tree() => Directionality(
            textDirection: TextDirection.ltr,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuildParent = setState;
                final report = reportDuringBuild;
                reportDuringBuild = null;
                if (report != null) FlutterError.reportError(report);
                return Offstage(
                  offstage: !current,
                  child: FirstPaintLeaseScope(
                    transaction: transaction,
                    child: FirstPaintLeaseGuard(
                      transaction: transaction,
                      armed: true,
                      child: RuntimeErrorBoundary(
                        onFirstPaintSuccess: () => ready = true,
                        onError: current ? currentOnError : staleOnError,
                        errorReplacement: (_, __, ___) =>
                            const Text('stale fallback'),
                        child: const SizedBox.square(
                          key: ValueKey<String>('stale-owner-child'),
                          dimension: 20,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );

      await tester.pumpWidget(tree());
      final renderObject = tester.renderObject<RenderObject>(
        find.byKey(
          const ValueKey<String>('stale-owner-child'),
          skipOffstage: false,
        ),
      );
      final staleReport = FlutterErrorDetails(
        exception: StateError('stale structurally owned report'),
        stack: StackTrace.current,
        library: 'restage_flutter_sdk_test',
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<RenderObject>('renderObject', renderObject),
        ],
      );
      rebuildParent!(() {
        current = true;
        reportDuringBuild = staleReport;
      });
      await tester.pump();
      await tester.pump();

      final escaped = tester.takeException();
      final observed = (
        committed: committed,
        painted: painted,
        ready: ready,
        afterCommit: afterCommit,
        staleErrors: staleErrors,
        currentErrors: currentErrors,
        fallbacks: find.text('stale fallback').evaluate().length,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(escaped, isNull);
      expect(transaction.isCommitted, isTrue);
      expect(observed, (
        committed: true,
        painted: true,
        ready: true,
        afterCommit: true,
        staleErrors: 0,
        currentErrors: 0,
        fallbacks: 0,
      ));
    },
  );

  testWidgets('nested lease paint report marks the nearest transaction only', (
    tester,
  ) async {
    var outerPainted = false;
    var outerReady = false;
    var outerAfterCommit = false;
    var outerErrors = 0;
    var innerPainted = false;
    var innerReady = false;
    var innerAfterCommit = false;
    var innerErrors = 0;
    final outer = FirstPaintLeaseTransaction(
      canCommit: () => true,
      commit: () {},
      onPainted: () => outerPainted = true,
      afterCommit: () => outerAfterCommit = true,
      afterRejection: () {},
    );
    final inner = FirstPaintLeaseTransaction(
      canCommit: () => true,
      commit: () {},
      onPainted: () => innerPainted = true,
      afterCommit: () => innerAfterCommit = true,
      afterRejection: () {},
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FirstPaintLeaseScope(
          transaction: outer,
          child: FirstPaintLeaseGuard(
            transaction: outer,
            armed: true,
            child: RuntimeErrorBoundary(
              onFirstPaintSuccess: () => outerReady = true,
              onError: (_, __) => outerErrors += 1,
              errorReplacement: (_, __, ___) => const SizedBox.shrink(),
              child: FirstPaintLeaseScope(
                transaction: inner,
                child: FirstPaintLeaseGuard(
                  transaction: inner,
                  armed: true,
                  child: RuntimeErrorBoundary(
                    onFirstPaintSuccess: () => innerReady = true,
                    onError: (_, __) => innerErrors += 1,
                    errorReplacement: (_, __, ___) => const SizedBox.shrink(),
                    child: const _ReportDuringPaint(structurallyOwned: true),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final observed = (
      outerPainted: outerPainted,
      outerReady: outerReady,
      outerAfterCommit: outerAfterCommit,
      outerErrors: outerErrors,
      innerPainted: innerPainted,
      innerReady: innerReady,
      innerAfterCommit: innerAfterCommit,
      innerErrors: innerErrors,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed, (
      outerPainted: true,
      outerReady: true,
      outerAfterCommit: true,
      outerErrors: 0,
      innerPainted: false,
      innerReady: false,
      innerAfterCommit: false,
      innerErrors: 1,
    ));
  });
}

Future<
    ({
      bool outerCommitted,
      bool outerPainted,
      bool outerReady,
      bool outerAfterCommit,
      int outerErrors,
      int innerErrors,
      bool outerIsCommitted,
      bool innerIsCommitted,
      int outerFallbacks,
      int innerFallbacks,
      Object? escaped,
    })> _runIdentityClaimScenario(
  WidgetTester tester, {
  required bool useIdenticalBuilderDetails,
}) async {
  var outerCommitted = false;
  var outerPainted = false;
  var outerReady = false;
  var outerAfterCommit = false;
  var outerErrors = 0;
  var innerErrors = 0;
  final outer = FirstPaintLeaseTransaction(
    canCommit: () => true,
    commit: () => outerCommitted = true,
    onPainted: () => outerPainted = true,
    afterCommit: () => outerAfterCommit = true,
    afterRejection: () {},
  );
  final inner = FirstPaintLeaseTransaction(
    canCommit: () => true,
    commit: () {},
    afterCommit: () {},
    afterRejection: () {},
  );

  void outerOnError(Object _, StackTrace __) => outerErrors += 1;
  void innerOnError(Object _, StackTrace __) => innerErrors += 1;

  Widget tree({
    FlutterErrorDetails? reportedDetails,
    FlutterErrorDetails? builderDetails,
  }) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Offstage(
          offstage: reportedDetails == null,
          child: FirstPaintLeaseScope(
            transaction: outer,
            child: FirstPaintLeaseGuard(
              transaction: outer,
              armed: true,
              child: RuntimeErrorBoundary(
                onFirstPaintSuccess: () => outerReady = true,
                onError: outerOnError,
                errorReplacement: (_, __, ___) => const Text('outer fallback'),
                child: FirstPaintLeaseScope(
                  transaction: inner,
                  child: FirstPaintLeaseGuard(
                    transaction: inner,
                    armed: true,
                    child: RuntimeErrorBoundary(
                      onError: innerOnError,
                      errorReplacement: (_, __, ___) =>
                          const Text('inner fallback'),
                      child: _ReportAndBuildErrorWidget(
                        reportedDetails: reportedDetails,
                        builderDetails: builderDetails,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  await tester.pumpWidget(tree());
  final evidence = tester.renderObject<RenderObject>(
    find.byKey(_ReportAndBuildErrorWidget.evidenceKey, skipOffstage: false),
  );
  final reportedDetails = FlutterErrorDetails(
    exception: StateError('structurally owned report for exact claim'),
    stack: StackTrace.current,
    library: 'restage_flutter_sdk_test',
    informationCollector: () => <DiagnosticsNode>[
      DiagnosticsProperty<RenderObject>('renderObject', evidence),
    ],
  );
  final builderDetails = useIdenticalBuilderDetails
      ? reportedDetails
      : FlutterErrorDetails(
          exception: reportedDetails.exception,
          stack: reportedDetails.stack,
          library: reportedDetails.library,
        );

  await tester.pumpWidget(
    tree(reportedDetails: reportedDetails, builderDetails: builderDetails),
  );
  await tester.pump();
  await tester.pump();

  final observed = (
    outerCommitted: outerCommitted,
    outerPainted: outerPainted,
    outerReady: outerReady,
    outerAfterCommit: outerAfterCommit,
    outerErrors: outerErrors,
    innerErrors: innerErrors,
    outerIsCommitted: outer.isCommitted,
    innerIsCommitted: inner.isCommitted,
    outerFallbacks: find.text('outer fallback').evaluate().length,
    innerFallbacks: find.text('inner fallback').evaluate().length,
    escaped: tester.takeException(),
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  return observed;
}

final class _ReportAndBuildErrorWidget extends StatelessWidget {
  const _ReportAndBuildErrorWidget({
    required this.reportedDetails,
    required this.builderDetails,
  });

  static const evidenceKey = ValueKey<String>('exact-claim-evidence');

  final FlutterErrorDetails? reportedDetails;
  final FlutterErrorDetails? builderDetails;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox.square(key: evidenceKey, dimension: 20),
          if (reportedDetails case final reportedDetails?)
            Builder(
              builder: (context) {
                FlutterError.reportError(reportedDetails);
                return ErrorWidget.builder(builderDetails!);
              },
            ),
        ],
      );
}

enum _FrameworkReportPhase { layout, paint }

final class _ReportDuringPaint extends LeafRenderObjectWidget {
  const _ReportDuringPaint({
    required this.structurallyOwned,
    this.onReport,
    this.phase = _FrameworkReportPhase.paint,
    this.lazyDiagnosticFailure = false,
  });

  final bool structurallyOwned;
  final ValueChanged<FlutterErrorDetails>? onReport;
  final _FrameworkReportPhase phase;
  final bool lazyDiagnosticFailure;

  @override
  RenderObject createRenderObject(BuildContext context) => _ReportingRenderBox(
        structurallyOwned,
        onReport,
        phase,
        lazyDiagnosticFailure,
      );
}

final class _ReportingRenderBox extends RenderBox {
  _ReportingRenderBox(
    this.structurallyOwned,
    this.onReport,
    this.phase,
    this.lazyDiagnosticFailure,
  );

  final bool structurallyOwned;
  final ValueChanged<FlutterErrorDetails>? onReport;
  final _FrameworkReportPhase phase;
  final bool lazyDiagnosticFailure;
  bool _reported = false;

  @override
  bool get sizedByParent => phase == _FrameworkReportPhase.layout;

  @override
  void performResize() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void performLayout() {
    if (!sizedByParent) {
      size = constraints.constrain(const Size.square(20));
    }
    if (phase == _FrameworkReportPhase.layout) _reportOnce();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (phase == _FrameworkReportPhase.paint) _reportOnce();
  }

  void _reportOnce() {
    if (_reported) return;
    _reported = true;
    final details = FlutterErrorDetails(
      exception: StateError('recoverable paint report'),
      stack: StackTrace.current,
      library: 'restage_flutter_sdk_test',
      informationCollector: structurallyOwned
          ? () => <DiagnosticsNode>[
                DiagnosticsProperty<RenderObject>('renderObject', this),
                if (lazyDiagnosticFailure)
                  DiagnosticsProperty<Object?>.lazy(
                    'lazy failure',
                    () => throw StateError('lazy diagnostic failed'),
                  ),
              ]
          : null,
    );
    onReport?.call(details);
    FlutterError.reportError(details);
  }
}

final class _ThrowDuringPaint extends LeafRenderObjectWidget {
  const _ThrowDuringPaint();

  @override
  RenderObject createRenderObject(BuildContext context) => _ThrowingRenderBox();
}

final class _ThrowingRenderBox extends RenderBox {
  @override
  void performLayout() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    throw StateError('paint failed');
  }
}
