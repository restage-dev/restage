import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_source_renderer.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('renders one native story declaration per planned Cartesian tuple',
      () async {
    await _runProbe(
      const {'apps_examples|lib/state_card.dart': _configuredStateWidget},
      outputMatcher: allOf(
        predicate<String>(
          (source) =>
              RegExp(r'^final \$', multiLine: true).allMatches(source).length ==
              4,
          'contains exactly four top-level Widgetbook story declarations',
        ),
        contains(r'final $RestageCatalog = _Story('),
        contains(r'final $ModeReady = _Story('),
        contains(r'final $EnabledTrue = _Story('),
        contains(r'final $EnabledTrueModeReady = _Story('),
        matches(
          RegExp(
            r'final \$ModeReady = _Story\([\s\S]*?'
            r'enabled: _RestageBoolArg\(\s*false,[\s\S]*?'
            r'mode: _RestageEnumArg<_RestageChoice1>\(\s*'
            r'_RestageChoice1\.value1,',
          ),
        ),
        matches(
          RegExp(
            r'final \$EnabledTrueModeReady = _Story\([\s\S]*?'
            r'enabled: _RestageBoolArg\(\s*true,[\s\S]*?'
            r'mode: _RestageEnumArg<_RestageChoice1>\(\s*'
            r'_RestageChoice1\.value1,',
          ),
        ),
      ),
    );
  });

  test('rejects a final RestageCatalog declaration collision before rendering',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/declaration_collision_card.dart':
            _restageCatalogDeclarationCollisionWidget,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains(r"story declaration '$RestageCatalog' collides"),
        contains(
          'restage=package:apps_examples/declaration_collision_card.dart'
          '#Mode:base@0',
        ),
        contains(
          'restage=package:apps_examples/declaration_collision_card.dart'
          '#Mode:catalog@1',
        ),
        isNot(contains('conflicting bare namespace bindings')),
      ),
    );
  });

  test('property enum aliases render through their canonical member', () async {
    await _runProbe(
      const {'apps_examples|lib/alias_state_card.dart': _enumAliasStateWidget},
      outputMatcher: allOf(
        contains(r'final $RestageCatalog = _Story('),
        contains(r'final $ModeReady = _Story('),
        matches(
          RegExp(
            r'final \$ModeReady = _Story\([\s\S]*?'
            r'mode: _RestageEnumArg<_RestageChoice0>\(\s*'
            r'_RestageChoice0\.value1,',
          ),
        ),
        contains('_RestageChoice0.value1 => restage_source.Mode.ready'),
      ),
    );
  });

  for (final alias in <({String name, String expression})>[
    (name: 'public', expression: 'defaultMode'),
    (name: 'chained', expression: 'chainedDefaultMode'),
  ]) {
    test('${alias.name} const enum defaults render one canonical choice domain',
        () async {
      await _runProbe(
        {
          'apps_examples|lib/alias_default_card.dart':
              _enumAliasConstructorDefaultWidget(alias.expression),
        },
        outputMatcher: allOf(<Matcher>[
          contains('enum _RestageChoice0 { value0, value1, value2 }'),
          contains('this.mode = _RestageChoice0.value1'),
          contains(r'final $RestageCatalog = _Story('),
          contains('_RestageChoice0.value0 => restage_source.Mode.idle'),
          contains('_RestageChoice0.value1 => restage_source.Mode.ready'),
          contains('_RestageChoice0.value2 => restage_source.Mode.done'),
          contains("Default: the widget constructor's Dart default."),
          isNot(contains('_RestageChoice0.value3')),
          isNot(contains('restage_source.${alias.expression}')),
        ]),
      );
    });
  }

  for (final alias in <({String name, String expression})>[
    (name: 'public', expression: 'defaultMode'),
    (name: 'chained', expression: 'chainedDefaultMode'),
  ]) {
    for (final configured in <bool>[false, true]) {
      test(
          '${alias.name} const null enum default renders one null choice '
          '${configured ? 'with' : 'without'} config', () async {
        await _runProbe(
          {
            'apps_examples|lib/nullable_alias_card.dart':
                _nullableEnumStaticNullAliasWidget(
              alias.expression,
              configured: configured,
            ),
          },
          outputMatcher: allOf(<Matcher>[
            contains(
              'enum _RestageChoice0 { value0, value1, value2, value3 }',
            ),
            contains('this.mode = _RestageChoice0.value3'),
            contains(r'final $RestageCatalog = _Story('),
            matches(
              RegExp(
                r'final \$RestageCatalog = _Story\([\s\S]*?'
                r'mode: _RestageEnumArg<_RestageChoice0>\(\s*'
                r'_RestageChoice0\.value3,',
              ),
            ),
            contains('_RestageChoice0.value3 => null'),
            contains('_RestageChoice0.value3 => "null"'),
            contains("Default: the widget constructor's Dart default."),
            isNot(contains('_RestageChoice0.value4')),
            isNot(contains('restage_source.${alias.expression}')),
            isNot(contains(r'final $ModeNull = _Story(')),
            if (configured)
              contains(r'final $ModeDone = _Story(')
            else
              isNot(contains(r'final $ModeIdle = _Story(')),
            predicate<String>(
              (source) =>
                  RegExp(
                    r'^final \$',
                    multiLine: true,
                  ).allMatches(source).length ==
                  (configured ? 4 : 1),
              configured
                  ? 'contains default plus three non-default enum stories'
                  : 'contains only the mandatory default story declaration',
            ),
          ]),
        );
      });
    }
  }

  for (final alias in <({String name, String expression})>[
    (name: 'public', expression: 'defaultEnabled'),
    (name: 'chained', expression: 'chainedDefaultEnabled'),
  ]) {
    test('${alias.name} constrained bool alias renders one typed choice',
        () async {
      await _runProbe(
        {
          'apps_examples|lib/constrained_bool_card.dart':
              _constrainedBoolStaticAliasWidget(alias.expression),
        },
        outputMatcher: allOf(<Matcher>[
          contains('enum _RestageChoice0 { value0, value1 }'),
          contains('this.enabled = _RestageChoice0.value1'),
          contains('_RestageChoice0.value0 => false'),
          contains('_RestageChoice0.value1 => true'),
          contains('_RestageChoice0.value1 => "true"'),
          contains("Default: the widget constructor's Dart default."),
          isNot(contains('_RestageChoice0.value2')),
          isNot(contains('restage_source.${alias.expression}')),
        ]),
      );
    });
  }

  for (final scalar in <({
    String name,
    String type,
    String expression,
    String declarations,
    String allowedValues,
    String runtimeValue,
  })>[
    (
      name: 'public int',
      type: 'int',
      expression: 'defaultValue',
      declarations: '''
const defaultValue = 2;
const chainedDefaultValue = defaultValue;
''',
      allowedValues: '1, 2',
      runtimeValue: '2',
    ),
    (
      name: 'chained real',
      type: 'double',
      expression: 'chainedDefaultValue',
      declarations: '''
const defaultValue = 2.5;
const chainedDefaultValue = defaultValue;
''',
      allowedValues: '1.5, 2.5',
      runtimeValue: '2.5',
    ),
    (
      name: 'public string',
      type: 'String',
      expression: 'defaultValue',
      declarations: '''
const defaultValue = 'second';
const chainedDefaultValue = defaultValue;
''',
      allowedValues: "'first', 'second'",
      runtimeValue: '"second"',
    ),
  ]) {
    test('${scalar.name} constrained alias renders the canonical direct value',
        () async {
      await _runProbe(
        {
          'apps_examples|lib/constrained_scalar_card.dart':
              _constrainedScalarStaticAliasWidget(
            type: scalar.type,
            defaultExpression: scalar.expression,
            declarations: scalar.declarations,
            allowedValues: scalar.allowedValues,
          ),
        },
        outputMatcher: allOf(<Matcher>[
          contains('enum _RestageChoice0 { value0, value1 }'),
          contains('this.value = _RestageChoice0.value1'),
          contains(
            '_RestageChoice0.value1 => ${scalar.runtimeValue}',
          ),
          contains("Default: the widget constructor's Dart default."),
          isNot(contains('_RestageChoice0.value2')),
          isNot(contains('restage_source.${scalar.expression}')),
        ]),
      );
    });
  }

  test('finite framework defaults render their true non-first choices',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/finite_framework_card.dart':
            _finiteFrameworkConstructorDefaultsWidget,
      },
      outputMatcher: allOf(<Matcher>[
        contains('this.color = _RestageChoice0.value1'),
        contains('this.duration = _RestageChoice1.value1'),
        contains('this.weight = _RestageChoice2.value1'),
        contains(
          '_RestageChoice0.value1 => '
          'const restage_native_0.Color(0xFF336699)',
        ),
        contains(
          '_RestageChoice1.value1 => const Duration(milliseconds: 250)',
        ),
        contains(
          '_RestageChoice2.value1 => restage_native_0.FontWeight.w700',
        ),
        contains("Default: the widget constructor's Dart default."),
        isNot(contains('_RestageChoice0.value2')),
        isNot(contains('_RestageChoice1.value2')),
        isNot(contains('_RestageChoice2.value2')),
        isNot(contains('restage_source.defaultDuration')),
        isNot(contains('restage_source.chainedDefaultWeight')),
      ]),
    );
  });

  final constrainedConstructorRenderCases = <({
    String family,
    List<({String name, String expression, String emitted})> forms,
  })>[
    (
      family: 'duration',
      forms: [
        (
          name: 'inline',
          expression: 'const Duration(milliseconds: 150)',
          emitted: 'this.duration = const Duration.new(milliseconds: 150)',
        ),
        (
          name: 'public',
          expression: 'defaultDuration',
          emitted: 'this.duration = restage_source.defaultDuration',
        ),
        (
          name: 'chained',
          expression: 'chainedDuration',
          emitted: 'this.duration = restage_source.chainedDuration',
        ),
      ],
    ),
    (
      family: 'font weight',
      forms: [
        (
          name: 'inline',
          expression: 'FontWeight.w700',
          emitted: ': restage_native_0.FontWeight.w700,',
        ),
        (
          name: 'public',
          expression: 'defaultWeight',
          emitted: ': restage_source.defaultWeight,',
        ),
        (
          name: 'chained',
          expression: 'chainedWeight',
          emitted: ': restage_source.chainedWeight,',
        ),
      ],
    ),
    (
      family: 'color',
      forms: [
        (
          name: 'inline',
          expression: 'const Color(0xFF336699)',
          emitted: 'this.color = const restage_native_0.Color.new(4281558681)',
        ),
        (
          name: 'public',
          expression: 'defaultColor',
          emitted: 'this.color = restage_source.defaultColor',
        ),
        (
          name: 'chained',
          expression: 'chainedColor',
          emitted: 'this.color = restage_source.chainedColor',
        ),
      ],
    ),
    (
      family: 'widget-list length',
      forms: [
        (
          name: 'inline',
          expression: 'const <Widget>[SizedBox.shrink(), SizedBox.shrink()]',
          emitted: ': const <restage_native_0.Widget>[',
        ),
        (
          name: 'public',
          expression: 'defaultChildren',
          emitted: ': restage_source.defaultChildren,',
        ),
        (
          name: 'chained',
          expression: 'chainedChildren',
          emitted: ': restage_source.chainedChildren,',
        ),
      ],
    ),
    (
      family: 'customer structured-list length',
      forms: [
        (
          name: 'inline',
          expression:
              "const <CustomerItem>[CustomerItem('one'), CustomerItem('two')]",
          emitted: 'const <restage_source.CustomerItem>[\n'
              "            const restage_source.CustomerItem.new('one'),\n"
              "            const restage_source.CustomerItem.new('two'),\n"
              '          ],',
        ),
        (
          name: 'public',
          expression: 'defaultItems',
          emitted: ': restage_source.defaultItems,',
        ),
        (
          name: 'chained',
          expression: 'chainedItems',
          emitted: ': restage_source.chainedItems,',
        ),
      ],
    ),
  ];

  for (final family in constrainedConstructorRenderCases) {
    for (final form in family.forms) {
      test('${form.name} ${family.family} retains exact emitted identity',
          () async {
        await _runProbe(
          {
            'apps_examples|lib/constrained_constructor_default.dart':
                widgetbookConstrainedConstructorDefaultFixture(
              family: family.family,
              defaultExpression: form.expression,
              matching: true,
            ),
          },
          outputMatcher: allOf(
            contains(form.emitted),
            contains("Default: the widget constructor's Dart default."),
          ),
        );
      });
    }
  }

  for (final defaultValue in <({String name, String expression})>[
    (name: 'direct', expression: '2.0'),
    (name: 'public', expression: 'defaultRatio'),
    (name: 'chained', expression: 'chainedDefaultRatio'),
  ]) {
    test('${defaultValue.name} mixed real default renders structurally',
        () async {
      await _runProbe(
        {
          'apps_examples|lib/mixed_real_card.dart':
              _mixedRealConstructorDefaultWidget(defaultValue.expression),
        },
        outputMatcher: allOf(<Matcher>[
          contains('enum _RestageChoice0 { value0, value1 }'),
          contains('this.ratio = _RestageChoice0.value1'),
          contains('_RestageChoice0.value0 => 1'),
          contains('_RestageChoice0.value1 => 2'),
          contains("Default: the widget constructor's Dart default."),
          isNot(contains('_RestageChoice0.value2')),
          isNot(contains('restage_source.${defaultValue.expression}')),
        ]),
      );
    });
  }

  for (final defaultValue in <({String name, String expression})>[
    (name: 'direct', expression: '-0.0'),
    (name: 'public', expression: 'defaultNegativeZero'),
    (name: 'chained', expression: 'chainedNegativeZero'),
  ]) {
    test('${defaultValue.name} negative-zero default renders losslessly',
        () async {
      await _runProbe(
        {
          'apps_examples|lib/signed_zero_card.dart':
              _signedZeroConstructorDefaultWidget(defaultValue.expression),
        },
        outputMatcher: allOf(<Matcher>[
          contains('enum _RestageChoice0 { value0, value1 }'),
          contains('this.ratio = _RestageChoice0.value0'),
          contains('_RestageChoice0.value0 => -0.0'),
          contains('_RestageChoice0.value1 => 2'),
          contains("Default: the widget constructor's Dart default."),
          isNot(contains('_RestageChoice0.value2')),
          isNot(contains('restage_source.${defaultValue.expression}')),
        ]),
      );
    });
  }

  test('negative-zero default outside the signed finite domain fails loudly',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/signed_zero_wrong_domain_card.dart':
            _signedZeroWrongDomainWidget,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('/constructorDefaults/ratio'),
        contains('allowed-value'),
      ),
    );
  });

  test('catalog literal negative zero renders only its authored domain',
      () async {
    await _runProbe(
      {
        'apps_examples|lib/catalog_literal_finite_card.dart':
            _catalogLiteralFiniteWidget(
          type: 'double',
          defaultValue: '-0.0',
          allowedValues: '-0.0, 2.0',
        ),
      },
      outputMatcher: allOf(<Matcher>[
        contains('enum _RestageChoice0 { value0, value1 }'),
        contains('this.value = _RestageChoice0.value0'),
        contains('_RestageChoice0.value0 => -0.0'),
        contains('_RestageChoice0.value1 => 2.0'),
        contains('Default: -0.0.'),
        isNot(contains('_RestageChoice0.value2')),
      ]),
    );
  });

  test('catalog literal negative zero outside the domain fails before render',
      () async {
    await _runProbe(
      {
        'apps_examples|lib/catalog_literal_finite_card.dart':
            _catalogLiteralFiniteWidget(
          type: 'double',
          defaultValue: '-0.0',
          allowedValues: '0.0, 2.0',
        ),
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('/defaults/value'),
        contains('finite allowed-value'),
      ),
    );
  });

  for (final representative in <({
    String name,
    String type,
    String defaultValue,
    String allowedValues,
    String mapping,
  })>[
    (
      name: 'framework color',
      type: 'Color',
      defaultValue: "'#FF336699'",
      allowedValues: "'#FF000000', '#FF336699'",
      mapping: '_RestageChoice0.value1 => '
          'const restage_native_0.Color(0xFF336699)',
    ),
    (
      name: 'enum',
      type: 'Mode',
      defaultValue: "'ready'",
      allowedValues: "'idle', 'ready'",
      mapping: '_RestageChoice0.value1 => restage_source.Mode.ready',
    ),
  ]) {
    test('catalog literal ${representative.name} renders its domain choice',
        () async {
      await _runProbe(
        {
          'apps_examples|lib/catalog_literal_finite_card.dart':
              _catalogLiteralFiniteWidget(
            type: representative.type,
            defaultValue: representative.defaultValue,
            allowedValues: representative.allowedValues,
          ),
        },
        outputMatcher: allOf(<Matcher>[
          contains('enum _RestageChoice0 { value0, value1 }'),
          contains('this.value = _RestageChoice0.value1'),
          contains(representative.mapping),
          isNot(contains('_RestageChoice0.value2')),
        ]),
      );
    });
  }

  for (final empty in <({String name, String type, String defaultValue})>[
    (name: 'bool', type: 'bool', defaultValue: 'true'),
    (name: 'String', type: 'String', defaultValue: "'value'"),
  ]) {
    test('empty ${empty.name} allowedValues fails before rendering', () async {
      await _runProbe(
        {
          'apps_examples|lib/catalog_literal_finite_card.dart':
              _catalogLiteralFiniteWidget(
            type: empty.type,
            defaultValue: empty.defaultValue,
            allowedValues: '',
          ),
        },
        captureErrors: true,
        outputMatcher: allOf(
          contains('CatalogLiteralFiniteCard.value'),
          contains('allowedValues must not be empty'),
        ),
      );
    });
  }

  for (final duplicate in <({String name, String allowedValues})>[
    (name: 'signed zero', allowedValues: '-0.0, 0'),
    (name: 'positive zero representation', allowedValues: '0, 0.0'),
    (name: 'mixed numeric', allowedValues: '1, 1.0'),
  ]) {
    test('renderer rejects ${duplicate.name} duplicate allowedValues',
        () async {
      await _runProbe(
        {
          'apps_examples|lib/catalog_literal_finite_card.dart':
              _catalogLiteralFiniteWidget(
            type: 'double',
            defaultValue: '2.0',
            allowedValues: duplicate.allowedValues,
          ),
        },
        captureErrors: true,
        outputMatcher: allOf(
          contains('CatalogLiteralFiniteCard.value'),
          contains('duplicate allowedValues[1]'),
        ),
      );
    });
  }

  test('unconfigured private enum default renders by exact ordinal', () async {
    await _runProbe(
      {
        'apps_examples|lib/private_enum_route_card.dart':
            _privateEnumRouteWidget(route: 'implicit'),
      },
      outputMatcher: allOf(<Matcher>[
        contains('enum _RestageChoice0 { value0, value1, value2 }'),
        contains('this.mode = _RestageChoice0.value1'),
        contains('_RestageChoice0.value0 => restage_source.SecretMode.visible'),
        contains(
          '_RestageChoice0.value1 => restage_source.SecretMode.values[1]',
        ),
        contains(
          '_RestageChoice0.value2 => restage_source.SecretMode.trailing',
        ),
        isNot(contains('SecretMode._hidden')),
      ]),
    );
  });

  test('allValues private enum variant renders by exact ordinal', () async {
    await _runProbe(
      {
        'apps_examples|lib/private_enum_route_card.dart':
            _privateEnumRouteWidget(route: 'allValues'),
      },
      outputMatcher: allOf(<Matcher>[
        contains(r'final $ModeHidden = _Story('),
        matches(
          RegExp(
            r'final \$ModeHidden = _Story\([\s\S]*?'
            r'_RestageChoice0\.value1,',
          ),
        ),
        contains(
          '_RestageChoice0.value1 => restage_source.SecretMode.values[1]',
        ),
        isNot(contains('SecretMode._hidden')),
      ]),
    );
  });

  test('explicit private enum storyValue renders by exact ordinal', () async {
    await _runProbe(
      {
        'apps_examples|lib/private_enum_route_card.dart':
            _privateEnumRouteWidget(route: 'explicit'),
      },
      outputMatcher: allOf(<Matcher>[
        contains(r'final $ModeHidden = _Story('),
        matches(
          RegExp(
            r'final \$ModeHidden = _Story\([\s\S]*?'
            r'_RestageChoice0\.value1,',
          ),
        ),
        contains(
          '_RestageChoice0.value1 => restage_source.SecretMode.values[1]',
        ),
        isNot(contains('SecretMode._hidden')),
      ]),
    );
  });

  test('a private enum type fails at its property path', () async {
    await _runProbe(
      const {
        'apps_examples|lib/private_enum_type_card.dart': _privateEnumTypeWidget,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('PrivateEnumTypeCard.mode'),
        contains('_SecretMode'),
        contains('generated Widgetbook source'),
      ),
    );
  });

  test('nullable enum variants map null through the local choice adapter',
      () async {
    await _runProbe(
      const {'apps_examples|lib/nullable_mode_card.dart': _nullableEnumWidget},
      outputMatcher: allOf(
        contains('enum _RestageChoice0 { value0, value1, value2 }'),
        contains('this.mode = _RestageChoice0.value2'),
        contains(r'final $RestageCatalog = _Story('),
        contains(r'final $ModeIdle = _Story('),
        contains(r'final $ModeReady = _Story('),
        matches(
          RegExp(
            r'final \$RestageCatalog = _Story\([\s\S]*?'
            r'_RestageChoice0\.value2,',
          ),
        ),
      ),
    );
  });

  test('unconfigured nullable enum null default renders its default story',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/unconfigured_nullable_mode_card.dart':
            _unconfiguredNullableEnumWidget,
      },
      outputMatcher: allOf(
        predicate<String>(
          (source) =>
              RegExp(r'^final \$', multiLine: true).allMatches(source).length ==
              1,
          'contains only the mandatory default story declaration',
        ),
        contains('enum _RestageChoice0 { value0, value1, value2 }'),
        contains('this.mode = _RestageChoice0.value2'),
        contains(r'final $RestageCatalog = _Story('),
        matches(
          RegExp(
            r'final \$RestageCatalog = _Story\([\s\S]*?'
            r'mode: _RestageEnumArg<_RestageChoice0>\(\s*'
            r'_RestageChoice0\.value2,',
          ),
        ),
        contains('_RestageChoice0.value2 => null'),
      ),
    );
  });

  test('explicit nullable null variants render bool and enum runtime values',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/nullable_state_card.dart':
            _explicitNullableNullWidget,
      },
      outputMatcher: allOf(
        contains(r'final $EnabledNull = _Story('),
        contains(r'final $ModeNull = _Story('),
        matches(
          RegExp(
            r'final \$EnabledNull = _Story\([\s\S]*?'
            r'enabled: _RestageNullableBoolArg\(\s*null,',
          ),
        ),
        matches(
          RegExp(
            r'final \$ModeNull = _Story\([\s\S]*?'
            r'mode: _RestageEnumArg<_RestageChoice1>\(\s*'
            r'_RestageChoice1\.value2,',
          ),
        ),
        contains('_RestageChoice1.value2 => null'),
      ),
    );
  });

  test('generated story declarations reserve their bare symbols', () async {
    await _runProbe(
      const {'apps_examples|lib/collision_card.dart': _storySymbolCollision},
      captureErrors: true,
      outputMatcher: allOf(
        contains(
          r'Dart type package:apps_examples/collision_card.dart#$ModeReady',
        ),
        contains('cannot be imported bare'),
        contains('generated Widgetbook story declaration'),
      ),
    );
  });

  group('runtime-resolved defaults', () {
    for (final variant in <({String name, String annotation})>[
      (
        name: 'token',
        annotation: '''
          TokenRefDefault(
            WireIdRef(
              library: 'fixture.tokens',
              wireId: WireId.unallocatedDesignToken,
            ),
          )
        ''',
      ),
      (
        name: 'theme',
        annotation: '''
          ThemeBindingDefault(ThemeBindingPath.path('colorScheme.primary'))
        ''',
      ),
    ]) {
      test('${variant.name} default receives an automatic native preview',
          () async {
        final source = _runtimeDefaultWidget(variant.annotation);
        await _runProbe(
          {'apps_examples|lib/customer_card.dart': source},
          outputMatcher: allOf(
            contains('.Color(0xFF000000)'),
            contains("import 'dart:ui' show Color;"),
            variant.name == 'token'
                ? contains('resolved from a design token at runtime')
                : contains('resolved from the Flutter theme at runtime'),
          ),
        );
      });
    }
  });

  test(
      'lookalike framework types are rejected by resolved identity during '
      'classification', () async {
    await _runProbe(
      const {'apps_examples|lib/lookalike.dart': _lookalikeColorWidget},
      captureErrors: true,
      logMatcher: allOf(
        contains("not Flutter's `Color`"),
        contains('matched by defining library'),
        contains('package:apps_examples/lookalike.dart'),
        isNot(contains('Supported types:')),
      ),
    );
  });

  test('a customer type named Widget is not accepted as Flutter Widget',
      () async {
    await _runProbe(
      const {'apps_examples|lib/lookalike_widget.dart': _lookalikeWidgetWidget},
      captureErrors: true,
      logMatcher: allOf(
        contains("not Flutter's `Widget`"),
        contains('matched by defining library'),
        contains('package:apps_examples/lookalike_widget.dart'),
        isNot(contains('Supported types:')),
      ),
    );
  });

  test('records Widgetbook auto-exclusions in the generated story artifact',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/host_state_card.dart': _hostStateWidget,
      },
      outputMatcher: allOf(
        contains(
          'const List<Map<String, String>> restageExclusions = [',
        ),
        contains('"widget": "HostStateCard"'),
        contains('"property": "hostState"'),
        contains('"target": "widgetbook"'),
        contains('Object?'),
      ),
    );
  });

  test('routes Widgetbook exclusions by source identity', () async {
    await _runProbe(
      const {
        'apps_examples|lib/first_card.dart': _firstSameNamedCard,
        'apps_examples|lib/second_card.dart': _secondSameNamedCard,
      },
      widgetName: 'SecondCard',
      outputMatcher: allOf(
        contains('class Card'),
        isNot(contains(r'$RestageExclusions')),
        isNot(contains('hostState')),
      ),
    );
  });

  test('malformed framework literal defaults fail with a default path',
      () async {
    await _runProbe(
      const {'apps_examples|lib/bad_default.dart': _badColorDefaultWidget},
      captureErrors: true,
      outputMatcher: allOf(
        contains('/defaults/color'),
        contains('valid color value'),
      ),
    );
  });

  test('constructor enum defaults are checked against allowed values',
      () async {
    await _runProbe(
      const {'apps_examples|lib/enum_default.dart': _enumDefaultWidget},
      captureErrors: true,
      outputMatcher: contains('/constructorDefaults/tone'),
    );
  });

  test('explicit null defaults are checked against allowed values', () async {
    await _runProbe(
      const {
        'apps_examples|lib/null_default.dart': _nullDefaultAllowedValueWidget,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('/constructorDefaults/value'),
        contains('finite allowed-value'),
      ),
    );
  });

  test('structural constructor defaults preserve the ordinary Dart story value',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/nonportable_default.dart':
            _nonportableConstructorDefaultWidget,
      },
      outputMatcher: allOf(
        contains(
          'this.color = const restage_native_0.Color.new(4281558681)',
        ),
        contains('restage_source.ColorDefaultCard(color: args.color)'),
      ),
    );
  });

  test('constraints without a deterministic valid seed fail loudly', () async {
    await _runProbe(
      const {'apps_examples|lib/patterned.dart': _patternedStringWidget},
      captureErrors: true,
      outputMatcher: allOf(
        contains('/generated/code'),
        contains('cannot deterministically satisfy its constraints'),
      ),
    );
  });

  test('nullable inputs may use null beside non-null constraints', () async {
    await _runProbe(
      const {'apps_examples|lib/nullable_pattern.dart': _nullablePatternWidget},
      outputMatcher: matches(
        RegExp(r'_RestageNullableStringArg\(\s+null,'),
      ),
    );
  });

  test('Dart grouping and alternation remain valid Widgetbook patterns',
      () async {
    await _runProbe(
      {
        'apps_examples|lib/grouped_pattern.dart':
            widgetbookPatternValidationFixture(
          legacy: false,
          nullable: false,
          malformed: false,
        ),
      },
      outputMatcher: allOf(
        contains(r'Pattern: ^(ready|set)\$.'),
        contains('"ready"'),
      ),
    );
  });

  test('collection synthesis satisfies the minimum item count', () async {
    await _runProbe(
      const {'apps_examples|lib/constrained_list.dart': _constrainedListWidget},
      outputMatcher: allOf(
        matches(
          RegExp(
            r'<restage_native_\d+\.Widget>\[\s*'
            r'const restage_native_\d+\.SizedBox\.shrink\(\),\s*'
            r'const restage_native_\d+\.SizedBox\.shrink\(\),?\s*\]',
          ),
        ),
        isNot(matches(RegExp(r'<restage_native_\d+\.Widget>\[\]'))),
      ),
    );
  });

  test('enum controls retain the customer enum member labels', () async {
    await _runProbe(
      const {'apps_examples|lib/status.dart': _enumLabelWidget},
      outputMatcher: allOf(
        contains('_RestageChoice0.value0 => "ready"'),
        contains('_RestageChoice0.value1 => "processing"'),
        contains('required super.labelBuilder'),
      ),
    );
  });

  test('legacy validation rules reject invalid catalog defaults', () async {
    await _runProbe(
      const {'apps_examples|lib/legacy_invalid.dart': _legacyInvalidWidget},
      captureErrors: true,
      outputMatcher: allOf(
        contains('/constructorDefaults/score'),
        contains('violates its constraints'),
      ),
    );
  });

  for (final nullable in <bool>[false, true]) {
    final seed = nullable ? 'nullable null' : 'non-null';
    final className =
        nullable ? 'MalformedLegacyNullableCard' : 'MalformedLegacyNonNullCard';
    test('malformed legacy grammar rejects a $seed seed with property context',
        () async {
      await _runProbe(
        {
          'apps_examples|lib/malformed_legacy.dart':
              _malformedLegacySyntaxWidget(nullable: nullable),
        },
        captureErrors: true,
        outputMatcher: allOf(
          contains('Widgetbook validation rule at $className.value'),
          contains('range(0)'),
          contains('Supported legacy forms are'),
          contains('range(<finite JSON number>, <finite JSON number>)'),
          contains('oneOf(<JSON scalar>, ...)'),
          contains('matches(<JSON string>)'),
          isNot(contains('A2uiLegacyConstraintParseException')),
        ),
      );
    });
  }

  test('legacy validation rules drive controls and sidebar descriptions',
      () async {
    await _runProbe(
      const {'apps_examples|lib/legacy_valid.dart': _legacyValidWidget},
      outputMatcher: allOf(
        contains('Inclusive range: 1–5.'),
        contains('SliderIntArgStyle(min: 1, max: 5, divisions: 4)'),
      ),
    );
  });

  test('portable constructor defaults retain sidebar provenance', () async {
    await _runProbe(
      const {
        'apps_examples|lib/constructor_default.dart': _constructorDefaultWidget,
      },
      outputMatcher: allOf(
        contains("Default: the widget constructor's Dart default."),
        contains('opacity: _RestageDoubleArg('),
        contains('      0.5,'),
      ),
    );
  });

  test('constructor default provenance wins over catalog default metadata',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/constructor_default_precedence.dart':
            _constructorDefaultPrecedenceWidget,
      },
      outputMatcher: allOf(
        contains(
          'Literal conflict. '
          "Default: the widget constructor's Dart default.",
        ),
        contains(
          'Token conflict. '
          "Default: the widget constructor's Dart default.",
        ),
        contains('opacity: _RestageDoubleArg('),
        contains('      0.5,'),
        matches(RegExp(r'label: _RestageStringArg\(\s*"constructor",')),
        isNot(contains('Default: 0.8.')),
        isNot(contains('Default: resolved from a design token at runtime.')),
      ),
    );
  });

  test('one-sided bounds remain descriptive without inventing a slider',
      () async {
    await _runProbe(
      const {'apps_examples|lib/bounded.dart': _boundedWidget},
      outputMatcher: allOf(<Matcher>[
        contains('Inclusive range: 0.1–unbounded.'),
        contains('_RestageDoubleArg('),
        isNot(contains('Slider')),
      ]),
    );
  });

  test('substituted super-formal inputs render as native story arguments',
      () async {
    await _runProbe(
      const {'apps_examples|lib/super_card.dart': _superFormalWidget},
      outputMatcher: allOf(
        contains('SuperCard('),
        contains('label:'),
        contains('_RestageStringArg'),
        isNot(contains('key:')),
      ),
    );
  });

  test('exact inherited backing-field config renders a native variant',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/inherited_state_card.dart':
            _inheritedConfiguredBoolWidget,
      },
      widgetName: 'InheritedStateCard',
      outputMatcher: allOf(
        contains(r'final $RestageCatalog = _Story('),
        contains(r'final $EnabledTrue = _Story('),
        matches(
          RegExp(
            r'final \$EnabledTrue = _Story\([\s\S]*?'
            r'enabled: _RestageBoolArg\(\s*true,',
          ),
        ),
      ),
    );
  });

  test('rejects a Widgetbook Meta collision at the widget property path',
      () async {
    await _runProbe(
      const {
        'restage_widgetbook_example|lib/models.dart': _metaModel,
        'restage_widgetbook_example|lib/customer_card.dart': _metaCard,
      },
      rootPackage: 'restage_widgetbook_example',
      includeWidgetbookNamespace: true,
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/customer_card.dart#CustomerCard.data'),
        contains('package:restage_widgetbook_example/models.dart#Meta'),
        contains('package:widgetbook/widgetbook.dart export'),
      ),
    );
  });

  test('rejects a model that collides with the source widget class', () async {
    await _runProbe(
      const {
        'apps_examples|lib/models.dart': _sameNamedWidgetModel,
        'apps_examples|lib/customer_card.dart': _sameNamedModelCard,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/customer_card.dart#CustomerCard.data'),
        contains('package:apps_examples/models.dart#CustomerCard'),
        contains('source widget import at lib/customer_card.dart#CustomerCard'),
      ),
    );
  });

  test('rejects a customer model that collides with implicit dart:core',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/models.dart': _stringModel,
        'apps_examples|lib/customer_card.dart': _stringModelCard,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/customer_card.dart#CustomerCard.data'),
        contains('package:apps_examples/models.dart#String'),
        contains('implicit dart:core namespace'),
      ),
    );
  });

  test('checks recursively required additional types for bare collisions',
      () async {
    await _runProbe(
      const {
        'restage_widgetbook_example|lib/models.dart': _metaModel,
        'restage_widgetbook_example|lib/customer_card.dart': _metaListCard,
      },
      rootPackage: 'restage_widgetbook_example',
      includeWidgetbookNamespace: true,
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/customer_card.dart#CustomerCard.items'),
        contains('package:restage_widgetbook_example/models.dart#Meta'),
        contains('package:widgetbook/widgetbook.dart export'),
      ),
    );
  });

  test('keeps a non-colliding source widget and customer model valid',
      () async {
    const sourceImport =
        "import 'package:apps_examples/customer_card.dart' show CustomerCard;";
    await _runProbe(
      const {
        'apps_examples|lib/models.dart': _cardDataModel,
        'apps_examples|lib/customer_card.dart': _cardDataCard,
      },
      outputMatcher: allOf(
        contains(
          "import 'package:apps_examples/models.dart' as restage_native_0;",
        ),
        contains(
          "import 'package:apps_examples/models.dart' show CardData;",
        ),
        contains('restage_native_0.CardData'),
        contains(sourceImport),
        predicate<String>(
          (source) => source.split(sourceImport).length == 2,
          'contains the source show import exactly once',
        ),
      ),
    );
  });

  test('rejects a source widget named for an actual Widgetbook export',
      () async {
    await _runProbe(
      const {
        'restage_widgetbook_example|lib/config.dart': _configWidget,
      },
      rootPackage: 'restage_widgetbook_example',
      includeWidgetbookNamespace: true,
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/config.dart#Config'),
        contains('package:widgetbook/widgetbook.dart export'),
        contains('conflicting bare namespace bindings'),
      ),
    );
  });

  test('rejects a source widget named for an implicit dart:core type',
      () async {
    await _runProbe(
      const {'apps_examples|lib/date_time.dart': _dateTimeWidget},
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/date_time.dart#DateTime'),
        contains('implicit dart:core namespace'),
        contains('conflicting bare namespace bindings'),
      ),
    );
  });
}

