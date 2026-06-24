import 'dart:typed_data';

import 'package:flutter/material.dart';
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

void _reportTestFlutterError(String message) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: StateError(message),
    stack: StackTrace.current,
    library: 'restage_flutter_sdk_test',
  ));
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
