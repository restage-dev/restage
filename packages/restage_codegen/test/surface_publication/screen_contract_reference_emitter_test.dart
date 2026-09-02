import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:crypto/crypto.dart';
import 'package:restage_codegen/src/onboarding/screen_builder.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _emptyEventHash = 'sha256:'
    'de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5';
const _multiEventHash = 'sha256:'
    'e8e6e96e91b1fa3ebab975bf91b75ddb201b88da6d5d3bb2baab4437546be450';
const _zeroEventHash = 'sha256:'
    '0000000000000000000000000000000000000000000000000000000000000000';
const _oneEventHash = 'sha256:'
    '1111111111111111111111111111111111111111111111111111111111111111';
const _emptyContractFingerprint = 'sha256:'
    '005037b32bb08a0a055114c6af93c430b99ee4508806aedb1b163fdcd69dbb7b';
const _multiContractFingerprint = 'sha256:'
    '18d0b8a332b67fb830a934913e410d0906904347e30a9dfba1036156bc8a5b60';

void main() {
  group('standalone screen contract/reference emitter', () {
    test('pins the shared event-hash and fingerprint vectors', () {
      final empty = SurfaceScreenEventSchema(events: const []);
      expect(
        SurfaceScreenEventContractHash.hash(empty),
        _emptyEventHash,
      );

      final multi = SurfaceScreenEventSchema(
        events: [
          SurfaceScreenEvent(
            id: 'submit',
            arguments: SurfaceScreenEventObjectArguments(
              const SurfaceScreenEventMapShapeV1(
                SurfaceScreenEventScalarShapeV1(
                  SurfaceScreenEventScalarKind.jsonValue,
                ),
              ),
            ),
          ),
          SurfaceScreenEvent(
            id: 'évent',
            arguments: const SurfaceScreenEventValueArguments(
              SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKind.integer,
              ),
            ),
          ),
          SurfaceScreenEvent(
            id: 'dismiss\n',
            arguments: const SurfaceScreenEventNoArguments(),
          ),
        ],
      );
      expect(
        SurfaceScreenEventContractHash.hash(multi),
        _multiEventHash,
      );

      expect(
        SurfaceScreenContractFingerprint.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: _capabilities(),
          eventContractHash: _zeroEventHash,
        ),
        _emptyContractFingerprint,
      );

      expect(
        SurfaceScreenContractFingerprint.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: CapabilityManifest(
            builtInFloor: 7,
            requiredLibraries: const [
              LibraryRequirement(namespace: 'é.core', minVersion: 3),
              LibraryRequirement(namespace: r'z/quote"slash\', minVersion: 2),
              LibraryRequirement(namespace: 'a\u001fedge', minVersion: 1),
            ],
          ),
          eventContractHash: _oneEventHash,
        ),
        _multiContractFingerprint,
      );
    });

    test('emits canonical typed event source from resolved SDK declarations',
        () async {
      final inspection = await _inspect(
        _screenSource(
          className: 'MaintenanceNotice',
          annotation: "@Screen(id: 'maintenance_notice', "
              'surface: Surface.general, version: 2)',
          events: r'''
  static const submit = SurfaceEvent<Map<String, Object?>>('submit');
  static const event = SurfaceEvent<int>('évent');
  static const dismiss = SurfaceEvent<void>('dismiss\n');
''',
        ),
        contractVersion: 2,
      );

      expect(inspection.issues, isEmpty);
      final contract = inspection.contract!;
      expect(
        contract.eventSchema.events.map((event) => event.id),
        ['dismiss\n', 'submit', 'évent'],
      );
      expect(
        contract.eventContractHash,
        _multiEventHash,
      );
      expect(
        contract.contractFingerprint,
        SurfaceScreenContractFingerprint.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: _capabilities(),
          eventContractHash: contract.eventContractHash,
        ),
      );

      final emitted = contract.emitReferenceDart();
      expect(parseString(content: emitted).errors, isEmpty, reason: emitted);
      await _assertGeneratedPartAnalyzes(
        _screenSource(
          className: 'MaintenanceNotice',
          annotation: "@Screen(id: 'maintenance_notice', "
              'surface: Surface.general, version: 2)',
          events: r'''
  static const submit = SurfaceEvent<Map<String, Object?>>('submit');
  static const event = SurfaceEvent<int>('évent');
  static const dismiss = SurfaceEvent<void>('dismiss\n');
''',
          part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
        ),
        emitted,
      );
      expect(emitted, contains('sealed class MaintenanceNoticeEvent'));
      expect(emitted, contains('MaintenanceNoticeDismissEvent'));
      expect(emitted, contains('SurfaceScreenRef<MaintenanceNoticeEvent>'));
      expect(emitted, contains('Map<String, Object?> arguments'));
      expect(emitted, isNot(contains('artifactPath')));
      expect(emitted, isNot(contains('.validate')));

      // The reference takes its identity and contract from provenance, and
      // the schema travels as canonical JSON so the runtime hashes the exact
      // value this build hashed.
      expect(emitted, contains('SurfaceScreenRuntimeProvenance.generated('));
      expect(emitted, contains('provenance: _maintenanceNoticeProvenance'));
      expect(emitted, contains('eventSchemaJson:'));
      expect(emitted, contains(r'{\"schemaVersion\":1,\"events\":['));
      // The fingerprint and event hash are derived at runtime, never
      // restated here. A generated constant repeating what this build
      // computed could only ever agree with itself, so emitting one would
      // silently disarm the encoder-agreement check on the reference.
      expect(emitted, isNot(contains('contractFingerprint:')));
      expect(emitted, isNot(contains(contract.contractFingerprint)));
      expect(
        sha256.convert(utf8.encode(emitted)).toString(),
        '59a844d0b0eae1036c56f72e1d73da01a2739200e0e4919cde29c0547a6cf170',
        reason: emitted,
      );
    });

    test('emits Never and a reject-all contract for event-free screens',
        () async {
      final inspection = await _inspect(
        _screenSource(
          className: 'ServiceStatus',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        ),
        className: 'ServiceStatus',
      );

      expect(inspection.issues, isEmpty);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(parseString(content: emitted).errors, isEmpty, reason: emitted);
      expect(emitted, contains('SurfaceScreenEventContract<Never>.none'));
      expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
      expect(emitted, isNot(contains('sealed class ServiceStatusEvent')));
      expect(emitted, isNot(contains('decodeValidated')));
    });

    test('maps the complete closed payload algebra through the shared schema',
        () async {
      final inspection = await _inspect(
        _screenSource(
          className: 'TypedNotice',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          events: '''
  static const boolean = SurfaceEvent<bool>('boolean');
  static const nullableInteger = SurfaceEvent<int?>('nullable-integer');
  static const json = SurfaceEvent<Object?>('json');
  static const list = SurfaceEvent<List<Map<String, int?>?>>('list');
  static const object = SurfaceEvent<Map<String, List<Object?>?>>('object');
  static const nullableMap = SurfaceEvent<Map<String, String>?>('nullable-map');
''',
        ),
        className: 'TypedNotice',
      );

      expect(inspection.issues, isEmpty);
      final contract = inspection.contract!;
      expect(
        SurfaceScreenEventSchemaV1Codec.encode(contract.eventSchema),
        {
          'schemaVersion': 1,
          'events': [
            {
              'id': 'boolean',
              'arguments': {
                'encoding': 'value',
                'shape': {'kind': 'bool'},
              },
            },
            {
              'id': 'json',
              'arguments': {
                'encoding': 'value',
                'shape': {'kind': 'jsonValue'},
              },
            },
            {
              'id': 'list',
              'arguments': {
                'encoding': 'value',
                'shape': {
                  'kind': 'list',
                  'items': {
                    'kind': 'nullable',
                    'value': {
                      'kind': 'map',
                      'values': {
                        'kind': 'nullable',
                        'value': {'kind': 'int'},
                      },
                    },
                  },
                },
              },
            },
            {
              'id': 'nullable-integer',
              'arguments': {
                'encoding': 'value',
                'shape': {
                  'kind': 'nullable',
                  'value': {'kind': 'int'},
                },
              },
            },
            {
              'id': 'nullable-map',
              'arguments': {
                'encoding': 'value',
                'shape': {
                  'kind': 'nullable',
                  'value': {
                    'kind': 'map',
                    'values': {'kind': 'string'},
                  },
                },
              },
            },
            {
              'id': 'object',
              'arguments': {
                'encoding': 'object',
                'shape': {
                  'kind': 'map',
                  'values': {
                    'kind': 'nullable',
                    'value': {
                      'kind': 'list',
                      'items': {'kind': 'jsonValue'},
                    },
                  },
                },
              },
            },
          ],
        },
      );
      final emitted = contract.emitReferenceDart();
      expect(emitted, contains('List<Map<String, int?>?> value'));
      expect(emitted, contains('Map<String, List<Object?>?> arguments'));
      expect(emitted, contains('Map<String, String>? value'));
    });

    test('uses the source library Restage prefix in emitted Dart', () async {
      final inspection = await _inspect(
        _screenSource(
          className: 'AliasedNotice',
          annotation: "@rs.Screen(id: 'maintenance_notice', "
              'surface: rs.Surface.general)',
          import: "import 'package:restage/restage.dart' as rs;",
          events: "  static const dismiss = rs.SurfaceEvent<void>('dismiss');",
        ),
        className: 'AliasedNotice',
      );

      expect(inspection.issues, isEmpty);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(parseString(content: emitted).errors, isEmpty, reason: emitted);
      expect(emitted, contains('rs.SurfaceScreenRef<AliasedNoticeEvent>'));
      expect(emitted, contains('rs.Surface.general'));
    });

    test('emits a typed mount with nested host values and exact fallback',
        () async {
      const source = '''
import 'package:flutter/widgets.dart' as fw;
import 'package:restage/restage.dart' as rs;
import 'support.dart' as support;

part 'restage.generated/maintenance_notice.restage.g.dart';

@rs.Screen(id: 'maintenance_notice', surface: rs.Surface.general)
final class TypedNotice extends fw.StatelessWidget {
  const TypedNotice(
    this.count, {
    required this.groups,
    this.message,
    this.controller = const support.Controller(),
    super.key,
  });

  final int count;
  final Map<String, List<int>?> groups;
  final String? message;
  final support.Controller controller;

  static const submit = rs.SurfaceEvent<void>('submit');

  @override
  fw.Widget build(fw.BuildContext context) => const fw.SizedBox.shrink();
}
''';
      const supportSource = '''
final class Controller {
  const Controller();
}
''';
      final inspection = await _inspect(
        source,
        className: 'TypedNotice',
        additionalSources: const {
          'apps_examples|lib/support.dart': supportSource,
        },
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(parseString(content: emitted).errors, isEmpty, reason: emitted);
      expect(
        emitted,
        contains('''
final class TypedNoticeSurface extends fw.StatelessWidget {
  const TypedNoticeSurface(
    int count, {
    required Map<String, List<int>?> groups,
    String? message,
    support.Controller controller = _typedNoticeMountDefault3,
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  })  : _restageArgument0 = count,
        _restageArgument1 = groups,
        _restageArgument2 = message,
        _restageArgument3 = controller;
'''),
      );
      expect(
        emitted.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'const support.Controller _typedNoticeMountDefault3 = '
          'const support.Controller();',
        ),
      );
      expect(
        emitted,
        contains('final support.Controller _restageArgument3;'),
      );
      expect(emitted, contains('"count": this._restageArgument0,'));
      expect(emitted, contains('"groups": this._restageArgument1,'));
      expect(emitted, contains('"message": this._restageArgument2,'));
      expect(emitted, isNot(contains('"controller":')));
      expect(
        emitted,
        contains('''
        builder: (context, error) => TypedNotice(
          this._restageArgument0,
          groups: this._restageArgument1,
          message: this._restageArgument2,
          controller: this._restageArgument3,
        ),
'''),
      );
      expect(
        emitted,
        contains('rs.SurfaceScreenUnavailablePolicy.fallback('),
      );
      expect(emitted, isNot(contains('this.unavailable')));
      await _assertGeneratedPartAnalyzes(
        source,
        emitted,
        additionalSources: const {
          'apps_examples|lib/support.dart': supportSource,
        },
      );
    });

    test('encodes plain mount data from the shared field shape', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

final class Address {
  const Address(this.city);
  final String? city;
}

final class Habit {
  const Habit({required this.id, required this.name, required this.address});
  final String id;
  final String name;
  final Address address;
}

typedef HabitAlias = Habit;

final class Controller {
  const Controller();
  String read() => 'value';
}

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class HabitNotice extends StatelessWidget {
  const HabitNotice({
    required this.habit,
    required this.habits,
    required this.byId,
    this.selected,
    this.controller = const Controller(),
    super.key,
  });

  final Habit habit;
  final List<HabitAlias> habits;
  final Map<String, Habit?> byId;
  final Habit? selected;
  final Controller controller;

  @override
  Widget build(BuildContext context) => Text(habit.name);
}
''';
      final inspection = await _inspect(source, className: 'HabitNotice');

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      final compact = emitted.replaceAll(RegExp(r'\s+'), ' ');
      expect(parseString(content: emitted).errors, isEmpty, reason: emitted);
      expect(
        emitted,
        contains('''
  const HabitNoticeSurface({
    required Habit habit,
    required List<HabitAlias> habits,
    required Map<String, Habit?> byId,
    Habit? selected,
    Controller controller = _habitNoticeMountDefault4,
    super.key,
'''),
      );
      expect(
        compact,
        contains(
          '"habit": <String, Object?>{ "id": this._restageArgument0.id, '
          '"name": this._restageArgument0.name, "address": '
          '<String, Object?>{ "city": this._restageArgument0.address.city } },',
        ),
      );
      expect(
        compact,
        contains(
          '"habits": <Object?>[ for (final _restageValue0 in '
          'this._restageArgument1) <String, Object?>{ "id": '
          '_restageValue0.id, "name": _restageValue0.name, "address": '
          '<String, Object?>{"city": _restageValue0.address.city} } ],',
        ),
      );
      expect(
        compact,
        contains(
          '"byId": <String, Object?>{ for (final _restageEntry0 in '
          'this._restageArgument2.entries) _restageEntry0.key: '
          'switch (_restageEntry0.value) { final _restagePresent1? => '
          '<String, Object?>{ "id": _restagePresent1.id, "name": '
          '_restagePresent1.name, "address": <String, Object?>{ "city": '
          '_restagePresent1.address.city } }, null => null } },',
        ),
      );
      expect(
        compact,
        contains(
          '"selected": switch (this._restageArgument3) { final '
          '_restagePresent0? => <String, Object?>{ "id": '
          '_restagePresent0.id, "name": _restagePresent0.name, "address": '
          '<String, Object?>{ "city": _restagePresent0.address.city } }, '
          'null => null },',
        ),
      );
      expect(emitted, isNot(contains('"controller":')));
      expect(
        emitted,
        contains('''
        builder: (context, error) => HabitNotice(
          habit: this._restageArgument0,
          habits: this._restageArgument1,
          byId: this._restageArgument2,
          selected: this._restageArgument3,
          controller: this._restageArgument4,
        ),
'''),
      );
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('mirrors optional positional arguments for an event-free mount',
        () async {
      final source = _screenSource(
        className: 'PositionalNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor: '  const PositionalNotice(this.title, [this.count = 2]);',
        fields: '''
  final String title;
  final int count;
''',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final inspection = await _inspect(
        source,
        className: 'PositionalNotice',
      );

      expect(inspection.issues, isEmpty);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(
        emitted,
        contains('''
  const PositionalNoticeSurface(
    String title, [
    int count = _positionalNoticeMountDefault1,
    Key? key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  ])  : _restageArgument0 = title,
        _restageArgument1 = count,
        super(key: key);
'''),
      );
      expect(
        emitted,
        contains('const int _positionalNoticeMountDefault1 = 2;'),
      );
      expect(emitted, contains('ValueChanged<Never>? onEvent;'));
      expect(
        emitted,
        contains('''
        builder: (context, error) => PositionalNotice(
          this._restageArgument0,
          this._restageArgument1,
        ),
'''),
      );
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('qualifies class-owned defaults without changing library defaults',
        () async {
      final source = _screenSource(
        className: 'DefaultedNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor: '''
  const DefaultedNotice({
    this.count = initialCount,
    this.limit = topLevelLimit,
    super.key,
  });
''',
        fields: '''
  final int count;
  final int limit;
''',
        events: '  static const initialCount = 2;',
        extraDeclarations: '''
const initialCount = 91;
const topLevelLimit = 7;
''',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final inspection = await _inspect(
        source,
        className: 'DefaultedNotice',
      );

      expect(inspection.issues, isEmpty);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(
        emitted,
        contains(
          'const int _defaultedNoticeMountDefault0 = '
          'DefaultedNotice.initialCount;',
        ),
      );
      expect(
        emitted,
        contains(
          'const int _defaultedNoticeMountDefault1 = topLevelLimit;',
        ),
      );
      expect(
        emitted,
        contains('int count = _defaultedNoticeMountDefault0,'),
      );
      expect(
        emitted,
        contains('int limit = _defaultedNoticeMountDefault1,'),
      );
      expect(emitted, isNot(contains('int count = initialCount')));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('qualifies inherited defaults from their declaring class', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

const initialCount = 91;

class DefaultNoticeBase extends StatelessWidget {
  const DefaultNoticeBase({this.count = initialCount, super.key});

  static const initialCount = 2;
  final int count;

  @override
  Widget build(BuildContext context) => Text('\$count');
}

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class InheritedDefaultNotice extends DefaultNoticeBase {
  const InheritedDefaultNotice({super.count, super.key});

  @override
  Widget build(BuildContext context) => Text('\$count');
}
''';
      final inspection = await _inspect(
        source,
        className: 'InheritedDefaultNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      final defaultSource = RegExp(
        'int count = ([^,]+),',
      ).firstMatch(emitted)!.group(1);
      expect(defaultSource, '_inheritedDefaultNoticeMountDefault0');
      expect(
        emitted,
        contains(
          'const int _inheritedDefaultNoticeMountDefault0 = '
          'DefaultNoticeBase.initialCount;',
        ),
      );
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('qualifies defaults inherited from imported declarations', () async {
      const source = r'''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'default_notice_base.dart' as base;

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class ImportedDefaultNotice extends base.ImportedDefaultNoticeBase {
  const ImportedDefaultNotice({super.count, super.key});

  @override
  Widget build(BuildContext context) => Text('$count');
}
''';
      const baseSource = '''
import 'package:flutter/widgets.dart';

abstract class ImportedDefaultNoticeBase extends StatelessWidget {
  const ImportedDefaultNoticeBase({this.count = initialCount, super.key});

  static const initialCount = 2;
  final int count;
}
''';
      const additionalSources = {
        'apps_examples|lib/default_notice_base.dart': baseSource,
      };
      final inspection = await _inspect(
        source,
        className: 'ImportedDefaultNotice',
        additionalSources: additionalSources,
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(
        emitted,
        contains(
          RegExp(
            r'const int _importedDefaultNoticeMountDefault0\s*=\s*'
            r'base\.ImportedDefaultNoticeBase\.initialCount;',
          ),
        ),
      );
      expect(
        emitted,
        contains(
          'int count = _importedDefaultNoticeMountDefault0,',
        ),
      );
      expect(
        emitted,
        contains(RegExp(r'count: this\._restageArgument\d+,')),
      );
      await _assertGeneratedPartAnalyzes(
        source,
        emitted,
        additionalSources: additionalSources,
      );
    });

    test('resolves default expressions through visible element identities',
        () async {
      final scenarios = <({
        String name,
        String source,
        Map<String, String> additionalSources,
        String expected,
        String? absent,
      })>[
        (
          name: 'literal',
          source: _directDefaultSource(
            expression: '2 + 3',
          ),
          additionalSources: const {},
          expected: 'const int _defaultRouteNoticeMountDefault0 = 2 + 3;',
          absent: null,
        ),
        (
          name: 'core type and constant',
          source: _directDefaultSource(
            expression: '.zero',
            type: 'Duration',
          ),
          additionalSources: const {},
          expected: 'const Duration _defaultRouteNoticeMountDefault0 = '
              'Duration.zero;',
          absent: '= .zero;',
        ),
        (
          name: 'same library top level',
          source: _directDefaultSource(
            expression: 'localDefault + 1',
            declarations: 'const localDefault = 2;',
          ),
          additionalSources: const {},
          expected: 'const int _defaultRouteNoticeMountDefault0 = '
              'localDefault + 1;',
          absent: null,
        ),
        (
          name: 'imported top level',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
            declarations: 'const sharedDefault = 91;',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'sharedDefault',
              declarations: 'const sharedDefault = 2;',
            ),
          },
          expected: 'const int _defaultRouteNoticeMountDefault0 = '
              'base.sharedDefault;',
          absent: '= sharedDefault;',
        ),
        (
          name: 'static member',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'DefaultRouteBase.staticDefault',
              members: 'static const staticDefault = 2;',
            ),
          },
          expected: 'const int _defaultRouteNoticeMountDefault0 = '
              'base.DefaultRouteBase.staticDefault;',
          absent: '= DefaultRouteBase.staticDefault;',
        ),
        (
          name: 'enum member',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'RouteTone.calm',
              type: 'RouteTone',
              declarations: 'enum RouteTone { calm, urgent }',
            ),
          },
          expected: 'const base.RouteTone '
              '_defaultRouteNoticeMountDefault0 = base.RouteTone.calm;',
          absent: '= RouteTone.calm;',
        ),
        (
          name: 'constructor',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'const RouteToken(2)',
              type: 'RouteToken',
              declarations: '''
final class RouteToken {
  const RouteToken(this.value);

  final int value;
}
''',
            ),
          },
          expected: 'const base.RouteToken '
              '_defaultRouteNoticeMountDefault0 = '
              'const base.RouteToken(2);',
          absent: 'const RouteToken(2)',
        ),
        (
          name: 'declaring prefix',
          source: _inheritedDefaultSource(
            imports: '''
import 'default_route_base.dart' as base;
import 'default_values.dart' as visible;
''',
            baseType: 'base.DefaultRouteBase',
            declarations: 'const sharedDefault = 91;',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'authored.sharedDefault',
              imports: "import 'default_values.dart' as authored;",
            ),
            'apps_examples|lib/default_values.dart': 'const sharedDefault = 2;',
          },
          expected: 'const int _defaultRouteNoticeMountDefault0 = '
              'visible.sharedDefault;',
          absent: 'authored.sharedDefault',
        ),
        (
          name: 'application barrel',
          source: _inheritedDefaultSource(
            imports: "import 'default_barrel.dart' as app;",
            baseType: 'app.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'authored.sharedDefault',
              imports: "import 'default_values.dart' as authored;",
            ),
            'apps_examples|lib/default_values.dart': 'const sharedDefault = 2;',
            'apps_examples|lib/default_barrel.dart': '''
export 'default_route_base.dart' show DefaultRouteBase;
export 'default_values.dart' show sharedDefault;
''',
          },
          expected: 'const int _defaultRouteNoticeMountDefault0 = '
              'app.sharedDefault;',
          absent: 'authored.sharedDefault',
        ),
        (
          name: 'nested expression',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'sharedDefault + DefaultRouteBase.staticDefault * 2',
              declarations: 'const sharedDefault = 2;',
              members: 'static const staticDefault = 3;',
            ),
          },
          expected: 'const int _defaultRouteNoticeMountDefault0 = '
              'base.sharedDefault + '
              'base.DefaultRouteBase.staticDefault * 2;',
          absent: '= sharedDefault +',
        ),
      ];

      for (final scenario in scenarios) {
        final inspection = await _inspect(
          scenario.source,
          className: 'DefaultRouteNotice',
          additionalSources: scenario.additionalSources,
        );
        final emitted = inspection.contract!.emitReferenceDart();
        final defaultProblem = inspection
            .contract!.input.constructorParams.first.mountDefaultProblem;
        final normalizedEmitted = emitted.replaceAll(RegExp(r'\s+'), ' ');

        expect(inspection.issues, isEmpty, reason: scenario.name);
        expect(
          inspection.contract!.mountOmissionMessage,
          isNull,
          reason: '${scenario.name}: $defaultProblem',
        );
        expect(
          emitted,
          contains('value = _defaultRouteNoticeMountDefault0,'),
          reason: scenario.name,
        );
        expect(
          normalizedEmitted,
          contains(scenario.expected.replaceAll(RegExp(r'\s+'), ' ')),
          reason: scenario.name,
        );
        if (scenario.absent case final absent?) {
          expect(
            normalizedEmitted,
            isNot(contains(absent.replaceAll(RegExp(r'\s+'), ' '))),
            reason: scenario.name,
          );
        }
        await _assertGeneratedPartAnalyzes(
          scenario.source,
          emitted,
          additionalSources: scenario.additionalSources,
        );
      }
    });

    test('resolves static defaults through exact receiver identities',
        () async {
      final aliasedDefaults = <({
        String name,
        String type,
        String expression,
      })>[
        (
          name: 'classValue',
          type: 'int',
          expression: '_ClassValues.constant',
        ),
        (
          name: 'classCall',
          type: 'String Function(String)',
          expression: '_ClassValues.convert',
        ),
        (
          name: 'enumValue',
          type: 'int',
          expression: '_EnumValues.constant',
        ),
        (
          name: 'enumCall',
          type: 'String Function(String)',
          expression: '_EnumValues.convert',
        ),
        (
          name: 'mixinValue',
          type: 'int',
          expression: '_MixinValues.constant',
        ),
        (
          name: 'mixinCall',
          type: 'String Function(String)',
          expression: '_MixinValues.convert',
        ),
        (
          name: 'extensionTypeValue',
          type: 'int',
          expression: '_ExtensionTypeValues.constant',
        ),
      ];
      final directDefaults = [
        for (final value in aliasedDefaults)
          (
            name: value.name,
            type: value.type,
            expression: value.expression.substring(1),
          ),
      ];
      final tokenDefaults = <({
        String name,
        String type,
        String expression,
      })>[
        (name: 'token', type: 'Token', expression: 'const Token(2)'),
        (
          name: 'maker',
          type: 'Token Function(int)',
          expression: 'Token.new',
        ),
      ];
      final scenarios = <({
        String name,
        String source,
        String className,
        Map<String, String> additionalSources,
        List<String> expected,
      })>[
        (
          name: 'direct named extension',
          source: _directDefaultSource(
            expression: 'Values.constant',
            declarations: '''
extension Values on Object {
  static const constant = 2;
}
''',
          ),
          className: 'DefaultRouteNotice',
          additionalSources: const {},
          expected: const [
            '_defaultRouteNoticeMountDefault0 = Values.constant;',
          ],
        ),
        (
          name: 'prefixed named extension',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          className: 'DefaultRouteNotice',
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'Values.constant',
              declarations: '''
extension Values on Object {
  static const constant = 2;
}
''',
            ),
          },
          expected: const [
            '_defaultRouteNoticeMountDefault0 = base.Values.constant;',
          ],
        ),
        (
          name: 'barrel named extension',
          source: _inheritedDefaultSource(
            imports: "import 'default_barrel.dart' as app;",
            baseType: 'app.DefaultRouteBase',
          ),
          className: 'DefaultRouteNotice',
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'Values.constant',
              declarations: '''
extension Values on Object {
  static const constant = 2;
}
''',
            ),
            'apps_examples|lib/default_barrel.dart': '''
export 'default_route_base.dart' show DefaultRouteBase, Values;
''',
          },
          expected: const [
            '_defaultRouteNoticeMountDefault0 = app.Values.constant;',
          ],
        ),
        (
          name: 'same library private extension and member',
          source: _directDefaultSource(
            expression: '_Values._constant',
            declarations: '''
extension _Values on Object {
  static const _constant = 2;
}
''',
          ),
          className: 'DefaultRouteNotice',
          additionalSources: const {},
          expected: const [
            '_defaultRouteNoticeMountDefault0 = _Values._constant;',
          ],
        ),
        (
          name: 'visible aliases to private interface owners',
          source: _receiverScreenSource(
            imports: "import 'static_receiver_base.dart' as base;",
            baseType: 'base.StaticReceiverBase',
            parameterNames: [for (final value in aliasedDefaults) value.name],
          ),
          className: 'StaticReceiverNotice',
          additionalSources: {
            'apps_examples|lib/static_receiver_base.dart': _receiverBaseSource(
              defaults: aliasedDefaults,
              declarations: _privateReceiverDeclarations,
            ),
          },
          expected: [
            for (var index = 0; index < aliasedDefaults.length; index++)
              _staticReceiverExpectation(
                index,
                aliasedDefaults[index].expression.substring(1),
              ),
          ],
        ),
        (
          name: 'direct interface owners',
          source: _receiverScreenSource(
            imports: "import 'static_receiver_base.dart' as base;",
            baseType: 'base.StaticReceiverBase',
            parameterNames: [for (final value in directDefaults) value.name],
          ),
          className: 'StaticReceiverNotice',
          additionalSources: {
            'apps_examples|lib/static_receiver_base.dart': _receiverBaseSource(
              defaults: directDefaults,
              declarations: _publicReceiverDeclarations,
            ),
          },
          expected: [
            for (var index = 0; index < directDefaults.length; index++)
              _staticReceiverExpectation(
                index,
                directDefaults[index].expression,
              ),
          ],
        ),
        (
          name: 'authored constructor alias',
          source: _receiverScreenSource(
            imports: "import 'static_receiver_base.dart' as base;",
            baseType: 'base.StaticReceiverBase',
            parameterNames: [for (final value in tokenDefaults) value.name],
          ),
          className: 'StaticReceiverNotice',
          additionalSources: {
            'apps_examples|lib/static_receiver_base.dart': _receiverBaseSource(
              defaults: tokenDefaults,
              declarations: '''
final class _Token {
  const _Token(this.value);

  final int value;
}
typedef Token = _Token;
''',
            ),
          },
          expected: const [
            '_staticReceiverNoticeMountDefault0 = const base.Token(2);',
            '_staticReceiverNoticeMountDefault1 = base.Token.new;',
          ],
        ),
        (
          name: 'exact dot shorthand owner',
          source: _directDefaultSource(
            expression: '.zero',
            type: 'Duration',
          ),
          className: 'DefaultRouteNotice',
          additionalSources: const {},
          expected: const [
            '_defaultRouteNoticeMountDefault0 = Duration.zero;',
          ],
        ),
      ];

      final omitted = <String>[];
      for (final scenario in scenarios) {
        final inspection = await _inspect(
          scenario.source,
          className: scenario.className,
          additionalSources: scenario.additionalSources,
        );
        final emitted = inspection.contract!.emitReferenceDart();
        final normalizedEmitted = emitted.replaceAll(RegExp(r'\s+'), ' ');

        expect(inspection.issues, isEmpty, reason: scenario.name);
        if (inspection.contract!.mountOmissionMessage case final problem?) {
          omitted.add('${scenario.name}: $problem');
          continue;
        }
        for (final expected in scenario.expected) {
          expect(normalizedEmitted, contains(expected), reason: scenario.name);
        }
        await _assertGeneratedPartAnalyzes(
          scenario.source,
          emitted,
          additionalSources: scenario.additionalSources,
        );
      }
      expect(omitted, isEmpty);
    });

    test('refuses static defaults without exact receiver identities', () async {
      final scenarios = <({
        String name,
        String source,
        Map<String, String> additionalSources,
      })>[
        (
          name: 'hidden named extension',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' show DefaultRouteBase;",
            baseType: 'DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'Values.constant',
              declarations: '''
extension Values on Object {
  static const constant = 2;
}
''',
            ),
          },
        ),
        (
          name: 'hidden alias',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' show DefaultRouteBase;",
            baseType: 'DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: '_Values.constant',
              declarations: '''
class _Values {
  static const constant = 2;
}
typedef Values = _Values;
''',
            ),
          },
        ),
        (
          name: 'deferred alias',
          source: _inheritedDefaultSource(
            imports: '''
import 'default_route_base.dart' show DefaultRouteBase;
import 'default_route_base.dart' deferred as delayed show Values;
''',
            baseType: 'DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: '_Values.constant',
              declarations: '''
class _Values {
  static const constant = 2;
}
typedef Values = _Values;
''',
            ),
          },
        ),
        (
          name: 'external private member',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'Values._constant',
              declarations: '''
class Values {
  static const _constant = 2;
}
''',
            ),
          },
        ),
        (
          name: 'wrong alias owner',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: '_Wanted.constant',
              declarations: '''
class _Wanted {
  static const constant = 2;
}
class Other {}
typedef Values = Other;
''',
            ),
          },
        ),
        (
          name: 'local alias shadow',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart';",
            baseType: 'DefaultRouteBase',
            declarations: 'class Values {}',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: '_Values.constant',
              declarations: '''
class _Values {
  static const constant = 2;
}
typedef Values = _Values;
''',
            ),
          },
        ),
        (
          name: 'private authored constructor owner',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'const _Token(2)',
              type: 'Token',
              declarations: '''
final class _Token {
  const _Token(this.value);

  final int value;
}
typedef Token = _Token;
''',
            ),
          },
        ),
        (
          name: 'private contextual dot shorthand owner',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: '.calm',
              type: 'Tone',
              declarations: '''
enum _Tone { calm }
typedef Tone = _Tone;
''',
            ),
          },
        ),
      ];

      for (final scenario in scenarios) {
        final inspection = await _inspect(
          scenario.source,
          className: 'DefaultRouteNotice',
          additionalSources: scenario.additionalSources,
        );
        final emitted = inspection.contract!.emitReferenceDart();

        expect(inspection.issues, isEmpty, reason: scenario.name);
        expect(
          inspection.contract!.mountOmissionMessage,
          contains('default for "value" has no visible spelling'),
          reason: scenario.name,
        );
        expect(
          emitted,
          isNot(contains('class DefaultRouteNoticeSurface')),
          reason: scenario.name,
        );
        await _assertGeneratedPartAnalyzes(
          scenario.source,
          emitted,
          additionalSources: scenario.additionalSources,
        );
      }

      const anonymousSource = '''
extension on Object {
  static const constant = 2;
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      String? anonymousSpelling;
      await testBuilder(
        _ScreenContractProbeBuilder((library, _) async {
          final member = library.extensions.single.getField('constant')!;
          anonymousSpelling =
              OwningLibraryNamespace(library).staticMemberName(member);
        }),
        const {
          'apps_examples|lib/maintenance_notice.dart': anonymousSource,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
      );
      expect(anonymousSpelling, isNull);
    });

    test('spells inherited mount types through exact visible aliases',
        () async {
      const baseId = 'apps_examples|lib/alias_type_base.dart';
      const baseSource = '''
