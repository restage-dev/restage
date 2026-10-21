import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show RfwConstructorPresenceProtocol;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  for (final scenario in [
    (
      name: 'authored_values',
      arguments: '''
        toolbarOpacity: 0.4,
        bottomOpacity: 0.7,
        excludeHeaderSemantics: true,
        useDefaultSemanticsOrder: false,
        automaticallyImplyActions: false,
        animateColor: true,
        centerTitle: false,
      ''',
      output: allOf([
        contains('toolbarOpacity: 0.4'),
        contains('bottomOpacity: 0.7'),
        contains('excludeHeaderSemantics: true'),
        contains('useDefaultSemanticsOrder: false'),
        contains('automaticallyImplyActions: false'),
        contains('animateColor: true'),
        contains('centerTitle: false'),
      ]),
    ),
    (
      name: 'zero_and_boolean_values',
      arguments: '''
        toolbarOpacity: 0,
        bottomOpacity: 0,
        excludeHeaderSemantics: false,
        useDefaultSemanticsOrder: true,
        automaticallyImplyActions: true,
        animateColor: false,
        centerTitle: true,
      ''',
      output: allOf([
        contains('toolbarOpacity: 0.0'),
        contains('bottomOpacity: 0.0'),
        contains('excludeHeaderSemantics: false'),
        contains('useDefaultSemanticsOrder: true'),
        contains('automaticallyImplyActions: true'),
        contains('animateColor: false'),
        contains('centerTitle: true'),
      ]),
    ),
    (
      name: 'omitted_values',
      arguments: '',
      output: allOf([
        isNot(contains('toolbarOpacity:')),
        isNot(contains('bottomOpacity:')),
        isNot(contains('excludeHeaderSemantics:')),
        isNot(contains('useDefaultSemanticsOrder:')),
        isNot(contains('automaticallyImplyActions:')),
        isNot(contains('animateColor:')),
        isNot(contains('centerTitle:')),
        isNot(contains('toolbarHeight:')),
      ]),
    ),
  ]) {
    test('AppBar lowers ${scenario.name} from Flutter authoring', () async {
      final id = 'app_bar_${scenario.name}';
      final source = '''
        import 'package:flutter/material.dart';

        class PaywallSource {
          const PaywallSource({required this.id});
          final String id;
        }

        @PaywallSource(id: '$id')
        class CapabilityAppBar extends StatelessWidget {
          const CapabilityAppBar();
          @override
          Widget build(BuildContext context) => Scaffold(
            appBar: AppBar(
              title: const Text('Welcome'),
              flexibleSpace: const Text('Background'),
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(30),
                child: Text('Bottom'),
              ),
              ${scenario.arguments}
            ),
            body: const SizedBox(),
          );
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      final sourceId = AssetId('apps_examples', 'lib/paywalls/$id.dart');
      readerWriter.testing.writeString(sourceId, source);
      final capability = decodedMatches(
        predicate<String>(
          (text) {
            final sidecar = jsonDecode(text) as Map<String, dynamic>;
            final manifest = sidecar['manifest'] as Map<String, dynamic>;
            return manifest['builtInFloor'] == 12;
          },
          'capability manifest with builtInFloor 12',
        ),
      );

      final result = await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {sourceId.toString(): source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/$id.rfwtxt': decodedMatches(
            allOf(
              contains('appBar: AppBar('),
              contains('flexibleSpace: Text(text: "Background")'),
              contains('bottom: PreferredSize(preferredSize: 30.0'),
              contains('child: Text(text: "Bottom")'),
              contains('bottomHeight: 30.0'),
              scenario.output,
            ),
          ),
          'apps_examples|assets/paywalls/$id.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/$id.capability.json': capability,
          'apps_examples|assets/paywalls/screens/paywall_$id.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/screens/paywall_$id.capability.json':
              capability,
        },
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    });
  }

  group('Scaffold AppBar preferred heights', () {
    late TestBuilderResult result;

    setUpAll(() async {
      final fixtures = {
        'default_height': _heightSource('default_height', 'AppBar()'),
        'null_heights': _heightSource(
          'null_heights',
          'AppBar(toolbarHeight: null, bottom: null)',
        ),
        'dynamic_heights': _heightSource(
          'dynamic_heights',
          '''
            AppBar(
              toolbarHeight: height,
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(bottomHeight),
                child: const Text('Bottom'),
              ),
            )
          ''',
        ),
        'aliased_heights': _heightSource(
          'aliased_heights',
          'bar',
          prelude: '''
            final toolbar = height;
            final bottom = NativePreferredSize(
              preferredSize: material.Size.fromHeight(bottomHeight),
              child: const material.Text('Bottom'),
            );
            final bar = NativeAppBar(toolbarHeight: toolbar, bottom: bottom);
          ''',
        ),
        'conditional_null': _heightSource(
          'conditional_null',
          'showBar ? AppBar(toolbarHeight: height) : null',
        ),
        'conditional_preferred_size': _heightSource(
          'conditional_preferred_size',
          '''
            showBar
                ? AppBar(
                    toolbarHeight: height,
                    bottom: PreferredSize(
                      preferredSize: Size.fromHeight(bottomHeight),
                      child: const Text('Bottom'),
                    ),
                  )
                : const PreferredSize(
                    preferredSize: Size.fromHeight(90),
                    child: Text('Standalone'),
                  )
          ''',
        ),
        'multi_arm_app_bar': _heightSource(
          'multi_arm_app_bar',
          '''
            mode == 'a'
                ? AppBar()
                : mode == 'b'
                    ? AppBar(toolbarHeight: 40)
                    : AppBar(toolbarHeight: 60)
          ''',
        ),
        'multi_arm_bottom': _heightSource(
          'multi_arm_bottom',
          '''
            AppBar(
              bottom: mode == 'a'
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(20),
                      child: Text('First'),
                    )
                  : mode == 'b'
                      ? const PreferredSize(
                          preferredSize: Size.fromHeight(30),
                          child: Text('Second'),
                        )
                      : null,
            )
          ''',
        ),
        'nested_nonnullable_height': _heightSource(
          'nested_nonnullable_height',
          'AppBar(bottom: AppBar(toolbarHeight: bottomHeight))',
        ),
        'nested_null_height': _heightSource(
          'nested_null_height',
          'AppBar(bottom: AppBar(toolbarHeight: null))',
        ),
        'nested_nullable_height': _heightSource(
          'nested_nullable_height',
          'AppBar(bottom: AppBar(toolbarHeight: height))',
        ),
        'preferred_size': _heightSource(
          'preferred_size',
          '''
            const PreferredSize(
              preferredSize: Size.fromHeight(90),
              child: Text('Standalone'),
            )
          ''',
        ),
        'tab_bar': _heightSource(
          'tab_bar',
          "const TabBar(tabs: [Tab(text: 'One'), Tab(text: 'Two')])",
        ),
      };
      final sources = {
        for (final fixture in fixtures.entries)
          'apps_examples|lib/paywalls/${fixture.key}.dart': fixture.value,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      for (final source in sources.entries) {
        readerWriter.testing
            .writeString(AssetId.parse(source.key), source.value);
      }
      result = await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      for (final id in fixtures.keys) {
        for (final path in [id, 'screens/paywall_$id']) {
          expect(
            result.readerWriter.testing.readBytes(
              AssetId('apps_examples', 'assets/paywalls/$path.rfw'),
            ),
            isNotEmpty,
            reason: path,
          );
        }
      }
    });

    for (final id in ['default_height', 'null_heights']) {
      test('$id preserves the native toolbar default', () {
        final scaffold = _heightScaffold(result, id);
        expect(_heights(scaffold), {
          'height': null,
          'toolbar': null,
          'bottom': 0.0,
        });
      });
    }

    for (final id in ['dynamic_heights', 'aliased_heights']) {
      test('$id retains independent toolbar and bottom data references', () {
        final scaffold = _heightScaffold(result, id);
        final appBar = scaffold.arguments['appBar']! as fmt.ConstructorCall;
        final bottom = appBar.arguments['bottom']! as fmt.ConstructorCall;
        expect(appBar.name, 'AppBar');
        expect(bottom.name, 'PreferredSize');
        expect(
          scaffold.arguments['appBarToolbarHeight'],
          isA<fmt.DataReference>().having(
            (value) => value.parts,
            'parts',
            ['context', 'height'],
          ),
        );
        expect(
          scaffold.arguments['appBarBottomHeight'],
          isA<fmt.DataReference>().having(
            (value) => value.parts,
            'parts',
            ['context', 'bottomHeight'],
          ),
        );
        expect(
          appBar.arguments['toolbarHeight'],
          isA<fmt.DataReference>().having(
            (value) => value.parts,
            'parts',
            ['context', 'height'],
          ),
        );
        expect(
          bottom.arguments['preferredSize'],
          isA<fmt.DataReference>().having(
            (value) => value.parts,
            'parts',
            ['context', 'bottomHeight'],
          ),
        );
        for (final toolbar in <double?>[null, 72]) {
          expect(
            _heights(scaffold, {'height': toolbar, 'bottomHeight': 23.5}),
            {'height': null, 'toolbar': toolbar, 'bottom': 23.5},
          );
        }
      });
    }

    test('a conditional AppBar and null select matching height metadata', () {
      final scaffold = _heightScaffold(result, 'conditional_null');
      for (final toolbar in <double?>[null, 72]) {
        expect(
          _heights(scaffold, {'showBar': true, 'height': toolbar}),
          {'height': null, 'toolbar': toolbar, 'bottom': 0.0},
        );
        expect(
          _heights(scaffold, {'showBar': false, 'height': toolbar}),
          {'height': null, 'toolbar': null, 'bottom': null},
        );
      }
      expect(
        _resolveHeight(scaffold.arguments['appBar'], {'showBar': false}),
        isNull,
      );
      expect(
        _resolveHeight(scaffold.arguments['appBar'], {'showBar': true}),
        isA<fmt.ConstructorCall>()
            .having((value) => value.name, 'name', 'AppBar'),
      );
    });

    test('a conditional PreferredSize retains its own total height', () {
      final scaffold = _heightScaffold(result, 'conditional_preferred_size');
      for (final toolbar in <double?>[null, 72]) {
        expect(
          _heights(scaffold, {
            'showBar': true,
            'height': toolbar,
            'bottomHeight': 23.5,
          }),
          {'height': null, 'toolbar': toolbar, 'bottom': 23.5},
        );
        expect(
          _heights(scaffold, {
            'showBar': false,
            'height': toolbar,
            'bottomHeight': 23.5,
          }),
          {'height': 90.0, 'toolbar': null, 'bottom': null},
        );
      }
      expect(
        _resolveHeight(scaffold.arguments['appBar'], {'showBar': false}),
        isA<fmt.ConstructorCall>()
            .having((value) => value.name, 'name', 'PreferredSize'),
      );
    });

    test('multi-arm string AppBar branches preserve native height metadata',
        () {
      final scaffold = _heightScaffold(result, 'multi_arm_app_bar');
      for (final branch in <String, double?>{
        'a': null,
        'b': 40,
        'other': 60,
      }.entries) {
        final context = {'mode': branch.key};
        expect(_heights(scaffold, context), {
          'height': null,
          'toolbar': branch.value,
          'bottom': 0.0,
        });
        final appBar = _resolveHeight(scaffold.arguments['appBar'], context)!
            as fmt.ConstructorCall;
        expect(appBar.name, 'AppBar');
        expect(appBar.arguments['toolbarHeight'], branch.value);
      }
    });

    test('multi-arm string bottoms preserve each preferred height', () {
      final scaffold = _heightScaffold(result, 'multi_arm_bottom');
      final appBar = scaffold.arguments['appBar']! as fmt.ConstructorCall;
      expect(appBar.name, 'AppBar');
      for (final branch in <String, double?>{
        'a': 20,
        'b': 30,
        'other': null,
      }.entries) {
        final context = {'mode': branch.key};
        expect(_heights(scaffold, context), {
          'height': null,
          'toolbar': null,
          'bottom': branch.value ?? 0.0,
        });
        expect(
          _resolveHeight(appBar.arguments['bottomHeight'], context),
          branch.value ?? 0.0,
        );
        final bottom = _resolveHeight(appBar.arguments['bottom'], context);
        if (branch.value == null) {
          expect(bottom, isNull);
        } else {
          expect(
            bottom,
            isA<fmt.ConstructorCall>()
                .having((value) => value.name, 'name', 'PreferredSize')
                .having(
                  (value) => value.arguments['preferredSize'],
                  'preferredSize',
                  branch.value,
                ),
          );
        }
      }
    });

    test('nested AppBar keeps a nonnullable runtime preferred height', () {
      final scaffold = _heightScaffold(result, 'nested_nonnullable_height');
      final appBar = scaffold.arguments['appBar']! as fmt.ConstructorCall;
      final bottom = appBar.arguments['bottom']! as fmt.ConstructorCall;
      expect(bottom.name, 'AppBar');
      for (final value in [
        scaffold.arguments['appBarBottomHeight'],
        appBar.arguments['bottomHeight'],
        bottom.arguments['toolbarHeight'],
      ]) {
        expect(
          value,
          isA<fmt.DataReference>().having(
            (value) => value.parts,
            'parts',
            ['context', 'bottomHeight'],
          ),
        );
      }
      for (final height in [0.0, 31.5]) {
        expect(_heights(scaffold, {'bottomHeight': height}), {
          'height': null,
          'toolbar': null,
          'bottom': height,
        });
      }
    });

    test('nested AppBar keeps a nullable runtime toolbar height', () {
      final scaffold = _heightScaffold(result, 'nested_nullable_height');
      final appBar = scaffold.arguments['appBar']! as fmt.ConstructorCall;
      final bottom = appBar.arguments['bottom']! as fmt.ConstructorCall;
      expect(bottom.name, 'AppBar');
      expect(scaffold.arguments['appBarHeight'], isNull);
      expect(scaffold.arguments['appBarToolbarHeight'], isNull);
      final supplied =
          scaffold.arguments['appBarBottomHeight']! as Map<String, Object?>;
      expect(supplied.keys, {
        RfwConstructorPresenceProtocol.markerKey,
        RfwConstructorPresenceProtocol.valueKey,
      });
      expect(supplied[RfwConstructorPresenceProtocol.markerKey], 1);
      for (final value in [
        supplied[RfwConstructorPresenceProtocol.valueKey],
        appBar.arguments['bottomHeight'],
        bottom.arguments['toolbarHeight'],
      ]) {
        expect(
          value,
          isA<fmt.DataReference>().having(
            (value) => value.parts,
            'parts',
            ['context', 'height'],
          ),
        );
      }
    });

    test('nested AppBar with explicit null uses its native preferred height',
        () {
      final scaffold = _heightScaffold(result, 'nested_null_height');
      final appBar = scaffold.arguments['appBar']! as fmt.ConstructorCall;
      final bottom = appBar.arguments['bottom']! as fmt.ConstructorCall;
      expect(_heights(scaffold), {
        'height': null,
        'toolbar': null,
        'bottom': 56.0,
      });
      expect(appBar.arguments['bottomHeight'], 56.0);
      expect(bottom.name, 'AppBar');
      expect(bottom.arguments['toolbarHeight'], isNull);
    });

    for (final entry in {'preferred_size': 90.0, 'tab_bar': 48.0}.entries) {
      test('${entry.key} uses its total height without native AppBar metadata',
          () {
        expect(_heights(_heightScaffold(result, entry.key)), {
          'height': entry.value,
          'toolbar': null,
          'bottom': null,
        });
      });
    }

    test('native AppBar height metadata requires capability floor 12', () {
      for (final id in [
        'default_height',
        'null_heights',
        'dynamic_heights',
        'aliased_heights',
        'conditional_null',
        'conditional_preferred_size',
        'multi_arm_app_bar',
        'multi_arm_bottom',
        'nested_nonnullable_height',
        'nested_null_height',
        'nested_nullable_height',
      ]) {
        for (final path in [id, 'screens/paywall_$id']) {
          final sidecar = jsonDecode(
            result.readerWriter.testing.readString(
              AssetId('apps_examples', 'assets/paywalls/$path.capability.json'),
            ),
          ) as Map<String, dynamic>;
          final manifest = sidecar['manifest'] as Map<String, dynamic>;
          expect(manifest['builtInFloor'], 12, reason: path);
        }
      }
    });
  });
}

String _heightSource(String id, String appBar, {String prelude = ''}) => '''
  import 'package:flutter/material.dart';
  import 'package:flutter/material.dart' as material;

  class PaywallSource {
    const PaywallSource({required this.id});
    final String id;
  }

  typedef NativeAppBar = material.AppBar;
  typedef NativePreferredSize = material.PreferredSize;

  @PaywallSource(id: '$id')
  class HeightAppBar extends StatelessWidget {
    const HeightAppBar({
      this.height,
      required this.bottomHeight,
      required this.showBar,
      required this.mode,
    });

    final double? height;
    final double bottomHeight;
    final bool showBar;
    final String mode;

    @override
    Widget build(BuildContext context) {
      $prelude
      return Scaffold(appBar: $appBar, body: const SizedBox());
    }
  }
''';

fmt.ConstructorCall _heightScaffold(TestBuilderResult result, String id) {
  final library = fmt.parseLibraryFile(
    result.readerWriter.testing.readString(
      AssetId('apps_examples', 'assets/paywalls/$id.rfwtxt'),
    ),
  );
  final scaffold = library.widgets.single.root as fmt.ConstructorCall;
  expect(scaffold.name, 'Scaffold');
  return scaffold;
}

Map<String, Object?> _heights(
  fmt.ConstructorCall scaffold, [
  Map<String, Object?> context = const {},
]) =>
    {
      'height': _resolveHeight(scaffold.arguments['appBarHeight'], context),
      'toolbar':
          _resolveHeight(scaffold.arguments['appBarToolbarHeight'], context),
      'bottom':
          _resolveHeight(scaffold.arguments['appBarBottomHeight'], context),
    };

Object? _resolveHeight(Object? value, Map<String, Object?> context) {
  if (value is fmt.DataReference) {
    Object? current = {'context': context};
    for (final part in value.parts) {
      final map = current! as Map<Object?, Object?>;
      expect(map.containsKey(part), isTrue, reason: value.toString());
      current = map[part];
    }
    return current;
  }
  if (value is fmt.Switch) {
    final input = _resolveHeight(value.input, context);
    return _resolveHeight(
      value.outputs.containsKey(input)
          ? value.outputs[input]
          : value.outputs[null],
      context,
    );
  }
  return value;
}
