import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:crypto/crypto.dart';
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
      final empty = SurfaceScreenEventSchemaV1(events: const []);
      expect(
        SurfaceScreenEventContractHashV1.hash(empty),
        _emptyEventHash,
      );

      final multi = SurfaceScreenEventSchemaV1(
        events: [
          SurfaceScreenEventV1(
            id: 'submit',
            arguments: SurfaceScreenEventObjectArgumentsV1(
              const SurfaceScreenEventMapShapeV1(
                SurfaceScreenEventScalarShapeV1(
                  SurfaceScreenEventScalarKindV1.jsonValue,
                ),
              ),
            ),
          ),
          SurfaceScreenEventV1(
            id: 'évent',
            arguments: const SurfaceScreenEventValueArgumentsV1(
              SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKindV1.integer,
              ),
            ),
          ),
          SurfaceScreenEventV1(
            id: 'dismiss\n',
            arguments: const SurfaceScreenEventNoArgumentsV1(),
          ),
        ],
      );
      expect(
        SurfaceScreenEventContractHashV1.hash(multi),
        _multiEventHash,
      );

      expect(
        SurfaceScreenContractFingerprintV1.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: _capabilities(),
          eventContractHash: _zeroEventHash,
        ),
        _emptyContractFingerprint,
      );

      expect(
        SurfaceScreenContractFingerprintV1.hash(
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
        SurfaceScreenContractFingerprintV1.hash(
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
        '2dc905655681252051cc0f9e3ef5f8f575624532b12a79de1ad5a6e7fb1f2de5',
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
    _ScreenContractProbeBuilder((library, resolvedAssetId) {
      final screen = library.classes.singleWhere(
        (candidate) => candidate.name == className,
      );
      inspection = inspectStandaloneScreenContract(
        ResolvedStandaloneScreenContractInput(
          assetId: resolvedAssetId,
          screen: screen,
          surface: surface,
          slug: slug,
          contractVersion: contractVersion,
          capabilities: capabilities ?? _capabilities(),
        ),
      );
    }),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  return inspection!;
}

String _screenSource({
  required String className,
  required String annotation,
  String import = "import 'package:restage/restage.dart';",
  String events = '',
  String extraDeclarations = '',
  String part = '',
}) =>
    '''
import 'package:flutter/widgets.dart';
$import
$part

$annotation
final class $className extends StatelessWidget {
  const $className({super.key});
$events
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

$extraDeclarations
''';

final class _ScreenContractProbeBuilder implements Builder {
  _ScreenContractProbeBuilder(this.onLibrary);

  final void Function(LibraryElement library, AssetId assetId) onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.screen_contract_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}

Future<void> _assertGeneratedPartAnalyzes(
  String source,
  String generated,
) async {
  const sourceId = 'apps_examples|lib/maintenance_notice.dart';
  const generatedId =
      'apps_examples|lib/restage.generated/maintenance_notice.restage.g.dart';
  // The package surface compiler never ships the header emitReferenceDart()
  // writes: it strips it and substitutes one resolved relative to the part's
  // placement (see _withoutPartHeader/_partOfHeader). Do the same here so
  // this proves the emitted body resolves as the compiler would place it,
  // not the header this call site bypasses.
  final trimmed = generated.trim();
  final withoutHeader = trimmed.startsWith('part of ')
      ? trimmed.substring(trimmed.indexOf('\n') + 1).trim()
      : trimmed;
  final relocated = "part of '../maintenance_notice.dart';\n\n$withoutHeader";
  await resolveSources(
    {
      sourceId: source,
      generatedId: relocated,
    },
    (resolver) async {
      final library = await resolver.libraryFor(AssetId.parse(sourceId));
      final resolved =
          await library.session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) {
        throw StateError(
          'Generated standalone-screen fixture did not resolve.',
        );
      }
      final errors = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error)
              diagnostic.problemMessage.messageText(includeUrl: false),
      ];
      expect(errors, isEmpty, reason: relocated);
    },
    resolverFor: sourceId,
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
}