Future<void> _runProbe(
  Map<String, String> sources, {
  Matcher outputMatcher = anything,
  Matcher? logMatcher,
  bool captureErrors = false,
  String? widgetName,
  String rootPackage = 'apps_examples',
  bool includeWidgetbookNamespace = false,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: rootPackage,
  );
  final logs = <String>[];
  for (final entry in sources.entries) {
    final separator = entry.key.indexOf('|');
    readerWriter.testing.writeString(
      AssetId(
        entry.key.substring(0, separator),
        entry.key.substring(separator + 1),
      ),
      entry.value,
    );
  }
  if (includeWidgetbookNamespace) {
    readerWriter.testing
      ..writeString(
        AssetId('widgetbook', 'lib/widgetbook.dart'),
        "export 'src/meta.dart';",
      )
      ..writeString(
        AssetId('widgetbook', 'lib/src/meta.dart'),
        '''
class Config { const Config(); }
class Meta { const Meta(); }
''',
      );
  }
  await testBuilder(
    _StoryPlanProbeBuilder(
      captureErrors: captureErrors,
      widgetName: widgetName,
    ),
    sources,
    rootPackage: rootPackage,
    readerWriter: readerWriter,
    outputs: {
      '$rootPackage|lib/customer.stories.dart': decodedMatches(outputMatcher),
    },
    onLog: logMatcher == null
        ? null
        : (record) {
            logs.add('${record.level.name}: ${record.message}');
          },
  );
  if (logMatcher != null) {
    expect(logs.join('\n'), logMatcher);
  }
}

