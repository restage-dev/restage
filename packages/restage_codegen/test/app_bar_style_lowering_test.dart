import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/restage_shared.dart'
    show kMaxStructuredCopyWithLayers;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import 'helpers.dart';

const _package = 'apps_examples';

const _light = <String, Object?>{
  'systemNavigationBarColor': 0xFF000000,
  'systemNavigationBarIconBrightness': 'light',
  'statusBarIconBrightness': 'light',
  'statusBarBrightness': 'dark',
};

const _dark = <String, Object?>{
  'systemNavigationBarColor': 0xFF000000,
  'systemNavigationBarIconBrightness': 'light',
  'statusBarIconBrightness': 'dark',
  'statusBarBrightness': 'light',
};

String _source(
  String id,
  String arguments, {
  String prelude = '',
  String declarations = '',
  String constructorParameters = '',
  String fields = '',
  String imports = '''
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
''',
}) =>
    '''
$imports

class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}

$declarations

@PaywallSource(id: '$id')
class StyledAppBar extends StatelessWidget {
  const StyledAppBar({super.key, $constructorParameters});

  $fields

  @override
  Widget build(BuildContext context) {
    $prelude
    return Scaffold(
      appBar: AppBar($arguments),
      body: const SizedBox(),
    );
  }
}
''';

Future<TestBuilderResult> _build(Map<String, String> fixtures) async {
  final sources = <String, String>{
    for (final fixture in fixtures.entries)
      '$_package|lib/paywalls/${fixture.key}.dart': fixture.value,
  };
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  for (final source in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(source.key), source.value);
  }
  return await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    sources,
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

Map<String, Object?> _appBar(TestBuilderResult result, String id) {
  final library = fmt.parseLibraryFile(
    result.readerWriter.testing.readString(
      AssetId(_package, 'assets/paywalls/$id.rfwtxt'),
    ),
  );
  final scaffold = library.widgets.single.root as fmt.ConstructorCall;
  expect(scaffold.name, 'Scaffold');
  final appBar = scaffold.arguments['appBar']! as fmt.ConstructorCall;
  expect(appBar.name, 'AppBar');
  return appBar.arguments;
}

Object? _atBrightness(Object? value, String brightness) => _resolve(value, {
      'theme': {'brightness': brightness},
    });

Matcher _dataReference(List<String> parts) => isA<fmt.DataReference>().having(
      (reference) => reference.parts,
      'parts',
      parts,
    );

Object? _resolve(Object? value, Map<String, Object?> data) {
  if (value is fmt.DataReference) {
    Object? current = data;
    for (final part in value.parts) {
      expect(current, isA<Map<Object?, Object?>>());
      final map = current! as Map<Object?, Object?>;
      expect(map.containsKey(part), isTrue, reason: value.toString());
      current = map[part];
    }
    return current;
  }
  if (value is fmt.Switch) {
    final input = _resolve(value.input, data);
    return _resolve(
      value.outputs.containsKey(input)
          ? value.outputs[input]
          : value.outputs[null],
      data,
    );
  }
  if (value is Map<Object?, Object?>) {
    return value.map(
      (key, item) => MapEntry(key, _resolve(item, data)),
    );
  }
  if (value is List) {
    return value.map((item) => _resolve(item, data)).toList();
  }
  return value;
}

