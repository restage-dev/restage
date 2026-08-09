import 'dart:io';

import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _annotation = '''
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
)
''';

void main() {
  group('constructor-first customer catalog authoring', () {
    test('unresolved-type detection is exhaustive over analyzer DartType', () {
      final source = File(
        'lib/src/widget_constructor_facts.dart',
      ).readAsStringSync();
      final visitorStart = source.indexOf(
        'final class _UnresolvedTypeVisitor',
      );
      final visitor = source.substring(
        visitorStart,
        source.indexOf(
          '\nvoid _addMigrationNotices',
          visitorStart,
        ),
      );

      expect(visitor, contains('extends TypeVisitor<bool>'));
      expect(visitor, contains('visitInvalidType(InvalidType type) => true'));
      expect(visitor, isNot(contains('_ =>')));
    });

    test('includes unannotated field formals in constructor order', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A constructor-authored probe.
$_annotation
class Probe {
  const Probe(this.count, {required this.label, this.enabled = true});

  /// Visible count.
  final int count;

  /// Visible label.
  final String label;

  /// Whether the probe is enabled.
  final bool enabled;
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final widget = result.widgets.single;
      expect(widget.description, 'A constructor-authored probe.');
      expect(
        widget.properties
            .map(
              (property) => (
                property.name,
                property.required,
                property.positional,
                property.description,
              ),
            )
            .toList(),
        [
          ('count', true, true, 'Visible count.'),
          ('label', true, false, 'Visible label.'),
          ('enabled', false, false, 'Whether the probe is enabled.'),
        ],
      );
    });

    test('announces newly inferred inputs on otherwise legacy authoring',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A mixed-authoring probe.
$_annotation
class Probe {
  const Probe({required this.legacy, required this.inferred});

  /// Explicit legacy input.
  @RestageProperty()
  final String legacy;

  /// Newly inferred input.
  final String inferred;
}
''',
      });

      final notices = result.issues
          .where(
            (issue) => issue.code == IssueCode.constructorCatalogMigration,
          )
          .toList();
      expect(notices, hasLength(1));
      expect(notices.single.location, 'lib/probe.dart#Probe.inferred');
    });

    test('constructor requiredness is authoritative on every target', () async {
      final sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A requiredness probe.
$_annotation
class Probe {
  const Probe({required this.label, this.note});

  /// Required label.
  @RestageProperty(required: false)
  final String label;

  /// Optional note strengthened for the catalog.
  @RestageProperty(required: true)
  final String? note;
}
''',
      };

      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isEmpty,
          reason: target.name,
        );
        expect(
          result.widgets.single.properties.map((property) => property.required),
          [true, true],
          reason: target.name,
        );
      }
    });

    test('portable constructor defaults feed RFW and A2UI target lowering',
        () async {
      final sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

enum Mode { ready, busy }

/// A constructor-default probe.
$_annotation
class Probe {
  const Probe({
    this.enabled = true,
    this.count = 3,
    this.label = 'Ready',
    this.mode = Mode.ready,
  });

  /// Whether the probe is enabled.
  final bool enabled;

  /// Visible count.
  final int count;

  /// Visible label.
  final String label;

  /// Current mode.
  final Mode mode;
}
''',
      };

      final rfw = await runWidgetVisitorOn(sources);
      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      final widgetbook = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.widgetbook,
      );

      expect(
        rfw.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(
        a2ui.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(
        widgetbook.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(
        rfw.widgets.single.properties.map((property) => property.defaultSource),
        const [
          LiteralDefault(true),
          LiteralDefault(3),
          LiteralDefault('Ready'),
          LiteralDefault('ready'),
        ],
      );
      expect(
        a2ui.widgets.single.properties
            .map((property) => property.defaultSource),
        const [
          LiteralDefault(true),
          LiteralDefault(3),
          LiteralDefault('Ready'),
          LiteralDefault('ready'),
        ],
      );
      expect(
        widgetbook.widgets.single.properties
            .map((property) => property.defaultSource),
        everyElement(isNull),
      );

      final factories = emitUserFactoriesDart(rfw.widgets)!;
      final flat = factories.replaceAll(RegExp(r'\s+'), ' ');
      for (final property in ['Enabled', 'Count', 'Label', 'Mode']) {
        expect(
          flat,
          contains(
            'if (_restagePresence$property.supplied) '
            '#${property[0].toLowerCase()}${property.substring(1)}:',
          ),
        );
      }
      expect(
        flat,
        contains('source.v<bool>(_restagePresenceEnabled.valuePath)'),
      );
      expect(
        flat,
        contains('source.v<int>(_restagePresenceCount.valuePath)'),
      );
      expect(
        flat,
        contains('source.v<String>(_restagePresenceLabel.valuePath)'),
      );
      expect(
        flat,
        contains('_restagePresenceMode.valuePath'),
      );
      expect(flat, isNot(contains('?? true')));
      expect(flat, isNot(contains('?? 3')));
      expect(flat, isNot(contains("?? 'Ready'")));
      expect(flat, isNot(contains('s0.Mode.ready')));
    });

    test('annotation defaults remain metadata beside constructor truth',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A metadata-default probe.
$_annotation
class Probe {
  const Probe({this.label = 'constructor'});

  @RestageProperty(
    description: 'Visible label.',
    defaultSource: LiteralDefault('preview'),
  )
  final String? label;
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final property = result.widgets.single.properties.single;
      expect(property.defaultSource, const LiteralDefault('preview'));
      expect(property.constructorNullable, isTrue);
      expect(
        property.constructorDefault,
        const DartConstScalar('constructor'),
      );
      final factory = emitUserFactoriesDart(result.widgets)!;
      expect(factory, contains('RestageRfwConstructorPresence.read('));
      expect(factory, contains('Function.apply('));
      expect(factory, isNot(contains("?? 'preview'")));
    });

    test('A2UI admits portable scalar-list constructor defaults', () async {
      final sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A portable collection-default probe.
$_annotation
class Probe {
  const Probe({this.counts = const <int>[7, 8]});

  /// Counts shown by the probe.
  @RestageProperty(defaultSource: LiteralDefault(<int>[99]))
  final List<int>? counts;
}
''',
      };

      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      expect(
        a2ui.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final property = a2ui.widgets.single.properties.single;
      expect(property.defaultSource, const LiteralDefault(<int>[99]));
      expect(
        property.constructorDefault,
        const DartConstList(
          [DartConstScalar(7), DartConstScalar(8)],
          type: DartTypeIdentity(
            libraryUri: 'dart:core',
            symbolName: 'List',
            typeArguments: [
              DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'int'),
            ],
          ),
        ),
      );
    });

    test('constructor invocation defaults feed enabled wire targets', () async {
      final sources = {
        'lib/probe.dart': '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A non-portable constructor-default probe.
$_annotation
class Probe {
  const Probe({this.color = const Color(0xFF123456)});

  /// Customer color.
  final Color color;
}
''',
      };

      final rfw = await runWidgetVisitorOn(sources);
      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      final widgetbook = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.widgetbook,
      );

      expect(
        rfw.issues.where((candidate) => !candidate.code.isInformational),
        isEmpty,
      );
      expect(
        a2ui.issues.where((candidate) => !candidate.code.isInformational),
        isEmpty,
      );
      expect(
        widgetbook.issues.where((candidate) => !candidate.code.isInformational),
        isEmpty,
      );
      expect(
        rfw.widgets.single.properties.single.constructorDefault,
        isA<DartConstInvocation>(),
      );
      final factory = emitUserFactoriesDart(rfw.widgets)!;
      expect(factory, contains('RestageRfwConstructorPresence.read('));
      expect(factory, isNot(contains("import 'dart:ui'")));
      expect(
        factory,
        contains(
          'ArgumentDecoders.color(source, _restagePresenceColor.valuePath)',
        ),
      );
      expect(factory, isNot(contains('Color.new(4279383126)')));
    });

    test('public scalar const defaults retain symbol identity', () async {
      final sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Tokens {
  static const retries = 3;
}

/// A symbol-default probe.
$_annotation
class Probe {
  const Probe({this.retries = Tokens.retries});

  /// Retry count.
  final int retries;
}
''',
      };

      for (final target in const [
        WidgetVisitorTarget.rfw,
        WidgetVisitorTarget.a2ui,
      ]) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(
          result.issues.where((candidate) => !candidate.code.isInformational),
          isEmpty,
          reason: target.name,
        );
        expect(
          result.widgets.single.properties.single.constructorDefault,
          const DartConstReference(
            libraryUri: 'package:apps_examples/probe.dart',
            owner: 'Tokens',
            member: 'retries',
          ),
        );
      }

      final rfw = await runWidgetVisitorOn(sources);
      final factory = emitUserFactoriesDart(rfw.widgets)!;
      expect(factory, contains('RestageRfwConstructorPresence.read('));
      expect(
        factory,
        contains('source.v<int>(_restagePresenceRetries.valuePath)'),
      );
      expect(factory, isNot(contains('Tokens.retries')));
    });

    test('public extension scalar const defaults retain symbol identity',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

extension Tokens on Object {
  static const retries = 3;
}

/// An extension-symbol-default probe.
$_annotation
class Probe {
  const Probe({this.retries = Tokens.retries});

  /// Retry count.
  final int retries;
}
''',
      });

      expect(
        result.issues.where((candidate) => !candidate.code.isInformational),
        isEmpty,
      );
      expect(
        result.widgets.single.properties.single.constructorDefault,
        const DartConstReference(
          libraryUri: 'package:apps_examples/probe.dart',
          owner: 'Tokens',
          member: 'retries',
        ),
      );
      final factory = emitUserFactoriesDart(result.widgets)!;
      expect(factory, contains('RestageRfwConstructorPresence.read('));
      expect(
        factory,
        contains('source.v<int>(_restagePresenceRetries.valuePath)'),
      );
      expect(factory, isNot(contains('Tokens.retries')));
    });

    test('private const defaults fail closed while public identities recurse',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:flutter/widgets.dart';

const topLevelDefault = 1;
const _privateTopLevel = 0xFF000002;

class PublicStatics {
  static const value = 0xFF000003;
}

extension PublicExtension on Object {
  static const value = 0xFF000004;
}

/// A const-identity probe.
$_annotation
class Probe {
  const Probe({
    this.privateOuter = _privateTopLevel,
    this.privateNested = const Color(_privateTopLevel),
    this.publicTopLevel = topLevelDefault,
    this.publicStaticNested = const Color(PublicStatics.value),
    this.publicExtensionNested = const Color(PublicExtension.value),
  });

  /// Private outer const.
  final int privateOuter;

  /// Private nested const.
  final Color privateNested;

  /// Public top-level const.
  final int publicTopLevel;

  /// Public static nested const.
  final Color publicStaticNested;

  /// Public extension nested const.
  final Color publicExtensionNested;
}
''',
      };

      final facts = await runWidgetConstructorFactsOn(sources);
      final defaults = {
        for (final input in facts.inputs) input.name: input.constructorDefault,
      };
      final privateOuter = defaults['privateOuter'];
      expect(privateOuter, isA<UnsupportedWidgetConstructorDefault>());
      expect(
        defaults['privateNested'],
        isA<UnsupportedWidgetConstructorDefault>(),
      );
      expect(
        defaults['publicTopLevel']!.reconstructedValue,
        const DartConstReference(
          libraryUri: 'package:apps_examples/probe.dart',
          member: 'topLevelDefault',
        ),
      );
      final publicStaticNested = defaults['publicStaticNested']!
          .reconstructedValue! as DartConstInvocation;
      expect(
        publicStaticNested.positional,
        const [
          DartConstReference(
            libraryUri: 'package:apps_examples/probe.dart',
            owner: 'PublicStatics',
            member: 'value',
          ),
        ],
      );
      final publicExtensionNested = defaults['publicExtensionNested']!
          .reconstructedValue! as DartConstInvocation;
      expect(
        publicExtensionNested.positional,
        const [
          DartConstReference(
            libraryUri: 'package:apps_examples/probe.dart',
            owner: 'PublicExtension',
            member: 'value',
          ),
        ],
      );

      for (final target in const [
        WidgetVisitorTarget.rfw,
        WidgetVisitorTarget.a2ui,
      ]) {
        final result = await runWidgetVisitorOn(sources, target: target);
        final issues = result.issues
            .where(
              (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
            )
            .toList();
        expect(issues, hasLength(2), reason: target.name);
        expect(
          issues.map((issue) => issue.location),
          containsAll([
            'lib/probe.dart#Probe.privateOuter',
            'lib/probe.dart#Probe.privateNested',
          ]),
          reason: target.name,
        );
      }
    });

    test('public callback tear-off defaults retain importable identity',
        () async {
      final facts = await runWidgetConstructorFactsOn({
        'lib/probe.dart': '''
typedef Callback = void Function();

void topLevelCallback() {}
void _privateCallback() {}

class PublicCallbacks {
  static void staticCallback() {}
}

class Probe {
  const Probe({
    this.topLevel = topLevelCallback,
    this.staticMethod = PublicCallbacks.staticCallback,
    this.privateFunction = _privateCallback,
  });

  final Callback topLevel;
  final Callback staticMethod;
  final Callback privateFunction;
}
''',
      });

      final defaults = {
        for (final input in facts.inputs) input.name: input.constructorDefault,
      };
      expect(
        defaults['topLevel']!.reconstructedValue,
        const DartConstReference(
          libraryUri: 'package:apps_examples/probe.dart',
          member: 'topLevelCallback',
        ),
      );
      expect(
        defaults['staticMethod']!.reconstructedValue,
        const DartConstReference(
          libraryUri: 'package:apps_examples/probe.dart',
          owner: 'PublicCallbacks',
          member: 'staticCallback',
        ),
      );
      expect(
        defaults['privateFunction'],
        isA<UnsupportedWidgetConstructorDefault>(),
      );
    });

    test('nested public null consts retain reference identity', () async {
      final facts = await runWidgetConstructorFactsOn({
        'lib/probe.dart': '''
const Object? absent = null;
const Object? _privateAbsent = null;

class Box {
  const Box(this.value);

  final Object? value;
}

class Probe {
  const Probe({
    this.literalNull = null,
    this.publicTopLevel = absent,
    this.invocation = const Box(absent),
    this.items = const <Object?>[absent],
    this.privateInvocation = const Box(_privateAbsent),
    this.privateItems = const <Object?>[_privateAbsent],
  });

  final Object? literalNull;
  final Object? publicTopLevel;
  final Box invocation;
  final List<Object?> items;
  final Box privateInvocation;
  final List<Object?> privateItems;
}
''',
      });

      expect(
        facts.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final defaults = {
        for (final input in facts.inputs)
          input.name: input.constructorDefault.reconstructedValue,
      };
      const absentReference = DartConstReference(
        libraryUri: 'package:apps_examples/probe.dart',
        member: 'absent',
      );
      expect(defaults['literalNull'], const DartConstNull());
      expect(defaults['publicTopLevel'], absentReference);
      expect(
        (defaults['invocation']! as DartConstInvocation).positional,
        const [absentReference],
      );
      expect(
        (defaults['items']! as DartConstList).values,
        const [absentReference],
      );
      expect(defaults['privateInvocation'], isNull);
      expect(defaults['privateItems'], isNull);
    });

    test('constructor constants retain identity, invocation, and structures',
        () async {
      final facts = await runWidgetConstructorFactsOn({
        'lib/probe.dart': '''
class Value<T> {
  const Value(this.value, {required this.meta});

  final T value;
  final ({int count, String label}) meta;
}

class Tokens {
  static const exact = Value<String>(
    'identity',
    meta: (count: 1, label: 'one'),
  );
  static const invocationLabel = 'invocation';
}

class Probe {
  const Probe({
    this.identity = Tokens.exact,
    this.invocation = const Value<String>(
      Tokens.invocationLabel,
      meta: (count: 2, label: 'two'),
    ),
    this.items = const <String>['a', 'b'],
    this.values = const <int>{1, 2},
    this.lookup = const <String, int>{'a': 1},
    this.record = (count: 3, label: 'three'),
  });

  final Value<String> identity;
  final Value<String> invocation;
  final List<String> items;
  final Set<int> values;
  final Map<String, int> lookup;
  final ({int count, String label}) record;
}
''',
      });

      expect(
        facts.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final defaults = {
        for (final input in facts.inputs)
          input.name: input.constructorDefault.reconstructedValue,
      };
      expect(
        defaults['identity'],
        const DartConstReference(
          libraryUri: 'package:apps_examples/probe.dart',
          owner: 'Tokens',
          member: 'exact',
        ),
      );
      final invocation = defaults['invocation']! as DartConstInvocation;
      final invocationType = invocation.type as DartNamedTypeIdentity;
      expect(invocationType.symbolName, 'Value');
      expect(
        (invocationType.typeArguments.single as DartNamedTypeIdentity)
            .symbolName,
        'String',
      );
      expect(
        invocation.positional,
        const [
          DartConstReference(
            libraryUri: 'package:apps_examples/probe.dart',
            owner: 'Tokens',
            member: 'invocationLabel',
          ),
        ],
      );
      expect(invocation.named.single.name, 'meta');
      expect(invocation.named.single.value, isA<DartConstRecord>());
      expect(defaults['items'], isA<DartConstList>());
      expect(defaults['values'], isA<DartConstSet>());
      expect(defaults['lookup'], isA<DartConstMap>());
      expect(defaults['record'], isA<DartConstRecord>());
    });

    test('reconstruction canonicalizes named members by name', () async {
      final facts = await runWidgetConstructorFactsOn({
        'lib/probe.dart': '''
class Pair {
  const Pair({required this.zeta, required this.alpha});

  final int zeta;
  final String alpha;
}

class Probe {
  const Probe({
    this.invocation = const Pair(zeta: 2, alpha: 'one'),
    this.record = (zeta: 3, alpha: 'two'),
    this.items = const <({int zeta, String alpha})>[],
  });

  final Pair invocation;
  final ({int zeta, String alpha}) record;
  final List<({int zeta, String alpha})> items;
}
''',
      });

      expect(
        facts.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final defaults = {
        for (final input in facts.inputs)
          input.name: input.constructorDefault.reconstructedValue,
      };
      final invocation = defaults['invocation']! as DartConstInvocation;
      final record = defaults['record']! as DartConstRecord;
      final items = defaults['items']! as DartConstList;
      final listType = items.type! as DartNamedTypeIdentity;
      final recordType =
          listType.typeArguments.single as DartRecordTypeIdentity;

      expect(invocation.named.map((field) => field.name), ['alpha', 'zeta']);
      expect(record.named.map((field) => field.name), ['alpha', 'zeta']);
      expect(recordType.named.map((field) => field.name), ['alpha', 'zeta']);
    });

    test('collection defaults retain explicit source generic identity',
        () async {
      final facts = await runWidgetConstructorFactsOn({
        'lib/probe.dart': '''
class Probe {
  const Probe({
    this.items = const <num>[1],
    this.values = const <Object>{'one'},
    this.lookup = const <String, num>{'one': 1},
  });

  final List<num> items;
  final Set<Object> values;
  final Map<String, num> lookup;
}
''',
      });

      expect(
        facts.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final defaults = {
        for (final input in facts.inputs)
          input.name: input.constructorDefault.reconstructedValue,
      };
      expect(
        (defaults['items']! as DartConstList).type,
        const DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'num'),
          ],
        ),
      );
      expect(
        (defaults['values']! as DartConstSet).type,
        const DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'Set',
          typeArguments: [
            DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'Object'),
          ],
        ),
      );
      expect(
        (defaults['lookup']! as DartConstMap).type,
        const DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'Map',
          typeArguments: [
            DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'String'),
            DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'num'),
          ],
        ),
      );
    });

    test('typed collection defaults retain structural record type identity',
        () async {
      final facts = await runWidgetConstructorFactsOn({
        'lib/model.dart': '''
class ExternalValue {
  const ExternalValue(this.value);

  final int value;
}
''',
        'lib/probe.dart': '''
import 'model.dart';

class Probe {
  const Probe({
    this.items = const <({int count, ExternalValue? value})>[
      (count: 1, value: ExternalValue(1)),
    ],
    this.values = const <(ExternalValue?, String)?>{
      (ExternalValue(2), 'two'),
    },
    this.lookup = const <
      String,
      ({List<int?>? counts, ExternalValue value})
    >{
      'three': (counts: <int?>[3, null], value: ExternalValue(3)),
    },
  });

  final List<({int count, ExternalValue? value})> items;
  final Set<(ExternalValue?, String)?> values;
  final Map<String, ({List<int?>? counts, ExternalValue value})> lookup;
}
''',
      });

      expect(
        facts.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final defaults = {
        for (final input in facts.inputs)
          input.name: input.constructorDefault.reconstructedValue,
      };

      final itemType =
          (defaults['items']! as DartConstList).type! as DartNamedTypeIdentity;
      final itemRecord =
          itemType.typeArguments.single as DartRecordTypeIdentity;
      expect(itemRecord.named.map((field) => field.name), ['count', 'value']);
      expect(itemRecord.named.last.type.nullable, isTrue);
      expect(
        itemRecord.named.last.type,
        isA<DartNamedTypeIdentity>().having(
          (type) => type.libraryUri,
          'libraryUri',
          'package:apps_examples/model.dart',
        ),
      );

      final setType =
          (defaults['values']! as DartConstSet).type! as DartNamedTypeIdentity;
      final setRecord = setType.typeArguments.single as DartRecordTypeIdentity;
      expect(setRecord.nullable, isTrue);
      expect(setRecord.positional, hasLength(2));
      expect(setRecord.positional.first.nullable, isTrue);

      final mapType =
          (defaults['lookup']! as DartConstMap).type! as DartNamedTypeIdentity;
      final mapRecord = mapType.typeArguments.last as DartRecordTypeIdentity;
      expect(mapRecord.named.map((field) => field.name), ['counts', 'value']);
      final countsType = mapRecord.named.first.type as DartNamedTypeIdentity;
      expect(countsType.nullable, isTrue);
      expect(countsType.typeArguments.single.nullable, isTrue);
    });

    test('private collection type arguments reject at the source property',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

typedef _PrivateInt = int;

/// A private collection-type probe.
$_annotation
class Probe {
  const Probe({this.values = const <_PrivateInt>[]});

  /// Values shown by the probe.
  final List<int> values;
}
''',
      };

      final facts = await runWidgetConstructorFactsOn(sources);
      expect(
        facts.inputs.single.constructorDefault,
        isA<UnsupportedWidgetConstructorDefault>(),
      );

      final result = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      expect(
        result.issues,
        contains(
          isA<Issue>()
              .having(
                (issue) => issue.code,
                'code',
                IssueCode.invalidWidgetConstructorInput,
              )
              .having(
                (issue) => issue.location,
                'location',
                'lib/probe.dart#Probe.values',
              ),
        ),
      );
    });

    test('supports substituted super formals and excludes Flutter super.key',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class BaseProbe<T> extends StatelessWidget {
  const BaseProbe({super.key, required this.value});

  /// Backing value documentation.
  final T value;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A super-formal probe.
$_annotation
class Probe extends BaseProbe<String> {
  const Probe({
    super.key,
    /// Local super-formal documentation.
    required super.value,
  });
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(result.widgets.single.properties, hasLength(1));
      final property = result.widgets.single.properties.single;
      expect(property.name, 'value');
      expect(property.type, PropertyType.string);
      expect(property.required, isTrue);
      expect(property.description, 'Local super-formal documentation.');
    });

    test('excludes positional super.key through its resolved forwarding chain',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

abstract class PositionalKeyBase extends StatelessWidget {
  const PositionalKeyBase([Key? key]) : super(key: key);
}

/// A positional super-key probe.
$_annotation
class Probe extends PositionalKeyBase {
  const Probe(this.label, [super.key]);

  /// Visible label.
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(result.widgets.single.properties, hasLength(1));
      expect(result.widgets.single.properties.single.name, 'label');
    });

    test('excludes classic Flutter Key forwarding by resolved identity',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A classic key-forwarding probe.
$_annotation
class Probe extends StatelessWidget {
  const Probe({Key? key, required this.label}) : super(key: key);

  /// Visible label.
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(result.widgets.single.properties.single.name, 'label');
    });

    test('rejects named-only and factory-only constructor classes', () async {
      for (final fixture in <({String name, String declaration})>[
        (
          name: 'NamedOnlyProbe',
          declaration: '''
class NamedOnlyProbe {
  const NamedOnlyProbe.named(this.label);

  /// Visible label.
  final String label;
}
''',
        ),
        (
          name: 'FactoryOnlyProbe',
          declaration: '''
abstract class FactoryOnlyProbe {
  const factory FactoryOnlyProbe(String label) = FactoryOnlyProbeImpl;

  String get label;
}

class FactoryOnlyProbeImpl implements FactoryOnlyProbe {
  const FactoryOnlyProbeImpl(this.label);

  @override
  final String label;
}
''',
        ),
      ]) {
        final result = await runWidgetVisitorOn({
          'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

$_annotation
${fixture.declaration}
''',
        });

        expect(result.widgets, isEmpty, reason: fixture.name);
        expect(
          result.issues,
          contains(
            isA<Issue>()
                .having(
                  (issue) => issue.location,
                  'location',
                  'lib/probe.dart#${fixture.name}',
                )
                .having(
                  (issue) => issue.message,
                  'message',
                  allOf(
                    contains('no unnamed generative constructor'),
                    contains('Generated customer catalog factories'),
                  ),
                ),
          ),
          reason: fixture.name,
        );
      }
    });

    test('rejects @ignore on an assert-guarded optional input', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// An assert-guarded exclusion probe.
$_annotation
class Probe {
  const Probe({@ignore this.label}) : assert(label != null);

  /// A label the constructor rejects when omitted in checked builds.
  final String? label;
}
''',
      });

      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.location, 'lib/probe.dart#Probe.label');
      expect(issue.message, contains('assert'));
      expect(issue.message, contains('label'));
    });

    test('rejects @ignore on an is-guarded optional input', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A type-guarded exclusion probe.
$_annotation
class Probe {
  const Probe({@ignore this.label}) : assert(label is String);

  /// A label the constructor rejects when omitted in checked builds.
  final String? label;
}
''',
      });

      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.location, 'lib/probe.dart#Probe.label');
      expect(issue.message, contains('assert'));
      expect(issue.message, contains('label'));
    });

    test('is guards respect generic bounds and nullable aliases', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

typedef MaybeLabel = String?;

/// A potentially-null type-guard probe.
$_annotation
class Probe<T extends Object?> {
  const Probe({@ignore this.label, @ignore this.value})
      : assert(label is MaybeLabel),
        assert(value is T);

  final Object? label;
  final Object? value;
}
''',
      });

      expect(
        result.issues.where(
          (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
        ),
        isEmpty,
      );
      expect(
        result.widgets.single.properties,
        isEmpty,
      );
    });

    test('is guards resolve non-null aliases semantically', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

typedef Label = String;

/// An aliased type-guard probe.
$_annotation
class Probe {
  const Probe({@ignore this.label}) : assert(label is Label);

  final Object? label;
}
''',
      });

      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.location, 'lib/probe.dart#Probe.label');
      expect(issue.message, contains('assert'));
    });

    test('raw generic is guards instantiate type arguments to bounds',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

typedef Maybe<T extends Object?> = T;
typedef Box<T extends Object?> = List<T>;
class Bucket<T extends Object?> {}

/// A raw-generic type-guard probe.
$_annotation
class Probe {
  const Probe({@ignore this.maybe, @ignore this.box, @ignore this.bucket})
      : assert(maybe is Maybe),
        assert(box is Box),
        assert(bucket is Bucket);

  final Object? maybe;
  final Object? box;
  final Object? bucket;
}
''',
      });

      final failures = result.issues
          .where(
            (candidate) =>
                candidate.code == IssueCode.invalidWidgetConstructorInput,
          )
          .toList();
      expect(failures, hasLength(2));
      expect(
        failures.map((issue) => issue.location),
        containsAll([
          'lib/probe.dart#Probe.box',
          'lib/probe.dart#Probe.bucket',
        ]),
      );
      expect(
        failures.map((issue) => issue.message),
        everyElement(contains('assert')),
      );
    });

    test(
        'rejects @ignore on an optional positional before a supplied '
        'positional', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A positional-hole exclusion probe.
$_annotation
class Probe {
  const Probe([@ignore this.internal = 0, this.label = 'visible']);

  final int internal;

  /// The later catalog input.
  final String label;
}
''',
      });

      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.location, 'lib/probe.dart#Probe.internal');
      expect(issue.message, contains('internal'));
      expect(issue.message, contains('label'));
      expect(issue.message, contains('shift'));
      expect(
        result.widgets.single.properties.map((property) => property.name),
        ['label'],
      );
    });

    test('rejects a target auto-exclusion that creates a positional hole',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// An automatic positional-hole probe.
$_annotation
class Probe {
  const Probe([this.hostOwned, this.label = 'visible']);

  /// State supplied only by the host application.
  final Object? hostOwned;

  /// The later catalog input.
  final String label;
}
''',
      });

      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.location, 'lib/probe.dart#Probe.hostOwned');
      expect(issue.message, contains('hostOwned'));
      expect(issue.message, contains('label'));
      expect(issue.message, contains('shift'));
    });

    test('dynamic optional input is semantically nullable and auto-excluded',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A semantic-nullability probe.
$_annotation
class Probe {
  const Probe({this.hostState});

  /// State supplied only by the host application.
  final dynamic hostState;
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(result.exclusions, hasLength(1));
      expect(result.exclusions.single.property, 'hostState');
    });

    test('announces annotated inputs inherited past the legacy field walk',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class BaseProbe {
  const BaseProbe({
    required this.backingAnnotated,
    required this.locallyAnnotated,
  });

  @RestageProperty(description: 'Inherited backing-field description.')
  final String backingAnnotated;

  final String locallyAnnotated;
}

/// An inherited-input migration probe.
$_annotation
class Probe extends BaseProbe {
  const Probe({
    required super.backingAnnotated,
    @RestageProperty(description: 'Local super-formal description.')
    required super.locallyAnnotated,
  });
}
''',
      });

      final notices = result.issues
          .where(
            (issue) => issue.code == IssueCode.constructorCatalogMigration,
          )
          .toList();
      expect(result.issues, hasLength(2));
      expect(notices, hasLength(2));
      expect(
        notices.map((issue) => issue.location),
        containsAll([
          'lib/probe.dart#Probe.backingAnnotated',
          'lib/probe.dart#Probe.locallyAnnotated',
        ]),
      );
      expect(
        notices.map((issue) => issue.message),
        everyElement(
          contains(
            'Legacy catalog discovery only admitted @RestageProperty fields '
            'declared directly on Probe.',
          ),
        ),
      );
      expect(
        result.widgets.single.properties
            .map(
              (property) => (
                property.name,
                property.description,
                property.required,
              ),
            )
            .toList(),
        [
          ('backingAnnotated', 'Inherited backing-field description.', true),
          ('locallyAnnotated', 'Local super-formal description.', true),
        ],
      );
    });

    test('accepts an unchanged ordinary parameter-to-field initializer',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// An ordinary binding probe.
$_annotation
class Probe {
  const Probe(String raw) : value = raw;

  /// Stored value.
  final String value;
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final property = result.widgets.single.properties.single;
      expect(property.name, 'raw');
      expect(property.type, PropertyType.string);
      expect(property.required, isTrue);
      expect(property.positional, isTrue);
      expect(property.description, 'Stored value.');
    });

    test('ordinary binding ignores unrelated same-named identifiers', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Tokens {
  static const raw = 1;
}

/// An identity-bound ordinary parameter probe.
$_annotation
class Probe {
  Probe(String raw)
      : value = raw,
        marker = _marker(raw: Tokens.raw),
        local = ((String raw) => raw)('local');

  static int _marker({required int raw}) => raw;

  /// Stored value.
  final String value;
  final int marker;
  final String local;
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(result.widgets.single.properties.single.name, 'raw');
    });

    test('ordinary binding respects nested local shadowing', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A locally-shadowed ordinary parameter probe.
$_annotation
class Probe {
  Probe(String raw)
      : value = raw,
        marker = (() {
          final raw = 'local';
          return raw.length;
        })(),
        labelMarker = (() {
          raw:
          while (true) {
            break raw;
          }
          return 0;
        })();

  /// Stored value.
  final String value;
  final int marker;
  final int labelMarker;
}
''',
      });

      expect(
        result.issues.where(
          (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
        ),
        isEmpty,
      );
      expect(result.widgets.single.properties.single.name, 'raw');
    });

    test('ordinary function binding respects a same-named local function',
        () async {
      final result = await runWidgetVisitorOn(
        {
          'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A locally-shadowed function parameter probe.
$_annotation
class Probe {
  Probe(void Function() raw)
      : callback = raw,
        marker = (() {
          void raw() {}
          raw();
          return 0;
        })();

  /// Stored callback.
  final void Function() callback;
  final int marker;
}
''',
        },
        target: WidgetVisitorTarget.widgetbook,
      );

      expect(
        result.issues.where(
          (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
        ),
        isEmpty,
      );
      expect(result.widgets.single.properties.single.name, 'raw');
    });

    test('rejects private and initializer-transformed constructor inputs',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probes.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A private-input probe.
@RestageWidget(
  name: 'PrivateProbe',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
)
class PrivateProbe {
  const PrivateProbe({required this._secret});
  final String _secret;
}

/// A transformed-input probe.
@RestageWidget(
  name: 'TransformedProbe',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
)
class TransformedProbe {
  const TransformedProbe(String raw) : value = raw.trim();

  /// Stored value.
  final String value;
}
''',
      });

      final failures = result.issues
          .where(
            (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
          )
          .toList();
      expect(failures, hasLength(2));
      expect(
        failures.map((issue) => issue.location),
        containsAll([
          'lib/probes.dart#PrivateProbe._secret',
          'lib/probes.dart#TransformedProbe.raw',
        ]),
      );
    });

    test('rejects an unresolved generic super-formal type', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class BaseProbe<T> {
  const BaseProbe({required this.value});

  /// Backing value documentation.
  final T value;
}

/// A generic super-formal probe.
$_annotation
class Probe<T> extends BaseProbe<T> {
  const Probe({required super.value});
}
''',
      });

      final issue = result.issues.singleWhere(
        (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.location, 'lib/probe.dart#Probe.value');
      expect(issue.message, contains('unresolved type parameter'));
    });

    test('super-formal metadata falls back to the backing formal', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class BaseProbe {
  const BaseProbe({
    @RestageProperty(description: 'Backing formal description.', required: true)
    this.first,
    @RestageProperty(description: 'Ignored backing description.')
    this.second,
  });

  final String? first;
  final String? second;
}

/// A super-formal metadata probe.
$_annotation
class Probe extends BaseProbe {
  const Probe({
    super.first,
    @RestageProperty(description: 'Local formal description.') super.second,
  });
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(
        result.widgets.single.properties
            .map(
              (property) => (
                property.name,
                property.description,
                property.required,
              ),
            )
            .toList(),
        [
          ('first', 'Backing formal description.', true),
          ('second', 'Local formal description.', false),
        ],
      );
    });

    test('field Dartdoc wins, parameter Dartdoc falls back, paragraphs remain',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// First widget paragraph.
///
/// Second widget paragraph.
$_annotation
class Probe {
  const Probe({
    /// Parameter text that the field overrides.
    required this.label,
    /// First parameter line.
    /// Second parameter line.
    ///
    /// Second parameter paragraph.
    required this.note,
  });

  /// Field text wins.
  final String label;

  final String note;
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(
        result.widgets.single.description,
        'First widget paragraph.\n\nSecond widget paragraph.',
      );
      expect(
        result.widgets.single.properties[0].description,
        'Field text wins.',
      );
      expect(
        result.widgets.single.properties[1].description,
        'First parameter line. Second parameter line.\n\n'
        'Second parameter paragraph.',
      );
    });

    test('explicit descriptions override Dartdoc', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Ignored class text.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
  description: 'Explicit widget text.',
)
class Probe {
  const Probe({required this.label});