import 'package:flutter/widgets.dart';

class _Defaults {
  const _Defaults();

  static const value = _Defaults();
}
typedef Defaults = _Defaults;

abstract class AliasTypeBase extends StatelessWidget {
  const AliasTypeBase({this.value = _Defaults.value, super.key});

  final _Defaults value;
}
''';
      final routeScenarios = <({
        String name,
        String imports,
        String baseType,
        String prefix,
        Map<String, String> sources,
      })>[
        (
          name: 'unprefixed',
          imports:
              "import 'alias_type_base.dart' show AliasTypeBase, Defaults;",
          baseType: 'AliasTypeBase',
          prefix: '',
          sources: const {baseId: baseSource},
        ),
        (
          name: 'prefixed',
          imports: "import 'alias_type_base.dart' as base;",
          baseType: 'base.AliasTypeBase',
          prefix: 'base.',
          sources: const {baseId: baseSource},
        ),
        (
          name: 'barrel',
          imports: "import 'alias_type_barrel.dart' as app;",
          baseType: 'app.AliasTypeBase',
          prefix: 'app.',
          sources: const {
            baseId: baseSource,
            'apps_examples|lib/alias_type_barrel.dart':
                "export 'alias_type_base.dart' show AliasTypeBase, Defaults;",
          },
        ),
      ];

      final omissions = <String>[];
      for (final scenario in routeScenarios) {
        final source = _aliasTypeScreenSource(
          imports: scenario.imports,
          baseType: scenario.baseType,
          className: 'AliasTypeNotice',
          parameters: 'super.value, super.key',
        );
        final inspection = await _inspect(
          source,
          className: 'AliasTypeNotice',
          additionalSources: scenario.sources,
        );
        final emitted = inspection.contract!.emitReferenceDart();
        final prefix = scenario.prefix;

        expect(inspection.issues, isEmpty, reason: scenario.name);
        if (inspection.contract!.mountOmissionMessage case final problem?) {
          omissions.add('${scenario.name}: $problem');
        } else {
          expect(
            emitted,
            contains(
              'const ${prefix}Defaults _aliasTypeNoticeMountDefault0 = '
              '${prefix}Defaults.value;',
            ),
            reason: scenario.name,
          );
          expect(
            emitted,
            contains(
              '${prefix}Defaults value = _aliasTypeNoticeMountDefault0,',
            ),
            reason: scenario.name,
          );
        }
        await _assertGeneratedPartAnalyzes(
          source,
          emitted,
          additionalSources: scenario.sources,
        );
      }

      const shapeBaseId = 'apps_examples|lib/alias_shape_base.dart';
      const shapeBaseSource = '''
