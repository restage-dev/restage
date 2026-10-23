import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/rfw.dart';

void main() {
  test('writes app values in the shape a surface reads', () {
    expect(restageHostValue(const Color(0xFF112233)), 0xFF112233);
    expect(
      restageHostValue(const EdgeInsets.fromLTRB(1, 2, 3, 4)),
      [1.0, 2.0, 3.0, 4.0],
    );
    expect(
      restageHostValue(const EdgeInsetsDirectional.fromSTEB(5, 6, 7, 8)),
      [5.0, 6.0, 7.0, 8.0],
    );
    expect(restageHostValue(TextAlign.end), 'end');
    expect(
      restageHostValue(<String, Object?>{
        'tones': [const Color(0xFF000000), null],
      }),
      {
        'tones': [0xFF000000, null],
      },
    );
  });

  test('a text style round-trips through the surface decoder', () {
    final style = TextStyle(
      inherit: false,
      color: const Color(0xFF1F2B24),
      backgroundColor: const Color(0xFFFAF5EA),
      fontSize: 22,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.italic,
      letterSpacing: -0.3,
      wordSpacing: 2,
      textBaseline: TextBaseline.ideographic,
      height: 1.2,
      leadingDistribution: TextLeadingDistribution.even,
      locale: const Locale('sv', 'SE'),
      shadows: const [
        Shadow(color: Color(0x40000000), offset: Offset(0, 2), blurRadius: 6),
      ],
      fontFeatures: const [FontFeature.tabularFigures()],
      fontVariations: const [FontVariation('wght', 640)],
      decoration: TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]),
      decorationColor: const Color(0xFF2F5D44),
      decorationStyle: TextDecorationStyle.dashed,
      decorationThickness: 1.5,
      debugLabel: 'headline',
      fontFamily: 'Serif',
      package: 'tokens',
      fontFamilyFallback: const ['Sans'],
      overflow: TextOverflow.fade,
    );
    final decoded = RestageDecoders.textStyle(
      _MapDataSource(<String, Object?>{'style': restageHostValue(style)}),
      const ['style'],
    );
    expect(decoded, style);
  });

  test('a paint keeps its color, blend mode, quality and anti-aliasing', () {
    final paint = Paint()
      ..color = const Color(0xFF2F5D44)
      ..blendMode = BlendMode.multiply
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = false;
    final decoded = RestageDecoders.textStyle(
      _MapDataSource(<String, Object?>{
        'style': restageHostValue(TextStyle(foreground: paint)),
      }),
      const ['style'],
    )!;
    expect(decoded.foreground!.color, paint.color);
    expect(decoded.foreground!.blendMode, paint.blendMode);
    expect(decoded.foreground!.filterQuality, paint.filterQuality);
    expect(decoded.foreground!.isAntiAlias, isFalse);
  });

  test('a value whose computation throws is left out and logged', () {
    final logged = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);
    addTearDown(() => debugPrint = previous);
    String? title;
    expect(
      restageHostValues({
        'offer': ('Store.instance.offer!.title', () => title!),
        'tone': ('Tones.ink', () => const Color(0xFF000000)),
      }),
      {'tone': 0xFF000000},
    );
    restageHostValues({
      'offer': ('Store.instance.offer!.title', () => title!),
    });
    expect(logged, [
      "[restage] 'Store.instance.offer!.title' threw while computing in the "
          'app, so the surface reads it as missing: Null check operator used '
          'on a null value',
    ]);
    title = 'Pro';
    expect(
      restageHostValues({
        'offer': ('Store.instance.offer!.title', () => title!),
      }),
      {'offer': 'Pro'},
    );
  });

  test('refuses a value a surface cannot receive', () {
    expect(() => restageHostValue(Object()), throwsArgumentError);
  });
}

final class _MapDataSource implements DataSource {
  const _MapDataSource(this.root);

  final Object? root;

  @override
  T? v<T extends Object>(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is T ? value : null;
  }

  @override
  bool isList(List<Object> argsKey) => _lookup(argsKey) is List<Object?>;

  @override
  int length(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is List<Object?> ? value.length : 0;
  }

  @override
  bool isMap(List<Object> argsKey) => _lookup(argsKey) is Map<String, Object?>;

  @override
  Widget child(List<Object> argsKey) => ErrorWidget('missing child');

  @override
  List<Widget> childList(List<Object> argsKey) => const [];

  @override
  Widget builder(List<Object> argsKey, DynamicMap builderArg) =>
      ErrorWidget('missing builder');

  @override
  T? handler<T extends Function>(
    List<Object> argsKey,
    HandlerGenerator<T> generator,
  ) =>
      null;

  @override
  Widget? optionalBuilder(List<Object> argsKey, DynamicMap builderArg) => null;

  @override
  Widget? optionalChild(List<Object> argsKey) => null;

  @override
  VoidCallback? voidHandler(
    List<Object> argsKey, [
    DynamicMap? extraArguments,
  ]) =>
      null;

  Object? _lookup(List<Object> path) {
    Object? current = root;
    for (final segment in path) {
      if (current is Map<String, Object?> && segment is String) {
        current = current[segment];
      } else if (current is List<Object?> && segment is int) {
        if (segment < 0 || segment >= current.length) return null;
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }
}