void main() {
  group('AppBar style authoring', () {
    late TestBuilderResult result;

    setUpAll(() async {
      result = await _build({
        'all_style_fields': _source('all_style_fields', '''
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Color(0xFF112233),
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: Color(0xFF445566),
            systemNavigationBarDividerColor: Color(0xFF778899),
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarContrastEnforced: false,
            systemStatusBarContrastEnforced: true,
          ),
          iconTheme: const IconThemeData(
            color: Color(0xFF123456),
            size: 24,
            opacity: 0.5,
            fill: 1,
            weight: 600,
            grade: -25,
            opticalSize: 48,
            shadows: [
              Shadow(
                color: Color(0x55010203),
                offset: Offset(0, 2),
                blurRadius: 4,
              ),
            ],
            applyTextScaling: true,
          ),
          actionsIconTheme: const IconThemeData(
            color: Colors.transparent,
            size: 0,
            opacity: 0,
            fill: 0,
            weight: 100,
            grade: 0,
            opticalSize: 20,
            shadows: [],
            applyTextScaling: false,
          ),
          titleTextStyle: const TextStyle(fontSize: 24, color: Colors.white),
          toolbarTextStyle: const TextStyle(fontSize: 14, color: Colors.black),
        '''),
        'omitted_styles': _source('omitted_styles', ''),
        'empty_styles': _source('empty_styles', '''
          systemOverlayStyle: const SystemUiOverlayStyle(),
          iconTheme: const IconThemeData(),
          actionsIconTheme: const IconThemeData(),
        '''),
        'null_styles': _source('null_styles', '''
          systemOverlayStyle: null,
          iconTheme: null,
          actionsIconTheme: null,
        '''),
        'null_style_fields': _source('null_style_fields', '''
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: null,
            statusBarBrightness: null,
            statusBarIconBrightness: null,
            systemNavigationBarColor: null,
            systemNavigationBarDividerColor: null,
            systemNavigationBarIconBrightness: null,
            systemNavigationBarContrastEnforced: null,
            systemStatusBarContrastEnforced: null,
          ),
          iconTheme: const IconThemeData(
            color: null, size: null, opacity: null, fill: null,
            weight: null, grade: null, opticalSize: null,
            shadows: null, applyTextScaling: null,
          ),
          actionsIconTheme: const IconThemeData(size: 18, color: null),
        '''),
        for (final name in ['light', 'dark'])
          'overlay_$name': _source(
            'overlay_$name',
            'systemOverlayStyle: SystemUiOverlayStyle.$name,',
          ),
        'overlay_copy_fields': _source(
          'overlay_copy_fields',
          '''
          systemOverlayStyle: changed.copyWith(
            statusBarColor: null,
            statusBarBrightness: null,
            statusBarIconBrightness: null,
            systemNavigationBarColor: null,
            systemNavigationBarDividerColor: null,
            systemNavigationBarIconBrightness: null,
            systemNavigationBarContrastEnforced: null,
            systemStatusBarContrastEnforced: null,
          ),
          ''',
          prelude: '''
            const original = SystemUiOverlayStyle(
              statusBarColor: Colors.white,
              statusBarBrightness: Brightness.light,
              statusBarIconBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.white,
              systemNavigationBarDividerColor: Colors.white,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: true,
              systemStatusBarContrastEnforced: false,
            );
            final changed = original.copyWith(
              statusBarColor: Colors.transparent,
              statusBarBrightness: Brightness.dark,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Color(0xFF112233),
              systemNavigationBarDividerColor: Color(0xFF445566),
              systemNavigationBarIconBrightness: Brightness.dark,
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: true,
            );
          ''',
        ),
        'prefixed_style_aliases': _source(
          'prefixed_style_aliases',
          '''
            systemOverlayStyle: Overlay.dark
                .copyWith(statusBarColor: Colors.transparent)
                .copyWith(systemStatusBarContrastEnforced: false),
            iconTheme: icons,
            actionsIconTheme: const material.IconThemeData(size: 18),
          ''',
          imports: '''
            import 'package:flutter/material.dart';
            import 'package:flutter/material.dart' as material;
            import 'package:flutter/services.dart' as services;
          ''',
          declarations: '''
            typedef Overlay = services.SystemUiOverlayStyle;
            typedef IconStyle = material.IconThemeData;
          ''',
          prelude:
              'const icons = IconStyle(size: 22, applyTextScaling: false);',
        ),
        'prefixed_overlay_constructor': _source(
          'prefixed_overlay_constructor',
          'systemOverlayStyle: overlay.copyWith(statusBarColor: null),',
          imports: '''
            import 'package:flutter/material.dart';
            import 'package:flutter/services.dart' as services;
          ''',
          declarations: 'typedef Overlay = services.SystemUiOverlayStyle;',
          prelude: '''
            const overlay = Overlay(
              statusBarColor: Color(0xFF123456),
              statusBarIconBrightness: Brightness.dark,
            );
          ''',
        ),
        'runtime_overlay_choice': _source(
          'runtime_overlay_choice',
          '''
            systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ''',
        ),
        'overlay_empty_copy': _source(
          'overlay_empty_copy',
          'systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(),',
        ),
        'nullable_color_copy_chain': _source(
          'nullable_color_copy_chain',
          '''
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.red,
            ).copyWith(
              statusBarColor: Theme.of(context).iconTheme.color,
            ).copyWith(
              statusBarColor: const Color(0xFF123456),
            ).copyWith(
              statusBarColor: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ''',
        ),
        'nullable_overlay_override': _source(
          'nullable_overlay_override',
          '''
            systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
              systemNavigationBarContrastEnforced: true,
              systemStatusBarContrastEnforced: false,
            ).copyWith(
              systemNavigationBarContrastEnforced: contrast,
              systemStatusBarContrastEnforced: contrast,
            ),
          ''',
          constructorParameters: 'this.contrast',
          fields: 'final bool? contrast;',
        ),
        'nullable_empty_overlay_override': _source(
          'nullable_empty_overlay_override',
          '''
            systemOverlayStyle: const SystemUiOverlayStyle().copyWith(
              systemNavigationBarContrastEnforced: contrast,
            ),
          ''',
          constructorParameters: 'this.contrast',
          fields: 'final bool? contrast;',
        ),
        'conditional_nullable_fields': _source(
          'conditional_nullable_fields',
          '''
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: isDark ? const Color(0xFF112233) : null,
              statusBarIconBrightness: isDark ? Brightness.light : null,
            ),
            iconTheme: IconThemeData(
              shadows: isDark
                  ? const [Shadow(color: Color(0x55010203), blurRadius: 4)]
                  : null,
              applyTextScaling: isDark ? false : null,
            ),
          ''',
          prelude: '''
            final isDark = Theme.of(context).brightness == Brightness.dark;
          ''',
        ),
        'helper_overlay_copy': _source(
          'helper_overlay_copy',
          '''
            systemOverlayStyle: _overlay(isDark)
                .copyWith(statusBarColor: const Color(0xFF123456))
                .copyWith(statusBarColor: _overlayColor(isDark)),
          ''',
          declarations: '''
            Color? _overlayColor(bool enabled) => enabled ? Colors.red : null;
            SystemUiOverlayStyle _overlay(bool dark) => dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark;
          ''',
          prelude: '''
            final isDark = Theme.of(context).brightness == Brightness.dark;
          ''',
        ),
        'runtime_overlay_copy': _source(
          'runtime_overlay_copy',
          '''
            systemOverlayStyle: colored.copyWith(
              statusBarColor: isDark ? null : Colors.transparent,
              statusBarIconBrightness: isDark ? Brightness.dark : null,
              systemNavigationBarContrastEnforced: isDark ? false : null,
            ),
          ''',
          prelude: '''
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final overlay = isDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark;
            final colored = overlay.copyWith(
              statusBarColor: const Color(0xFF123456),
              systemNavigationBarContrastEnforced: true,
            );
          ''',
        ),
      });
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    });

    test('all eight overlay fields reach the AppBar slot', () {
      expect(_appBar(result, 'all_style_fields')['systemOverlayStyle'], {
        'statusBarColor': 0xFF112233,
        'statusBarBrightness': 'dark',
        'statusBarIconBrightness': 'light',
        'systemNavigationBarColor': 0xFF445566,
        'systemNavigationBarDividerColor': 0xFF778899,
        'systemNavigationBarIconBrightness': 'dark',
        'systemNavigationBarContrastEnforced': false,
        'systemStatusBarContrastEnforced': true,
      });
    });

    test('both icon slots preserve all nine fields and numeric wire types', () {
      final appBar = _appBar(result, 'all_style_fields');
      final iconTheme = appBar['iconTheme']! as Map<Object?, Object?>;
      final actionsIconTheme =
          appBar['actionsIconTheme']! as Map<Object?, Object?>;
      expect(iconTheme, {
        'color': 0xFF123456,
        'size': 24.0,
        'opacity': 0.5,
        'fill': 1.0,
        'weight': 600.0,
        'grade': -25.0,
        'opticalSize': 48.0,
        'shadows': [
          {
            'color': 0x55010203,
            'offset': {'x': 0.0, 'y': 2.0},
            'blurRadius': 4.0,
          },
        ],
        'applyTextScaling': true,
      });
      expect(actionsIconTheme, {
        'color': 0,
        'size': 0.0,
        'opacity': 0.0,
        'fill': 0.0,
        'weight': 100.0,
        'grade': 0.0,
        'opticalSize': 20.0,
        'shadows': <Object?>[],
        'applyTextScaling': false,
      });
      for (final field in [
        'size',
        'opacity',
        'fill',
        'weight',
        'grade',
        'opticalSize',
      ]) {
        expect(iconTheme[field], isA<double>(), reason: field);
        expect(actionsIconTheme[field], isA<double>(), reason: field);
      }
    });

    test('the existing text style slots remain independent', () {
      final appBar = _appBar(result, 'all_style_fields');
      expect(appBar['titleTextStyle'], {'fontSize': 24.0, 'color': 0xFFFFFFFF});
      expect(
        appBar['toolbarTextStyle'],
        {'fontSize': 14.0, 'color': 0xFF000000},
      );
    });

    test('omitted and null styles remain unset while empty styles stay maps',
        () {
      final omitted = _appBar(result, 'omitted_styles');
      final empty = _appBar(result, 'empty_styles');
      final explicitNull = _appBar(result, 'null_styles');
      for (final field in [
        'systemOverlayStyle',
        'iconTheme',
        'actionsIconTheme',
      ]) {
        expect(omitted.containsKey(field), isFalse, reason: field);
        expect(explicitNull[field], isNull, reason: field);
        expect(empty[field], <String, Object?>{}, reason: field);
      }
    });

    test('explicit null fields never acquire compiler defaults', () {
      final appBar = _appBar(result, 'null_style_fields');
      for (final field in ['systemOverlayStyle', 'iconTheme']) {
        final style = appBar[field]! as Map<Object?, Object?>;
        expect(style.values, everyElement(isNull), reason: field);
      }
      final actions = appBar['actionsIconTheme']! as Map<Object?, Object?>;
      expect(actions['size'], 18.0);
      expect(actions['color'], isNull);
      expect(actions.containsKey('shadows'), isFalse);
    });

    for (final (name, expected) in [('light', _light), ('dark', _dark)]) {
      test('SystemUiOverlayStyle.$name matches Flutter 3.47.7', () {
        expect(
          _appBar(result, 'overlay_$name')['systemOverlayStyle'],
          expected,
        );
      });
    }

    test('copyWith preserves every field and the layer for null overrides', () {
      expect(_appBar(result, 'overlay_copy_fields')['systemOverlayStyle'], {
        'statusBarColor': 0xFFFFFFFF,
        'statusBarBrightness': 'light',
        'statusBarIconBrightness': 'dark',
        'systemNavigationBarColor': 0xFFFFFFFF,
        'systemNavigationBarDividerColor': 0xFFFFFFFF,
        'systemNavigationBarIconBrightness': 'light',
        'systemNavigationBarContrastEnforced': true,
        'systemStatusBarContrastEnforced': false,
        'copyWith': [
          {
            'statusBarColor': 0,
            'statusBarBrightness': 'dark',
            'statusBarIconBrightness': 'light',
            'systemNavigationBarColor': 0xFF112233,
            'systemNavigationBarDividerColor': 0xFF445566,
            'systemNavigationBarIconBrightness': 'dark',
            'systemNavigationBarContrastEnforced': false,
            'systemStatusBarContrastEnforced': true,
          },
          // RFW omits literal null entries; omitted overrides retain fields.
          <String, Object?>{},
        ],
      });
    });

    test('prefixes and type aliases preserve constants and chained copyWith',
        () {
      final appBar = _appBar(result, 'prefixed_style_aliases');
      expect(appBar['systemOverlayStyle'], {
        ..._dark,
        'copyWith': [
          {'statusBarColor': 0},
          {'systemStatusBarContrastEnforced': false},
        ],
      });
      expect(appBar['iconTheme'], {'size': 22.0, 'applyTextScaling': false});
      expect(appBar['actionsIconTheme'], {'size': 18.0});
      expect(
        _appBar(result, 'prefixed_overlay_constructor')['systemOverlayStyle'],
        {
          'statusBarColor': 0xFF123456,
          'statusBarIconBrightness': 'dark',
          'copyWith': [<String, Object?>{}],
        },
      );
    });

    test('runtime brightness selects the matching native overlay constant', () {
      final overlay =
          _appBar(result, 'runtime_overlay_choice')['systemOverlayStyle'];
      expect(_atBrightness(overlay, 'dark'), _light);
      expect(_atBrightness(overlay, 'light'), _dark);
    });

    test('runtime receivers preserve their bases and nullable override layers',
        () {
      final overlay =
          _appBar(result, 'runtime_overlay_copy')['systemOverlayStyle'];
      expect(_atBrightness(overlay, 'dark'), {
        ..._light,
        'copyWith': [
          {
            'statusBarColor': 0xFF123456,
            'systemNavigationBarContrastEnforced': true,
          },
          {
            'statusBarColor': null,
            'statusBarIconBrightness': 'dark',
            'systemNavigationBarContrastEnforced': false,
          },
        ],
      });
      expect(_atBrightness(overlay, 'light'), {
        ..._dark,
        'copyWith': [
          {
            'statusBarColor': 0xFF123456,
            'systemNavigationBarContrastEnforced': true,
          },
          {
            'statusBarColor': 0,
            'statusBarIconBrightness': null,
            'systemNavigationBarContrastEnforced': null,
          },
        ],
      });
    });

    test('nullable host booleans remain separate from previous copy layers',
        () {
      final overlay =
          _appBar(result, 'nullable_overlay_override')['systemOverlayStyle'];
      expect(overlay, {
        ..._dark,
        'copyWith': [
          {
            'systemNavigationBarContrastEnforced': true,
            'systemStatusBarContrastEnforced': false,
          },
          {
            'systemNavigationBarContrastEnforced':
                _dataReference(['context', 'contrast']),
            'systemStatusBarContrastEnforced':
                _dataReference(['context', 'contrast']),
          },
        ],
      });
    });

    test('a nullable override on an empty receiver remains in its copy layer',
        () {
      final overlay = _appBar(
        result,
        'nullable_empty_overlay_override',
      )['systemOverlayStyle'];
      expect(overlay, {
        'copyWith': [
          {
            'systemNavigationBarContrastEnforced':
                _dataReference(['context', 'contrast']),
          },
        ],
      });
    });

    test('conditional null fields remain nullable in style constructors', () {
      final appBar = _appBar(result, 'conditional_nullable_fields');
      expect(_atBrightness(appBar['systemOverlayStyle'], 'dark'), {
        'statusBarColor': 0xFF112233,
        'statusBarIconBrightness': 'light',
      });
      expect(_atBrightness(appBar['systemOverlayStyle'], 'light'), {
        'statusBarColor': null,
        'statusBarIconBrightness': null,
      });
      expect(_atBrightness(appBar['iconTheme'], 'dark'), {
        'shadows': [
          {'color': 0x55010203, 'blurRadius': 4.0},
        ],
        'applyTextScaling': false,
      });
      expect(_atBrightness(appBar['iconTheme'], 'light'), {
        'shadows': null,
        'applyTextScaling': null,
      });
    });

    test('ordinary helpers preserve nullable overrides and overlay receivers',
        () {
      final overlay =
          _appBar(result, 'helper_overlay_copy')['systemOverlayStyle'];
      expect(_atBrightness(overlay, 'dark'), {
        ..._light,
        'copyWith': [
          {'statusBarColor': 0xFF123456},
          {'statusBarColor': 0xFFF44336},
        ],
      });
      expect(_atBrightness(overlay, 'light'), {
        ..._dark,
        'copyWith': [
          {'statusBarColor': 0xFF123456},
          {'statusBarColor': null},
        ],
      });
    });

    test('copyWith with no arguments preserves an empty override layer', () {
      expect(_appBar(result, 'overlay_empty_copy')['systemOverlayStyle'], {
        ..._dark,
        'copyWith': [<String, Object?>{}],
      });
    });

    test('nullable color and later nonnull overrides preserve chain order', () {
      expect(
        _appBar(result, 'nullable_color_copy_chain')['systemOverlayStyle'],
        {
          'statusBarColor': 0xFFF44336,
          'copyWith': [
            {
              'statusBarColor': _dataReference(['theme', 'iconTheme', 'color']),
            },
            {'statusBarColor': 0xFF123456},
            {
              'statusBarColor':
                  _dataReference(['theme', 'textTheme', 'bodyMedium', 'color']),
            },
          ],
        },
      );
    });

    test('the delivered style properties require capability version 12', () {
      final sidecar = jsonDecode(
        result.readerWriter.testing.readString(
          AssetId(_package, 'assets/paywalls/all_style_fields.capability.json'),
        ),
      ) as Map<String, dynamic>;
      final manifest = sidecar['manifest'] as Map<String, dynamic>;
      expect(manifest['builtInFloor'], 12);
      expect(
        result.readerWriter.testing.readBytes(
          AssetId(_package, 'assets/paywalls/all_style_fields.rfw'),
        ),
        isNotEmpty,
      );
    });
  });

  const overlayColorFields = [
    'statusBarColor',
    'systemNavigationBarColor',
    'systemNavigationBarDividerColor',
  ];
  const nullableThemeColors = [
    (
      'icon',
      'Theme.of(context).iconTheme.color',
      ['theme', 'iconTheme', 'color'],
    ),
    (
      'text',
      'Theme.of(context).textTheme.bodyMedium!.color',
      ['theme', 'textTheme', 'bodyMedium', 'color'],
    ),
  ];

  for (final field in overlayColorFields) {
    for (final (readName, expression, parts) in nullableThemeColors) {
      test('nullable color $readName preserves the $field base and copy layer',
          () async {
        final id = 'nullable_color_${readName}_$field';
        final source = _source(id, '''
          systemOverlayStyle: const SystemUiOverlayStyle($field: Colors.red)
              .copyWith($field: $expression),
        ''');
        final result = await _build({id: source});
        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        expect(_appBar(result, id)['systemOverlayStyle'], {
          field: 0xFFF44336,
          'copyWith': [
            {field: _dataReference(parts)},
          ],
        });
      });
    }
  }

  group('nullable color without an existing fallback', () {
    late TestBuilderResult result;

    setUpAll(() async {
      final fixtures = <String, String>{};
      for (final (readName, expression, _) in nullableThemeColors) {
        final arguments = [
          for (final field in overlayColorFields) '$field: $expression',
        ].join(', ');
        final nullArguments = [
          for (final field in overlayColorFields) '$field: null',
        ].join(', ');
        for (final (form, style) in [
          ('constructor', 'SystemUiOverlayStyle($arguments)'),
          ('empty_copy', 'const SystemUiOverlayStyle().copyWith($arguments)'),
          (
            'null_copy',
            'const SystemUiOverlayStyle($nullArguments).copyWith($arguments)',
          ),
        ]) {
          final id = 'nullable_color_${readName}_$form';
          fixtures[id] = _source(id, 'systemOverlayStyle: $style,');
        }
      }
      result = await _build(fixtures);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    });

    for (final (readName, _, parts) in nullableThemeColors) {
      for (final form in ['constructor', 'empty_copy', 'null_copy']) {
        test('$readName $form preserves all three theme color references', () {
          final id = 'nullable_color_${readName}_$form';
          final overlay = _appBar(result, id)['systemOverlayStyle']!
              as Map<String, Object?>;
          final references = {
            for (final field in overlayColorFields)
              field: _dataReference(parts),
          };
          expect(
            overlay,
            form == 'constructor'
                ? references
                : {
                    'copyWith': [references],
                  },
          );
        });
      }
    }
  });

  test('copyWith supports 1000 ordered empty override layers', () async {
    const id = 'overlay_copy_limit';
    expect(kMaxStructuredCopyWithLayers, 1000);
    final chain = List<String>.filled(
      kMaxStructuredCopyWithLayers,
      '.copyWith()',
    ).join();
    final result = await _build({
      id: _source(id, 'systemOverlayStyle: SystemUiOverlayStyle.dark$chain,'),
    });
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(_appBar(result, id)['systemOverlayStyle'], {
      ..._dark,
      'copyWith': List<Map<String, Object?>>.filled(1000, const {}),
    });
  });

  test('copyWith refuses a chain exceeding the 1000 layer limit', () async {
    const id = 'overlay_copy_over_limit';
    final chain = List<String>.filled(
      kMaxStructuredCopyWithLayers + 1,
      '.copyWith()',
    ).join();
    final source =
        _source(id, 'systemOverlayStyle: SystemUiOverlayStyle.dark$chain,');
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: _package,
      includeFlutter: true,
    );
    final sourceId = AssetId(_package, 'lib/paywalls/$id.dart');
    readerWriter.testing.writeString(sourceId, source);
    final messages = <String>[];
    final result = await testBuilder(
      restageCodegenBuilder(BuilderOptions.empty),
      {sourceId.toString(): source},
      rootPackage: _package,
      readerWriter: readerWriter,
      onLog: (record) => messages.add(record.message),
      outputs: const {},
    );
    expect(result.succeeded, isFalse, reason: messages.join('\n'));
    expect(
      messages.join('\n'),
      allOf(contains('[unrecognizedMethodCall]'), contains('at most 1000')),
    );
  });

  group('IconThemeData operations', () {
    late TestBuilderResult result;

    setUpAll(() async {
      const runtimeFields =
          'this.size, required this.progress, required this.dark';
      const fieldDeclarations = '''
        final double? size;
        final double progress;
        final bool dark;
      ''';
      result = await _build({
        'icon_fallback': _source(
          'icon_fallback',
          '''
            iconTheme: const IconThemeData.fallback(),
            actionsIconTheme: IconThemeData.fallback(),
          ''',
        ),
        'icon_issue_example': _source(
          'icon_issue_example',
          '''
            iconTheme: (const IconThemeData.fallback()).copyWith(size: size),
            actionsIconTheme: IconThemeData.lerp(start, end, progress),
          ''',
          constructorParameters: runtimeFields,
          fields: fieldDeclarations,
          prelude: '''
            const start = IconThemeData(size: 18, opacity: 0.5);
            const end = IconThemeData(
              size: 30,
              color: Color(0xFF102030),
              shadows: [],
              applyTextScaling: true,
            );
          ''',
        ),
        'icon_copy_chain': _source(
          'icon_copy_chain',
          '''
            iconTheme: const IconThemeData(size: 20, fill: 1)
                .copyWith(size: 0, color: null)
                .copyWith(applyTextScaling: false, shadows: const []),
            actionsIconTheme: const Icons().copyWith(),
          ''',
          imports: '''
            import 'package:flutter/material.dart' as material;
            import 'package:flutter/material.dart' hide Icons;
          ''',
          declarations: 'typedef Icons = material.IconThemeData;',
        ),
        'icon_lerp_nulls': _source(
          'icon_lerp_nulls',
          '''
            iconTheme: IconThemeData.lerp(null, null, progress),
            actionsIconTheme: IconThemeData.lerp(
              dark ? const IconThemeData.fallback() : null,
              IconThemeData.lerp(null, const IconThemeData(weight: 700), 2),
              -0.5,
            ).copyWith(grade: 25),
          ''',
          constructorParameters: runtimeFields,
          fields: fieldDeclarations,
        ),
        'icon_helper': _source(
          'icon_helper',
          '''
            iconTheme: themed(dark).copyWith(opticalSize: 40),
            actionsIconTheme: dark
                ? IconThemeData.lerp(base, base.copyWith(size: size), 0.5)
                : base,
          ''',
          constructorParameters: runtimeFields,
          fields: fieldDeclarations,
          declarations: '''
            const base = IconThemeData(size: 12);
            IconThemeData themed(bool dark) =>
                dark ? const IconThemeData.fallback() : base;
          ''',
        ),
      });
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    });

    test('fallback is carried for the native constructor', () {
      final appBar = _appBar(result, 'icon_fallback');
      expect(appBar['iconTheme'], {'fallback': true});
      expect(appBar['actionsIconTheme'], {'fallback': true});
    });

    test('copyWith and lerp keep runtime values for native evaluation', () {
      final appBar = _appBar(result, 'icon_issue_example');
      expect(appBar['iconTheme'], {
        'fallback': true,
        'copyWith': [
          {
            'size': _dataReference(['context', 'size']),
          },
        ],
      });
      expect(appBar['actionsIconTheme'], {
        'lerp': {
          'a': {'size': 18.0, 'opacity': 0.5},
          'b': {
            'size': 30.0,
            'color': 0xFF102030,
            'shadows': <Object?>[],
            'applyTextScaling': true,
          },
          't': _dataReference(['context', 'progress']),
        },
      });
    });

    test('copyWith chains keep ordered layers, zero, false and empty lists',
        () {
      final appBar = _appBar(result, 'icon_copy_chain');
      expect(appBar['iconTheme'], {
        'size': 20.0,
        'fill': 1.0,
        'copyWith': [
          {'size': 0.0},
          {'applyTextScaling': false, 'shadows': <Object?>[]},
        ],
      });
      expect(appBar['actionsIconTheme'], {
        'copyWith': [<String, Object?>{}],
      });
    });

    test('lerp keeps null endpoints, extrapolation and nested operations', () {
      final appBar = _appBar(result, 'icon_lerp_nulls');
      expect(appBar['iconTheme'], {
        'lerp': {
          't': _dataReference(['context', 'progress']),
        },
      });
      final actions = appBar['actionsIconTheme']! as Map<Object?, Object?>;
      expect(actions['copyWith'], [
        {'grade': 25.0},
      ]);
      final lerp = actions['lerp']! as Map<Object?, Object?>;
      expect(lerp['t'], -0.5);
      expect(lerp['b'], {
        'lerp': {
          'b': {'weight': 700.0},
          't': 2.0,
        },
      });
      expect(
        _resolve(lerp['a'], {
          'context': {'dark': true},
        }),
        {'fallback': true},
      );
      expect(
        lerp['a'],
        isA<fmt.Switch>().having(
          (value) => value.outputs.containsKey(false),
          'null branch present',
          isFalse,
        ),
      );
    });

    test('helpers, conditionals and bound constants compose', () {
      final appBar = _appBar(result, 'icon_helper');
      expect(
        _resolve(appBar['iconTheme'], {
          'context': {'dark': true},
        }),
        {
          'fallback': true,
          'copyWith': [
            {'opticalSize': 40.0},
          ],
        },
      );
      expect(
        _resolve(appBar['iconTheme'], {
          'context': {'dark': false},
        }),
        {
          'size': 12.0,
          'copyWith': [
            {'opticalSize': 40.0},
          ],
        },
      );
      expect(
        _resolve(appBar['actionsIconTheme'], {
          'context': {'dark': true, 'size': 16.0},
        }),
        {
          'lerp': {
            'a': {'size': 12.0},
            'b': {
              'size': 12.0,
              'copyWith': [
                {'size': 16.0},
              ],
            },
            't': 0.5,
          },
        },
      );
    });

    test('icon theme operations stay within capability version 12', () {
      for (final id in [
        'icon_fallback',
        'icon_issue_example',
        'icon_copy_chain',
        'icon_lerp_nulls',
        'icon_helper',
      ]) {
        final sidecar = jsonDecode(
          result.readerWriter.testing.readString(
            AssetId(_package, 'assets/paywalls/$id.capability.json'),
          ),
        ) as Map<String, dynamic>;
        final manifest = sidecar['manifest'] as Map<String, dynamic>;
        expect(manifest['builtInFloor'], 12, reason: id);
      }
    });
  });

  for (final (name, expression) in [
    ('theme_read', 'Theme.of(context).iconTheme.copyWith(size: 18)'),
    ('named_lerp', 'IconThemeData.lerp(null, null, 0.5).merge(null)'),
  ]) {
    test('unsupported IconThemeData $name refuses instead of losing fields',
        () async {
      final id = 'unsupported_icon_$name';
      final source = _source(id, 'iconTheme: $expression,');
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: _package,
        includeFlutter: true,
      );
      final sourceId = AssetId(_package, 'lib/paywalls/$id.dart');
      readerWriter.testing.writeString(sourceId, source);
      final messages = <String>[];
      final result = await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {sourceId.toString(): source},
        rootPackage: _package,
        readerWriter: readerWriter,
        onLog: (record) => messages.add(record.message),
        outputs: const {},
      );
      expect(result.succeeded, isFalse, reason: messages.join('\n'));
      expect(messages.join('\n'), contains('IconThemeData'));
    });
  }

  group('AppBar notification predicate', () {
    late TestBuilderResult result;
    const accepted = {
      'predicate_literal': (
        '(notification) => notification.depth == 1,',
        '',
        '',
      ),
      'predicate_block': (
        '(ScrollNotification n) { return 2 == (n).depth; },',
        '',
        '',
      ),
      'predicate_runtime': ('(n) => n.depth == depth,', '', ''),
      'predicate_constant': (
        '(n) => n.depth == nested,',
        'const nested = 3;',
        ''
      ),
      'predicate_default': ('defaultScrollNotificationPredicate,', '', ''),
      'predicate_bound': (
        'predicate,',
        '',
        'final predicate = (ScrollNotification n) => n.depth == 1;'
      ),
    };

    setUpAll(() async {
      result = await _build({
        for (final MapEntry(key: id, value: (predicate, declarations, prelude))
            in accepted.entries)
          id: _source(
            id,
            'notificationPredicate: $predicate scrolledUnderElevation: 4,',
            declarations: declarations,
            prelude: prelude,
            constructorParameters: 'required this.depth',
            fields: 'final int depth;',
          ),
      });
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    });

    test('depth comparisons carry the accepted depth', () {
      expect(_appBar(result, 'predicate_literal')['notificationPredicate'], 1);
      expect(_appBar(result, 'predicate_block')['notificationPredicate'], 2);
      expect(_appBar(result, 'predicate_constant')['notificationPredicate'], 3);
      expect(_appBar(result, 'predicate_bound')['notificationPredicate'], 1);
      expect(
        _appBar(result, 'predicate_runtime')['notificationPredicate'],
        _dataReference(['context', 'depth']),
      );
      expect(
        _appBar(result, 'predicate_literal')['scrolledUnderElevation'],
        4.0,
      );
    });

    test("Flutter's default predicate keeps the default", () {
      expect(
        _appBar(result, 'predicate_default'),
        isNot(contains('notificationPredicate')),
      );
    });

    test('predicates stay within capability version 12', () {
      for (final id in accepted.keys) {
        final sidecar = jsonDecode(
          result.readerWriter.testing.readString(
            AssetId(_package, 'assets/paywalls/$id.capability.json'),
          ),
        ) as Map<String, dynamic>;
        final manifest = sidecar['manifest'] as Map<String, dynamic>;
        expect(manifest['builtInFloor'], 12, reason: id);
      }
    });
  });

  for (final (name, predicate) in [
    ('side_effect', '(n) { debugPrint("scroll"); return n.depth == 1; }'),
    ('relational', '(n) => n.depth <= 1'),
    ('double', '(n) => n.depth == 1.0'),
    ('nullable', '(n) => n.depth == maybeDepth'),
    ('self', '(n) => n.depth == n.depth'),
    ('other_field', '(n) => n.metrics.axis == Axis.vertical'),
    ('combined', '(n) => n.depth == 1 || n.depth == 0'),
    ('tear_off', 'nestedOnly'),
  ]) {
    test('notificationPredicate $name is refused precisely', () async {
      final id = 'predicate_$name';
      final source = _source(
        id,
        'notificationPredicate: $predicate,',
        declarations: 'bool nestedOnly(ScrollNotification n) => n.depth == 1;',
        constructorParameters: 'this.maybeDepth',
        fields: 'final int? maybeDepth;',
      );
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: _package,
        includeFlutter: true,
      );
      final sourceId = AssetId(_package, 'lib/paywalls/$id.dart');
      readerWriter.testing.writeString(sourceId, source);
      final messages = <String>[];
      final result = await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {sourceId.toString(): source},
        rootPackage: _package,
        readerWriter: readerWriter,
        onLog: (record) => messages.add(record.message),
        outputs: const {},
      );
      expect(result.succeeded, isFalse, reason: messages.join('\n'));
      expect(
        messages.join('\n'),
        allOf(
          contains('[unknownProperty]'),
          contains('notification.depth == <int>'),
        ),
      );
    });
  }

  group('AppBar style canonical identity', () {
    for (final (name, expression, slot) in [
      (
        'overlay_constructor',
        'const SystemUiOverlayStyle()',
        'systemOverlayStyle'
      ),
      ('overlay_constant', 'SystemUiOverlayStyle.dark', 'systemOverlayStyle'),
      (
        'overlay_copy',
        'SystemUiOverlayStyle.dark.copyWith()',
        'systemOverlayStyle'
      ),
      ('overlay_alias', 'Overlay.dark', 'systemOverlayStyle'),
      ('icon_constructor', 'const IconThemeData()', 'iconTheme'),
      ('actions_icon_constructor', 'const IconThemeData()', 'actionsIconTheme'),
    ]) {
      test('an app-defined $name cannot impersonate the Flutter type',
          () async {
        final id = 'lookalike_$name';
        final source = _source(
          id,
          '$slot: $expression,',
          imports: "import 'package:flutter/material.dart' hide IconThemeData;",
          declarations: '''
            class SystemUiOverlayStyle {
              const SystemUiOverlayStyle();
              static const dark = SystemUiOverlayStyle();
              SystemUiOverlayStyle copyWith() => this;
            }
            typedef Overlay = SystemUiOverlayStyle;
            class IconThemeData {
              const IconThemeData();
            }
          ''',
        );
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: _package,
          includeFlutter: true,
        );
        final sourceId = AssetId(_package, 'lib/paywalls/$id.dart');
        readerWriter.testing.writeString(sourceId, source);
        final messages = <String>[];
        final result = await testBuilder(
          restageCodegenBuilder(BuilderOptions.empty),
          {sourceId.toString(): source},
          rootPackage: _package,
          readerWriter: readerWriter,
          onLog: (record) => messages.add(record.message),
          outputs: const {},
        );
        expect(result.succeeded, isFalse, reason: messages.join('\n'));
        final code = switch (name) {
          'overlay_constant' || 'overlay_alias' => 'unresolvedIdentifier',
          'overlay_copy' => 'unrecognizedMethodCall',
          _ => 'unknownWidget',
        };
        expect(
          messages.join('\n'),
          allOf(
            contains('[$code]'),
            contains(
              slot == 'systemOverlayStyle'
                  ? 'SystemUiOverlayStyle'
                  : 'IconThemeData',
            ),
          ),
        );
      });
    }
  });
}