import 'package:flutter/widgets.dart';

class _Exact {
  const _Exact();

  static const value = _Exact();
}
typedef Exact = _Exact;

class _Box<T> {
  const _Box();
}
typedef Box<T> = _Box<T>;

class _Closed<T> {
  const _Closed();
}
typedef Closed<T> = _Closed<int>;

class _Defaulted<T> {
  const _Defaulted();
}
typedef Defaulted<T extends num> = _Defaulted<T>;

class _Reordered<A, B> {
  const _Reordered();
}
typedef Reordered<A, B> = _Reordered<B, A>;

class _Repeated<A, B> {
  const _Repeated();
}
typedef Repeated<T> = _Repeated<T, T>;

class _FunctionValue {}
typedef Callback = _FunctionValue Function(_FunctionValue);

class _RecordValue {}
typedef RecordShape = (_RecordValue, {_RecordValue value});

typedef _PrivateCount = int;

abstract class AliasShapeBase extends StatelessWidget {
  const AliasShapeBase({
    this.exact = _Exact.value,
    required this.box,
    required this.closed,
    required this.defaulted,
    required this.reordered,
    required this.repeated,
    required this.nested,
    required this.record,
    required this.callback,
    required this.recordShape,
    required this.nullable,
    required this.genericCallback,
    required this.count,
    super.key,
  });

  final _Exact exact;
  final _Box<int> box;
  final _Closed<int> closed;
  final _Defaulted<num> defaulted;
  final _Reordered<String, int> reordered;
  final _Repeated<int, int> repeated;
  final List<_Exact> nested;
  final (_Exact, {List<_Exact> values}) record;
  final _FunctionValue Function(_FunctionValue) callback;
  final (_RecordValue, {_RecordValue value}) recordShape;
  final _Exact? nullable;
  final T? Function<T>(T?) genericCallback;
  final _PrivateCount count;
}
''';
      final shapeSource = _aliasTypeScreenSource(
        imports: "import 'alias_shape_base.dart' as shape;",
        baseType: 'shape.AliasShapeBase',
        className: 'AliasShapeNotice',
        parameters: '''
super.exact,
required super.box,
required super.closed,
required super.defaulted,
required super.reordered,
required super.repeated,
required super.nested,
required super.record,
required super.callback,
required super.recordShape,
required super.nullable,
required super.genericCallback,
required super.count,
super.key
''',
      );
      final shapeSources = {shapeBaseId: shapeBaseSource};
      final shapeInspection = await _inspect(
        shapeSource,
        className: 'AliasShapeNotice',
        additionalSources: shapeSources,
      );
      final shapeOutput = shapeInspection.contract!.emitReferenceDart();
      final normalizedShapeOutput = shapeOutput.replaceAll(RegExp(r'\s+'), ' ');
      const exactDefaultSource =
          'const shape.Exact _aliasShapeNoticeMountDefault0 = '
          'shape.Exact.value;';

      expect(shapeInspection.issues, isEmpty);
      final shapeTypes = {
        for (final parameter
            in shapeInspection.contract!.input.constructorParams)
          if (!parameter.forwardsFlutterKey) parameter.name: parameter.typeCode,
      };
      if (shapeInspection.contract!.mountOmissionMessage case final problem?) {
        omissions.add('shapes: $problem');
      } else {
        for (final expected in const [
          exactDefaultSource,
          'shape.Exact exact = _aliasShapeNoticeMountDefault0,',
          'required shape.Box<int> box,',
          'required shape.Closed<dynamic> closed,',
          'required shape.Defaulted<num> defaulted,',
          'required shape.Reordered<int, String> reordered,',
          'required shape.Repeated<int> repeated,',
          'required List<shape.Exact> nested,',
          'required (shape.Exact, {List<shape.Exact> values}) record,',
          'required shape.Callback callback,',
          'required shape.RecordShape recordShape,',
          'required shape.Exact? nullable,',
          'required T? Function<T>(T?) genericCallback,',
          'required int count,',
        ]) {
          expect(normalizedShapeOutput, contains(expected), reason: expected);
        }
      }
      await _assertGeneratedPartAnalyzes(
        shapeSource,
        shapeOutput,
        additionalSources: shapeSources,
      );
      expect(
        [omissions, shapeTypes],
        const [
          <String>[],
          <String, String?>{
            'exact': 'shape.Exact',
            'box': 'shape.Box<int>',
            'closed': 'shape.Closed<dynamic>',
            'defaulted': 'shape.Defaulted<num>',
            'reordered': 'shape.Reordered<int, String>',
            'repeated': 'shape.Repeated<int>',
            'nested': 'List<shape.Exact>',
            'record': '(shape.Exact, {List<shape.Exact> values})',
            'callback': 'shape.Callback',
            'recordShape': 'shape.RecordShape',
            'nullable': 'shape.Exact?',
            'genericCallback': 'T? Function<T>(T?)',
            'count': 'int',
          },
        ],
      );
    });

    test('refuses inherited mount types without an exact alias proof',
        () async {
      const baseId = 'apps_examples|lib/alias_refusal_base.dart';
      final scenarios = <({
        String name,
        String imports,
        String baseType,
        String declarations,
        String type,
        String localDeclarations,
      })>[
        (
          name: 'hidden',
          imports:
              "import 'alias_refusal_base.dart' as base show AliasRefusalBase;",
          baseType: 'base.AliasRefusalBase',
          declarations: '''
class _Hidden {}
typedef Visible = _Hidden;
''',
          type: '_Hidden',
          localDeclarations: '',
        ),
        (
          name: 'deferred',
          imports: '''
import 'alias_refusal_base.dart' show AliasRefusalBase;
import 'alias_refusal_base.dart' deferred as delayed show Visible;
''',
          baseType: 'AliasRefusalBase',
          declarations: '''
class _Hidden {}
typedef Visible = _Hidden;
''',
          type: '_Hidden',
          localDeclarations: '',
        ),
        (
          name: 'shadowed',
          imports: "import 'alias_refusal_base.dart' "
              'show AliasRefusalBase, Visible;',
          baseType: 'AliasRefusalBase',
          declarations: '''
class _Hidden {}
typedef Visible = _Hidden;
''',
          type: '_Hidden',
          localDeclarations: 'class Visible {}',
        ),
        (
          name: 'wrong target',
          imports: "import 'alias_refusal_base.dart' as base;",
          baseType: 'base.AliasRefusalBase',
          declarations: '''
class _Hidden {}
class Other {}
typedef Visible = Other;
''',
          type: '_Hidden',
          localDeclarations: '',
        ),
        (
          name: 'dependent bound',
          imports: "import 'alias_refusal_base.dart' as base;",
          baseType: 'base.AliasRefusalBase',
          declarations: '''
class _Bounded<T> {}
typedef Visible<T extends num> = _Bounded<T>;
''',
          type: '_Bounded<String>',
          localDeclarations: '',
        ),
        (
          name: 'nullable preimage',
          imports: "import 'alias_refusal_base.dart' as base;",
          baseType: 'base.AliasRefusalBase',
          declarations: '''
class _Nullable<T> {}
typedef Visible<T> = _Nullable<T?>;
''',
          type: '_Nullable<int?>',
          localDeclarations: '',
        ),
        (
          name: 'generic binder',
          imports: "import 'alias_refusal_base.dart' as base;",
          baseType: 'base.AliasRefusalBase',
          declarations: '''
class _BinderValue {}
typedef Visible<T> = T Function<U>(U, _BinderValue);
''',
          type: 'int Function<V>(V, _BinderValue)',
          localDeclarations: '',
        ),
        (
          name: 'repeated mismatch',
          imports: "import 'alias_refusal_base.dart' as base;",
          baseType: 'base.AliasRefusalBase',
          declarations: '''
