// Nested-composition end-to-end smokes covering every combination of
// curated (rfw built-in) and customer widgets the runtime might see at
// render time:
//
//   1. curated containing customer: Column(children: [AcmeMarker, Text])
//   2. customer containing curated: AcmeBorder(child: Text)
//   3. customer containing customer: AcmeBorder(child: AcmeMarker)
//   4. mixed deep tree: AcmeStack([Column([AcmeBorder(AcmeMarker)]), Text])
//
// Each case asserts no exceptions surface during pumpAndSettle and that
// the canonical child / children slots resolve to the expected widgets.
// The customer fixtures are private to this test file so `find.byType`
// against them stays unambiguous regardless of any incidental tree
// composition the curated builders introduce.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// rfw exposes a `WidgetLibrary` that collides with the catalog identifier
// re-exported from `restage`. Hide rfw's symbol.
import 'package:rfw/formats.dart' hide WidgetLibrary;

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);
  final Uint8List bytes;
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, paywallId: id);
}

const _kFixturesLibrary = WidgetLibrary.custom('acme.fixtures');

/// Customer fixture: wraps a single child in a colored border. Exists
/// only to make `find.byType(_AcmeBorderFixture)` unambiguous in the
/// rendered tree.
class _AcmeBorderFixture extends StatelessWidget {
  const _AcmeBorderFixture({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(border: Border.all()),
        child: child,
      );
}

/// Customer fixture: overlays a list of children. Same uniqueness role
/// as `_AcmeBorderFixture`.
class _AcmeStackFixture extends StatelessWidget {
  const _AcmeStackFixture({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Stack(children: children);
}

void _registerFixtures() {
  Restage.registerWidgetLibrary(
    _kFixturesLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'AcmeMarker',
        builder: (context, source) => Text(
          source.v<String>(<Object>['label']) ?? '<missing>',
          textDirection: TextDirection.ltr,
        ),
      ),
      RestageWidgetFactory(
        name: 'AcmeBorder',
        builder: (context, source) => _AcmeBorderFixture(
          child: source.child(<Object>['child']),
        ),
      ),
      RestageWidgetFactory(
        name: 'AcmeStack',
        builder: (context, source) => _AcmeStackFixture(
          children: source.childList(<Object>['children']),
        ),
      ),
    ],
  );
}

/// Renders [source] through `RestagePaywall` and returns every
/// `PaywallLoadFailed` event the SDK fires. The runtime error boundary
/// claims widget-construction exceptions from the matching subtree and fires
/// `PaywallLoadFailed` on the per-paywall `onEvent` channel. Collecting load
/// failures gives each test a positive signal: a clean render is "no exception
/// AND no failure event."
Future<List<PaywallLoadFailed>> _renderBlob(
  WidgetTester tester,
  String source,
) async {
  final failures = <PaywallLoadFailed>[];
  final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'p',
          resolver: _StaticResolver(bytes),
          onEvent: (event) {
            if (event is PaywallLoadFailed) failures.add(event);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return failures;
}

void main() {
  setUp(() {
    Restage.debugReset();
    _registerFixtures();
  });

  testWidgets('curated containing customer: Column of [AcmeMarker, Text]',
      (tester) async {
    const source = '''
      import restage.core;
      import acme.fixtures;
      widget Paywall = Column(
        children: [
          AcmeMarker(label: "nested-leaf"),
          Text(text: "after"),
        ],
      );
    ''';
    final failures = await _renderBlob(tester, source);
    expect(tester.takeException(), isNull);
    expect(failures, isEmpty);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(Column), findsOneWidget);
    expect(find.text('nested-leaf'), findsOneWidget);
    expect(find.text('after'), findsOneWidget);
  });

  testWidgets('customer containing curated: AcmeBorder(child: Text)',
      (tester) async {
    const source = '''
      import restage.core;
      import acme.fixtures;
      widget Paywall = AcmeBorder(
        child: Text(text: "wrapped"),
      );
    ''';
    final failures = await _renderBlob(tester, source);
    expect(tester.takeException(), isNull);
    expect(failures, isEmpty);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(_AcmeBorderFixture), findsOneWidget);
    expect(find.text('wrapped'), findsOneWidget);
  });

  testWidgets('customer containing customer: AcmeBorder(child: AcmeMarker)',
      (tester) async {
    const source = '''
      import acme.fixtures;
      widget Paywall = AcmeBorder(
        child: AcmeMarker(label: "deep-leaf"),
      );
    ''';
    final failures = await _renderBlob(tester, source);
    expect(tester.takeException(), isNull);
    expect(failures, isEmpty);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(_AcmeBorderFixture), findsOneWidget);
    expect(find.text('deep-leaf'), findsOneWidget);
  });

  testWidgets(
      'mixed deep tree: AcmeStack of [Column of [AcmeBorder(AcmeMarker)], Text]',
      (tester) async {
    const source = '''
      import restage.core;
      import acme.fixtures;
      widget Paywall = AcmeStack(
        children: [
          Column(
            children: [
              AcmeBorder(child: AcmeMarker(label: "deep-leaf")),
            ],
          ),
          Text(text: "overlay"),
        ],
      );
    ''';
    final failures = await _renderBlob(tester, source);
    expect(tester.takeException(), isNull);
    expect(failures, isEmpty);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(_AcmeStackFixture), findsOneWidget);
    expect(find.byType(Column), findsOneWidget);
    expect(find.byType(_AcmeBorderFixture), findsOneWidget);
    expect(find.text('deep-leaf'), findsOneWidget);
    expect(find.text('overlay'), findsOneWidget);
  });
}