const _superFormalWidget = r'''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class BaseCard<T> extends StatelessWidget {
  const BaseCard({super.key, required this.label});

  /// Visible label.
  final T label;

  @override
  Widget build(BuildContext context) => Text('$label');
}

/// A concrete customer card.
@RestageWidget(
  name: 'SuperCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
)
class SuperCard extends BaseCard<String> {
  const SuperCard({super.key, required super.label});
}
''';

const _configuredStateWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready }

@wb.Config.expansion(wb.StoryExpansion.cartesian)
@RestageWidget(
  name: 'StateCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A finite state card.',
)
class StateCard extends StatelessWidget {
  const StateCard({this.enabled = false, this.mode = Mode.idle});

  /// Whether the card is enabled.
  @wb.Config.allValues()
  final bool enabled;

  /// Current card mode.
  @wb.Config.allValues()
  final Mode mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _enumAliasStateWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready }

const readyAlias = Mode.ready;

@RestageWidget(
  name: 'AliasStateCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A finite state card configured through an enum alias.',
)
class AliasStateCard extends StatelessWidget {
  const AliasStateCard({this.mode = Mode.idle});

  /// Current card mode.
  @wb.Config.values([readyAlias])
  final Mode mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _enumAliasConstructorDefaultWidget(String defaultExpression) => '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready, done }

const defaultMode = Mode.ready;
const chainedDefaultMode = defaultMode;

@RestageWidget(
  name: 'AliasDefaultCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A finite state card with an aliased constructor default.',
)
class AliasDefaultCard extends StatelessWidget {
  const AliasDefaultCard({this.mode = $defaultExpression});