class _Pair<A, B> {}
typedef Visible<T> = _Pair<T, T>;
''',
          type: '_Pair<int, String>',
          localDeclarations: '',
        ),
      ];

      for (final scenario in scenarios) {
        final baseSource = _aliasRefusalBaseSource(
          declarations: scenario.declarations,
          type: scenario.type,
        );
        final source = _aliasTypeScreenSource(
          imports: scenario.imports,
          baseType: scenario.baseType,
          className: 'AliasRefusalNotice',
          parameters: 'required super.value, super.key',
          declarations: scenario.localDeclarations,
        );
        final additionalSources = {baseId: baseSource};
        final inspection = await _inspect(
          source,
          className: 'AliasRefusalNotice',
          additionalSources: additionalSources,
        );
        final emitted = inspection.contract!.emitReferenceDart();

        expect(inspection.issues, isEmpty, reason: scenario.name);
        expect(
          inspection.contract!.mountOmissionMessage,
          contains('"value" has no reusable Dart type spelling'),
          reason: scenario.name,
        );
        expect(
          emitted,
          isNot(contains('class AliasRefusalNoticeSurface')),
          reason: scenario.name,
        );
        await _assertGeneratedPartAnalyzes(
          source,
          emitted,
          additionalSources: additionalSources,
        );
      }
    });

    test('omits mounts when default references have no visible spelling',
        () async {
      final scenarios = <({
        String name,
        String source,
        Map<String, String> additionalSources,
      })>[
        (
          name: 'private top level',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: '_hiddenDefault',
              declarations: 'const _hiddenDefault = 2;',
            ),
          },
        ),
        (
          name: 'hidden top level',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base "
                'show DefaultRouteBase;',
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'hiddenDefault',
              declarations: 'const hiddenDefault = 2;',
            ),
          },
        ),
        (
          name: 'private static member',
          source: _inheritedDefaultSource(
            imports: "import 'default_route_base.dart' as base;",
            baseType: 'base.DefaultRouteBase',
          ),
          additionalSources: {
            'apps_examples|lib/default_route_base.dart': _defaultBaseSource(
              expression: 'DefaultRouteBase._hiddenDefault',
              members: 'static const _hiddenDefault = 2;',
            ),
          },
        ),
      ];

      for (final scenario in scenarios) {
        final inspection = await _inspect(
          scenario.source,
          className: 'DefaultRouteNotice',
          additionalSources: scenario.additionalSources,
        );
        final emitted = inspection.contract!.emitReferenceDart();

        expect(inspection.issues, isEmpty, reason: scenario.name);
        expect(
          inspection.contract!.mountOmissionMessage,
          contains('default for "value" has no visible spelling'),
          reason: scenario.name,
        );
        expect(
          emitted,
          isNot(contains('class DefaultRouteNoticeSurface')),
          reason: scenario.name,
        );
        expect(
          emitted,
          contains('SurfaceScreenRef<Never>.generated'),
          reason: scenario.name,
        );
        await _assertGeneratedPartAnalyzes(
          scenario.source,
          emitted,
          additionalSources: scenario.additionalSources,
        );
      }
    });

    test('binds top-level defaults outside generated mount scopes', () async {
      for (final name in const [
        'onEvent',
        'resolver',
        'onUnavailable',
        'loadingBuilder',
        '_restageArgument0',
        'localValue',
      ]) {
        final source = _directDefaultSource(
          expression: name,
          declarations: 'const $name = 7;',
        );
        final inspection = await _inspect(
          source,
          className: 'DefaultRouteNotice',
        );
        final emitted = inspection.contract!.emitReferenceDart();

        expect(inspection.issues, isEmpty, reason: name);
        expect(
          inspection.contract!.mountOmissionMessage,
          isNull,
          reason: name,
        );
        expect(
          emitted,
          contains(
            'const int _defaultRouteNoticeMountDefault0 = $name;',
          ),
          reason: name,
        );
        expect(
          emitted,
          contains('int value = _defaultRouteNoticeMountDefault0,'),
          reason: name,
        );
        expect(
          emitted,
          isNot(contains('int value = $name,')),
          reason: name,
        );
        await _assertGeneratedPartAnalyzes(source, emitted);
      }
    });

    test('types default bindings and preserves constructor order', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

typedef Labeler = String Function(String);

String labeler(String value) => value;

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class TypedDefaultNotice extends StatelessWidget {
  const TypedDefaultNotice({
    this.ratio = 0,
    this.labels = const [],
    this.counts = const {},
    this.tags = const {},
    this.label = labeler,
    this.note = null,
    super.key,
  });

  final double ratio;
  final List<String> labels;
  final Map<String, int> counts;
  final Set<String> tags;
  final Labeler label;
  final String? note;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(
        source,
        className: 'TypedDefaultNotice',
      );
      final emitted = inspection.contract!.emitReferenceDart();
      final bindings = [
        'const double _typedDefaultNoticeMountDefault0 = 0;',
        'const List<String> _typedDefaultNoticeMountDefault1 = const [];',
        'const Map<String, int> _typedDefaultNoticeMountDefault2 = const {};',
        'const Set<String> _typedDefaultNoticeMountDefault3 = const {};',
        'const Labeler _typedDefaultNoticeMountDefault4 = labeler;',
        'const String? _typedDefaultNoticeMountDefault5 = null;',
      ];

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      expect(
        inspection.contract!.input.constructorParams
            .take(6)
            .map((parameter) => parameter.defaultValueCode),
        orderedEquals([
          '0',
          'const []',
          'const {}',
          'const {}',
          'labeler',
          'null',
        ]),
      );
      final bindingNames = inspection.contract!.generatedTopLevelSymbols
          .where((name) => name.contains('MountDefault'))
          .toSet();
      final captureNames = {
        'onEvent',
        'resolver',
        'onUnavailable',
        'loadingBuilder',
        for (final parameter in inspection.contract!.input.constructorParams)
          parameter.name,
        for (var index = 0;
            index < inspection.contract!.input.constructorParams.length;
            index++)
          '_restageArgument$index',
      };
      expect(bindingNames, everyElement(startsWith('_')));
      expect(bindingNames.intersection(captureNames), isEmpty);
      var previous = -1;
      for (final binding in bindings) {
        final offset = emitted.indexOf(binding);
        expect(offset, greaterThan(previous), reason: binding);
        previous = offset;
      }
      expect(
        previous,
        lessThan(emitted.indexOf('final class TypedDefaultNoticeSurface')),
      );
      for (var index = 0; index < bindings.length; index++) {
        expect(
          emitted,
          contains('= _typedDefaultNoticeMountDefault$index,'),
          reason: bindings[index],
        );
      }
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('refuses occupied binding names and replaces exact warm bindings',
        () async {
      final collisionSource = _screenSource(
        className: 'BindingCollisionNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor:
            '  const BindingCollisionNotice({this.value = 1, super.key});',
        fields: '  final int value;',
        extraDeclarations: 'const _bindingCollisionNoticeMountDefault0 = 9;',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final collision = await _inspect(
        collisionSource,
        className: 'BindingCollisionNotice',
      );
      final collisionOutput = collision.contract!.emitReferenceDart();

      expect(collision.issues, isEmpty);
      expect(
        collision.contract!.mountOmissionMessage,
        contains('_bindingCollisionNoticeMountDefault0 is already visible'),
      );
      expect(
        collisionOutput,
        isNot(contains('class BindingCollisionNoticeSurface')),
      );

      final warmSource = _screenSource(
        className: 'WarmBindingNotice',
        annotation: "@Screen(id: 'warm_binding', surface: Surface.general)",
        constructor: '  const WarmBindingNotice({this.value = 1, super.key});',
        fields: '  final int value;',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final warm = await _inspect(
        warmSource,
        className: 'WarmBindingNotice',
        slug: 'warm_binding',
        additionalSources: const {
          'apps_examples|lib/restage.generated/maintenance_notice.restage.g.dart':
              '''
part of '../maintenance_notice.dart';

const int _warmBindingNoticeMountDefault0 = 1;
final class WarmBindingNoticeSurface {}
''',
        },
      );
      final warmOutput = warm.contract!.emitReferenceDart();

      expect(warm.issues, isEmpty);
      expect(warm.contract!.mountOmissionMessage, isNull);
      expect(
        warm.contract!.generatedTopLevelSymbols,
        containsAll({
          '_warmBindingNoticeMountDefault0',
          'WarmBindingNoticeSurface',
        }),
      );
      expect(
        warmOutput,
        contains('const int _warmBindingNoticeMountDefault0 = 1;'),
      );
      await _assertGeneratedPartAnalyzes(warmSource, warmOutput);
    });

    test('refuses the mount for a required non-nullable typed key', () async {
      final source = _screenSource(
        className: 'PinnedKeyNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor: '''
  const PinnedKeyNotice({required Key super.key});
''',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final inspection = await _inspect(source, className: 'PinnedKeyNotice');

      expect(inspection.issues, isEmpty);
      expect(
        inspection.contract!.mountOmissionMessage,
        contains('required non-nullable key'),
      );
    });

    test('names the host data a screen keeps when its mount is omitted',
        () async {
      final source = _screenSource(
        className: 'HabitBoard',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor: '''
  const HabitBoard({required this.rows, super.key});
''',
        fields: '  final List<String> rows;',
        extraDeclarations: 'final class HabitBoardSurface {}',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final inspection = await _inspect(source, className: 'HabitBoard');

      expect(inspection.issues, isEmpty);
      expect(
        inspection.contract!.mountOmissionMessage,
        contains('declares host-supplied inputs'),
      );
      expect(
        inspection.contract!.mountOmissionMessage,
        contains('already exists'),
      );
    });

    test('preserves key requiredness on the generated mount', () async {
      final requiredSource = _screenSource(
        className: 'RequiredKeyNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor: '''
  const RequiredKeyNotice({required super.key, required this.label});
''',
        fields: '  final String label;',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final requiredInspection = await _inspect(
        requiredSource,
        className: 'RequiredKeyNotice',
      );

      expect(requiredInspection.issues, isEmpty);
      final requiredOutput = requiredInspection.contract!.emitReferenceDart();
      expect(requiredOutput, contains('required super.key,'));
      expect(requiredOutput, contains('key: null,'));
      expect(requiredOutput, contains('label: this.'));
      await _assertGeneratedPartAnalyzes(requiredSource, requiredOutput);

      final optionalSource = _screenSource(
        className: 'OptionalKeyNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final optionalInspection = await _inspect(
        optionalSource,
        className: 'OptionalKeyNotice',
      );
      final optionalOutput = optionalInspection.contract!.emitReferenceDart();
      expect(optionalOutput, contains('super.key,'));
      expect(optionalOutput, isNot(contains('key: key,')));
      await _assertGeneratedPartAnalyzes(optionalSource, optionalOutput);
    });

    test('never gives the fallback widget the mount own key', () async {
      final optionalSource = _screenSource(
        className: 'OptionalKeyNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor: '  const OptionalKeyNotice({this.label = 1, super.key});',
        fields: '  final int label;',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final optional = await _inspect(
        optionalSource,
        className: 'OptionalKeyNotice',
      );
      final optionalOutput = optional.contract!.emitReferenceDart();

      expect(optional.issues, isEmpty);
      expect(
        optionalOutput,
        contains('''
        builder: (context, error) => OptionalKeyNotice(
          label: this._restageArgument0,
        ),
'''),
      );
      await _assertGeneratedPartAnalyzes(optionalSource, optionalOutput);

      final requiredSource = _screenSource(
        className: 'RequiredKeyNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor: '  const RequiredKeyNotice({required super.key, '
            'required this.label});',
        fields: '  final String label;',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final required = await _inspect(
        requiredSource,
        className: 'RequiredKeyNotice',
      );
      final requiredOutput = required.contract!.emitReferenceDart();

      expect(required.issues, isEmpty);
      expect(requiredOutput, contains('required super.key,'));
      // A required key cannot be dropped from the call, so it is passed as
      // absent rather than as the mount's own key.
      expect(requiredOutput, contains('key: null,'));
      expect(requiredOutput, isNot(contains('key: key,')));
      await _assertGeneratedPartAnalyzes(requiredSource, requiredOutput);
    });

    test('passes a positional key position as absent to the fallback widget',
        () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class PositionalKeyNotice extends StatelessWidget {
  const PositionalKeyNotice(this.title, [Key? key]) : super(key: key);

  final String title;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(
        source,
        className: 'PositionalKeyNotice',
      );
      final emitted = inspection.contract!.emitReferenceDart();

      expect(inspection.issues, isEmpty);
      expect(
        emitted,
        contains('''
        builder: (context, error) => PositionalKeyNotice(
          this._restageArgument0,
          null,
        ),
