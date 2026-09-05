// A lowered collection-`if` renders what Flutter renders. Flutter omits an
// unselected element entirely, so the delivered surface must too. A placeholder child
// would show up as a spacing gap, a run item, or a shifted index, so the
// emitter guards each branch with a loop over a one-or-zero-element list. The
// DSL below is verbatim emitter output.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

String _column(String children, {String extra = ''}) => '''
import restage.core;

widget Paywall { isPro: false } = Column(
  mainAxisSize: "min",
  $extra
  children: [$children],
);
''';

/// `Column(children: [Text('a'), if (isPro) Text('b'), Text('c')])`.
const String _conditional = 'Text(text: "a"), '
    '...for presence in switch state.isPro { true: [0], false: [] }: '
    'Text(text: "b"), Text(text: "c")';

/// The same column with the conditional element never written.
const String _absent = 'Text(text: "a"), Text(text: "c")';

Widget _remote(String source) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RemoteWidget(
          runtime: Runtime()
            ..update(_coreLibrary, buildCoreWidgetLibrary())
            ..update(_rootLibrary, parseLibraryFile(source)),
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
          onEvent: (String name, DynamicMap arguments) {},
        ),
      ),
    );

String _whenTrue(String source) =>
    source.replaceFirst('isPro: false', 'isPro: true');

List<String?> _texts() => find
    .byType(Text)
    .evaluate()
    .map((Element element) => (element.widget as Text).data)
    .toList();

void main() {
  testWidgets('the false branch contributes no child',
      (WidgetTester tester) async {
    await tester.pumpWidget(_remote(_column(_conditional)));
    expect(tester.takeException(), isNull);
    expect(_texts(), <String>['a', 'c']);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('the true branch renders the conditional child',
      (WidgetTester tester) async {
    await tester.pumpWidget(_remote(_whenTrue(_column(_conditional))));
    expect(tester.takeException(), isNull);
    expect(_texts(), <String>['a', 'b', 'c']);
  });

  testWidgets('a spaced column measures as if the element were never written',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _remote(_column(_conditional, extra: 'spacing: 12.0,')),
    );
    final Size conditional = tester.getSize(find.byType(Column).first);
    final Offset conditionalLast = tester.getTopLeft(find.text('c'));

    await tester.pumpWidget(
      _remote(_column(_absent, extra: 'spacing: 12.0,')),
    );
    expect(tester.getSize(find.byType(Column).first), conditional);
    expect(tester.getTopLeft(find.text('c')), conditionalLast);
  });

  testWidgets('the true branch adds exactly one child and one gap',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _remote(_column(_conditional, extra: 'spacing: 12.0,')),
    );
    final double falseHeight = tester.getSize(find.byType(Column).first).height;
    final double childHeight = tester.getSize(find.text('a')).height;

    await tester.pumpWidget(
      _remote(_whenTrue(_column(_conditional, extra: 'spacing: 12.0,'))),
    );
    final double trueHeight = tester.getSize(find.byType(Column).first).height;

    expect(trueHeight - falseHeight, childHeight + 12.0);
  });

  testWidgets('a Wrap gains no phantom run item', (WidgetTester tester) async {
    String wrap(String children) => '''
import restage.core;

widget Paywall { isPro: false } = Wrap(
  spacing: 8.0,
  children: [$children],
);
''';
    await tester.pumpWidget(_remote(wrap(_conditional)));
    final Offset conditionalLast = tester.getTopLeft(find.text('c'));
    await tester.pumpWidget(_remote(wrap(_absent)));
    expect(tester.getTopLeft(find.text('c')), conditionalLast);
  });

  testWidgets('a Stack index is not shifted by the absent branch',
      (WidgetTester tester) async {
    // `Positioned` reads its own offsets, so a shifted child order shows up
    // as the wrong label at the pinned position.
    String stack(String third) => '''
import restage.core;

widget Paywall { isPro: false } = Stack(
  children: [
    Positioned(left: 0.0, top: 0.0, child: Text(text: "first")),
    ...for presence in switch state.isPro { true: [0], false: [] }:
        Positioned(left: 0.0, top: 20.0, child: Text(text: "gated")),
    $third,
  ],
);
''';
    await tester.pumpWidget(
      _remote(
        stack('Positioned(left: 0.0, top: 40.0, child: Text(text: "last"))'),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(_texts(), <String>['first', 'last']);
    expect(tester.getTopLeft(find.text('last')).dy, 40.0);
  });

  testWidgets('a false guard leaves a scalar list element out',
      (WidgetTester tester) async {
    // `fontFamilyFallback` is a plain string list, so the guarded loop is
    // resolved by the list decoder rather than by the widget builder.
    String styled(String families) => '''
import restage.core;

widget Paywall { isPro: false } = DefaultTextStyle(
  fontFamilyFallback: [$families],
  child: Text(text: "a"),
);
''';
    const String guarded = '"first", '
        '...for presence in switch state.isPro { true: [0], false: [] }: '
        '"gated", "last"';

    await tester.pumpWidget(_remote(styled(guarded)));
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<DefaultTextStyle>(find.byType(DefaultTextStyle).first)
          .style
          .fontFamilyFallback,
      <String>['first', 'last'],
    );

    await tester.pumpWidget(_remote(_whenTrue(styled(guarded))));
    expect(
      tester
          .widget<DefaultTextStyle>(find.byType(DefaultTextStyle).first)
          .style
          .fontFamilyFallback,
      <String>['first', 'gated', 'last'],
    );
  });

  testWidgets('an arm-less switch element builds an error widget',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _remote(
        _column(
            'Text(text: "a"), switch state.isPro { true: Text(text: "b") }'),
      ),
    );
    expect(tester.takeException(), isNotNull);
    expect(find.byType(ErrorWidget), findsOneWidget);
  });
}