  /// Current card mode.
  @wb.Config.allValues()
  final Mode mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _nullableEnumStaticNullAliasWidget(
  String defaultExpression, {
  required bool configured,
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready, done }

const Mode? defaultMode = null;
const Mode? chainedDefaultMode = defaultMode;

@RestageWidget(
  name: 'NullableAliasCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A nullable enum alias card.',
)
class NullableAliasCard extends StatelessWidget {
  const NullableAliasCard({this.mode = $defaultExpression});

  /// Current optional mode.
  ${configured ? '@wb.Config.allValues()' : ''}
  final Mode? mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _restageCatalogDeclarationCollisionWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { base, catalog }

@RestageWidget(
  name: 'DeclarationCollisionCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A final story declaration collision card.',
)
class DeclarationCollisionCard extends StatelessWidget {
  const DeclarationCollisionCard({this.restage = Mode.base});

  /// Current mode.
  @wb.Config.values([Mode.catalog])
  final Mode restage;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _constrainedBoolStaticAliasWidget(String defaultExpression) => '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const defaultEnabled = true;
const chainedDefaultEnabled = defaultEnabled;

@RestageWidget(
  name: 'ConstrainedBoolCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A constrained boolean alias card.',
)
class ConstrainedBoolCard extends StatelessWidget {
  const ConstrainedBoolCard({this.enabled = $defaultExpression});

  /// Whether the card is enabled.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [false, true]),
  )
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _constrainedScalarStaticAliasWidget({
  required String type,
  required String defaultExpression,
  required String declarations,
  required String allowedValues,
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

$declarations
@RestageWidget(
  name: 'ConstrainedScalarCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A constrained scalar alias card.',
)
class ConstrainedScalarCard extends StatelessWidget {
  const ConstrainedScalarCard({this.value = $defaultExpression});

  /// Current constrained value.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [$allowedValues]),
  )
  final $type value;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _catalogLiteralFiniteWidget({
  required String type,
  required String defaultValue,
  required String allowedValues,
}) =>
    '''
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

enum Mode { idle, ready }

@RestageWidget(
  name: 'CatalogLiteralFiniteCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A catalog-literal finite-domain card.',
)
class CatalogLiteralFiniteCard extends StatelessWidget {
  const CatalogLiteralFiniteCard({required this.value});

  /// Finite customer value.
  @RestageProperty(
    defaultSource: LiteralDefault($defaultValue),
    constraints: RestageConstraints(allowedValues: [$allowedValues]),
  )
  final $type value;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _finiteFrameworkConstructorDefaultsWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const defaultDuration = Duration(milliseconds: 250);
const defaultWeight = FontWeight.bold;
const chainedDefaultWeight = defaultWeight;

@RestageWidget(
  name: 'FiniteFrameworkCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Finite framework constructor defaults.',
)
class FiniteFrameworkCard extends StatelessWidget {
  const FiniteFrameworkCard({
    this.color = const Color(0xFF336699),
    this.duration = defaultDuration,
    this.weight = chainedDefaultWeight,
  });

  /// Customer color.
  @RestageProperty(
    constraints: RestageConstraints(
      allowedValues: ['#FF000000', '#FF336699'],
    ),
  )
  final Color color;

  /// Customer duration.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [100, 250]),
  )
  final Duration duration;

  /// Customer font weight.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [400, 700]),
  )
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _mixedRealConstructorDefaultWidget(String defaultExpression) => '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const defaultRatio = 2.0;
const chainedDefaultRatio = defaultRatio;

@RestageWidget(
  name: 'MixedRealCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A mixed-representation real card.',
)
class MixedRealCard extends StatelessWidget {
  const MixedRealCard({this.ratio = $defaultExpression});

  /// Customer ratio.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [1, 2]),
  )
  final double ratio;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _inheritedConfiguredBoolWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class BaseStateCard extends StatelessWidget {
  const BaseStateCard({this.enabled = false});

  /// Whether the card is enabled.
  @wb.Config.values([true])
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'InheritedStateCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A card with inherited finite state.',
)
class InheritedStateCard extends BaseStateCard {
  const InheritedStateCard({super.enabled});
}
''';

const _nullableEnumWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready }

@RestageWidget(
  name: 'NullableModeCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A nullable mode card.',
)
class NullableModeCard extends StatelessWidget {
  const NullableModeCard({this.mode = null});

  /// Current optional mode.
  @wb.Config.allValues()
  final Mode? mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _signedZeroConstructorDefaultWidget(String defaultExpression) => '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const defaultNegativeZero = -0.0;
const chainedNegativeZero = defaultNegativeZero;

@RestageWidget(
  name: 'SignedZeroCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A signed-zero constructor-default card.',
)
class SignedZeroCard extends StatelessWidget {
  const SignedZeroCard({this.ratio = $defaultExpression});

  /// Signed finite ratio.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [-0.0, 2]),
  )
  final double ratio;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _signedZeroWrongDomainWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'SignedZeroWrongDomainCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A signed-zero wrong-domain card.',
)
class SignedZeroWrongDomainCard extends StatelessWidget {
  const SignedZeroWrongDomainCard({this.ratio = -0.0});

  /// Signed finite ratio.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [0.0, 2]),
  )
  final double ratio;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _privateEnumRouteWidget({required String route}) {
  final config = switch (route) {
    'implicit' => '',
    'allValues' => '@wb.Config.allValues()',
    'explicit' => '@wb.Config.values([SecretMode._hidden])',
    _ => throw ArgumentError.value(route, 'route'),
  };
  final defaultValue =
      route == 'implicit' ? 'SecretMode._hidden' : 'SecretMode.visible';
  return '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum SecretMode { visible, _hidden, trailing }

@RestageWidget(
  name: 'PrivateEnumRouteCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A private-enum route card.',
)
class PrivateEnumRouteCard extends StatelessWidget {
  const PrivateEnumRouteCard({this.mode = $defaultValue});

  /// Current secret mode.
  $config
  final SecretMode mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
}

const _privateEnumTypeWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

enum _SecretMode { visible, _hidden }

@RestageWidget(
  name: 'PrivateEnumTypeCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A private enum-type card.',
)
class PrivateEnumTypeCard extends StatelessWidget {
  const PrivateEnumTypeCard({this.mode = _SecretMode.visible});

  /// Current private mode.
  final _SecretMode mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _unconfiguredNullableEnumWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

enum Mode { idle, ready }

@RestageWidget(
  name: 'UnconfiguredNullableModeCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'An unconfigured nullable mode card.',
)
class UnconfiguredNullableModeCard extends StatelessWidget {
  const UnconfiguredNullableModeCard({this.mode = null});

  /// Current optional mode.
  final Mode? mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _explicitNullableNullWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready }

@RestageWidget(
  name: 'NullableStateCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A nullable state card.',
)
class NullableStateCard extends StatelessWidget {
  const NullableStateCard({this.enabled = true, this.mode = Mode.ready});

  /// Whether the card is enabled.
  @wb.Config.values([null])
  final bool? enabled;

  /// Current optional mode.
  @wb.Config.values([null])
  final Mode? mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _storySymbolCollision = r'''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum $ModeReady { idle, ready }

@RestageWidget(
  name: 'CollisionCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A generated story symbol collision.',
)
class CollisionCard extends StatelessWidget {
  const CollisionCard({this.mode = $ModeReady.idle});

  /// Current mode.
  @wb.Config.values([$ModeReady.ready])
  final $ModeReady mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _metaModel = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Meta {
  const Meta({required this.label});

  @RestageProperty(description: 'Metadata label.')
  final String label;
}
''';

const _metaCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart';

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.data});

  @RestageProperty(description: 'Customer metadata.')
  final Meta data;

  @override
  Widget build(BuildContext context) => Text(data.label);
}
''';

const _sameNamedWidgetModel = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class CustomerCard {
  const CustomerCard({required this.label});

  @RestageProperty(description: 'Model label.')
  final String label;
}
''';

const _sameNamedModelCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart' as models;

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.data});

  @RestageProperty(description: 'Customer data.')
  final models.CustomerCard data;

  @override
  Widget build(BuildContext context) => Text(data.label);
}
''';

const _stringModel = '''
import 'dart:core' as core;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class String {
  const String({required this.value});

  @RestageProperty(description: 'Model value.')
  final core.String value;
}
''';

const _stringModelCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart' as models;

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.data});

  @RestageProperty(description: 'Customer data.')
  final models.String data;

  @override
  Widget build(BuildContext context) => Text(data.value);
}
''';

const _metaListCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart';

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.items});

