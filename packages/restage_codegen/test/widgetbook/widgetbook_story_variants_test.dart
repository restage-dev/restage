import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_native_value_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_property_capability.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show PropertyType;
import 'package:rfw_catalog_schema/widgetbook.dart' show StoryExpansion;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('no config emits only the stable default and callbacks are not axes',
      () async {
    await _runVariantProbe(
      _stateWidget(),
      outputMatcher: allOf(
        contains('axes='),
        contains('variants=Default[]'),
        isNot(contains('onChanged=')),
      ),
    );
  });

  test('unconfigured nullable enum null seed belongs to its choice domain',
      () async {
    await _runVariantProbe(
      _stateWidget(modeType: 'Mode?', modeDefault: 'null'),
      outputMatcher: allOf(
        contains('axes='),
        contains('variants=Default[]'),
        contains('choiceDomains=mode[Idle,Ready,Done,Null]/seed=Null'),
      ),
    );
  });

  test('storyValues preserve authored order after default-first typed dedup',
      () async {
    await _runVariantProbe(
      _stateWidget(enabledConfig: '@wb.Config.values([true, false, true])'),
      outputMatcher: allOf(
        contains('axes=enabled[False,True]'),
        contains('variants=Default[enabled=False]'),
        contains('|EnabledTrue[enabled=True]'),
      ),
    );
  });

  test('nullable bool allValues use canonical false, true, null order',
      () async {
    await _runVariantProbe(
      _stateWidget(
        enabledType: 'bool?',
        enabledDefault: 'true',
        enabledConfig: '@wb.Config.allValues()',
      ),
      outputMatcher: allOf(
        contains('axes=enabled[True,False,Null]'),
        contains('variants=Default[enabled=True]'),
        contains('|EnabledFalse[enabled=False]'),
        contains('|EnabledNull[enabled=Null]'),
      ),
    );
  });

  test('nullable enum allValues use declaration order plus null', () async {
    await _runVariantProbe(
      _stateWidget(
        modeType: 'Mode?',
        modeDefault: 'Mode.ready',
        modeConfig: '@wb.Config.allValues()',
      ),
      outputMatcher: allOf(
        contains('axes=mode[Ready,Idle,Done,Null]'),
        contains('variants=Default[mode=Ready]'),
        contains('|ModeIdle[mode=Idle]'),
        contains('|ModeDone[mode=Done]'),
        contains('|ModeNull[mode=Null]'),
      ),
    );
  });

  test('public const bool and enum defaults remain exact axis defaults',
      () async {
    await _runVariantProbe(
      _stateWidget(
        enabledDefault: 'defaultEnabled',
        modeDefault: 'defaultMode',
        enabledConfig: '@wb.Config.allValues()',
        modeConfig: '@wb.Config.allValues()',
        extraDeclarations: '''
const defaultEnabled = true;
const defaultMode = Mode.ready;
''',
      ),
      outputMatcher: allOf(
        contains('axes=enabled[True,False];mode[Ready,Idle,Done]'),
        contains('variants=Default[enabled=True,mode=Ready]'),
      ),
    );
  });

  for (final alias in <({String name, String expression})>[
    (name: 'public', expression: 'defaultMode'),
    (name: 'chained', expression: 'chainedDefaultMode'),
  ]) {
    test(
        '${alias.name} const enum defaults use the declared choice domain once',
        () async {
      await _runVariantProbe(
        _stateWidget(
          modeDefault: alias.expression,
          modeConfig: '@wb.Config.allValues()',
          extraDeclarations: '''
const defaultMode = Mode.ready;
const chainedDefaultMode = defaultMode;
''',
        ),
        outputMatcher: allOf(
          contains('axes=mode[Ready,Idle,Done]'),
          contains('variants=Default[mode=Ready]'),
          contains('choiceDomains=mode[Idle,Ready,Done]/seed=Ready'),
          isNot(contains('WidgetbookStaticMemberValuePlan')),
        ),
      );
    });
  }

  for (final alias in <({String name, String expression})>[
    (name: 'public', expression: 'defaultMode'),
    (name: 'chained', expression: 'chainedDefaultMode'),
  ]) {
    for (final configured in <bool>[false, true]) {
      test(
          '${alias.name} const null enum default uses one canonical null '
          '${configured ? 'with' : 'without'} config', () async {
        await _runVariantProbe(
          _nullableEnumStaticNullAliasWidget(
            alias.expression,
            configured: configured,
          ),
          outputMatcher: allOf(
            contains('choiceDomains=mode[Idle,Ready,Done,Null]/seed=Null'),
            contains('provenance=constructorDefault'),
            isNot(contains('WidgetbookStaticMemberValuePlan')),
          ),
        );
      });
    }
  }

  for (final alias in <({String name, String expression})>[
    (name: 'public', expression: 'defaultEnabled'),
    (name: 'chained', expression: 'chainedDefaultEnabled'),
  ]) {
    test('${alias.name} constrained bool alias deduplicates by typed value',
        () async {
      await _runVariantProbe(
        _constrainedBoolStaticAliasWidget(alias.expression),
        outputMatcher: allOf(
          contains('choiceDomains=enabled[false,true]/seed=true'),
          contains('provenance=constructorDefault'),
          isNot(contains('WidgetbookStaticMemberValuePlan')),
        ),
      );
    });
  }

  for (final scalar in <({
    String name,
    String type,
    String expression,
    String declarations,
    String allowedValues,
    String domain,
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
      domain: '1,2',
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
      domain: '1.5,2.5',
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
      domain: 'first,second',
    ),
  ]) {
    test('${scalar.name} constrained alias canonicalizes at the finite seam',
        () async {
      await _runVariantProbe(
        _constrainedScalarStaticAliasWidget(
          type: scalar.type,
          defaultExpression: scalar.expression,
          declarations: scalar.declarations,
          allowedValues: scalar.allowedValues,
        ),
        outputMatcher: allOf(
          contains(
            'choiceDomains=value[${scalar.domain}]'
            '/seed=${scalar.domain.split(',').last}',
          ),
          contains('provenance=constructorDefault'),
          isNot(contains('WidgetbookStaticMemberValuePlan')),
        ),
      );
    });
  }

  test(
      'finite framework defaults retain constructor truth without extra '
      'choices', () async {
    await _runVariantProbe(
      _finiteFrameworkConstructorDefaultsWidget,
      outputMatcher: allOf(
        contains(
          'choiceDomains=color[color:#FF000000,color:#FF336699]'
          '/seed=color:#FF336699/provenance=constructorDefault;',
        ),
        contains(
          'duration[duration:100,duration:250]'
          '/seed=duration:250/provenance=constructorDefault;',
        ),
        contains(
          'weight[fontWeight:400,fontWeight:700]'
          '/seed=fontWeight:700/provenance=constructorDefault',
        ),
        isNot(contains('WidgetbookDartConstValuePlan')),
        isNot(contains('WidgetbookStaticMemberValuePlan')),
      ),
    );
  });

  final constrainedConstructorFamilies = <({
    String name,
    String property,
    List<({String name, String expression, String planType})> forms,
  })>[
    (
      name: 'duration',
      property: 'duration',
      forms: [
        (
          name: 'inline',
          expression: 'const Duration(milliseconds: 150)',
          planType: 'WidgetbookDartConstValuePlan',
        ),
        (
          name: 'public',
          expression: 'defaultDuration',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
        (
          name: 'chained',
          expression: 'chainedDuration',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
      ],
    ),
    (
      name: 'font weight',
      property: 'weight',
      forms: [
        (
          name: 'inline',
          expression: 'FontWeight.w700',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
        (
          name: 'public',
          expression: 'defaultWeight',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
        (
          name: 'chained',
          expression: 'chainedWeight',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
      ],
    ),
    (
      name: 'color',
      property: 'color',
      forms: [
        (
          name: 'inline',
          expression: 'const Color(0xFF336699)',
          planType: 'WidgetbookDartConstValuePlan',
        ),
        (
          name: 'public',
          expression: 'defaultColor',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
        (
          name: 'chained',
          expression: 'chainedColor',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
      ],
    ),
    (
      name: 'widget-list length',
      property: 'children',
      forms: [
        (
          name: 'inline',
          expression: 'const <Widget>[SizedBox.shrink(), SizedBox.shrink()]',
          planType: 'WidgetbookDartConstValuePlan',
        ),
        (
          name: 'public',
          expression: 'defaultChildren',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
        (
          name: 'chained',
          expression: 'chainedChildren',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
      ],
    ),
    (
      name: 'customer structured-list length',
      property: 'items',
      forms: [
        (
          name: 'inline',
          expression:
              "const <CustomerItem>[CustomerItem('one'), CustomerItem('two')]",
          planType: 'WidgetbookDartConstValuePlan',
        ),
        (
          name: 'public',
          expression: 'defaultItems',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
        (
          name: 'chained',
          expression: 'chainedItems',
          planType: 'WidgetbookStaticMemberValuePlan',
        ),
      ],
    ),
  ];

  for (final family in constrainedConstructorFamilies) {
    for (final form in family.forms) {
      test(
          '${form.name} ${family.name} default is validated and retains its '
          'exact plan', () async {
        await _runVariantProbe(
          widgetbookConstrainedConstructorDefaultFixture(
            family: family.name,
            defaultExpression: form.expression,
            matching: true,
          ),
          outputMatcher: contains(
            'seeds=${family.property}[${form.planType}]'
            '/provenance=constructorDefault',
          ),
        );
      });

      test('${form.name} ${family.name} constraint mismatch fails at its path',
          () async {
        await _runVariantProbe(
          widgetbookConstrainedConstructorDefaultFixture(
            family: family.name,
            defaultExpression: form.expression,
            matching: false,
          ),
          captureErrors: true,
          outputMatcher: allOf(
            contains('/constructorDefaults/${family.property}'),
            contains('violates its constraints'),
          ),
        );
      });
      if (const {
        'widget-list length',
        'customer structured-list length',
      }.contains(family.name)) {
        test('${form.name} ${family.name} maxItems mismatch fails at its path',
            () async {
          await _runVariantProbe(
            widgetbookConstrainedConstructorDefaultFixture(
              family: family.name,
              defaultExpression: form.expression,
              matching: false,
              collectionMaximumMismatch: true,
            ),
            captureErrors: true,
            outputMatcher: allOf(
              contains('/constructorDefaults/${family.property}'),
              contains('violates its constraints'),
            ),
          );
        });
      }
    }
  }

  for (final defaultValue in <({String name, String expression})>[
    (name: 'direct', expression: '2.0'),
    (name: 'public', expression: 'defaultRatio'),
    (name: 'chained', expression: 'chainedDefaultRatio'),
  ]) {
    test('${defaultValue.name} mixed real default has one typed domain',
        () async {
      await _runVariantProbe(
        _mixedRealConstructorDefaultWidget(defaultValue.expression),
        outputMatcher: allOf(
          contains(
            'choiceDomains=ratio[1,2]/seed=2'
            '/provenance=constructorDefault',
          ),
          isNot(contains('WidgetbookDartConstValuePlan')),
          isNot(contains('WidgetbookStaticMemberValuePlan')),
        ),
      );
    });
  }

  for (final defaultValue in <({String name, String expression})>[
    (name: 'direct', expression: '-0.0'),
    (name: 'public', expression: 'defaultNegativeZero'),
    (name: 'chained', expression: 'chainedNegativeZero'),
  ]) {
    test('${defaultValue.name} negative-zero default preserves its domain',
        () async {
      await _runVariantProbe(
        _signedZeroConstructorDefaultWidget(defaultValue.expression),
        outputMatcher: allOf(
          contains(
            'choiceDomains=ratio[-0.0,2]/seed=-0.0'
            '/provenance=constructorDefault',
          ),
          isNot(contains('WidgetbookStaticMemberValuePlan')),
        ),
      );
    });
  }

  test('negative-zero default outside the signed finite domain fails loudly',
      () async {
    await _runVariantProbe(
      _signedZeroWrongDomainWidget,
      captureErrors: true,
      outputMatcher: allOf(
        contains('/constructorDefaults/ratio'),
        contains('allowed-value'),
      ),
    );
  });

  final finiteCatalogCases = <({
    PropertyType propertyType,
    String name,
    String type,
    String defaultValue,
    String allowedValues,
    String domain,
    String seed,
    String mismatchAllowedValues,
  })>[
    (
      propertyType: PropertyType.boolean,
      name: 'bool',
      type: 'bool',
      defaultValue: 'true',
      allowedValues: 'false, true',
      domain: 'false,true',
      seed: 'true',
      mismatchAllowedValues: 'false',
    ),
    (
      propertyType: PropertyType.integer,
      name: 'int',
      type: 'int',
      defaultValue: '2',
      allowedValues: '1, 2',
      domain: '1,2',
      seed: '2',
      mismatchAllowedValues: '1',
    ),
    (
      propertyType: PropertyType.real,
      name: 'real',
      type: 'double',
      defaultValue: '2.0',
      allowedValues: '1, 2',
      domain: '1,2',
      seed: '2',
      mismatchAllowedValues: '0.0, 1.0',
    ),
    (
      propertyType: PropertyType.string,
      name: 'String',
      type: 'String',
      defaultValue: "'second'",
      allowedValues: "'first', 'second'",
      domain: 'first,second',
      seed: 'second',
      mismatchAllowedValues: "'first'",
    ),
    (
      propertyType: PropertyType.color,
      name: 'color',
      type: 'Color',
      defaultValue: "'#FF336699'",
      allowedValues: "'#FF000000', '#FF336699'",
      domain: 'color:#FF000000,color:#FF336699',
      seed: 'color:#FF336699',
      mismatchAllowedValues: "'#FF000000'",
    ),
    (
      propertyType: PropertyType.duration,
      name: 'duration',
      type: 'Duration',
      defaultValue: '250',
      allowedValues: '100, 250',
      domain: 'duration:100,duration:250',
      seed: 'duration:250',
      mismatchAllowedValues: '100',
    ),
    (
      propertyType: PropertyType.fontWeight,
      name: 'fontWeight',
      type: 'FontWeight',
      defaultValue: '700',
      allowedValues: '400, 700',
      domain: 'fontWeight:400,fontWeight:700',
      seed: 'fontWeight:700',
      mismatchAllowedValues: '400',
    ),
    (
      propertyType: PropertyType.enumValue,
      name: 'enum',
      type: 'Mode',
      defaultValue: "'ready'",
      allowedValues: "'idle', 'ready'",
      domain: 'Idle,Ready',
      seed: 'Ready',
      mismatchAllowedValues: "'idle'",
    ),
  ];

  test('catalog literal matrix covers every finite transport family', () {
    expect(
      {for (final finite in finiteCatalogCases) finite.propertyType},
      {
        for (final type in PropertyType.values)
          if (widgetbookFiniteChoiceTransport(type) != null) type,
      },
    );
  });

  for (final finite in finiteCatalogCases) {
    test('catalog literal ${finite.name} canonicalizes to its finite domain',
        () async {
      await _runVariantProbe(
        _catalogLiteralFiniteWidget(
          type: finite.type,
          defaultValue: finite.defaultValue,
          allowedValues: finite.allowedValues,
        ),
        outputMatcher: contains(
          'choiceDomains=value[${finite.domain}]'
          '/seed=${finite.seed}/provenance=catalogLiteral',
        ),
      );
    });

    test('catalog literal ${finite.name} mismatch fails at its default path',
        () async {
      await _runVariantProbe(
        _catalogLiteralFiniteWidget(
          type: finite.type,
          defaultValue: finite.defaultValue,
          allowedValues: finite.mismatchAllowedValues,
        ),
        captureErrors: true,
        outputMatcher: allOf(
          contains('/defaults/value'),
          contains('finite allowed-value'),
        ),
      );
    });
  }

  test('nullable null canonicalizes to its finite domain choice', () async {
    await _runVariantProbe(
      _nullableNullFiniteWidget(includeNull: true),
      outputMatcher: contains(
        'choiceDomains=value[Null,ready]'
        '/seed=Null/provenance=constructorDefault',
      ),
    );
  });

  test('nullable null outside its finite domain fails at constructor path',
      () async {
    await _runVariantProbe(
      _nullableNullFiniteWidget(includeNull: false),
      captureErrors: true,
      outputMatcher: allOf(
        contains('/constructorDefaults/value'),
        contains('finite allowed-value'),
      ),
    );
  });

  test('catalog literal negative zero is rejected by a positive-zero domain',
      () async {
    await _runVariantProbe(
      _catalogLiteralFiniteWidget(
        type: 'double',
        defaultValue: '-0.0',
        allowedValues: '0.0, 2.0',
      ),
      captureErrors: true,
      outputMatcher: allOf(
        contains('/defaults/value'),
        contains('finite allowed-value'),
      ),
    );
  });

  test('catalog literal negative zero remains the authored domain choice',
      () async {
    await _runVariantProbe(
      _catalogLiteralFiniteWidget(
        type: 'double',
        defaultValue: '-0.0',
        allowedValues: '-0.0, 2.0',
      ),
      outputMatcher: contains(
        'choiceDomains=value[-0.0,2.0]'
        '/seed=-0.0/provenance=catalogLiteral',
      ),
    );
  });

  for (final empty in <({String name, String type, String defaultValue})>[
    (name: 'bool', type: 'bool', defaultValue: 'true'),
    (name: 'String', type: 'String', defaultValue: "'value'"),
  ]) {
    test('empty ${empty.name} allowedValues fails before seed planning',
        () async {
      await _runVariantProbe(
        _catalogLiteralFiniteWidget(
          type: empty.type,
          defaultValue: empty.defaultValue,
          allowedValues: '',
        ),
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
    test('Widgetbook rejects ${duplicate.name} duplicates like sibling targets',
        () async {
      await _runVariantProbe(
        _catalogLiteralFiniteWidget(
          type: 'double',
          defaultValue: '2.0',
          allowedValues: duplicate.allowedValues,
        ),
        captureErrors: true,
        outputMatcher: allOf(
          contains('CatalogLiteralFiniteCard.value'),
          contains('duplicate allowedValues[1]'),
        ),
      );
    });
  }

  test('unconfigured private enum default remains an exact implicit choice',
      () async {
    await _runVariantProbe(
      _privateEnumRouteWidget(route: 'implicit'),
      outputMatcher: allOf(
        contains('axes='),
        contains('variants=Default[]'),
        contains('choiceDomains=mode[Visible,_hidden,Trailing]/seed=_hidden'),
      ),
    );
  });

  test('allValues preserves a private enum constant in declaration order',
      () async {
    await _runVariantProbe(
      _privateEnumRouteWidget(route: 'allValues'),
      outputMatcher: allOf(
        contains('axes=mode[Visible,Hidden,Trailing]'),
        contains('variants=Default[mode=Visible]'),
        contains('|ModeHidden[mode=Hidden]'),
        contains('|ModeTrailing[mode=Trailing]'),
      ),
    );
  });

  test('explicit storyValues retains a private enum constant exactly',
      () async {
    await _runVariantProbe(
      _privateEnumRouteWidget(route: 'explicit'),
      outputMatcher: allOf(
        contains('axes=mode[Visible,Hidden]'),
        contains('variants=Default[mode=Visible]'),
        contains('|ModeHidden[mode=Hidden]'),
      ),
    );
  });

  test('a private enum type fails at its property path', () async {
    await _runVariantProbe(
      _privateEnumTypeWidget,
      captureErrors: true,
      outputMatcher: allOf(
        contains('PrivateEnumTypeCard.mode'),
        contains('_SecretMode'),
        contains('generated Widgetbook source'),
      ),
    );
  });

  test('finite constructor defaults reject a wrong transport type', () async {
    await _runVariantProbe(
      _wrongFiniteTransportWidget,
      captureErrors: true,
      outputMatcher: allOf(
        contains('WrongFiniteTransportCard.ratio'),
        contains('PropertyType.real'),
        contains('String'),
      ),
    );
  });

  test('non-lossless framework constructor defaults fail at their path',
      () async {
    await _runVariantProbe(
      _nonLosslessDurationDefaultWidget,
      captureErrors: true,
      outputMatcher: allOf(
        contains('/constructorDefaults/duration'),
        contains('losslessly'),
      ),
    );
  });

  test('constraints preserve valid public const bool and enum axis defaults',
      () async {
    await _runVariantProbe(
      _stateWidget(
        enabledDefault: 'defaultEnabled',
        modeDefault: 'defaultMode',
        enabledConfig: '@wb.Config.allValues()',
        modeConfig: '@wb.Config.allValues()',
        enabledPropertyConfig: '''
@RestageProperty(
  constraints: RestageConstraints(allowedValues: [false, true]),
)
''',
        modePropertyConfig: '''
@RestageProperty(
  constraints: RestageConstraints(
    allowedValues: ['idle', 'ready', 'done'],
  ),
)
''',
        extraDeclarations: '''
const defaultEnabled = true;
const defaultMode = Mode.ready;
''',
      ),
      outputMatcher: allOf(
        contains('axes=enabled[True,False];mode[Ready,Idle,Done]'),
        contains('variants=Default[enabled=True,mode=Ready]'),
      ),
    );
  });

  test('implicit enum choices select the first constraint-valid seed',
      () async {
    await _runVariantProbe(
      _requiredConstrainedEnumAxisWidget,
      outputMatcher: allOf(
        contains('axes=mode[Ready]'),
        contains('variants=Default[mode=Ready]'),
        isNot(contains('mode=Idle')),
      ),
    );
  });

  test('independent mode emits default plus one-axis non-default tuples',
      () async {
    await _runVariantProbe(
      _stateWidget(
        enabledConfig: '@wb.Config.values([true])',
        modeConfig: '@wb.Config.values([Mode.ready, Mode.done])',
      ),
      outputMatcher: contains(
        'variants=Default[enabled=False,mode=Idle]'
        '|EnabledTrue[enabled=True,mode=Idle]'
        '|ModeReady[enabled=False,mode=Ready]'
        '|ModeDone[enabled=False,mode=Done]',
      ),
    );
  });

  test('cartesian mode emits the full source-ordered product once', () async {
    await _runVariantProbe(
      _stateWidget(
        classConfig: '@wb.Config.expansion(wb.StoryExpansion.cartesian)',
        enabledConfig: '@wb.Config.values([true])',
        modeConfig: '@wb.Config.values([Mode.ready, Mode.done])',
      ),
      outputMatcher: contains(
        'variants=Default[enabled=False,mode=Idle]'
        '|ModeReady[enabled=False,mode=Ready]'
        '|ModeDone[enabled=False,mode=Done]'
        '|EnabledTrue[enabled=True,mode=Idle]'
        '|EnabledTrueModeReady[enabled=True,mode=Ready]'
        '|EnabledTrueModeDone[enabled=True,mode=Done]',
      ),
    );
  });

  test('aggregate and shorthand config produce the same planned tuples',
      () async {
    const expected = 'variants=Default[enabled=False,mode=Idle]'
        '|ModeReady[enabled=False,mode=Ready]'
        '|EnabledTrue[enabled=True,mode=Idle]'
        '|EnabledTrueModeReady[enabled=True,mode=Ready]';
    for (final classConfig in [
      '@wb.Config(expansion: wb.StoryExpansion.cartesian, maxStories: 4)',
      [
        '@wb.Config.expansion(wb.StoryExpansion.cartesian)',
        '@wb.Config.maxStories(4)',
      ].join('\n'),
    ]) {
      await _runVariantProbe(
        _stateWidget(
          classConfig: classConfig,
          enabledConfig: '@wb.Config.values([true])',
          modeConfig: '@wb.Config.values([Mode.ready])',
        ),
        outputMatcher: contains(expected),
      );
    }
  });

  test('chained property enum aliases plan as their canonical member',
      () async {
    await _runVariantProbe(
      _stateWidget(
        extraDeclarations: '''
const readyAlias = Mode.ready;
const chainedReadyAlias = readyAlias;
''',
        modeConfig: '@wb.Config.values([chainedReadyAlias])',
      ),
      outputMatcher: allOf(
        contains('axes=mode[Idle,Ready]'),
        contains('|ModeReady[mode=Ready]'),
      ),
    );
  });

  test('wrong enum members are rejected by resolved enum identity', () async {
    await _runVariantProbe(
      _stateWidget(
        extraDeclarations: 'enum OtherMode { idle }',
        modeConfig: '@wb.Config.values([OtherMode.idle])',
      ),
      captureErrors: true,
      outputMatcher: allOf(
        contains('outside the exact accepted set'),
        contains("property's resolved enum type"),
      ),
    );
  });

  test('wrong-enum aliases remain rejected by resolved enum identity',
      () async {
    await _runVariantProbe(
      _stateWidget(
        extraDeclarations: '''
enum OtherMode { idle }
const wrongModeAlias = OtherMode.idle;
''',
        modeConfig: '@wb.Config.values([wrongModeAlias])',
      ),
      captureErrors: true,
      outputMatcher: allOf(
        contains('outside the exact accepted set'),
        contains("property's resolved enum type"),
      ),
    );
  });

  test('callbacks cannot be configured as story axes', () async {
    await _runVariantProbe(
      _stateWidget(onChangedConfig: '@wb.Config.allValues()'),
      captureErrors: true,
      outputMatcher: allOf(
        contains("callback property 'onChanged'"),
        contains('Callbacks are never story axes'),
      ),
    );
  });

  test('null is rejected for a non-nullable finite property', () async {
    await _runVariantProbe(
      _stateWidget(enabledConfig: '@wb.Config.values([null])'),
      captureErrors: true,
      outputMatcher: contains('selects null for non-nullable property'),
    );
  });

  test('explicit null values are accepted for nullable bool and enum axes',
      () async {
    await _runVariantProbe(
      _stateWidget(
        enabledType: 'bool?',
        enabledDefault: 'true',
        enabledConfig: '@wb.Config.values([null])',
        modeType: 'Mode?',
        modeDefault: 'Mode.ready',
        modeConfig: '@wb.Config.values([null])',
      ),
      outputMatcher: allOf(
        contains('axes=enabled[True,Null];mode[Ready,Null]'),
        contains('variants=Default[enabled=True,mode=Ready]'),
        contains('|EnabledNull[enabled=Null,mode=Ready]'),
        contains('|ModeNull[enabled=True,mode=Null]'),
        contains('count=3'),
      ),
    );
  });

  for (final expansion in StoryExpansion.values) {
    test('empty explicit values produce only the default in ${expansion.name}',
        () async {
      await _runVariantProbe(
        _stateWidget(
          classConfig: expansion == StoryExpansion.cartesian
              ? '@wb.Config.expansion(wb.StoryExpansion.cartesian)'
              : '',
          enabledConfig: '@wb.Config.values([])',
          modeConfig: '@wb.Config.values([])',
        ),
        outputMatcher: allOf(
          contains('axes=enabled[False];mode[Idle]'),
          contains('variants=Default[enabled=False,mode=Idle]'),
          contains('count=1'),
          isNot(contains('|Enabled')),
          isNot(contains('|Mode')),
        ),
      );
    });
  }

  test('configured values are constraint-checked instead of filtered',
      () async {
    await _runVariantProbe(
      _stateWidget(
        modeConfig: '@wb.Config.values([Mode.ready])',
        modePropertyConfig: '''
@RestageProperty(
  constraints: RestageConstraints(allowedValues: ['idle']),
)
''',
      ),
      captureErrors: true,
      outputMatcher: allOf(
        contains('#StateCard.mode'),
        contains('violates its constraints'),
      ),
    );
  });

  test('type-invalid constraints fail closed before axis planning', () async {
    await _runVariantProbe(
      _stateWidget(
        enabledConfig: '@wb.Config.allValues()',
        enabledPropertyConfig: '''
@RestageProperty(
  constraints: RestageConstraints(minimum: 1),
)
''',
      ),
      captureErrors: true,
      outputMatcher: allOf(
        contains('StateCard.enabled'),
        contains('numeric constraints are not valid'),
        contains('PropertyType.boolean'),
      ),
    );
  });

  test('ordinary formal names remain the exact story-axis identity', () async {
    await _runVariantProbe(
      _ordinaryBindingAxisWidget,
      outputMatcher: allOf(
        contains('axes=isEnabled[False,True]'),
        contains('variants=Default[isEnabled=False]'),
        contains('|IsEnabledTrue[isEnabled=True]'),
        isNot(contains('axes=enabled[')),
      ),
    );
  });

  for (final rejected in <({String name, String source})>[
    (name: 'String', source: _stringAxisWidget),
    (name: 'number', source: _numberAxisWidget),
    (name: 'framework const', source: _frameworkAxisWidget),
    (name: 'customer structured const', source: _structuredAxisWidget),
  ]) {
    test('${rejected.name} storyValues are rejected rather than coerced',
        () async {
      await _runVariantProbe(
        rejected.source,
        captureErrors: true,
        outputMatcher: contains('exact bool/enum/null accepted set'),
      );
    });
  }

  test('allValues rejects a non-finite property family', () async {
    await _runVariantProbe(
      _stringAxisWidget.replaceFirst(
        "@wb.Config.values(['hello'])",
        '@wb.Config.allValues()',
      ),
      captureErrors: true,
      outputMatcher: contains('allValues supports only exact bool and enum'),
    );
  });

  test('normalization collisions fail with both source tuples', () async {
    await _runVariantProbe(
      _collisionWidget,
      captureErrors: true,
      outputMatcher: allOf(
        contains("story name 'ModeFooBar' collides"),
        contains('mode='),
        contains('foo_bar'),
        contains('fooBar'),
        isNot(contains('ModeFooBar2')),
      ),
    );
  });

  test('final RestageCatalog declaration collision names both tuples',
      () async {
    await _runVariantProbe(
      _restageCatalogDeclarationCollisionWidget,
      captureErrors: true,
      outputMatcher: allOf(
        contains(r"story declaration '$RestageCatalog' collides"),
        contains('restage=package:apps_examples/state_card.dart#Mode:base@0'),
        contains(
          'restage=package:apps_examples/state_card.dart#Mode:catalog@1',
        ),
      ),
    );
  });

  for (final malformed in <({String name, String type, String constraints})>[
    (
      name: 'inclusive and exclusive lower bounds',
      type: 'double',
      constraints: 'minimum: 0, exclusiveMinimum: 1',
    ),
    (
      name: 'inverted string lengths',
      type: 'String',
      constraints: 'minLength: 3, maxLength: 2',
    ),
  ]) {
    test('malformed ${malformed.name} fail before Widgetbook planning',
        () async {
      await _runVariantProbe(
        _malformedConstraintWidget(
          type: malformed.type,
          constraints: malformed.constraints,
        ),
        captureErrors: true,
        outputMatcher: allOf(
          contains('Widgetbook constraints at MalformedConstraintCard.value'),
          contains('constraints'),
        ),
      );
    });
  }

  for (final legacy in <bool>[false, true]) {
    for (final nullable in <bool>[false, true]) {
      final sourceKind = legacy ? 'legacy' : 'typed';
      final seedKind = nullable ? 'null' : 'non-null';
      final className = '${legacy ? 'Legacy' : 'Typed'}'
          '${nullable ? 'Nullable' : 'NonNull'}PatternCard';
      test('$sourceKind malformed pattern rejects a $seedKind seed uniformly',
          () async {
        await _runVariantProbe(
          widgetbookPatternValidationFixture(
            legacy: legacy,
            nullable: nullable,
            malformed: true,
          ),
          captureErrors: true,
          outputMatcher: allOf(
            contains('Widgetbook constraints at $className.value'),
            contains('pattern is not valid Dart RegExp syntax'),
            isNot(contains('FormatException')),
          ),
        );
      });
    }
  }

  test('the default limit rejects a larger configured plan', () async {
    await _runVariantProbe(
      _stateWidget(
        enabledConfig: '@wb.Config.values([true])',
        modeConfig: '@wb.Config.values([Mode.ready, Mode.done])',
      ),
      defaultLimit: 3,
      absoluteLimit: 8,
      captureErrors: true,
      outputMatcher: allOf(<Matcher>[
        contains('story count for StateCard is 4'),
        contains('exceeds its effective limit 3'),
        contains('Effective limit: 3 (package default)'),
        contains('package default: 3'),
        contains('absolute ceiling: 8'),
        contains('axes/cardinalities: enabled=2, mode=3'),
        contains('independent expansion'),
        contains('select fewer values'),
        contains('raise maxStories'),
      ]),
    );
  });

  test('maxStories may deliberately raise the package default', () async {
    await _runVariantProbe(
      _stateWidget(
        classConfig: '@wb.Config.maxStories(4)',
        enabledConfig: '@wb.Config.values([true])',
        modeConfig: '@wb.Config.values([Mode.ready, Mode.done])',
      ),
      defaultLimit: 3,
      absoluteLimit: 8,
      outputMatcher: contains('count=4'),
    );
  });

  test('maxStories may deliberately lower the package default', () async {
    await _runVariantProbe(
      _stateWidget(
        classConfig: '@wb.Config.maxStories(3)',
        enabledConfig: '@wb.Config.values([true])',
        modeConfig: '@wb.Config.values([Mode.ready, Mode.done])',
      ),
      captureErrors: true,
      outputMatcher: allOf(
        contains('story count for StateCard is 4'),
        contains('exceeds its effective limit 3'),
        contains('Effective limit: 3 (configured maxStories)'),
      ),
    );
  });

  test('maxStories must be positive', () async {
    await _runVariantProbe(
      _stateWidget(classConfig: '@wb.Config.maxStories(0)'),
      captureErrors: true,
      outputMatcher: allOf(
        contains('must be greater than zero; received 0'),
        contains('Effective limit: 0 (configured maxStories)'),
        contains('package default: 32'),
        contains('absolute ceiling: 256'),
        contains('axes/cardinalities: none'),
        contains('Remove maxStories'),
      ),
    );
  });

  test('maxStories accepts the minimum value of one', () async {
    await _runVariantProbe(
      _stateWidget(classConfig: '@wb.Config(maxStories: 1)'),
      useProductionLimits: true,
      outputMatcher: allOf(
        contains('axes='),
        contains('variants=Default[]'),
        contains('count=1'),
      ),
    );
  });

  test('maxStories cannot exceed the absolute ceiling', () async {
    await _runVariantProbe(
      _stateWidget(classConfig: '@wb.Config.maxStories(9)'),
      defaultLimit: 3,
      absoluteLimit: 8,
      captureErrors: true,
      outputMatcher: allOf(
        contains('maxStories for StateCard is 9'),
        contains('absolute ceiling 8'),
        contains('Effective limit: 9 (configured maxStories)'),
        contains('package default: 3'),
        contains('absolute ceiling: 8'),
        contains('axes/cardinalities: none'),
        contains('set maxStories no higher than 8'),
      ),
    );
  });

  test('production policy defaults to 32 and caps overrides at 256', () async {
    final members =
        [for (var index = 0; index < 33; index++) 'value$index'].join(', ');
    final source = _stateWidget(
      modeDefault: 'Mode.value0',
      modeConfig: '@wb.Config.allValues()',
    ).replaceFirst('enum Mode { idle, ready, done }', 'enum Mode { $members }');
    await _runVariantProbe(
      source,
      useProductionLimits: true,
      captureErrors: true,
      outputMatcher: allOf(
        contains('story count for StateCard is 33'),
        contains('Effective limit: 32 (package default)'),
        contains('package default: 32'),
        contains('absolute ceiling: 256'),
        contains('axes/cardinalities: mode=33'),
      ),
    );
    await _runVariantProbe(
      _stateWidget(classConfig: '@wb.Config.maxStories(257)'),
      useProductionLimits: true,
      captureErrors: true,
      outputMatcher: allOf(
        contains('maxStories for StateCard is 257'),
        contains('absolute ceiling 256'),
        contains('package default: 32'),
      ),
    );
  });

  test('production limits accept exactly 32 default and 256 configured stories',
      () async {
    await _runVariantProbe(
      _cartesianBoolAxesWidget(5),
      useProductionLimits: true,
      outputMatcher: allOf(
        contains('count=32'),
        contains('value0[False,True]'),
        contains('value4[False,True]'),
      ),
    );
    await _runVariantProbe(
      _cartesianBoolAxesWidget(
        8,
        classConfig: '@wb.Config(maxStories: 256)',
      ),
      useProductionLimits: true,
      outputMatcher: allOf(
        contains('count=256'),
        contains('value0[False,True]'),
        contains('value7[False,True]'),
      ),
    );
  });

  test('cartesian count is rejected before enormous tuple materialization',
      () async {
    final fields = [
      for (var index = 0; index < 20; index++)
        '''
  /// Finite value $index.
  @wb.Config.allValues()
  final bool value$index;
''',
    ].join();
    final parameters = [
      for (var index = 0; index < 20; index++) 'this.value$index = false',
    ].join(',');
    final source = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@wb.Config.expansion(wb.StoryExpansion.cartesian)
@RestageWidget(
  name: 'HugeCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A card with many finite values.',
)
class HugeCard extends StatelessWidget {
  const HugeCard({$parameters});
$fields
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
    await _runVariantProbe(
      source,
      captureErrors: true,
      outputMatcher: allOf(
        contains('1048576'),
        contains('value0=2'),
        contains('value19=2'),
      ),
    );
  });

  test('cartesian singleton axes materialize iteratively', () async {
    final fields = [
      for (var index = 0; index < 1500; index++)
        '''
  /// Finite value $index.
  @wb.Config.values([false])
  final bool value$index;
''',
    ].join();
    final parameters = [
      for (var index = 0; index < 1500; index++) 'this.value$index = false',
    ].join(',');
    final source = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@wb.Config.expansion(wb.StoryExpansion.cartesian)
@RestageWidget(
  name: 'WideCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A card with many singleton axes.',
)
class WideCard extends StatelessWidget {
  const WideCard({$parameters});
$fields
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
    await _runVariantProbe(
      source,
      outputMatcher: allOf(
        contains('value0[False]'),
        contains('value1499[False]'),
        contains('count=1'),
      ),
    );
  });
}

Future<void> _runVariantProbe(
  String source, {
  Matcher outputMatcher = anything,
  bool captureErrors = false,
  int defaultLimit = 32,
  int absoluteLimit = 256,
  bool useProductionLimits = false,
}) async {
  final sources = {'apps_examples|lib/state_card.dart': source};
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/state_card.dart'),
    source,
  );
  await testBuilder(
    _VariantPlanProbeBuilder(
      captureErrors: captureErrors,
      limits: useProductionLimits
          ? null
          : WidgetbookStoryLimitPolicy(
              defaultLimit: defaultLimit,
              absoluteLimit: absoluteLimit,
            ),
    ),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    outputs: {
      'apps_examples|lib/story_variants.txt': decodedMatches(outputMatcher),
    },
  );
}

final class _VariantPlanProbeBuilder implements Builder {
  const _VariantPlanProbeBuilder({
    required this.captureErrors,
    required this.limits,
  });

  final bool captureErrors;
  final WidgetbookStoryLimitPolicy? limits;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['story_variants.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      final index = await loadWidgetbookCatalogSourceIndex(buildStep);
      final widget = index.widgets.single;
      final limits = this.limits;
      final plan = limits == null
          ? planWidgetbookStory(index: index, widget: widget)
          : planWidgetbookStory(
              index: index,
              widget: widget,
              storyLimits: limits,
            );
      final axes = plan.axes
          .map(
            (axis) => '${axis.property.property.name}'
                '[${axis.values.map((value) => value.nameFragment).join(',')}]',
          )
          .join(';');
      final variants = plan.variants.map((variant) {
        final values = plan.axes.map((axis) {
          final name = axis.property.property.name;
          return '$name=${variant.valuesByProperty[name]!.nameFragment}';
        }).join(',');
        return '${variant.name}[$values]';
      }).join('|');
      final choiceDomains = plan.properties
          .whereType<WidgetbookStoryChoicePropertyPlan>()
          .map(
            (property) => '${property.property.name}'
                '[${property.choices.map(_choiceValueLabel).join(',')}]'
                '/seed=${_choiceValueLabel(property.seed)}'
                '/provenance=${property.seedProvenance.name}',
          )
          .join(';');
      final seeds = plan.properties
          .map((property) {
            final seedAndProvenance = switch (property) {
              WidgetbookStoryEditablePropertyPlan(
                :final seed,
                :final seedProvenance
              ) ||
              WidgetbookStoryChoicePropertyPlan(
                :final seed,
                :final seedProvenance
              ) ||
              WidgetbookStoryNativePropertyPlan(
                :final seed,
                :final seedProvenance
              ) =>
                (seed: seed, provenance: seedProvenance),
              WidgetbookStoryEventPropertyPlan() => null,
            };
            if (seedAndProvenance == null) return null;
            return '${property.property.name}'
                '[${seedAndProvenance.seed.runtimeType}]'
                '/provenance=${seedAndProvenance.provenance.name}';
          })
          .whereType<String>()
          .join(';');
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'lib/story_variants.txt'),
        'axes=$axes\n'
        'variants=$variants\n'
        'count=${plan.variants.length}\n'
        'choiceDomains=$choiceDomains\n'
        'seeds=$seeds',
      );
    } catch (error) {
      if (!captureErrors) rethrow;
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'lib/story_variants.txt'),
        error.toString(),
      );
    }
  }
}

String _choiceValueLabel(WidgetbookNativeValuePlan value) => switch (value) {
      WidgetbookNullValuePlan() => 'Null',
      WidgetbookScalarValuePlan(:final value) => '$value',
      WidgetbookEnumValuePlan(:final member) =>
        '${member[0].toUpperCase()}${member.substring(1)}',
      WidgetbookFrameworkValuePlan(:final kind, :final value) =>
        '${kind.name}:$value',
      _ => value.runtimeType.toString(),
    };

String _stateWidget({
  String classConfig = '',
  String enabledConfig = '',
  String enabledPropertyConfig = '',
  String enabledType = 'bool',
  String enabledDefault = 'false',
  String modeConfig = '',
  String modePropertyConfig = '',
  String modeType = 'Mode',
  String modeDefault = 'Mode.idle',
  String extraDeclarations = '',
  String onChangedConfig = '',
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready, done }
$extraDeclarations

$classConfig
@RestageWidget(
  name: 'StateCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A finite state card.',
)
class StateCard extends StatelessWidget {
  const StateCard({
    this.enabled = $enabledDefault,
    this.mode = $modeDefault,
    this.onChanged,
  });

  /// Whether the card is enabled.
  $enabledPropertyConfig
  $enabledConfig
  final $enabledType enabled;

  /// Current card mode.
  $modePropertyConfig
  $modeConfig
  final $modeType mode;

  /// Reports enabled changes.
  $onChangedConfig
  final ValueChanged<bool>? onChanged;

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

const _wrongFiniteTransportWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'WrongFiniteTransportCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A wrong finite transport card.',
)
class WrongFiniteTransportCard extends StatelessWidget {
  const WrongFiniteTransportCard({this.ratio = 2.0});

  /// Customer ratio.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [1, '2']),
  )
  final double ratio;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _nonLosslessDurationDefaultWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'NonLosslessDurationCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A non-lossless duration card.',
)
class NonLosslessDurationCard extends StatelessWidget {
  const NonLosslessDurationCard({
    this.duration = const Duration(microseconds: 1),
  });

  /// Customer duration.
  @RestageProperty(
    constraints: RestageConstraints(allowedValues: [0, 1]),
  )
  final Duration duration;

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

String _nullableNullFiniteWidget({required bool includeNull}) => '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'NullableNullFiniteCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A nullable-null finite-domain card.',
)
class NullableNullFiniteCard extends StatelessWidget {
  const NullableNullFiniteCard({this.value = null});

  /// Finite nullable customer value.
  @RestageProperty(
    constraints: RestageConstraints(
      allowedValues: [${includeNull ? "null, 'ready'" : "'ready'"}],
    ),
  )
  final String? value;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

String _cartesianBoolAxesWidget(
  int axisCount, {
  String classConfig = '',
}) {
  final fields = [
    for (var index = 0; index < axisCount; index++)
      '''
  /// Finite value $index.
  @wb.Config.allValues()
  final bool value$index;
''',
  ].join();
  final parameters = [
    for (var index = 0; index < axisCount; index++) 'this.value$index = false',
  ].join(', ');
  return '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@wb.Config.expansion(wb.StoryExpansion.cartesian)
$classConfig
@RestageWidget(
  name: 'StateCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A finite state card.',
)
class StateCard extends StatelessWidget {
  const StateCard({$parameters});
$fields
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
}

const _ordinaryBindingAxisWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@RestageWidget(
  name: 'OrdinaryBindingCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'An ordinary constructor binding card.',
)
class OrdinaryBindingCard extends StatelessWidget {
  const OrdinaryBindingCard({bool isEnabled = false}) : enabled = isEnabled;

  /// Whether the card is enabled.
  @wb.Config.allValues()
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _requiredConstrainedEnumAxisWidget = r'''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready }

@RestageWidget(
  name: 'ConstrainedModeCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A constrained enum card.',
)
class ConstrainedModeCard extends StatelessWidget {
  const ConstrainedModeCard({required this.mode});

  /// Current mode.
  @RestageProperty(constraints: RestageConstraints(pattern: r'^ready$'))
  @wb.Config.values([Mode.ready])
  final Mode mode;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _stringAxisWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@RestageWidget(
  name: 'StringCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A string card.',
)
class StringCard extends StatelessWidget {
  const StringCard({this.label = 'hello'});
  /// Visible label.
  @wb.Config.values(['hello'])
  final String label;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _numberAxisWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@RestageWidget(
  name: 'NumberCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A number card.',
)
class NumberCard extends StatelessWidget {
  const NumberCard({this.count = 1});
  /// Visible count.
  @wb.Config.values([1])
  final int count;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _frameworkAxisWidget = '''
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@RestageWidget(
  name: 'ColorCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A color card.',
)
class ColorCard extends StatelessWidget {
  const ColorCard({this.color = const Color(0xFF000000)});
  /// Visible color.
  @wb.Config.values([Color(0xFFFFFFFF)])
  final Color color;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _structuredAxisWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class Data {
  const Data({required this.label});
  @RestageProperty(description: 'Label.')
  final String label;
}

@RestageWidget(
  name: 'DataCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A structured data card.',
)
class DataCard extends StatelessWidget {
  const DataCard({this.data = const Data(label: 'default')});
  /// Customer data.
  @wb.Config.values([Data(label: 'story')])
  final Data data;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

const _collisionWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { base, foo_bar, fooBar }

@RestageWidget(
  name: 'CollisionCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A story-name collision card.',
)
class CollisionCard extends StatelessWidget {
  const CollisionCard({this.mode = Mode.base});
  /// Current mode.
  @wb.Config.values([Mode.foo_bar, Mode.fooBar])
  final Mode mode;
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

String _malformedConstraintWidget({
  required String type,
  required String constraints,
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'MalformedConstraintCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A malformed constraint card.',
)
class MalformedConstraintCard extends StatelessWidget {
  const MalformedConstraintCard({required this.value});

  /// Constrained value.
  @RestageProperty(
    constraints: RestageConstraints($constraints),
  )
  final $type value;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