'''),
      );
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('routes a required concrete key to the fallback widget alone',
        () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class ConcreteKeyNotice extends StatelessWidget {
  const ConcreteKeyNotice({required ValueKey<String> key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(source, className: 'ConcreteKeyNotice');
      final emitted = inspection.contract!.emitReferenceDart();

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      expect(emitted, contains('required ValueKey<String> key,'));
      expect(emitted, contains('key: key,'));
      // The authored key identifies the screen, so the mount does not also
      // take it: one Key on two live elements breaks a GlobalKey.
      expect(emitted, isNot(contains('super(key:')));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('stores legal member-shaped arguments in private slots', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class MemberNameNotice extends StatelessWidget {
  const MemberNameNotice({
    required String build,
    required String runtimeType,
    required String label,
    super.key,
  })  : _buildValue = build,
        _runtimeTypeValue = runtimeType,
        _label = label;

  final String _buildValue;
  final String _runtimeTypeValue;
  final String _label;

  @override
  Widget build(BuildContext context) => Text(
        '\$_buildValue:\$_runtimeTypeValue:\$_label',
      );
}
''';
      final inspection = await _inspect(
        source,
        className: 'MemberNameNotice',
      );

      expect(inspection.issues, isEmpty);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('required String build,'));
      expect(emitted, contains('required String runtimeType,'));
      expect(emitted, contains('required String label,'));
      expect(emitted, isNot(contains('final String build;')));
      expect(emitted, isNot(contains('final String runtimeType;')));
      expect(emitted, contains(RegExp(r'build: this\._[A-Za-z0-9_]+,')));
      expect(
        emitted,
        contains(RegExp(r'runtimeType: this\._[A-Za-z0-9_]+,')),
      );
      expect(emitted, contains(RegExp(r'label: this\._[A-Za-z0-9_]+,')));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('passes scalar and collection values unchanged to the SDK', () async {
      final source = _screenSource(
        className: 'CollectionNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        constructor: '''
  const CollectionNotice({
    required this.count,
    required this.values,
    super.key,
  });
''',
        fields: '''
  final int count;
  final Map<String, List<int>> values;
''',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final inspection = await _inspect(
        source,
        className: 'CollectionNotice',
      );

      expect(inspection.issues, isEmpty);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains(RegExp(r'"count": this\._[A-Za-z0-9_]+,')));
      expect(emitted, contains(RegExp(r'"values": this\._[A-Za-z0-9_]+,')));
      expect(emitted, isNot(contains('List<Object?>.unmodifiable')));
      expect(emitted, isNot(contains('Map<String, Object?>.unmodifiable')));
      expect(emitted, isNot(contains('.map(')));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('treats import prefixes and warm declarations as mount names',
        () async {
      final prefixSource = _screenSource(
        className: 'PrefixReserved',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        import: '''
import 'package:restage/restage.dart';
import 'support.dart' as PrefixReservedSurface;
''',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final prefixInspection = await _inspect(
        prefixSource,
        className: 'PrefixReserved',
        additionalSources: const {
          'apps_examples|lib/support.dart': 'const supportValue = 1;',
        },
      );
      expect(prefixInspection.issues, isEmpty);
      expect(prefixInspection.contract!.mountOmissionMessage, isNotNull);
      final prefixOutput = prefixInspection.contract!.emitReferenceDart();
      expect(prefixOutput, contains('SurfaceScreenRef<Never>.generated'));
      expect(prefixOutput, isNot(contains('class PrefixReservedSurface')));
      await _assertGeneratedPartAnalyzes(
        prefixSource,
        prefixOutput,
        additionalSources: const {
          'apps_examples|lib/support.dart': 'const supportValue = 1;',
        },
      );

      final warmSource = _screenSource(
        className: 'WarmReserved',
        annotation: "@Screen(id: 'warm_reserved', surface: Surface.general)",
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final warmInspection = await _inspect(
        warmSource,
        className: 'WarmReserved',
        slug: 'warm_reserved',
        additionalSources: const {
          'apps_examples|lib/restage.generated/maintenance_notice.restage.g.dart':
              '''
part of '../maintenance_notice.dart';

final WarmReservedSurface = Object();
''',
        },
      );
      expect(warmInspection.issues, isEmpty);
      expect(warmInspection.contract!.mountOmissionMessage, isNull);
      expect(
        warmInspection.contract!.emitReferenceDart(),
        contains('class WarmReservedSurface'),
      );

      final availableSource = _screenSource(
        className: 'PrefixAvailable',
        annotation: "@Screen(id: 'available', surface: Surface.general)",
        import: '''
import 'package:restage/restage.dart';
import 'support.dart' as SupportValues;
''',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final availableInspection = await _inspect(
        availableSource,
        className: 'PrefixAvailable',
        slug: 'available',
        additionalSources: const {
          'apps_examples|lib/support.dart': 'const supportValue = 1;',
        },
      );
      expect(availableInspection.issues, isEmpty);
      expect(availableInspection.contract!.mountOmissionMessage, isNull);
      final availableOutput = availableInspection.contract!.emitReferenceDart();
      expect(availableOutput, contains('class PrefixAvailableSurface'));
      await _assertGeneratedPartAnalyzes(
        availableSource,
        availableOutput,
        additionalSources: const {
          'apps_examples|lib/support.dart': 'const supportValue = 1;',
        },
      );
    });

    test('uses only SDK spellings that resolve to the SDK origin', () async {
      const shadow = '''
final class RestageScreen {
  const RestageScreen();
}
''';
      final unavailableSource = _screenSource(
        className: 'ShadowedSdkNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        extraDeclarations: shadow,
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final unavailableInspection = await _inspect(
        unavailableSource,
        className: 'ShadowedSdkNotice',
      );

      expect(unavailableInspection.issues, isEmpty);
      expect(unavailableInspection.contract!.mountOmissionMessage, isNotNull);
      final unavailableOutput =
          unavailableInspection.contract!.emitReferenceDart();
      expect(unavailableOutput, contains('SurfaceScreenRef<Never>.generated'));
      expect(unavailableOutput, isNot(contains('ShadowedSdkNoticeSurface')));
      await _assertGeneratedPartAnalyzes(unavailableSource, unavailableOutput);

      final qualifiedSource = _screenSource(
        className: 'QualifiedSdkNotice',
        annotation:
            "@rs.Screen(id: 'maintenance_notice', surface: rs.Surface.general)",
        import: '''
import 'package:restage/restage.dart';
import 'package:restage/restage.dart' as rs;
''',
        extraDeclarations: shadow,
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final qualifiedInspection = await _inspect(
        qualifiedSource,
        className: 'QualifiedSdkNotice',
      );
      expect(qualifiedInspection.issues, isEmpty);
      expect(qualifiedInspection.contract!.mountOmissionMessage, isNull);
      final qualifiedOutput = qualifiedInspection.contract!.emitReferenceDart();
      expect(qualifiedOutput, contains('return rs.RestageScreen<Never>('));
      await _assertGeneratedPartAnalyzes(qualifiedSource, qualifiedOutput);
    });

    test('emits mounts for callable abstract factory screens', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
abstract class RedirectedNotice extends StatelessWidget {
  const RedirectedNotice._({super.key});
  const factory RedirectedNotice({Key? key}) = _RedirectedNotice;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final class _RedirectedNotice extends RedirectedNotice {
  const _RedirectedNotice({super.key}) : super._();
}
''';
      final inspection = await _inspect(
        source,
        className: 'RedirectedNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('class RedirectedNoticeSurface'));
      expect(emitted, isNot(contains('key: key,')));
      await _assertGeneratedPartAnalyzes(source, emitted);

      const uncallableSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
abstract class UncallableNotice extends StatelessWidget {
  const UncallableNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final uncallableInspection = await _inspect(
        uncallableSource,
        className: 'UncallableNotice',
      );
      expect(uncallableInspection.issues, isEmpty);
      expect(uncallableInspection.contract!.mountOmissionMessage, isNotNull);
      expect(
        uncallableInspection.contract!.emitReferenceDart(),
        isNot(contains('class UncallableNoticeSurface')),
      );
    });

    test('omits factories without a resolved generative target', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
abstract class FactoryBodyNotice extends StatelessWidget {
  factory FactoryBodyNotice({Key? key}) => _FactoryBodyNotice(key: key);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final class _FactoryBodyNotice extends StatelessWidget
    implements FactoryBodyNotice {
  const _FactoryBodyNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(
        source,
        className: 'FactoryBodyNotice',
      );
      final emitted = inspection.contract!.emitReferenceDart();
      const expectedMessage =
          'Generated screen mount FactoryBodyNoticeSurface was omitted '
          'because FactoryBodyNotice has a non-redirecting unnamed factory.';

      expect(inspection.issues, isEmpty);
      expect(
        [
          inspection.contract!.mountOmissionMessage,
          emitted.contains('class FactoryBodyNoticeSurface'),
          emitted.contains('super(key: key)'),
          RegExp(r'key: this\._restageArgument\d+,').hasMatch(emitted),
        ],
        [expectedMessage, false, false, false],
      );
      expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
    });

    test('admits only reproducible Flutter key values', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'direct_named_key', surface: Surface.general)
final class DirectNamedKeyRoute extends StatelessWidget {
  const DirectNamedKeyRoute({Key? widgetKey}) : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'direct_positional_key', surface: Surface.general)
final class DirectPositionalKeyRoute extends StatelessWidget {
  const DirectPositionalKeyRoute(Key? widgetKey) : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'field_formal_key', surface: Surface.general)
final class FieldFormalKeyRoute extends StatelessWidget {
  const FieldFormalKeyRoute(this.widgetKey) : super(key: widgetKey);

  final Key? widgetKey;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'super_formal_key', surface: Surface.general)
final class SuperFormalKeyRoute extends StatelessWidget {
  const SuperFormalKeyRoute({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'parenthesized_key', surface: Surface.general)
final class ParenthesizedKeyRoute extends StatelessWidget {
  const ParenthesizedKeyRoute({Key? widgetKey})
      : super(key: (((widgetKey))));

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'factory_key', surface: Surface.general)
final class FactoryKeyRoute extends StatelessWidget {
  const factory FactoryKeyRoute({Key? widgetKey}) = _FactoryKeyRoute;

  const FactoryKeyRoute._({Key? widgetKey}) : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final class _FactoryKeyRoute extends FactoryKeyRoute {
  const _FactoryKeyRoute({Key? widgetKey})
      : super._(widgetKey: widgetKey);
}

@Screen(id: 'multi_hop_key', surface: Surface.general)
final class MultiHopKeyRoute extends StatelessWidget {
  const MultiHopKeyRoute(Key? first, Key? second)
      : this.middle(second, first);

  const MultiHopKeyRoute.middle(Key? widgetKey, Key? other)
      : this.target(other, widgetKey);

  const MultiHopKeyRoute.target(Key? other, Key? widgetKey)
      : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'dual_use_key', surface: Surface.general)
final class DualUseKeyRoute extends StatelessWidget {
  const DualUseKeyRoute({Key? widgetKey})
      : retained = widgetKey,
        super(key: widgetKey);

  final Key? retained;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'implicit_null_key', surface: Surface.general)
final class ImplicitNullKeyRoute extends StatelessWidget {
  const ImplicitNullKeyRoute();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'explicit_null_key', surface: Surface.general)
final class ExplicitNullKeyRoute extends StatelessWidget {
  const ExplicitNullKeyRoute() : super(key: ((null)));

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'default_null_key', surface: Surface.general)
final class DefaultNullKeyRoute extends StatelessWidget {
  const DefaultNullKeyRoute() : this.target();

  const DefaultNullKeyRoute.target({Key? widgetKey = (null)})
      : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

abstract class InheritedNullKeyBase extends StatelessWidget {
  const InheritedNullKeyBase({Key? forwardedKey = (null)})
      : super(key: forwardedKey);
}

abstract class InheritedNullKeyMiddle extends InheritedNullKeyBase {
  const InheritedNullKeyMiddle({super.forwardedKey});
}

@Screen(id: 'inherited_null_key', surface: Surface.general)
final class InheritedNullKeyRoute extends InheritedNullKeyMiddle {
  const InheritedNullKeyRoute() : super();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

abstract class InheritedNonNullKeyBase extends StatelessWidget {
  const InheritedNonNullKeyBase({
    Key? forwardedKey = const ValueKey<String>('base'),
  }) : super(key: forwardedKey);
}

abstract class InheritedNonNullKeyMiddle extends InheritedNonNullKeyBase {
  const InheritedNonNullKeyMiddle({super.forwardedKey});
}

@Screen(id: 'inherited_non_null_key', surface: Surface.general)
final class InheritedNonNullKeyRoute extends InheritedNonNullKeyMiddle {
  const InheritedNonNullKeyRoute() : super();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

abstract class NullOverrideKeyBase extends StatelessWidget {
  const NullOverrideKeyBase({
    Key? forwardedKey = const ValueKey<String>('base'),
  }) : super(key: forwardedKey);
}

abstract class NullOverrideKeyMiddle extends NullOverrideKeyBase {
  const NullOverrideKeyMiddle({super.forwardedKey = (null)});
}

abstract class NullOverrideKeyLeaf extends NullOverrideKeyMiddle {
  const NullOverrideKeyLeaf({super.forwardedKey});
}

@Screen(id: 'null_override_key', surface: Surface.general)
final class NullOverrideKeyRoute extends NullOverrideKeyLeaf {
  const NullOverrideKeyRoute() : super();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

abstract class NonNullOverrideKeyBase extends StatelessWidget {
  const NonNullOverrideKeyBase({Key? forwardedKey = (null)})
      : super(key: forwardedKey);
}

abstract class NonNullOverrideKeyMiddle extends NonNullOverrideKeyBase {
  const NonNullOverrideKeyMiddle({
    super.forwardedKey = const ValueKey<String>('middle'),
  });
}

abstract class NonNullOverrideKeyLeaf extends NonNullOverrideKeyMiddle {
  const NonNullOverrideKeyLeaf({super.forwardedKey});
}

@Screen(id: 'non_null_override_key', surface: Surface.general)
final class NonNullOverrideKeyRoute extends NonNullOverrideKeyLeaf {
  const NonNullOverrideKeyRoute() : super();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'transformed_key', surface: Surface.general)
final class TransformedKeyRoute extends StatelessWidget {
  TransformedKeyRoute({Key? widgetKey})
      : super(key: ValueKey<Key?>(widgetKey));

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'multiple_origin_key', surface: Surface.general)
final class MultipleOriginKeyRoute extends StatelessWidget {
  const MultipleOriginKeyRoute({Key? first, Key? second})
      : super(key: first ?? second);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'repeated_origin_key', surface: Surface.general)
final class RepeatedOriginKeyRoute extends StatelessWidget {
  const RepeatedOriginKeyRoute({Key? widgetKey})
      : super(key: widgetKey ?? widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'fixed_key', surface: Surface.general)
final class FixedKeyRoute extends StatelessWidget {
  const FixedKeyRoute() : super(key: const ValueKey<String>('fixed'));

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'default_non_null_key', surface: Surface.general)
final class DefaultNonNullKeyRoute extends StatelessWidget {
  const DefaultNonNullKeyRoute() : this.target();

  const DefaultNonNullKeyRoute.target({
    Key? widgetKey = const ValueKey<String>('default'),
  }) : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'cast_key', surface: Surface.general)
final class CastKeyRoute extends StatelessWidget {
  CastKeyRoute({Key? widgetKey}) : super(key: widgetKey as Key?);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'asserted_key', surface: Surface.general)
final class AssertedKeyRoute extends StatelessWidget {
  AssertedKeyRoute({Key? widgetKey}) : super(key: widgetKey!);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Key? copyKey(Key? value) => value;

@Screen(id: 'call_key', surface: Surface.general)
final class CallKeyRoute extends StatelessWidget {
  CallKeyRoute({Key? widgetKey}) : super(key: copyKey(widgetKey));

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final class KeyBox {
  const KeyBox(this.value);

  final Key? value;
}

@Screen(id: 'property_key', surface: Surface.general)
final class PropertyKeyRoute extends StatelessWidget {
  PropertyKeyRoute(KeyBox box) : super(key: box.value);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'index_key', surface: Surface.general)
final class IndexKeyRoute extends StatelessWidget {
  IndexKeyRoute(List<Key?> values) : super(key: values[0]);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'conditional_key', surface: Surface.general)
final class ConditionalKeyRoute extends StatelessWidget {
  const ConditionalKeyRoute(bool choose, Key? first, Key? second)
      : super(key: choose ? first : second);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'record_key', surface: Surface.general)
final class RecordKeyRoute extends StatelessWidget {
  RecordKeyRoute(Object? first, Object? second)
      : super(key: ObjectKey((first, second)));

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspections = await _inspectAll(source);
      final cases = <({
        String className,
        bool admitted,
        List<String> includes,
        List<String> excludes,
      })>[
        (
          className: 'DirectNamedKeyRoute',
          admitted: true,
          includes: const [
            'super(key: widgetKey)',
            'DirectNamedKeyRoute(),',
          ],
          excludes: const ['_restageArgument0'],
        ),
        (
          className: 'DirectPositionalKeyRoute',
          admitted: true,
          includes: const [
            'super(key: widgetKey)',
            'DirectPositionalKeyRoute(\n          null,',
          ],
          excludes: const ['_restageArgument0'],
        ),
        (
          className: 'FieldFormalKeyRoute',
          admitted: true,
          includes: const [
            'super(key: widgetKey)',
            'FieldFormalKeyRoute(\n          null,',
          ],
          excludes: const ['_restageArgument0'],
        ),
        (
          className: 'SuperFormalKeyRoute',
          admitted: true,
          includes: const ['super.key,'],
          excludes: const ['_restageArgument0', 'key: key,'],
        ),
        (
          className: 'ParenthesizedKeyRoute',
          admitted: true,
          includes: const [
            'super(key: widgetKey)',
          ],
          excludes: const ['_restageArgument0'],
        ),
        (
          className: 'FactoryKeyRoute',
          admitted: true,
          includes: const [
            'super(key: widgetKey)',
          ],
          excludes: const ['_restageArgument0'],
        ),
        (
          className: 'MultiHopKeyRoute',
          admitted: true,
          includes: const [
            'super(key: second)',
            'this._restageArgument0,\n          null,',
          ],
          excludes: const ['super(key: first)'],
        ),
        (
          className: 'DualUseKeyRoute',
          admitted: true,
          includes: const [
            'super(key: widgetKey)',
          ],
          excludes: const ['_restageArgument0'],
        ),
        (
          className: 'ImplicitNullKeyRoute',
          admitted: true,
          includes: const ['super.key,', 'ImplicitNullKeyRoute()'],
          excludes: const [],
        ),
        (
          className: 'ExplicitNullKeyRoute',
          admitted: true,
          includes: const ['super.key,', 'ExplicitNullKeyRoute()'],
          excludes: const [],
        ),
        (
          className: 'DefaultNullKeyRoute',
          admitted: true,
          includes: const ['super.key,', 'DefaultNullKeyRoute()'],
          excludes: const [],
        ),
        (
          className: 'InheritedNullKeyRoute',
          admitted: true,
          includes: const ['super.key,', 'InheritedNullKeyRoute()'],
          excludes: const [],
        ),
        (
          className: 'InheritedNonNullKeyRoute',
          admitted: false,
          includes: const [],
          excludes: const [],
        ),
        (
          className: 'NullOverrideKeyRoute',
          admitted: true,
          includes: const ['super.key,', 'NullOverrideKeyRoute()'],
          excludes: const [],
        ),
        (
          className: 'NonNullOverrideKeyRoute',
          admitted: false,
          includes: const [],
          excludes: const [],
        ),
        for (final className in const [
          'TransformedKeyRoute',
          'MultipleOriginKeyRoute',
          'RepeatedOriginKeyRoute',
          'FixedKeyRoute',
          'DefaultNonNullKeyRoute',
          'CastKeyRoute',
          'AssertedKeyRoute',
          'CallKeyRoute',
          'PropertyKeyRoute',
          'IndexKeyRoute',
          'ConditionalKeyRoute',
          'RecordKeyRoute',
        ])
          (
            className: className,
            admitted: false,
            includes: const [],
            excludes: const [],
          ),
      ];

      const inheritedDefaultClasses = {
        'InheritedNullKeyRoute',
        'InheritedNonNullKeyRoute',
        'NullOverrideKeyRoute',
        'NonNullOverrideKeyRoute',
      };
      final generatedBodies = <String>[];
      final inheritedDefaultValues = <String>[];
      final refusedValues = <String>[];
      expect(
          inspections.keys.toSet(), {for (final item in cases) item.className});
      for (final item in cases) {
        final inspection = inspections[item.className]!;
        final output = inspection.contract!.emitReferenceDart();
        expect(inspection.issues, isEmpty, reason: item.className);
        if (inheritedDefaultClasses.contains(item.className)) {
          final expectedMessage = item.admitted
              ? null
              : 'Generated screen mount ${item.className}Surface was omitted '
                  'because its constructor key value cannot be preserved.';
          final outputMatches = item.admitted
              ? item.includes.every(output.contains) &&
                  item.excludes.every((snippet) => !output.contains(snippet))
              : output.contains('SurfaceScreenRef<Never>.generated');
          final omission = inspection.contract!.mountOmissionMessage;
          final messageMatches = expectedMessage == null
              ? omission == null
              : (omission?.startsWith(expectedMessage) ?? false);
          inheritedDefaultValues.add(
            [
              item.className,
              '$messageMatches',
              '${output.contains('class ${item.className}Surface') == item.admitted}',
              '$outputMatches',
            ].join(':'),
          );
          if (item.admitted &&
              inspection.contract!.mountOmissionMessage == null) {
            generatedBodies.add(_generatedPartBody(output));
          }
          continue;
        }
        if (item.admitted) {
          expect(
            inspection.contract!.mountOmissionMessage,
            isNull,
            reason: item.className,
          );
          expect(
            output,
            contains('class ${item.className}Surface'),
            reason: item.className,
          );
          for (final snippet in item.includes) {
            expect(output, contains(snippet), reason: item.className);
          }
          for (final snippet in item.excludes) {
            expect(output, isNot(contains(snippet)), reason: item.className);
          }
          generatedBodies.add(_generatedPartBody(output));
        } else {
          final expectedMessage =
              'Generated screen mount ${item.className}Surface was omitted '
              'because its constructor key value cannot be preserved.';
          final omission = inspection.contract!.mountOmissionMessage;
          refusedValues.add(
            [
              item.className,
              '${omission?.startsWith(expectedMessage) ?? false}',
              '${!output.contains('class ${item.className}Surface')}',
              '${output.contains('SurfaceScreenRef<Never>.generated')}',
            ].join(':'),
          );
        }
      }
      expect(
        inheritedDefaultValues,
        [
          for (final className in inheritedDefaultClasses)
            '$className:true:true:true',
        ],
      );
      expect(
        refusedValues,
        [
          for (final item in cases.where(
            (item) =>
                !item.admitted &&
                !inheritedDefaultClasses.contains(item.className),
          ))
            '${item.className}:true:true:true',
        ],
      );
      await _assertGeneratedPartAnalyzes(
        source,
        generatedBodies.join('\n\n'),
      );
    });

    test('routes reordered generative arguments by resolved destination',
        () async {
      const positionalSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class PositionalRedirectNotice extends StatelessWidget {
  const PositionalRedirectNotice(Key? first, Key? second)
      : this.named(second, first);

  const PositionalRedirectNotice.named(Key? widgetKey, Key? other)
      : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final positional = await _inspect(
        positionalSource,
        className: 'PositionalRedirectNotice',
      );

      expect(positional.issues, isEmpty);
      expect(positional.contract!.mountOmissionMessage, isNull);
      final positionalOutput = positional.contract!.emitReferenceDart();
      expect(
        positionalOutput,
        contains('''
  })  : _restageArgument0 = first,
        super(key: second);
'''),
      );
      expect(
        positionalOutput,
        contains('''
        builder: (context, error) => PositionalRedirectNotice(
          this._restageArgument0,
          null,
        ),
'''),
      );
      expect(positionalOutput, isNot(contains('super(key: first)')));
      await _assertGeneratedPartAnalyzes(
        positionalSource,
        positionalOutput,
      );

      const namedSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class NamedRedirectNotice extends StatelessWidget {
  const NamedRedirectNotice({Key? first, Key? second})
      : this.named(widgetKey: second, other: first);

  const NamedRedirectNotice.named({Key? widgetKey, Key? other})
      : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final named = await _inspect(
        namedSource,
        className: 'NamedRedirectNotice',
      );

      expect(named.issues, isEmpty);
      expect(named.contract!.mountOmissionMessage, isNull);
      final namedOutput = named.contract!.emitReferenceDart();
      expect(namedOutput, contains('super(key: second)'));
      expect(namedOutput, isNot(contains('super.key,')));
      expect(
        namedOutput,
        contains(RegExp(r'first: this\._restageArgument\d+,')),
      );
      expect(namedOutput, isNot(contains('second:')));
      await _assertGeneratedPartAnalyzes(namedSource, namedOutput);

      const multiHopSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class MultiHopRedirectNotice extends StatelessWidget {
  const MultiHopRedirectNotice(Key? first, Key? second)
      : this.middle(second, first);

  const MultiHopRedirectNotice.middle(Key? widgetKey, Key? other)
      : this.target(widgetKey, other);

  const MultiHopRedirectNotice.target(Key? widgetKey, Key? other)
      : super(key: widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final multiHop = await _inspect(
        multiHopSource,
        className: 'MultiHopRedirectNotice',
      );

      expect(multiHop.issues, isEmpty);
      expect(multiHop.contract!.mountOmissionMessage, isNull);
      final multiHopOutput = multiHop.contract!.emitReferenceDart();
      expect(multiHopOutput, contains('super(key: second)'));
      expect(multiHopOutput, isNot(contains('super(key: first)')));
      expect(
        multiHopOutput,
        contains(
          RegExp(r'MultiHopRedirectNotice\(\s*this\._restageArgument0,'),
        ),
      );
      expect(multiHopOutput, contains('null,'));
      expect(multiHopOutput, isNot(contains('this._restageArgument1,')));
      await _assertGeneratedPartAnalyzes(multiHopSource, multiHopOutput);

      const unchangedSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class UnchangedRedirectNotice extends StatelessWidget {
  const UnchangedRedirectNotice(Key? widgetKey, String label)
      : this.named(widgetKey, label);

  const UnchangedRedirectNotice.named(Key? widgetKey, String label)
      : _label = label,
        super(key: widgetKey);

  final String _label;

  @override
  Widget build(BuildContext context) => Text(_label);
}
''';
      final unchanged = await _inspect(
        unchangedSource,
        className: 'UnchangedRedirectNotice',
      );

      expect(unchanged.issues, isEmpty);
      expect(unchanged.contract!.mountOmissionMessage, isNull);
      final unchangedOutput = unchanged.contract!.emitReferenceDart();
      expect(unchangedOutput, contains('super(key: widgetKey)'));
      expect(
        unchangedOutput,
        contains(RegExp(r'"label": this\._restageArgument\d+,')),
      );
      expect(
        unchangedOutput,
        contains(RegExp(r'UnchangedRedirectNotice\(\s*null,')),
      );
      await _assertGeneratedPartAnalyzes(unchangedSource, unchangedOutput);
    });

    test('mirrors concrete Flutter key types', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class ConcreteKeyNotice extends StatelessWidget {
  const ConcreteKeyNotice({required ValueKey<String> key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(
        source,
        className: 'ConcreteKeyNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('required ValueKey<String> key,'));
      expect(emitted, isNot(contains('required Key? key,')));
      expect(emitted, contains('key: key,'));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('treats unrelated key names as ordinary values', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class TextKeyNotice extends StatelessWidget {
  const TextKeyNotice({required String key}) : _textKey = key;

  final String _textKey;

  @override
  Widget build(BuildContext context) => Text(_textKey);
}
''';
      final inspection = await _inspect(
        source,
        className: 'TextKeyNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('required String key,'));
      expect(emitted, contains(RegExp(r'"key": this\._restageArgument\d+,')));
      expect(
        emitted,
        contains(RegExp(r'key: this\._restageArgument\d+,')),
      );
      expect(emitted, isNot(contains('super.key,')));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('qualifies class constants used by forwarded keys', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

const defaultKey = ValueKey<String>('library');

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class DefaultKeyNotice extends StatelessWidget {
  const DefaultKeyNotice({ValueKey<String> key = defaultKey})
      : super(key: key);

  static const defaultKey = ValueKey<String>('screen');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(
        source,
        className: 'DefaultKeyNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(
        emitted,
        contains(
          RegExp(
            r'const ValueKey<String> _defaultKeyNoticeMountDefault0\s*=\s*'
            r'DefaultKeyNotice\.defaultKey;',
          ),
        ),
      );
      expect(
        emitted,
        contains(
          'ValueKey<String> key = _defaultKeyNoticeMountDefault0,',
        ),
      );
      expect(emitted, isNot(contains('ValueKey<String> key = defaultKey,')));
      expect(emitted, contains('key: key,'));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('lowers renamed inherited named keys as ordinary formals', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

abstract class NamedKeyBase extends StatelessWidget {
  const NamedKeyBase({required Key widgetKey}) : super(key: widgetKey);
}

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class RenamedNamedKeyNotice extends NamedKeyBase {
  const RenamedNamedKeyNotice({required super.widgetKey});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(
        source,
        className: 'RenamedNamedKeyNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('required Key widgetKey,'));
      expect(emitted, isNot(contains('super.widgetKey')));
      expect(emitted, isNot(contains('super(key:')));
      expect(
        emitted,
        contains(RegExp(r'widgetKey: this\._restageArgument\d+,')),
      );
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('lowers renamed inherited positional keys as ordinary formals',
        () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

abstract class PositionalKeyBase extends StatelessWidget {
  const PositionalKeyBase(Key widgetKey) : super(key: widgetKey);
}

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class RenamedPositionalKeyNotice extends PositionalKeyBase {
  const RenamedPositionalKeyNotice(super.widgetKey);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(
        source,
        className: 'RenamedPositionalKeyNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('Key widgetKey,'));
      expect(emitted, isNot(contains('super.widgetKey')));
      expect(emitted, isNot(contains('super(key:')));
      expect(
        emitted,
        contains(
          RegExp(r'RenamedPositionalKeyNotice\(\s*this\._restageArgument'),
        ),
      );
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('routes a field-formal key to the fallback widget alone', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class FieldKeyNotice extends StatelessWidget {
  const FieldKeyNotice(this.widgetKey) : super(key: widgetKey);

  final Key widgetKey;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(source, className: 'FieldKeyNotice');

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('Key widgetKey,'));
      expect(emitted, isNot(contains('super(key:')));
      expect(emitted, isNot(contains('super.key,')));
      expect(
        emitted,
        contains(RegExp(r'_restageArgument\d+ = widgetKey')),
      );
      expect(
        emitted,
        contains(RegExp(r'FieldKeyNotice\(\s*this\._restageArgument\d+,')),
      );
      expect(emitted, isNot(contains('"widgetKey":')));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('routes stored and forwarded keys through one value', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class StoredKeyNotice extends StatelessWidget {
  const StoredKeyNotice({required Key? widgetKey})
      : storedWidgetKey = widgetKey,
        super(key: widgetKey);

  final Key? storedWidgetKey;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(source, className: 'StoredKeyNotice');

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('required Key? widgetKey,'));
      expect(emitted, contains('super(key: widgetKey)'));
      expect(emitted, isNot(contains('super.key,')));
      expect(
        emitted,
        isNot(contains(RegExp(r'_restageArgument\d+ = widgetKey'))),
      );
      expect(emitted, contains('widgetKey: null,'));
      expect(emitted, isNot(contains('"widgetKey":')));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('omits key formals that collide with mount controls', () async {
      for (final control in const [
        'onEvent',
        'resolver',
        'onUnavailable',
        'loadingBuilder',
      ]) {
        final source = _screenSource(
          className: 'ReservedKeyNotice',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          constructor: '''
  const ReservedKeyNotice({required Key $control}) : super(key: $control);
''',
          part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
        );
        final inspection = await _inspect(
          source,
          className: 'ReservedKeyNotice',
        );
        final emitted = inspection.contract!.emitReferenceDart();
        final errors = await _generatedPartErrors(source, emitted);
        final expectedMessage =
            'Generated screen mount ReservedKeyNoticeSurface was omitted '
            'because ReservedKeyNotice declares the reserved constructor '
            'parameter "$control".';

        expect(inspection.issues, isEmpty);
        expect(
          [inspection.contract!.mountOmissionMessage, ...errors],
          [expectedMessage],
          reason: control,
        );
        expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
        expect(emitted, isNot(contains('class ReservedKeyNoticeSurface')));
      }
    });

    test('omits generic mounts when a key type depends on the screen',
        () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class GenericKeyNotice<T extends Key> extends StatelessWidget {
  const GenericKeyNotice({required T key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(source, className: 'GenericKeyNotice');
      final emitted = inspection.contract!.emitReferenceDart();
      final errors = await _generatedPartErrors(source, emitted);
      const expectedMessage =
          'Generated screen mount GenericKeyNoticeSurface was omitted because '
          '"key" depends on the screen type parameter "T".';

      expect(inspection.issues, isEmpty);
      expect(
        [inspection.contract!.mountOmissionMessage, ...errors],
        [expectedMessage],
      );
      expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
      expect(emitted, isNot(contains('class GenericKeyNoticeSurface')));
    });

    test('omits generic screens whose formals do not mention the type',
        () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class GenericShapeNotice<T> extends StatelessWidget {
  const GenericShapeNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final inspection = await _inspect(
        source,
        className: 'GenericShapeNotice',
      );
      final emitted = inspection.contract!.emitReferenceDart();
      const expectedMessage =
          'Generated screen mount GenericShapeNoticeSurface was omitted '
          'because GenericShapeNotice declares the screen type parameter "T".';

      expect(inspection.issues, isEmpty);
      expect(
        [
          inspection.contract!.mountOmissionMessage,
          emitted.contains('class GenericShapeNoticeSurface'),
        ],
        [expectedMessage, false],
      );
      expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
    });

    test('infers inherited super-parameter types', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

class BaseLabelNotice extends StatelessWidget {
  const BaseLabelNotice(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class InheritedLabelNotice extends BaseLabelNotice {
  const InheritedLabelNotice(super.label, {super.key});

  @override
  Widget build(BuildContext context) => Text(label);
}
''';
      final inspection = await _inspect(
        source,
        className: 'InheritedLabelNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('String label,'));
      expect(
        emitted,
        contains(RegExp(r'InheritedLabelNotice\(\s*this\._restageArgument0,')),
      );
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('emits dynamic for untyped field parameters', () async {
      const source = r'''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class DynamicValueNotice extends StatelessWidget {
  const DynamicValueNotice(this.value, {super.key});

  final value;

  @override
  Widget build(BuildContext context) => Text('$value');
}
''';
      final inspection = await _inspect(
        source,
        className: 'DynamicValueNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('dynamic value,'));
      expect(
        emitted,
        contains(RegExp(r'DynamicValueNotice\(\s*this\._restageArgument0,')),
      );
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('reserves visible unprefixed imported mount names', () async {
      const supportSource = '''
final class NoticeSurface {
  const NoticeSurface.named();
}
''';
      final collisionSource = _screenSource(
        className: 'Notice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        import: '''
import 'package:restage/restage.dart';
import 'support.dart';
''',
        extraDeclarations:
            'Object existingSurface() => const NoticeSurface.named();',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final collision = await _inspect(
        collisionSource,
        className: 'Notice',
        additionalSources: const {
          'apps_examples|lib/support.dart': supportSource,
        },
      );

      expect(collision.issues, isEmpty);
      expect(collision.contract!.mountOmissionMessage, isNotNull);
      final collisionOutput = collision.contract!.emitReferenceDart();
      expect(collisionOutput, contains('SurfaceScreenRef<Never>.generated'));
      expect(collisionOutput, isNot(contains('class NoticeSurface')));
      await _assertGeneratedPartAnalyzes(
        collisionSource,
        collisionOutput,
        additionalSources: const {
          'apps_examples|lib/support.dart': supportSource,
        },
      );

      final availableSource = _screenSource(
        className: 'AvailableNotice',
        annotation: "@Screen(id: 'available', surface: Surface.general)",
        import: '''
import 'package:restage/restage.dart';
import 'support.dart';
''',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final available = await _inspect(
        availableSource,
        className: 'AvailableNotice',
        slug: 'available',
        additionalSources: const {
          'apps_examples|lib/support.dart': supportSource,
        },
      );
      expect(available.issues, isEmpty);
      expect(available.contract!.mountOmissionMessage, isNull);
      final availableOutput = available.contract!.emitReferenceDart();
      expect(availableOutput, contains('class AvailableNoticeSurface'));
      await _assertGeneratedPartAnalyzes(
        availableSource,
        availableOutput,
        additionalSources: const {
          'apps_examples|lib/support.dart': supportSource,
        },
      );
    });

    test('reserves transitively exported mount names for consumers', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

export 'middle.dart' show ExportedNoticeSurface;

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class ExportedNotice extends StatelessWidget {
  const ExportedNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      const additionalSources = {
        'apps_examples|lib/support.dart': '''
final class ExportedNoticeSurface {
  const ExportedNoticeSurface.named();
}
''',
        'apps_examples|lib/middle.dart': '''
export 'support.dart' show ExportedNoticeSurface;
''',
        'apps_examples|lib/consumer.dart': '''
import 'maintenance_notice.dart';

Object existingSurface() => const ExportedNoticeSurface.named();
''',
      };
      expect(
        await _generatedPartErrors(
          source,
          '',
          additionalSources: additionalSources,
          sourceIds: const ['apps_examples|lib/consumer.dart'],
        ),
        isEmpty,
      );
      final inspection = await _inspect(
        source,
        className: 'ExportedNotice',
        additionalSources: additionalSources,
      );
      final emitted = inspection.contract!.emitReferenceDart();
      final errors = await _generatedPartErrors(
        source,
        emitted,
        additionalSources: additionalSources,
        sourceIds: const ['apps_examples|lib/consumer.dart'],
      );
      const expectedMessage =
          'Generated screen mount ExportedNoticeSurface was omitted because '
          'ExportedNoticeSurface already exists in '
          'lib/maintenance_notice.dart.';

      expect(inspection.issues, isEmpty);
      expect(
        [inspection.contract!.mountOmissionMessage, ...errors],
        [expectedMessage],
      );
      expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
      expect(emitted, isNot(contains('class ExportedNoticeSurface')));
    });

    test('reserves exports hidden beneath the exact warm mount', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

export 'support.dart' show WarmExportNoticeSurface;

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class WarmExportNotice extends StatelessWidget {
  const WarmExportNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      const supportSources = {
        'apps_examples|lib/support.dart': '''
final class WarmExportNoticeSurface {
  const WarmExportNoticeSurface.named();
}
''',
        'apps_examples|lib/consumer.dart': '''
import 'maintenance_notice.dart';

Object existingSurface() => const WarmExportNoticeSurface.named();
''',
      };
      final inspection = await _inspect(
        source,
        className: 'WarmExportNotice',
        additionalSources: const {
          ...supportSources,
          'apps_examples|lib/restage.generated/maintenance_notice.restage.g.dart':
              '''
part of '../maintenance_notice.dart';

final class WarmExportNoticeSurface {}
''',
        },
      );
      final emitted = inspection.contract!.emitReferenceDart();
      final errors = await _generatedPartErrors(
        source,
        emitted,
        additionalSources: supportSources,
        sourceIds: const ['apps_examples|lib/consumer.dart'],
      );
      const expectedMessage =
          'Generated screen mount WarmExportNoticeSurface was omitted because '
          'WarmExportNoticeSurface already exists in '
          'lib/maintenance_notice.dart.';

      expect(inspection.issues, isEmpty);
      expect(
        [inspection.contract!.mountOmissionMessage, ...errors],
        [expectedMessage],
      );
      expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
      expect(emitted, isNot(contains('class WarmExportNoticeSurface')));
    });

    test('ignores hidden exports and the exact warm mount', () async {
      const supportSource = '''
final class HiddenNoticeSurface {
  const HiddenNoticeSurface.named();
}
''';
      const hiddenSource = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

export 'support.dart' hide HiddenNoticeSurface;

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class HiddenNotice extends StatelessWidget {
  const HiddenNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      final hidden = await _inspect(
        hiddenSource,
        className: 'HiddenNotice',
        additionalSources: const {
          'apps_examples|lib/support.dart': supportSource,
        },
      );
      expect(hidden.issues, isEmpty);
      expect(hidden.contract!.mountOmissionMessage, isNull);
      final hiddenOutput = hidden.contract!.emitReferenceDart();
      expect(hiddenOutput, contains('class HiddenNoticeSurface'));
      await _assertGeneratedPartAnalyzes(
        hiddenSource,
        hiddenOutput,
        additionalSources: const {
          'apps_examples|lib/support.dart': supportSource,
        },
      );

      final warmSource = _screenSource(
        className: 'WarmMountNotice',
        annotation: "@Screen(id: 'warm_mount', surface: Surface.general)",
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final warm = await _inspect(
        warmSource,
        className: 'WarmMountNotice',
        slug: 'warm_mount',
        additionalSources: const {
          'apps_examples|lib/restage.generated/maintenance_notice.restage.g.dart':
              '''
part of '../maintenance_notice.dart';

final class WarmMountNoticeSurface {}
''',
        },
      );
      expect(warm.issues, isEmpty);
      expect(warm.contract!.mountOmissionMessage, isNull);
      expect(
        warm.contract!.emitReferenceDart(),
        contains('class WarmMountNoticeSurface'),
      );
    });

    test('combines restricted imports sharing one prefix', () async {
      final source = _screenSource(
        className: 'SplitImportNotice',
        annotation:
            "@rs.Screen(id: 'maintenance_notice', surface: rs.Surface.general)",
        import: '''
import 'package:restage/restage.dart' as rs
    show
        Screen,
        Surface,
        SurfaceScreenRef,
        SurfaceScreenEventContract,
        SurfaceScreenRuntimeProvenance,
        CapabilityManifest,
        LibraryRequirement,
        RestageScreen;
import 'package:restage/restage.dart' as rs
    show
        SurfaceScreenUnavailablePolicy,
        SurfaceScreenResolver,
        SurfaceScreenUnavailableError;
''',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final inspection = await _inspect(
        source,
        className: 'SplitImportNotice',
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract!.mountOmissionMessage, isNull);
      final emitted = inspection.contract!.emitReferenceDart();
      expect(emitted, contains('return rs.RestageScreen<Never>('));
      await _assertGeneratedPartAnalyzes(source, emitted);
    });

    test('uses exact-origin symbols re-exported through a barrel', () async {
      const source = '''
import 'package:flutter/widgets.dart'
    show StatelessWidget, Widget, BuildContext, SizedBox;
import 'package:restage/restage.dart'
    show
        Screen,
        Surface,
        SurfaceScreenRef,
        SurfaceScreenEventContract,
        SurfaceScreenRuntimeProvenance,
        CapabilityManifest,
        LibraryRequirement;
import 'support.dart' as app;

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class BarrelNotice extends StatelessWidget {
  const BarrelNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
      const additionalSources = {
        'apps_examples|lib/support.dart': '''
export 'package:flutter/widgets.dart'
    show StatelessWidget, Widget, BuildContext, ValueChanged, WidgetBuilder;
export 'package:restage/restage.dart'
    show
        RestageScreen,
        SurfaceScreenUnavailablePolicy,
        SurfaceScreenResolver,
        SurfaceScreenUnavailableError;
''',
      };
      final inspection = await _inspect(
        source,
        className: 'BarrelNotice',
        additionalSources: additionalSources,
      );
      final emitted = inspection.contract!.emitReferenceDart();

      expect(inspection.issues, isEmpty);
      expect(
        [
          inspection.contract!.mountOmissionMessage,
          emitted.contains('extends app.StatelessWidget'),
          emitted.contains('return app.RestageScreen<Never>('),
        ],
        [null, true, true],
      );
      await _assertGeneratedPartAnalyzes(
        source,
        emitted,
        additionalSources: additionalSources,
      );

      final unprefixedSource = source.replaceFirst(
        "import 'support.dart' as app;",
        "import 'support.dart';",
      );
      final unprefixed = await _inspect(
        unprefixedSource,
        className: 'BarrelNotice',
        additionalSources: additionalSources,
      );
      final unprefixedOutput = unprefixed.contract!.emitReferenceDart();
      expect(unprefixed.issues, isEmpty);
      expect(
        [
          unprefixed.contract!.mountOmissionMessage,
          unprefixedOutput.contains('extends StatelessWidget'),
          unprefixedOutput.contains('return RestageScreen<Never>('),
        ],
        [null, true, true],
      );
      await _assertGeneratedPartAnalyzes(
        unprefixedSource,
        unprefixedOutput,
        additionalSources: additionalSources,
      );
    });

    test('selects mount qualifiers from non-deferred import routes', () async {
      const exactBarrel = '''
export 'package:restage/restage.dart'
    show
        RestageScreen,
        SurfaceScreenUnavailablePolicy,
        SurfaceScreenResolver,
        SurfaceScreenUnavailableError;
''';
      const wrongOrigin = '''
final class RestageScreen {}
final class SurfaceScreenUnavailablePolicy {}
final class SurfaceScreenResolver {}
final class SurfaceScreenUnavailableError {}
''';
      final scenarios = <({
        String name,
        String imports,
        String declarations,
        Map<String, String> additionalSources,
        String? prefix,
        bool analyzeGenerated,
      })>[
        (
          name: 'direct restricted',
          imports: _directMountImport('app'),
          declarations: '',
          additionalSources: const {},
          prefix: 'app.',
          analyzeGenerated: true,
        ),
        (
          name: 'barrel',
          imports: "import 'mount_symbols.dart' as app;",
          declarations: '',
          additionalSources: const {
            'apps_examples|lib/mount_symbols.dart': exactBarrel,
          },
          prefix: 'app.',
          analyzeGenerated: true,
        ),
        (
          name: 'split restricted',
          imports: '''
import 'package:restage/restage.dart' as app
    show RestageScreen, SurfaceScreenUnavailablePolicy;
import 'package:restage/restage.dart' as app
    show SurfaceScreenResolver, SurfaceScreenUnavailableError;
''',
          declarations: '',
          additionalSources: const {},
          prefix: 'app.',
          analyzeGenerated: true,
        ),
        (
          name: 'unprefixed barrel',
          imports: "import 'mount_symbols.dart';",
          declarations: '',
          additionalSources: const {
            'apps_examples|lib/mount_symbols.dart': exactBarrel,
          },
          prefix: '',
          analyzeGenerated: true,
        ),
        (
          name: 'deferred alternative',
          imports: '''
import 'mount_symbols.dart' deferred as lazy;
${_directMountImport('app')}
''',
          declarations: '',
          additionalSources: const {
            'apps_examples|lib/mount_symbols.dart': exactBarrel,
          },
          prefix: 'app.',
          analyzeGenerated: true,
        ),
        (
          name: 'deferred only',
          imports: "import 'mount_symbols.dart' deferred as app;",
          declarations: '',
          additionalSources: const {
            'apps_examples|lib/mount_symbols.dart': exactBarrel,
          },
          prefix: null,
          analyzeGenerated: true,
        ),
        (
          name: 'mixed prefix missing non-deferred symbol',
          imports: '''
import 'package:restage/restage.dart' deferred as app
    show RestageScreen;
import 'package:restage/restage.dart' as app
    show
        SurfaceScreenUnavailablePolicy,
        SurfaceScreenResolver,
        SurfaceScreenUnavailableError;
''',
          declarations: '',
          additionalSources: const {},
          prefix: null,
          analyzeGenerated: false,
        ),
        (
          name: 'mixed prefix with complete non-deferred routes',
          imports: '''
import 'package:restage/restage.dart' deferred as app
    show RestageScreen;
${_directMountImport('app')}
''',
          declarations: '',
          additionalSources: const {},
          prefix: 'app.',
          analyzeGenerated: false,
        ),
        (
          name: 'hidden symbol',
          imports: "import 'mount_symbols.dart' as app "
              'hide SurfaceScreenResolver;',
          declarations: '',
          additionalSources: const {
            'apps_examples|lib/mount_symbols.dart': exactBarrel,
          },
          prefix: null,
          analyzeGenerated: true,
        ),
        (
          name: 'local shadow',
          imports: "import 'mount_symbols.dart';",
          declarations: 'final class RestageScreen {}',
          additionalSources: const {
            'apps_examples|lib/mount_symbols.dart': exactBarrel,
          },
          prefix: null,
          analyzeGenerated: true,
        ),
        (
          name: 'wrong origin',
          imports: "import 'wrong_mount_symbols.dart' as app;",
          declarations: '',
          additionalSources: const {
            'apps_examples|lib/wrong_mount_symbols.dart': wrongOrigin,
          },
          prefix: null,
          analyzeGenerated: true,
        ),
      ];

      for (final scenario in scenarios) {
        final source = _mountQualifierSource(
          imports: scenario.imports,
          declarations: scenario.declarations,
        );
        final inspection = await _inspect(
          source,
          className: 'QualifierNotice',
          additionalSources: scenario.additionalSources,
        );
        final emitted = inspection.contract!.emitReferenceDart();

        expect(inspection.issues, isEmpty, reason: scenario.name);
        if (scenario.prefix case final prefix?) {
          expect(
            inspection.contract!.mountOmissionMessage,
            isNull,
            reason: scenario.name,
          );
          expect(
            emitted,
            contains('return ${prefix}RestageScreen<Never>('),
            reason: scenario.name,
          );
        } else {
          expect(
            inspection.contract!.mountOmissionMessage,
            contains('required Restage widget symbols'),
            reason: scenario.name,
          );
          expect(
            emitted,
            isNot(contains('class QualifierNoticeSurface')),
            reason: scenario.name,
          );
        }
        if (scenario.analyzeGenerated) {
          await _assertGeneratedPartAnalyzes(
            source,
            emitted,
            additionalSources: scenario.additionalSources,
          );
        }
      }
    });

    test('omits only mounts with local constructor or name conflicts',
        () async {
      final nameCollision = await _inspect(
        _screenSource(
          className: 'NameCollision',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          extraDeclarations: 'final class NameCollisionSurface {}',
        ),
        className: 'NameCollision',
      );
      final controlCollision = await _inspect(
        _screenSource(
          className: 'ControlCollision',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          constructor: '  const ControlCollision({this.onEvent, super.key});',
          fields: '  final Object? onEvent;',
        ),
        className: 'ControlCollision',
      );
      final namedOnly = await _inspect(
        _screenSource(
          className: 'NamedOnly',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          constructor: '  const NamedOnly.named({super.key});',
        ),
        className: 'NamedOnly',
      );

      for (final inspection in [nameCollision, controlCollision, namedOnly]) {
        expect(inspection.issues, isEmpty);
        expect(inspection.contract, isNotNull);
        expect(inspection.contract!.mountOmissionMessage, isNotNull);
        final emitted = inspection.contract!.emitReferenceDart();
        expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
        expect(emitted, isNot(contains('extends StatelessWidget')));
      }
    });

    test('keeps references with restricted mount-only imports', () async {
      final source = _screenSource(
        className: 'RestrictedNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        flutterImport: "import 'package:flutter/widgets.dart' "
            'show StatelessWidget, Widget, BuildContext, SizedBox;',
        import: "import 'package:restage/restage.dart' "
            'show Screen, Surface, SurfaceScreenRef, '
            'SurfaceScreenEventContract, SurfaceScreenRuntimeProvenance, '
            'CapabilityManifest, LibraryRequirement;',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final missingSdk = await _inspect(
        source,
        className: 'RestrictedNotice',
      );

      expect(missingSdk.issues, isEmpty);
      expect(
        missingSdk.contract!.mountOmissionMessage,
        contains('required Restage widget symbols'),
      );
      final emitted = missingSdk.contract!.emitReferenceDart();
      expect(emitted, contains('SurfaceScreenRef<Never>.generated'));
      expect(emitted, isNot(contains('RestrictedNoticeSurface')));
      await _assertGeneratedPartAnalyzes(source, emitted);

      final flutterSource = _screenSource(
        className: 'RestrictedFlutterNotice',
        annotation:
            "@Screen(id: 'maintenance_notice', surface: Surface.general)",
        flutterImport: "import 'package:flutter/widgets.dart' "
            'show StatelessWidget, Widget, BuildContext, SizedBox;',
        part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
      );
      final missingFlutter = await _inspect(
        flutterSource,
        className: 'RestrictedFlutterNotice',
      );
      expect(missingFlutter.issues, isEmpty);
      expect(
        missingFlutter.contract!.mountOmissionMessage,
        contains('required Flutter widget symbols'),
      );
      final flutterEmitted = missingFlutter.contract!.emitReferenceDart();
      expect(flutterEmitted, contains('SurfaceScreenRef<Never>.generated'));
      expect(flutterEmitted, isNot(contains('RestrictedFlutterNoticeSurface')));
      await _assertGeneratedPartAnalyzes(flutterSource, flutterEmitted);
    });

    test('accepts canonical implicit and explicit screen identities', () async {
      final implicit = await _inspect(
        _screenSource(
          className: 'ImplicitIdentityNotice',
          annotation: '@Screen(surface: Surface.general)',
        ),
        className: 'ImplicitIdentityNotice',
      );
      expect(implicit.issues, isEmpty);
      expect(implicit.contract!.slug, 'maintenance_notice');

      final explicit = await _inspect(
        _screenSource(
          className: 'ExplicitIdentityNotice',
          annotation: "@Screen(id: 'stable_notice', surface: Surface.general)",
        ),
        className: 'ExplicitIdentityNotice',
        slug: 'stable_notice',
      );
      expect(explicit.issues, isEmpty);
      expect(explicit.contract!.slug, 'stable_notice');

      final mismatch = await _inspect(
        _screenSource(
          className: 'MismatchedIdentityNotice',
          annotation: "@Screen(id: 'stable_notice', surface: Surface.general)",
        ),
        className: 'MismatchedIdentityNotice',
      );
      expect(mismatch.contract, isNull);
      expect(
        mismatch.issues.map((issue) => issue.message).join('\n'),
        contains('does not match the normalized publication slug'),
      );

      final nonPositiveVersion = await _inspect(
        _screenSource(
          className: 'ZeroVersionNotice',
          annotation: "@Screen(id: 'maintenance_notice', "
              'surface: Surface.general, version: 0)',
        ),
        className: 'ZeroVersionNotice',
        contractVersion: 0,
      );
      expect(nonPositiveVersion.contract, isNull);
      expect(
        nonPositiveVersion.issues.map((issue) => issue.message).join('\n'),
        contains('contractVersion must be positive'),
      );
    });

    test('event and capability mutations produce the expected hash changes',
        () async {
      final original = await _inspect(
        _screenSource(
          className: 'MutableNotice',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          events: "  static const dismiss = SurfaceEvent<void>('dismiss');",
        ),
        className: 'MutableNotice',
      );
      final eventMutation = await _inspect(
        _screenSource(
          className: 'MutableNotice',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          events: "  static const dismiss = SurfaceEvent<void>('close');",
        ),
        className: 'MutableNotice',
      );
      final capabilityMutation = await _inspect(
        _screenSource(
          className: 'MutableNotice',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          events: "  static const dismiss = SurfaceEvent<void>('dismiss');",
        ),
        className: 'MutableNotice',
        capabilities: CapabilityManifest(
          builtInFloor: 2,
          requiredLibraries: const [],
        ),
      );

      expect(original.issues, isEmpty);
      expect(eventMutation.issues, isEmpty);
      expect(capabilityMutation.issues, isEmpty);
      expect(
        eventMutation.contract!.eventContractHash,
        isNot(original.contract!.eventContractHash),
      );
      expect(
        eventMutation.contract!.contractFingerprint,
        isNot(original.contract!.contractFingerprint),
      );
      expect(
        capabilityMutation.contract!.eventContractHash,
        original.contract!.eventContractHash,
      );
      expect(
        capabilityMutation.contract!.contractFingerprint,
        isNot(original.contract!.contractFingerprint),
      );
    });

    test('rejects lookalikes, unstable IDs, and every unsupported type family',
        () async {
      final lookalike = await _inspect(
        '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

class SurfaceEvent<T> {
  const SurfaceEvent(this.id);
  final String id;
}

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class LookalikeNotice extends StatelessWidget {
  const LookalikeNotice({super.key});
  static const dismiss = SurfaceEvent<void>('dismiss');
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
        className: 'LookalikeNotice',
      );
      expect(lookalike.contract, isNull);
      expect(
        lookalike.issues.map((issue) => issue.message).join('\n'),
        contains('does not resolve to package:restage'),
      );

      final invalid = await _inspect(
        _screenSource(
          className: 'InvalidEvents',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          events: '''
  static const empty = SurfaceEvent<void>('');
  static const first = SurfaceEvent<void>('same');
  static const second = SurfaceEvent<void>('same');
  static final unstable = SurfaceEvent<void>('unstable');
  static const rawList = SurfaceEvent<List>('raw-list');
  static const rawMap = SurfaceEvent<Map>('raw-map');
  static const dynamicMap = SurfaceEvent<Map<String, dynamic>>('dynamic-map');
  static const invalidKey = SurfaceEvent<Map<int, String>>('invalid-key');
  static const custom = SurfaceEvent<DateTime>('custom');
  static const unsupported = SurfaceEvent<Set<int>>('unsupported');
''',
        ),
        className: 'InvalidEvents',
      );
      expect(invalid.contract, isNull);
      final messages = invalid.issues.map((issue) => issue.message).join('\n');
      expect(messages, contains('non-empty const ID'));
      expect(messages, contains('Duplicate standalone SurfaceEvent ID'));
      expect(messages, contains('must be const'));
      expect(messages, contains('dynamic is not part'));
      expect(
        messages,
        contains('Map keys must be exactly non-nullable String'),
      );
      expect(messages, contains('custom and unsupported collection types'));
    });

    test('accepts symbols from the exact warm generated sibling part',
        () async {
      final inspection = await _inspect(
        _screenSource(
          className: 'WarmNotice',
          annotation: "@Screen(id: 'warm_notice', surface: Surface.general)",
          events: "  static const finish = SurfaceEvent<void>('finish');",
          part: "part 'restage.generated/maintenance_notice.restage.g.dart';",
        ),
        className: 'WarmNotice',
        slug: 'warm_notice',
        additionalSources: {
          'apps_examples|lib/restage.generated/maintenance_notice.restage.g.dart':
              '''
part of '../maintenance_notice.dart';

final warmNoticeRef = Object();
final _warmNoticeEvents = Object();
final _decodeValidatedWarmNoticeEvent = Object();
final WarmNoticeEvent = Object();
final WarmNoticeFinishEvent = Object();
''',
        },
      );

      expect(inspection.issues, isEmpty);
      expect(inspection.contract, isNotNull);
    });

    test('rejects authored and foreign lookalike generated collisions',
        () async {
      final neutral = await _inspect(
        _screenSource(
          className: 'NeutralNotice',
          annotation: '@Screen()',
        ),
        className: 'NeutralNotice',
      );
      expect(neutral.contract, isNull);
      expect(
        neutral.issues.map((issue) => issue.message).join('\n'),
        contains('require a resolved surface'),
      );

      final mismatch = await _inspect(
        _screenSource(
          className: 'MismatchNotice',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.message)",
        ),
        className: 'MismatchNotice',
      );
      expect(mismatch.contract, isNull);
      expect(
        mismatch.issues.map((issue) => issue.message).join('\n'),
        contains('does not match the normalized publication surface'),
      );

      final collision = await _inspect(
        _screenSource(
          className: 'CollisionNotice',
          annotation:
              "@Screen(id: 'maintenance_notice', surface: Surface.general)",
          extraDeclarations: '''
final collisionNoticeRef = Object();
''',
        ),
        className: 'CollisionNotice',
      );
      expect(collision.contract, isNull);
      expect(
        collision.issues.map((issue) => issue.message).join('\n'),
        contains('Generated standalone screen symbol collisionNoticeRef'),
      );

      final foreign = await _inspect(
        _screenSource(
          className: 'ForeignNotice',
          annotation: "@Screen(id: 'foreign_notice', surface: Surface.general)",
          events: "  static const finish = SurfaceEvent<void>('finish');",
          part: "part 'restage.generated/lookalike.restage.g.dart';",
        ),
        className: 'ForeignNotice',
        slug: 'foreign_notice',
        additionalSources: {
          'apps_examples|lib/restage.generated/lookalike.restage.g.dart': '''
part of '../maintenance_notice.dart';

final foreignNoticeRef = Object();
final _foreignNoticeEvents = Object();
final _decodeValidatedForeignNoticeEvent = Object();
final ForeignNoticeEvent = Object();
final ForeignNoticeFinishEvent = Object();
''',
        },
      );
      expect(foreign.contract, isNull);
      expect(
        foreign.issues.map((issue) => issue.message).join('\n'),
        contains('Generated standalone screen symbol foreignNoticeRef'),
      );
    });
  });
}

String _aliasTypeScreenSource({
  required String imports,
  required String baseType,
  required String className,
  required String parameters,
  String declarations = '',
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
$imports

part 'restage.generated/maintenance_notice.restage.g.dart';

$declarations

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class $className extends $baseType {
  const $className({$parameters});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _aliasRefusalBaseSource({
  required String declarations,
  required String type,
}) =>
    '''
import 'package:flutter/widgets.dart';

$declarations

abstract class AliasRefusalBase extends StatelessWidget {
  const AliasRefusalBase({required this.value, super.key});

  final $type value;
}
''';

String _directDefaultSource({
  required String expression,
  String type = 'int',
  String declarations = '',
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/maintenance_notice.restage.g.dart';

$declarations

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class DefaultRouteNotice extends StatelessWidget {
  const DefaultRouteNotice({this.value = $expression, super.key});

  final $type value;

  @override
  Widget build(BuildContext context) => Text('\$value');
}
''';

String _inheritedDefaultSource({
  required String imports,
  required String baseType,
  String declarations = '',
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
$imports

part 'restage.generated/maintenance_notice.restage.g.dart';

$declarations

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class DefaultRouteNotice extends $baseType {
  const DefaultRouteNotice({super.value, super.key});

  @override
  Widget build(BuildContext context) => Text('\$value');
}
''';

String _defaultBaseSource({
  required String expression,
  String type = 'int',
  String imports = '',
  String declarations = '',
  String members = '',
}) =>
    '''
import 'package:flutter/widgets.dart';
$imports

$declarations

abstract class DefaultRouteBase extends StatelessWidget {
  const DefaultRouteBase({this.value = $expression, super.key});

  $members
  final $type value;
}
''';

const _privateReceiverDeclarations = '''
class _ClassValues {
  static const constant = 11;
  static String convert(String value) => value;
}
typedef ClassValues = _ClassValues;

enum _EnumValues {
  item;

  static const constant = 12;
  static String convert(String value) => value;
}
typedef EnumValues = _EnumValues;

mixin _MixinValues {
  static const constant = 13;
  static String convert(String value) => value;
}
typedef MixinValues = _MixinValues;

extension type const _ExtensionTypeValues(int raw) {
  static const constant = 14;
  static String convert(String value) => value;
}
typedef ExtensionTypeValues = _ExtensionTypeValues;
''';

const _publicReceiverDeclarations = '''
class ClassValues {
  static const constant = 11;
  static String convert(String value) => value;
}

enum EnumValues {
  item;

  static const constant = 12;
  static String convert(String value) => value;
}

mixin MixinValues {
  static const constant = 13;
  static String convert(String value) => value;
}

extension type const ExtensionTypeValues(int raw) {
  static const constant = 14;
  static String convert(String value) => value;
}
''';

String _receiverScreenSource({
  required String imports,
  required String baseType,
  required List<String> parameterNames,
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
$imports

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class StaticReceiverNotice extends $baseType {
  const StaticReceiverNotice({
${parameterNames.map((name) => '    super.$name,').join('\n')}
    super.key,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _receiverBaseSource({
  required List<({String name, String type, String expression})> defaults,
  required String declarations,
}) =>
    '''
import 'package:flutter/widgets.dart';

$declarations

abstract class StaticReceiverBase extends StatelessWidget {
  const StaticReceiverBase({
${defaults.map((value) => '    this.${value.name} = ${value.expression},').join('\n')}
    super.key,
  });

${defaults.map((value) => '  final ${value.type} ${value.name};').join('\n')}
}
''';

String _staticReceiverExpectation(int index, String expression) =>
    '_staticReceiverNoticeMountDefault$index = base.$expression;';

String _directMountImport(String prefix) => '''
import 'package:restage/restage.dart' as $prefix
    show
        RestageScreen,
        SurfaceScreenUnavailablePolicy,
        SurfaceScreenResolver,
        SurfaceScreenUnavailableError;
''';

String _mountQualifierSource({
  required String imports,
  required String declarations,
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart'
    show
        Screen,
        Surface,
        SurfaceScreenRef,
        SurfaceScreenEventContract,
        SurfaceScreenRuntimeProvenance,
        CapabilityManifest,
        LibraryRequirement;
$imports

part 'restage.generated/maintenance_notice.restage.g.dart';

@Screen(id: 'maintenance_notice', surface: Surface.general)
final class QualifierNotice extends StatelessWidget {
  const QualifierNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

$declarations
''';

CapabilityManifest _capabilities() => CapabilityManifest(
      builtInFloor: 1,
      requiredLibraries: const [],
    );

Future<StandaloneScreenContractInspection> _inspect(
  String source, {
  String className = 'MaintenanceNotice',
  Surface surface = Surface.general,
  String slug = 'maintenance_notice',
  int contractVersion = 1,
  CapabilityManifest? capabilities,
  Map<String, String> additionalSources = const {},
}) async {
  final assetId = AssetId('apps_examples', 'lib/maintenance_notice.dart');
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  readerWriter.testing.writeString(assetId, source);

  StandaloneScreenContractInspection? inspection;
  final sources = <String, String>{
    'apps_examples|lib/maintenance_notice.dart': source,
    ...additionalSources,
  };
  await testBuilder(
    _ScreenContractProbeBuilder((library, resolvedAssetId) async {
      final screen = library.classes.singleWhere(
        (candidate) => candidate.name == className,
      );
      final screenInput = (await inspectCanonicalScreenDeclarations(
        library,
        resolvedAssetId,
      ))
          .screens
          .singleWhere((candidate) => candidate.declaration == screen);
      inspection = inspectStandaloneScreenContract(
        ResolvedStandaloneScreenContractInput(
          assetId: resolvedAssetId,
          screen: screen,
          surface: surface,
          slug: slug,
          contractVersion: contractVersion,
          capabilities: capabilities ?? _capabilities(),
          rootParams: screenInput.build.rootParams,
          constructorParams: screenInput.build.constructorParams,
          mountConstructorProblem: screenInput.build.mountConstructorProblem,
        ),
      );
    }),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  return inspection!;
}

Future<Map<String, StandaloneScreenContractInspection>> _inspectAll(
  String source,
) async {
  final assetId = AssetId('apps_examples', 'lib/maintenance_notice.dart');
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  readerWriter.testing.writeString(assetId, source);

  final inspections = <String, StandaloneScreenContractInspection>{};
  await testBuilder(
    _ScreenContractProbeBuilder((library, resolvedAssetId) async {
      final result = await inspectCanonicalScreenDeclarations(
        library,
        resolvedAssetId,
      );
      for (final screenInput in result.screens) {
        final screen = screenInput.declaration;
        final name = screen.name;
        final surface = screenInput.surface;
        if (name == null || surface == null) continue;
        inspections[name] = inspectStandaloneScreenContract(
          ResolvedStandaloneScreenContractInput(
            assetId: resolvedAssetId,
            screen: screen,
            surface: surface,
            slug: screenInput.id,
            contractVersion: screenInput.version,
            capabilities: _capabilities(),
            rootParams: screenInput.build.rootParams,
            constructorParams: screenInput.build.constructorParams,
            mountConstructorProblem: screenInput.build.mountConstructorProblem,
          ),
        );
      }
    }),
    {'apps_examples|lib/maintenance_notice.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  return inspections;
}

String _generatedPartBody(String generated) {
  final trimmed = generated.trim();
  return trimmed.startsWith('part of ')
      ? trimmed.substring(trimmed.indexOf('\n') + 1).trim()
      : trimmed;
}

String _screenSource({
  required String className,
  required String annotation,
  String import = "import 'package:restage/restage.dart';",
  String flutterImport = "import 'package:flutter/widgets.dart';",
  String? constructor,
  String fields = '',
  String events = '',
  String extraDeclarations = '',
  String part = '',
}) =>
    '''
$flutterImport
$import
$part

$annotation
final class $className extends StatelessWidget {
${constructor ?? '  const $className({super.key});'}
$fields
$events
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

$extraDeclarations
''';

final class _ScreenContractProbeBuilder implements Builder {
  _ScreenContractProbeBuilder(this.onLibrary);

  final Future<void> Function(LibraryElement library, AssetId assetId)
      onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.screen_contract_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path != 'lib/maintenance_notice.dart') return;
    await onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}

Future<void> _assertGeneratedPartAnalyzes(
  String source,
  String generated, {
  Map<String, String> additionalSources = const {},
}) async {
  expect(
    await _generatedPartErrors(
      source,
      generated,
      additionalSources: additionalSources,
    ),
    isEmpty,
  );
}

Future<List<String>> _generatedPartErrors(
  String source,
  String generated, {
  Map<String, String> additionalSources = const {},
  List<String> sourceIds = const [
    'apps_examples|lib/maintenance_notice.dart',
  ],
}) async {
  const sourceId = 'apps_examples|lib/maintenance_notice.dart';
  const generatedId =
      'apps_examples|lib/restage.generated/maintenance_notice.restage.g.dart';
  // The package surface compiler never ships the header emitReferenceDart()
  // writes: it strips it and substitutes one resolved relative to the part's
  // placement (see _withoutPartHeader/_partOfHeader). Do the same here so
  // this proves the emitted body resolves as the compiler would place it,
  // not the header this call site bypasses.
  final withoutHeader = _generatedPartBody(generated);
  final relocated = "part of '../maintenance_notice.dart';\n\n$withoutHeader";
  final errors = <String>[];
  await resolveSources(
    {
      sourceId: source,
      generatedId: relocated,
      ...additionalSources,
    },
    (resolver) async {
      for (final id in sourceIds) {
        final library = await resolver.libraryFor(AssetId.parse(id));
        final resolved =
            await library.session.getResolvedLibraryByElement(library);
        if (resolved is! ResolvedLibraryResult) {
          throw StateError(
            'Generated standalone-screen fixture did not resolve.',
          );
        }
        errors.addAll([
          for (final unit in resolved.units)
            for (final diagnostic in unit.diagnostics)
              if (diagnostic.severity == Severity.error ||
                  (unit.path.endsWith(AssetId.parse(generatedId).path) &&
                      diagnostic.severity == Severity.warning))
                '$id: ${diagnostic.problemMessage.messageText(
                  includeUrl: false,
                )}',
        ]);
      }
    },
    resolverFor: sourceId,
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
  return errors;
}