  @RestageProperty(description: 'Customer metadata items.')
  final List<Meta> items;

  @override
  Widget build(BuildContext context) => Text(items.length.toString());
}
''';

const _cardDataModel = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class CardData {
  const CardData({required this.label});

  @RestageProperty(description: 'Card label.')
  final String label;
}
''';

const _cardDataCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart';

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.data});

  @RestageProperty(description: 'Customer data.')
  final CardData data;

  @override
  Widget build(BuildContext context) => Text(data.label);
}
''';

const _configWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'Config',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A customer widget named like a Widgetbook export.',
)
class Config extends StatelessWidget {
  const Config({required this.label});

  @RestageProperty(description: 'Visible label.')
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

const _dateTimeWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'DateTime',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A customer widget named like a dart:core type.',
)
class DateTime extends StatelessWidget {
  const DateTime({required this.label});

  @RestageProperty(description: 'Visible label.')
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

final class _StoryPlanProbeBuilder implements Builder {
  const _StoryPlanProbeBuilder({
    this.captureErrors = false,
    this.widgetName,
  });

  final bool captureErrors;
  final String? widgetName;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['customer.stories.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      final index = await loadWidgetbookCatalogSourceIndex(buildStep);
      final widget = widgetName == null
          ? index.widgets.single
          : index.widgets.singleWhere(
              (candidate) => candidate.entry.name == widgetName,
            );
      final plan = planWidgetbookStory(
        index: index,
        widget: widget,
      );
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'lib/customer.stories.dart'),
        renderWidgetbookStorySource(
          plan: plan,
          packageName: buildStep.inputId.package,
          sourcePath: widget.sourceAsset.path,
        ),
      );
    } catch (error) {
      if (!captureErrors) rethrow;
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'lib/customer.stories.dart'),
        error.toString(),
      );
    }
  }
}

String _runtimeDefaultWidget(String defaultSource) => '''
  import 'package:flutter/material.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'CustomerCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Customer card.',
  )
  class CustomerCard extends StatelessWidget {
    const CustomerCard({this.color});
    @RestageProperty(
      description: 'Customer color.',
      defaultSource: $defaultSource,
    )
    final Color? color;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _lookalikeColorWidget = '''
  import 'package:flutter/widgets.dart' hide Color;
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  class Color {
    const Color();
  }

  @RestageWidget(
    name: 'LookalikeCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Lookalike card.',
  )
  class LookalikeCard extends StatelessWidget {
    const LookalikeCard({required this.color});
    @RestageProperty(
      description: 'Lookalike color.',
      defaultSource: LiteralDefault('#336699'),
    )
    final Color color;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _lookalikeWidgetWidget = '''
  import 'package:flutter/widgets.dart' as flutter;
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  class Widget {
    const Widget();
  }

  @RestageWidget(
    name: 'LookalikeWidgetCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Lookalike widget card.',
  )
  class LookalikeWidgetCard extends flutter.StatelessWidget {
    const LookalikeWidgetCard({this.child});
    @RestageProperty(description: 'Lookalike child.')
    final Widget? child;
    @override
    flutter.Widget build(flutter.BuildContext context) =>
        const flutter.SizedBox();
  }
''';

const _hostStateWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'HostStateCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Host state card.',
  )
  class HostStateCard extends StatelessWidget {
    const HostStateCard({required this.label, this.hostState});
    @RestageProperty(description: 'Visible label.')
    final String label;
    /// State supplied only by the host application.
    final Object? hostState;
    @override
    Widget build(BuildContext context) => Text(label);
  }
''';

const _firstSameNamedCard = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'FirstCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'First same-named card.',
  )
  class Card extends StatelessWidget {
    const Card({required this.label, this.hostState});
    @RestageProperty(description: 'Visible label.')
    final String label;
    /// State supplied only by the host application.
    final Object? hostState;
    @override
    Widget build(BuildContext context) => Text(label);
  }
