import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Locks the `DecorationImage` value lowering: a developer writing
/// `Container(decoration: BoxDecoration(image: DecorationImage(...)))` ships a
/// real background image. The two serializable providers (`NetworkImage` /
/// `AssetImage`) lower to a self-describing `{kind, src}` map; `fit` /
/// `alignment` / `repeat` / `opacity` / `scale` carry through; an unsupported
/// provider or a not-yet-lowered field defers LOUD, never a silent drop.
void main() {
  final translator =
      ExpressionTranslator(catalog: kEmptyCatalog, helpers: HelperRegistry());

  Future<({String dsl, List<Issue> issues})> translateUnresolved(
    String source,
  ) async {
    final r = translator.translate(await parseExpressionForTest(source));
    return (dsl: r.dsl, issues: r.issues);
  }

  group('ImageProvider value lowering', () {
    test('NetworkImage(url) -> {kind: "network", src: <url>}', () async {
      final r = await translateUnresolved("NetworkImage('https://x/h.jpg')");
      expect(r.issues, isEmpty);
      expect(r.dsl, '{kind: "network", src: "https://x/h.jpg"}');
    });

    test('AssetImage(name) -> {kind: "asset", src: <name>}', () async {
      final r = await translateUnresolved("AssetImage('assets/bg.png')");
      expect(r.issues, isEmpty);
      expect(r.dsl, '{kind: "asset", src: "assets/bg.png"}');
    });

    test('NetworkImage without a URL argument defers loud', () async {
      final r = await translateUnresolved('NetworkImage()');
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
    });

    test('NetworkImage scale is mapped onto the provider map', () async {
      final r = await translateUnresolved("NetworkImage('u', scale: 2.0)");
      expect(r.issues, isEmpty);
      expect(r.dsl, '{kind: "network", src: "u", scale: 2.0}');
    });

    test('AssetImage package is mapped onto the provider map', () async {
      final r =
          await translateUnresolved("AssetImage('x.png', package: 'my_pkg')");
      expect(r.issues, isEmpty);
      expect(r.dsl, '{kind: "asset", src: "x.png", package: "my_pkg"}');
    });

    test('a NetworkImage non-serializable named arg (headers) defers loud',
        () async {
      final r =
          await translateUnresolved("NetworkImage('u', headers: {'a': 'b'})");
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.issues.any((i) => i.message.contains('headers')), isTrue);
      // Failure DSL — never a partial provider map that drops headers silently.
      expect(r.dsl, isNot(contains('kind: "network"')));
    });

    test('an AssetImage non-serializable named arg (bundle) defers loud',
        () async {
      final r =
          await translateUnresolved("AssetImage('x.png', bundle: someBundle)");
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.issues.any((i) => i.message.contains('bundle')), isTrue);
      expect(r.dsl, isNot(contains('kind: "asset"')));
    });
  });

  group('DecorationImage value lowering', () {
    test(
        'recurses the provider and threads fit + alignment member -> '
        'a self-describing map', () async {
      final r = await translateUnresolved(
        "DecorationImage(image: NetworkImage('https://x/h.jpg'), "
        'fit: BoxFit.cover, alignment: Alignment.topCenter)',
      );
      expect(r.issues, isEmpty);
      // The provider recursed into the network-image map; fit carried as the
      // enum member name; the concrete Alignment member lowered to its {x, y}
      // pair (the shape the runtime alignmentXY decoder reads).
      expect(
        r.dsl,
        contains('image: {kind: "network", src: "https://x/h.jpg"}'),
      );
      // The enum member lowers to its name as a quoted string — the shape the
      // runtime `ArgumentDecoders.enumValue<BoxFit>(BoxFit.values, …)` reads.
      expect(r.dsl, contains('fit: "cover"'));
      expect(r.dsl, contains('alignment: {x: 0.0, y: -1.0}'));
    });

    test('an AssetImage provider variant recurses too', () async {
      final r = await translateUnresolved(
        "DecorationImage(image: AssetImage('assets/bg.png'), "
        'fit: BoxFit.fill)',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('image: {kind: "asset", src: "assets/bg.png"}'));
      expect(r.dsl, contains('fit: "fill"'));
    });

    test('threads repeat, an Alignment(x, y) ctor, opacity, and scale',
        () async {
      final r = await translateUnresolved(
        "DecorationImage(image: NetworkImage('https://x/h.jpg'), "
        'repeat: ImageRepeat.repeatX, alignment: Alignment(0.5, -0.25), '
        'opacity: 0.8, scale: 2.0)',
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('repeat: "repeatX"'));
      expect(r.dsl, contains('alignment: {x: 0.5, y: -0.25}'));
      expect(r.dsl, contains('opacity: 0.8'));
      expect(r.dsl, contains('scale: 2.0'));
    });

    test('omits every optional field when unset — decoder applies defaults',
        () async {
      final r = await translateUnresolved(
        "DecorationImage(image: NetworkImage('https://x/h.jpg'))",
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, '{image: {kind: "network", src: "https://x/h.jpg"}}');
    });

    test('an int opacity literal coerces to a double on the wire', () async {
      // `opacity: 1` is valid Dart (int -> double); the runtime decoder reads
      // it via `_number` which tolerates int, but the recipe coerces to a
      // double literal for wire consistency with the other length-like slots.
      final r = await translateUnresolved(
        "DecorationImage(image: AssetImage('a.png'), opacity: 1)",
      );
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('opacity: 1.0'));
    });
  });

  group('DecorationImage fails loud rather than silently dropping', () {
    test('a not-yet-lowered field (colorFilter) defers loud — never silent',
        () async {
      final r = await translateUnresolved(
        "DecorationImage(image: NetworkImage('https://x/h.jpg'), "
        'colorFilter: ColorFilter.mode(Color(0xFF000000), BlendMode.darken))',
      );
      // The field is present but unsupported: one loud diagnostic, and the
      // emit is the recipe's failure DSL (NOT a partial map that renders as if
      // colorFilter were unset).
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.issues.any((i) => i.message.contains('colorFilter')), isTrue);
      expect(r.dsl, isNot(contains('kind: "network"')));
    });

    test('every named deferred field is reported when several are present',
        () async {
      final r = await translateUnresolved(
        "DecorationImage(image: AssetImage('a.png'), "
        'matchTextDirection: true, isAntiAlias: true)',
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.issues.any((i) => i.message.contains('isAntiAlias')), isTrue);
      expect(
        r.issues.any((i) => i.message.contains('matchTextDirection')),
        isTrue,
      );
    });

    test('invertColors (render-affecting) defers loud — never a silent drop',
        () async {
      // invertColors changes the painted pixels (Flutter inverts the image
      // colors), so dropping it is a wrong render, not a debug no-op.
      final r = await translateUnresolved(
        "DecorationImage(image: NetworkImage('u'), invertColors: true)",
      );
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(r.issues.any((i) => i.message.contains('invertColors')), isTrue);
      expect(r.dsl, isNot(contains('kind: "network"')));
    });
  });

  group('alignment members: only the 9 concrete Alignment constants lower', () {
    test(
        'a resolved AlignmentDirectional.* member defers LOUD — no bare-name '
        'silent null to Alignment.center', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show DecorationImage, NetworkImage, AlignmentDirectional;
        Object x() => DecorationImage(
          image: NetworkImage('u'),
          alignment: AlignmentDirectional.centerStart,
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(
        r.issues.map((i) => i.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      // No bare member-name string that the alignmentXY decoder would null.
      expect(r.dsl, isNot(contains('"centerStart"')));
      expect(r.dsl, isNot(contains('centerStart')));
    });

    test('a resolved Alignment(x, y) constructor still lowers to {x, y}',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show DecorationImage, NetworkImage, Alignment;
        Object x() => DecorationImage(
          image: NetworkImage('u'),
          alignment: Alignment(0.5, -0.25),
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('alignment: {x: 0.5, y: -0.25}'));
    });

    test('a resolved Alignment.<member> still lowers to {x, y}', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show DecorationImage, NetworkImage, Alignment;
        Object x() => DecorationImage(
          image: NetworkImage('u'),
          alignment: Alignment.bottomRight,
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(r.dsl, contains('alignment: {x: 1.0, y: 1.0}'));
    });
  });

  group('an unsupported provider defers loud (resolved)', () {
    test(
        'a real-Flutter MemoryImage provider is not lowered as a fabricated '
        'image — it defers loud', () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show DecorationImage, MemoryImage;
        import 'dart:typed_data' show Uint8List;
        Object x() => DecorationImage(image: MemoryImage(Uint8List(0)));
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      // No fabricated provider map — MemoryImage carries runtime bytes that
      // cannot ride a delivered blob, so it must defer loud, never silently
      // emit an empty / wrong image.
      expect(r.issues, isNotEmpty);
      expect(r.dsl, isNot(contains('kind:')));
    });

    test('a real-Flutter NetworkImage provider DOES lower when fully resolved',
        () async {
      final expr = await parseExpressionFromSourceForTest(
        '''
        import 'package:flutter/material.dart'
            show DecorationImage, NetworkImage, BoxFit;
        Object x() => DecorationImage(
          image: NetworkImage('https://x/h.jpg'),
          fit: BoxFit.cover,
        );
        ''',
        rootPackage: 'apps_examples',
      );
      final r = translator.translate(expr);
      expect(r.issues, isEmpty);
      expect(
        r.dsl,
        contains('image: {kind: "network", src: "https://x/h.jpg"}'),
      );
      expect(r.dsl, contains('fit: "cover"'));
    });
  });
}