  /// Ignored field text.
  @RestageProperty(description: 'Explicit property text.')
  final String label;
}
''',
      });

      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(result.widgets.single.description, 'Explicit widget text.');
      expect(
        result.widgets.single.properties.single.description,
        'Explicit property text.',
      );
    });

    test('missing descriptions fail with widget and property paths', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

$_annotation
class Probe {
  const Probe({required this.label});
  final String label;
}
''',
      });

      expect(
        result.issues
            .where(
              (issue) => issue.code == IssueCode.missingCatalogDescription,
            )
            .map((issue) => issue.location),
        containsAll(['lib/probe.dart#Probe', 'lib/probe.dart#Probe.label']),
      );
    });

    test('annotated legacy fields migrate explicitly to constructor order',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// An ordering probe.
$_annotation
class Probe {
  const Probe({required this.first, required this.second});

  /// Second value.
  @RestageProperty()
  final String second;

  /// First value.
  @RestageProperty()
  final String first;
}
''',
      });

      expect(
        result.widgets.single.properties.map((property) => property.name),
        ['first', 'second'],
      );
      expect(
        result.issues.where(
          (issue) => issue.code == IssueCode.constructorCatalogMigration,
        ),
        hasLength(1),
      );
    });

    test(
        'a widget with no property annotations still announces every input '
        'it newly admits', () async {
      // Under the older rule this class produced a widget with ZERO
      // properties. It now produces two. Saying nothing about that is the
      // largest silent change of the lot.
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A greenfield probe.
$_annotation
class Probe {
  const Probe({required this.title, this.subtitle});

  /// The title.
  final String title;

  /// The subtitle.
  final String? subtitle;
}
''',
      });

      final notices = result.issues
          .where(
            (issue) => issue.code == IssueCode.constructorCatalogMigration,
          )
          .toList();
      expect(notices, hasLength(2));
      expect(
        notices.map((issue) => issue.location),
        containsAll([
          'lib/probe.dart#Probe.title',
          'lib/probe.dart#Probe.subtitle',
        ]),
      );
    });

    test(
        'an explicit required: false on a Dart-required formal announces '
        'that the constructor wins', () async {
      // The one real behavioural change in the shipped corpus: the annotation
      // says optional, the constructor says required, and the constructor is
      // authoritative. The property silently becomes required today.
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A conflicting-authoring probe.
$_annotation
class Probe {
  const Probe({required this.children});

  /// The children.
  @RestageProperty(description: 'The children.', required: false)
  final String children;
}
''',
      });

      final notices = result.issues
          .where(
            (issue) => issue.code == IssueCode.constructorCatalogMigration,
          )
          .toList();
      expect(notices, hasLength(1));
      expect(notices.single.location, 'lib/probe.dart#Probe.children');
      expect(notices.single.message, contains('children'));
      expect(notices.single.message.toLowerCase(), contains('required'));
    });

    test('a bare @RestageProperty on a required formal announces nothing',
        () async {
      // Guard against the noisy version of the rule. Omitting `required` is
      // not a claim that the input is optional, so there is no disagreement
      // to announce and no notice belongs here.
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A plain-authoring probe.
$_annotation
class Probe {
  const Probe({required this.label});

  /// The label.
  @RestageProperty(description: 'The label.')
  final String label;
}
''',
      });

      expect(
        result.issues.where(
          (issue) => issue.code == IssueCode.constructorCatalogMigration,
        ),
        isEmpty,
      );
    });
  });
}