''';

const _secondSameNamedCard = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'SecondCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Second same-named card.',
  )
  class Card extends StatelessWidget {
    const Card({required this.label});
    @RestageProperty(description: 'Visible label.')
    final String label;
    @override
    Widget build(BuildContext context) => Text(label);
  }
''';

const _badColorDefaultWidget = '''
  import 'package:flutter/material.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'BadDefaultCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Bad default card.',
  )
  class BadDefaultCard extends StatelessWidget {
    const BadDefaultCard({required this.color});
    @RestageProperty(
      description: 'Card color.',
      defaultSource: LiteralDefault('not-a-color'),
    )
    final Color color;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _enumDefaultWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  enum Tone { calm, urgent }

  @RestageWidget(
    name: 'EnumCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Enum card.',
  )
  class EnumCard extends StatelessWidget {
    const EnumCard({this.tone = Tone.urgent});
    @RestageProperty(
      description: 'Card tone.',
      constraints: RestageConstraints(allowedValues: ['calm']),
    )
    final Tone tone;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _nonportableConstructorDefaultWidget = '''
  import 'package:flutter/material.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'ColorDefaultCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Color default card.',
  )
  class ColorDefaultCard extends StatelessWidget {
    const ColorDefaultCard({this.color = const Color(0xFF336699)});
    @RestageProperty(description: 'Card color.')
    final Color color;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _nullDefaultAllowedValueWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'NullDefaultCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Null-default card.',
  )
  class NullDefaultCard extends StatelessWidget {
    const NullDefaultCard({this.value = null});
    @RestageProperty(
      description: 'Finite customer value.',
      constraints: RestageConstraints(allowedValues: ['ready']),
    )
    final String? value;
    @override
    Widget build(BuildContext context) => Text(value ?? 'none');
  }
