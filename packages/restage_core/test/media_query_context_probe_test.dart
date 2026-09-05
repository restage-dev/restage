// Which context a MediaQuery inset read is answered from. The read resolves at
// the context it is handed, not at the position it is written: a screen's own
// build context sits above every consumer that screen authors, so the published
// inset is what Flutter renders there. Only a context taken below a consumer —
// a Builder, or another widget's own build — reads zero.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const EdgeInsets _kPadding = EdgeInsets.only(top: 44, bottom: 34);

/// The probe box, found by the width no other box in the tree uses.
final Finder _probe = find.byWidgetPredicate(
  (widget) => widget is SizedBox && widget.width == 10,
);

Widget _mounted(Widget child) => MediaQuery(
      data: const MediaQueryData(padding: _kPadding),
      child: MaterialApp(
        home: Align(alignment: Alignment.topLeft, child: child),
      ),
    );

class _SafeAreaScreen extends StatelessWidget {
  const _SafeAreaScreen();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(width: 10, height: MediaQuery.paddingOf(context).top),
      );
}

class _HelperScreen extends StatelessWidget {
  const _HelperScreen();

  Widget _body(BuildContext c) =>
      SizedBox(width: 10, height: MediaQuery.paddingOf(c).top);

  @override
  Widget build(BuildContext context) => SafeArea(child: _body(context));
}

class _ScaffoldBodyScreen extends StatelessWidget {
  const _ScaffoldBodyScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Plans')),
        body: SizedBox(width: 10, height: MediaQuery.paddingOf(context).top),
      );
}

class _AppBarTitleScreen extends StatelessWidget {
  const _AppBarTitleScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: SizedBox(width: 10, height: MediaQuery.paddingOf(context).top),
        ),
        body: const SizedBox(),
      );
}

class _BuilderScreen extends StatelessWidget {
  const _BuilderScreen();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Builder(
          builder: (c) =>
              SizedBox(width: 10, height: MediaQuery.paddingOf(c).top),
        ),
      );
}

void main() {
  testWidgets('a screen-context read under a SafeArea is the full inset',
      (tester) async {
    await tester.pumpWidget(_mounted(const _SafeAreaScreen()));

    expect(tester.getSize(_probe).height, _kPadding.top);
  });

  testWidgets("a helper handed the screen's context reads the full inset",
      (tester) async {
    await tester.pumpWidget(_mounted(const _HelperScreen()));

    expect(tester.getSize(_probe).height, _kPadding.top);
  });

  testWidgets('a Scaffold body under an appBar is the full inset',
      (tester) async {
    await tester.pumpWidget(_mounted(const _ScaffoldBodyScreen()));

    expect(tester.getSize(_probe).height, _kPadding.top);
  });

  testWidgets('an AppBar title is the full inset', (tester) async {
    await tester.pumpWidget(_mounted(const _AppBarTitleScreen()));

    expect(tester.getSize(_probe).height, _kPadding.top);
  });

  testWidgets('a Builder context below the SafeArea reads zero',
      (tester) async {
    await tester.pumpWidget(_mounted(const _BuilderScreen()));

    expect(tester.getSize(_probe).height, 0.0);
  });
}
