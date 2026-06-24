// End-to-end coverage for the data.theme.* channel: the SDK publishes the
// host theme into a rendered paywall's DynamicContent, re-publishing it when
// the ambient theme changes, and an RFW widget's state survives that update.
//
// Test shape note: `RestagePaywall` installs a runtime error boundary while
// mounted. Every test here reads values into locals while the paywall is
// mounted, then unmounts before assertions so a failed assertion reports
// through the flutter_test harness with no boundary state involved.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// rfw's `WidgetLibrary` collides with the catalog identifier re-exported from
// `restage`. Hide rfw's symbol.
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

/// Custom-widget fixture: reads a theme value out of `data.theme.*` and holds
/// it where `tester.widget<_ThemeProbe>` can read it back. Private type so
/// `find.byType(_ThemeProbe)` is unambiguous in the rendered tree.
class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe({this.primaryArgb});
  final int? primaryArgb;
  @override
  Widget build(BuildContext context) => const SizedBox(width: 50, height: 50);
}

void _registerProbe() {
  Restage.registerWidgetLibrary(
    _kFixturesLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'ThemeProbe',
        builder: (context, source) =>
            _ThemeProbe(primaryArgb: source.v<int>(<Object>['primaryArgb'])),
      ),
    ],
  );
}

Uint8List _blob(String source) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

ThemeData _themeWithPrimary(Color primary) => ThemeData(
      colorScheme: const ColorScheme.light().copyWith(primary: primary),
    );

void main() {
  setUp(() {
    Restage.debugReset();
    _registerProbe();
  });

  testWidgets(
      'data.theme.colorScheme.primary resolves in a rendered paywall and '
      're-pushes when the host theme changes', (tester) async {
    final resolver = _StaticResolver(_blob('''
      import restage.core;
      import acme.fixtures;
      widget Paywall = ThemeProbe(
        primaryArgb: data.theme.colorScheme.primary,
      );
    '''));

    Widget app(Color primary) => MaterialApp(
          theme: _themeWithPrimary(primary),
          home: Scaffold(
            body: RestagePaywall(id: 'p', resolver: resolver),
          ),
        );

    // What the data.theme.* channel published, and what the ambient theme
    // actually resolves to — read while the paywall is mounted.
    int? channelPrimary() =>
        tester.widget<_ThemeProbe>(find.byType(_ThemeProbe)).primaryArgb;
    int themePrimary() => Theme.of(tester.element(find.byType(_ThemeProbe)))
        .colorScheme
        .primary
        .toARGB32();

    await tester.pumpWidget(app(const Color(0xFF112233)));
    await tester.pumpAndSettle();
    final firstChannel = channelPrimary();
    final firstTheme = themePrimary();

    // Host theme changes — same RestagePaywall element, same resolver.
    await tester.pumpWidget(app(const Color(0xFF445566)));
    await tester.pumpAndSettle();
    final changedChannel = channelPrimary();
    final changedTheme = themePrimary();

    // Re-pump with an equal-valued theme (fresh ThemeData instance): the
    // identity gate skips the redundant re-push; the paywall stays correct.
    await tester.pumpWidget(app(const Color(0xFF445566)));
    await tester.pumpAndSettle();
    final gatedChannel = channelPrimary();
    final gatedTheme = themePrimary();

    // Unmount the paywall before asserting (see the file header note).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(firstChannel, firstTheme,
        reason: 'theme channel resolves at first render');
    expect(changedChannel, changedTheme,
        reason: 'didChangeDependencies re-pushes data.theme.* on theme change');
    expect(changedChannel, isNot(firstChannel),
        reason: 'the published value actually changed');
    expect(gatedChannel, gatedTheme,
        reason: 'the identity gate keeps the paywall correct');
  });

  testWidgets('RFW widget state survives a data.theme.* update',
      (tester) async {
    // A stateful Paywall: tapping flips state.expanded; a ThemeProbe reads
    // data.theme.*; a switch renders the state. A host-theme change
    // re-publishes data.theme.* and rebuilds the subtree — the toggled state
    // must survive that rebuild (the guarantee a later state phase depends on).
    final resolver = _StaticResolver(_blob('''
      import restage.core;
      import acme.fixtures;
      widget Paywall { expanded: false } = Column(
        children: [
          GestureDetector(
            onTap: set state.expanded = true,
            child: Text(text: "tap-target"),
          ),
          ThemeProbe(primaryArgb: data.theme.colorScheme.primary),
          switch state.expanded {
            false: Text(text: "collapsed"),
            true: Text(text: "expanded"),
          },
        ],
      );
    '''));

    Widget app(Color primary) => MaterialApp(
          theme: _themeWithPrimary(primary),
          home: Scaffold(
            body: RestagePaywall(id: 'p', resolver: resolver),
          ),
        );
    bool showing(String text) => find.text(text).evaluate().isNotEmpty;
    int? channelPrimary() =>
        tester.widget<_ThemeProbe>(find.byType(_ThemeProbe)).primaryArgb;

    await tester.pumpWidget(app(const Color(0xFF112233)));
    await tester.pumpAndSettle();
    final collapsedInitially = showing('collapsed');
    final probeBefore = channelPrimary();

    // Toggle the RFW state.
    await tester.tap(find.text('tap-target'));
    await tester.pumpAndSettle();
    final expandedAfterTap = showing('expanded');

    // Host theme changes -> data.theme.* re-published -> the subtree rebuilds.
    await tester.pumpWidget(app(const Color(0xFF445566)));
    await tester.pumpAndSettle();
    final expandedAfterThemeChange = showing('expanded');
    final probeAfter = channelPrimary();

    // Unmount the paywall before asserting (see the file header note).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(collapsedInitially, isTrue, reason: 'state.expanded starts false');
    expect(expandedAfterTap, isTrue,
        reason: 'set state.expanded = true took effect');
    expect(probeAfter, isNot(probeBefore),
        reason: 'the data.theme.* update genuinely propagated');
    expect(expandedAfterThemeChange, isTrue,
        reason: 'RFW widget state survived the data.theme.* update');
  });
}