''';

const _patternedStringWidget = r'''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'PatternedCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Patterned card.',
  )
  class PatternedCard extends StatelessWidget {
    const PatternedCard({required this.code});
    @RestageProperty(
      description: 'Uppercase code.',
      constraints: RestageConstraints(pattern: r'^[A-Z]+$'),
    )
    final String code;
    @override
    Widget build(BuildContext context) => Text(code);
  }
''';

const _nullablePatternWidget = r'''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'NullablePatternCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Nullable patterned card.',
  )
  class NullablePatternCard extends StatelessWidget {
    const NullablePatternCard({this.code});
    @RestageProperty(
      description: 'Optional uppercase code.',
      constraints: RestageConstraints(pattern: r'^[A-Z]+$'),
    )
    final String? code;
    @override
    Widget build(BuildContext context) => Text(code ?? 'none');
  }
''';

const _constrainedListWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'ConstrainedListCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.layout,
    description: 'Constrained list card.',
  )
  class ConstrainedListCard extends StatelessWidget {
    const ConstrainedListCard({required this.children});
    @RestageProperty(
      description: 'Customer children.',
      constraints: RestageConstraints(minItems: 2, maxItems: 3),
    )
    final List<Widget> children;
    @override
    Widget build(BuildContext context) => Column(children: children);
  }
''';

const _enumLabelWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  enum Status { ready, processing }

  @RestageWidget(
    name: 'StatusCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Status card.',
  )
  class StatusCard extends StatelessWidget {
    const StatusCard({required this.status});
    @RestageProperty(description: 'Current status.')
    final Status status;
    @override
    Widget build(BuildContext context) => Text(status.name);
  }
''';

const _boundedWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'BoundedCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Bounded card.',
  )
  class BoundedCard extends StatelessWidget {
    const BoundedCard({this.opacity = 0.5});
    @RestageProperty(
      description: 'Card opacity.',
      constraints: RestageConstraints(minimum: 0.1),
    )
    final double opacity;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _legacyInvalidWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'LegacyInvalidCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Legacy invalid card.',
  )
  class LegacyInvalidCard extends StatelessWidget {
    const LegacyInvalidCard({this.score = 9});
    @RestageProperty(
      description: 'Card score.',
      defaultSource: LiteralDefault(9),
      validationRule: ValidationExpr(
        expression: 'range(1, 5)',
        message: 'Score must be between one and five.',
      ),
    )
    final int score;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _legacyValidWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'LegacyValidCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Legacy valid card.',
  )
  class LegacyValidCard extends StatelessWidget {
    const LegacyValidCard({this.score = 3});
    @RestageProperty(
      description: 'Card score.',
      defaultSource: LiteralDefault(3),
      validationRule: ValidationExpr(
        expression: 'range(1, 5)',
        message: 'Score must be between one and five.',
      ),
    )
    final int score;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

String _malformedLegacySyntaxWidget({required bool nullable}) {
  final className =
      nullable ? 'MalformedLegacyNullableCard' : 'MalformedLegacyNonNullCard';
  final type = nullable ? 'int?' : 'int';
  final defaultValue = nullable ? 'null' : '1';
  return '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: '$className',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Malformed legacy grammar proof.',
  )
  class $className extends StatelessWidget {
    const $className({this.value = $defaultValue});
    @RestageProperty(
      description: 'Malformed legacy value.',
      validationRule: ValidationExpr(
        expression: 'range(0)',
        message: 'Malformed range.',
      ),
    )
    final $type value;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';
}

const _constructorDefaultWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'ConstructorDefaultCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Constructor default card.',
  )
  class ConstructorDefaultCard extends StatelessWidget {
    const ConstructorDefaultCard({this.opacity = 0.5});
    @RestageProperty(description: 'Card opacity.')
    final double opacity;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _constructorDefaultPrecedenceWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'ConstructorDefaultPrecedenceCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Constructor default precedence card.',
  )
  class ConstructorDefaultPrecedenceCard extends StatelessWidget {
    const ConstructorDefaultPrecedenceCard({
      this.opacity = 0.5,
      this.label = 'constructor',
    });
    @RestageProperty(
      description: 'Literal conflict.',
      defaultSource: LiteralDefault(0.8),
    )
    final double opacity;
    @RestageProperty(
      description: 'Token conflict.',
      defaultSource: TokenRefDefault(
        WireIdRef(
          library: 'fixture.tokens',
          wireId: WireId.unallocatedDesignToken,
        ),
      ),
    )
    final String label;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';
