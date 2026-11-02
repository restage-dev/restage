import 'dart:convert';
import 'dart:io';

import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _custom = WidgetLibrary.custom('example.data');
final _core = decodeCatalog(
  File(
    '../restage_core/lib/src/widget_catalog/catalog.json',
  ).readAsStringSync(),
);
final _catalog = Catalog(
  schemaVersion: kSupportedSchemaVersion,
  generatedAt: '',
  libraries: {
    ..._core.libraries,
    _custom: const LibraryInfo(version: '1', capabilityVersion: 1),
  },
  widgets: [
    ..._core.widgets,
    WidgetEntry(
      wireId: WireId('w9000'),
      name: 'DataCard',
      library: _custom,
      category: WidgetCategory.decoration,
      description: 'Application data',
      flutterType: 'package:example/data.dart#DataCard',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p9000'),
          name: 'data',
          type: PropertyType.dataReference,
          description: 'Data',
        ),
        PropertyEntry(
          wireId: WireId('p9001'),
          name: 'onTap',
          type: PropertyType.event,
          description: 'Action',
          constructorNullable: true,
        ),
      ],
    ),
  ],
  structuredTypes: _core.structuredTypes,
  unions: _core.unions,
);
final _events = SurfaceScreenEventSchema(
  events: [
    SurfaceScreenEvent(
      id: 'send',
      arguments: const SurfaceScreenEventValueArguments(
        SurfaceScreenEventScalarShapeV1(SurfaceScreenEventScalarKind.jsonValue),
      ),
    ),
  ],
);

rfw.RemoteWidgetLibrary _library(String declarations) => rfw.parseLibraryFile(
  'import restage.core; import example.data; $declarations',
);

SurfaceFitRequirementV1 _fit(
  rfw.RemoteWidgetLibrary library, {
  Catalog? catalog,
  SurfaceScreenHostDataSchema context =
      const SurfaceScreenHostDataSchema.empty(),
  required CapabilityManifest capabilities,
}) {
  catalog ??= _catalog;
  final resolution = rfw.RfwCatalogOccurrenceResolutionInput(
    artifactProvenance: 'data.artifact',
    sourceLibraryIdentity: 'data.library',
    sourceDeclarationIdentity: 'data.root',
    renderEntryNames: ['Paywall'],
    localSymbols: [
      for (final widget in library.widgets)
        rfw.RfwCatalogLocalSymbol(name: widget.name),
    ],
    catalogConstructors: [
      for (final widget in catalog.widgets)
        rfw.RfwCatalogConstructorProvenance(
          constructorName: widget.name,
          catalogLibraryNamespace: widget.library.namespace,
          catalogWidgetWireId: widget.wireId,
        ),
    ],
  );
  final blob = rfw.encodeLibraryBlob(library);
  final hash = CapabilitySidecar.hashBlob(blob);
  final payload = BlobSurfacePayload(
    minClient: capabilities.builtInFloor,
    blob: blob,
  );
  final publication = SurfacePublication(
    surface: Surface.paywall,
    slug: 'data',
    sourceKind: SurfaceSourceKind.paywall,
    payloadKind: SurfacePayloadKind.blob,
    payloadContentHash: payload.contentHash,
    compiledScreenContracts: {
      hash: SurfaceCompiledScreenContractV1(
        context: context,
        events: _events,
        catalogResolution: resolution,
        catalog: catalog,
      ),
    },
  );
  final sidecar = utf8.encode(
    jsonEncode(
      CapabilitySidecar(blobSha256: hash, manifest: capabilities).toJson(),
    ),
  );
  final manifest = SurfacePublicationManifest(
    publications: [
      SurfacePublicationManifestEntry(
        publication: publication,
        artifacts: [
          SurfacePublicationArtifact(
            contentHash: hash,
            id: 'data',
            path: 'assets/data.rfw',
            role: SurfacePublicationArtifactRole.screenBlob,
          ),
          SurfacePublicationArtifact(
            contentHash: CapabilitySidecar.hashBlob(sidecar),
            id: 'data',
            path: 'assets/data.capability.json',
            role: SurfacePublicationArtifactRole.capabilitySidecar,
          ),
        ],
      ),
    ],
  );
  return manifest
      .validateArtifactClosure({
        'assets/data.rfw': blob,
        'assets/data.capability.json': sidecar,
      })
      .single
      .projectFitRequirement();
}

CapabilityManifest _capability(
  rfw.RemoteWidgetLibrary library, {
  Catalog? catalog,
}) {
  final derived = deriveSurfaceCapability(library, catalog ?? _catalog);
  return CapabilityManifest(
    builtInFloor: derived.builtInFloor,
    requiredLibraries: derived.requiredLibraries,
  );
}

Map<String, Object?> _program(
  ValueProgram program,
  Map<String, Object?> captures,
) => {
  'version': 1,
  'program': program.encode(),
  'captures': captures,
};

rfw.RemoteWidgetLibrary _body(
  rfw.ConstructorCall root, {
  List<rfw.WidgetDeclaration> locals = const [],
}) => rfw.RemoteWidgetLibrary(
  [
    rfw.Import(rfw.LibraryName(['restage', 'core'])),
    rfw.Import(rfw.LibraryName(['example', 'data'])),
  ],
  [...locals, rfw.WidgetDeclaration('Paywall', null, root)],
);

Map<String, Object?> _nativeBuilder(Object? body, {String slot = 'color'}) {
  const type = ValueType.native('flutter.Color');
  return {
    'version': 1,
    'program': BuilderProgram(
      values: ValueProgram(
        nodes: [
          const ValueNode('capture', type, name: 'color'),
          ValueNode('local.write', type, inputs: [0], name: slot),
        ],
        root: 1,
        locals: {slot: type},
        captures: {'color': type},
        parameters: {'arg1': builderConstraintsValueType},
      ),
      result: const BuilderResult.let(1, BuilderResult.body(0)),
      bodyCount: 1,
    ).encode(),
    'captures': {
      'color': const NativeBindingContract(
        type: 'flutter.Color',
      ).reference('color'),
    },
    'bodies': [
      rfw.WidgetBuilderDeclaration('frame', body as rfw.ConstructorCall),
    ],
  };
}

rfw.RemoteWidgetLibrary _forwarded(
  Object? value,
  int count, {
  bool ordinary = false,
}) => _body(
  rfw.ConstructorCall('Forward0', {'color': value}),
  locals: [
    for (var index = 0; index < count; index++)
      rfw.WidgetDeclaration(
        'Forward$index',
        null,
        rfw.ConstructorCall(
          index == count - 1
              ? (ordinary ? 'DataCard' : 'ColoredBox')
              : 'Forward${index + 1}',
          {
            index == count - 1 && ordinary ? 'data' : 'color':
                rfw.ArgsReference(['color']),
          },
        ),
      ),
  ],
);

rfw.RemoteWidgetLibrary _recursiveForwarded(
  Object? value, {
  bool ordinary = false,
}) {
  Object? chain = {'color': value};
  for (var index = 0; index < 70; index++) {
    chain = {'next': chain};
  }
  return _body(
    rfw.ConstructorCall('Recursive', {'value': chain}),
    locals: [
      rfw.WidgetDeclaration(
        'Recursive',
        null,
        rfw.ConstructorCall('Column', {
          'children': [
            rfw.ConstructorCall(ordinary ? 'DataCard' : 'ColoredBox', {
              ordinary ? 'data' : 'color': rfw.ArgsReference([
                'value',
                'color',
              ]),
            }),
            rfw.ConstructorCall('Recursive', {
              'value': rfw.ArgsReference(['value', 'next']),
            }),
          ],
        }),
      ),
    ],
  );
}

rfw.RemoteWidgetLibrary _projectedForwarded(
  Object? value,
  int count,
  int padding, {
  required String widget,
  required String property,
}) {
  for (var index = 0; index < padding; index++) {
    value = {'v': value};
  }
  return _body(
    rfw.ConstructorCall('Forward0', {'value': value}),
    locals: [
      for (var index = 0; index < count; index++)
        rfw.WidgetDeclaration(
          'Forward$index',
          null,
          rfw.ConstructorCall(
            index == count - 1 ? widget : 'Forward${index + 1}',
            {
              index == count - 1 ? property : 'value': rfw.ArgsReference([
                'value',
                if (index == count - 1) ...List.filled(padding, 'v'),
              ]),
            },
          ),
        ),
    ],
  );
}

Catalog _configCatalog({StructuredField? payload}) => Catalog(
  schemaVersion: _catalog.schemaVersion,
  generatedAt: '',
  libraries: _catalog.libraries,
  widgets: [
    ..._catalog.widgets,
    WidgetEntry(
      wireId: WireId('w9001'),
      name: 'ConfigCard',
      library: _custom,
      category: WidgetCategory.decoration,
      description: 'Typed configuration',
      flutterType: 'package:example/data.dart#ConfigCard',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p9002'),
          name: 'config',
          type: PropertyType.structured,
          description: 'Configuration',
          structuredRef: WireIdRef(
            library: _custom.namespace,
            wireId: WireId('s9000'),
          ),
        ),
      ],
    ),
  ],
  structuredTypes: [
    ..._catalog.structuredTypes,
    StructuredEntry(
      wireId: WireId('s9000'),
      name: 'Config',
      library: _custom,
      description: 'Color with independent application data',
      sourceType: 'package:example/data.dart#Config',
      fields: [
        StructuredField(
          wireId: WireId('p9003'),
          name: 'color',
          type: PropertyType.color,
          description: 'Color',
        ),
        payload ??
            StructuredField(
              wireId: WireId('p9004'),
              name: 'payload',
              type: PropertyType.dataReference,
              description: 'Ordinary data',
            ),
      ],
      variants: [],
    ),
  ],
  unions: _catalog.unions,
);

rfw.RemoteWidgetLibrary _ordinaryTypedChild(
  Object? value,
  int count, {
  bool custom = false,
  Object? color = 4279383126,
  bool forwardedColor = false,
}) => _body(
  rfw.ConstructorCall('Forward0', {'payload': value, 'color': color}),
  locals: [
    for (var index = 0; index < count; index++)
      rfw.WidgetDeclaration(
        'Forward$index',
        null,
        index != count - 1
            ? rfw.ConstructorCall('Forward${index + 1}', {
                'payload': rfw.ArgsReference(['payload']),
                'color': rfw.ArgsReference(['color']),
              })
            : rfw.ConstructorCall(custom ? 'ConfigCard' : 'TextRich', {
                custom ? 'config' : 'textSpan': custom
                    ? {
                        'color': forwardedColor
                            ? rfw.ArgsReference(['color'])
                            : color,
                        'payload': rfw.ArgsReference(['payload']),
                      }
                    : {
                        'text': 'Hi',
                        'style': {
                          'color': forwardedColor
                              ? rfw.ArgsReference(['color'])
                              : color,
                          'fontFamilyFallback': rfw.ArgsReference(['payload']),
                        },
                      },
              }),
      ),
  ],
);

void main() {
  for (final custom in [false, true]) {
    final catalog = custom ? _configCatalog() : _catalog;
    final value = custom
        ? {
            'kind': 'nativeLocal',
            'slot': 'ordinary',
            'type': 'application.record',
            'nullable': false,
          }
        : ['Arial', 'Fallback'];
    for (final publication in [false, true]) {
      test(
        'ordinary typed child ${custom ? 'data' : 'font list'} stays inert at ${publication ? 'publication' : 'catalog'} boundary beside Color',
        () {
          final shallow = _ordinaryTypedChild(value, 3, custom: custom);
          final expected = _capability(shallow, catalog: catalog);
          for (final count in [3, 60]) {
            final library = _ordinaryTypedChild(value, count, custom: custom);
            final capability = _capability(library, catalog: catalog);
            expect(capability.toJson(), expected.toJson());
            expect(capability.builtInFloor, lessThan(24));
            if (publication) {
              expect(
                _fit(
                  library,
                  catalog: catalog,
                  capabilities: capability,
                ).requiredContext.inputs,
                isEmpty,
              );
            } else {
              expect(validateModelAgainstCatalog(library, catalog), isEmpty);
            }
          }
        },
      );
    }
    test(
      'ordinary typed child ${custom ? 'data' : 'font list'} retains native sibling authority',
      () {
        const native = NativeBindingContract(type: 'flutter.Color');
        final valid = _ordinaryTypedChild(
          value,
          60,
          custom: custom,
          color: native.reference('color'),
        );
        expect(validateModelAgainstCatalog(valid, catalog), isEmpty);
        final fit = _fit(
          valid,
          catalog: catalog,
          capabilities: _capability(valid, catalog: catalog),
          context: SurfaceScreenHostDataSchema({
            'color': const SurfaceScreenHostDataNativeBindingShapeV1(native),
          }),
        );
        expect(fit.requiredContext.inputs.keys, ['color']);
        for (final forwarded in [false, true]) {
          final invalid = _ordinaryTypedChild(
            value,
            60,
            custom: custom,
            color: const NativeBindingContract(
              type: 'flutter.Key',
            ).reference('wrong'),
            forwardedColor: forwarded,
          );
          expect(
            () => validateModelAgainstCatalog(invalid, catalog),
            throwsFormatException,
          );
          expect(
            () => _fit(
              invalid,
              catalog: catalog,
              capabilities: CapabilityManifest(
                builtInFloor: 24,
                requiredLibraries: [],
              ),
            ),
            throwsFormatException,
          );
        }
      },
    );
  }
  for (final record in [false, true]) {
    test(
      'ordinary typed child honors admitted opaque ${record ? 'record' : 'map'} shape',
      () {
        final catalog = _configCatalog(
          payload: StructuredField(
            wireId: WireId('p9004'),
            name: 'payload',
            type: PropertyType.unknown,
            description: 'Opaque JSON value',
            valueShape: record
                ? ScalarShape.opaqueRecord()
                : ScalarShape.opaqueStringKeyedMap(),
          ),
        );
        for (final count in [3, 60]) {
          final library = _ordinaryTypedChild(
            {
              'item': {
                'kind': 'nativeLocal',
                'slot': 'ordinary',
                'type': 'application.record',
                'nullable': false,
              },
            },
            count,
            custom: true,
          );
          expect(validateModelAgainstCatalog(library, catalog), isEmpty);
          final capability = _capability(library, catalog: catalog);
          expect(capability.builtInFloor, lessThan(24));
          expect(
            _fit(
              library,
              catalog: catalog,
              capabilities: capability,
            ).requiredContext.inputs,
            isEmpty,
          );
        }
      },
    );
  }
  for (final union in [false, true]) {
    test(
      'ordinary typed child does not infer ordinary from missing ${union ? 'union' : 'structured'} metadata',
      () {
        final catalog = _configCatalog(
          payload: StructuredField(
            wireId: WireId('p9004'),
            name: 'payload',
            type: PropertyType.structured,
            description: 'Unresolved metadata',
            structuredRef: union
                ? null
                : WireIdRef(
                    library: _custom.namespace,
                    wireId: WireId('s9999'),
                  ),
            unionRef: union
                ? WireIdRef(library: _custom.namespace, wireId: WireId('u9999'))
                : null,
            valueShape: union
                ? UnionShape(
                    propertyType: PropertyType.structured,
                    unionRef: WireIdRef(
                      library: _custom.namespace,
                      wireId: WireId('u9999'),
                    ),
                  )
                : null,
          ),
        );
        final library = _ordinaryTypedChild(
          {'value': 'data'},
          60,
          custom: true,
        );
        expect(
          () => validateModelAgainstCatalog(library, catalog),
          throwsFormatException,
        );
        expect(
          () => _fit(
            library,
            catalog: catalog,
            capabilities: CapabilityManifest(
              builtInFloor: 24,
              requiredLibraries: [],
            ),
          ),
          throwsFormatException,
        );
      },
    );
  }
  for (final recipe in <(String, String, String, Object? Function(Object?))>[
    (
      'shape side map',
      'ClipPathShape',
      'shape',
      (color) => {
        'type': 'rounded',
        'side': {'color': color},
      },
    ),
    (
      'gradient color list',
      'Container',
      'gradient',
      (color) => {
        'type': 'linear',
        'colors': [color, color],
      },
    ),
    (
      'span style map',
      'TextRich',
      'textSpan',
      (color) => {
        'text': 'Hi',
        'style': {'color': color},
      },
    ),
    (
      'nested discriminator',
      'TextRich',
      'textSpan',
      (color) => {
        'text': 'Hi',
        'style': {
          'foreground': {
            'colorFilter': {
              'type': 'mode',
              'color': color,
              'blendMode': 'srcIn',
            },
          },
        },
      },
    ),
  ]) {
    for (final publication in [false, true]) {
      test(
        'nested projection preserves ${recipe.$1} authority at ${publication ? 'publication' : 'catalog'} bound edges',
        () {
          final control = _projectedForwarded(
            recipe.$4(4279383126),
            3,
            1,
            widget: recipe.$2,
            property: recipe.$3,
          );
          expect(validateModelAgainstCatalog(control, _catalog), isEmpty);
          expect(
            _fit(
              control,
              capabilities: _capability(control),
            ).requiredContext.inputs,
            isEmpty,
          );
          final wrong = const NativeBindingContract(
            type: 'flutter.Key',
          ).reference('wrong');
          for (final (count, padding) in [
            (3, 1),
            (40, 0),
            (41, 0),
            (41, 4),
            (42, 0),
            (42, 1),
            (43, 0),
            (60, 0),
          ]) {
            final library = _projectedForwarded(
              recipe.$4(wrong),
              count,
              padding,
              widget: recipe.$2,
              property: recipe.$3,
            );
            void admit() {
              if (publication) {
                _fit(
                  library,
                  capabilities: CapabilityManifest(
                    builtInFloor: 24,
                    requiredLibraries: [],
                  ),
                );
              } else {
                validateModelAgainstCatalog(library, _catalog);
              }
            }

            expect(
              admit,
              throwsFormatException,
              reason: 'count=$count padding=$padding',
            );
          }
        },
      );
    }
    test('nested projection leaves ordinary ${recipe.$1} data inert', () {
      final value = recipe.$4(
        const NativeBindingContract(type: 'flutter.Key').reference('wrong'),
      );
      for (final (count, padding) in [(42, 1), (41, 4), (60, 0)]) {
        final library = _projectedForwarded(
          value,
          count,
          padding,
          widget: 'DataCard',
          property: 'data',
        );
        expect(validateModelAgainstCatalog(library, _catalog), isEmpty);
        final capability = _capability(library);
        expect(capability.builtInFloor, lessThan(24));
        expect(
          _fit(library, capabilities: capability).requiredContext.inputs,
          isEmpty,
        );
      }
    });
  }
  test('exhausted union projection retains nested callback obligations', () {
    rfw.RemoteWidgetLibrary forwarded(int count, {bool invalid = false}) =>
        _body(
          rfw.ConstructorCall('Forward0', {
            'delegate': {
              '_s': 's0033',
              if (invalid)
                'findChildIndexCallback': {
                  'nativeKeyIndex': const NativeBindingContract(
                    type: 'flutter.Color',
                  ).reference('wrong'),
                },
            },
          }),
          locals: [
            for (var index = 0; index < count; index++)
              rfw.WidgetDeclaration(
                'Forward$index',
                null,
                rfw.ConstructorCall(
                  index == count - 1 ? 'GridViewCustom' : 'Forward${index + 1}',
                  index == count - 1
                      ? {
                          'gridDelegate': {
                            '_s': 's0034',
                            'crossAxisCount': 2,
                          },
                          'childrenDelegate': rfw.ArgsReference(['delegate']),
                        }
                      : {
                          'delegate': rfw.ArgsReference(['delegate']),
                        },
                ),
              ),
          ],
        );
    final control = forwarded(3);
    expect(validateModelAgainstCatalog(control, _catalog), isEmpty);
    expect(
      _fit(control, capabilities: _capability(control)).requiredContext.inputs,
      isEmpty,
    );
    for (final count in [3, 60]) {
      final invalid = forwarded(count, invalid: true);
      expect(
        () => validateModelAgainstCatalog(invalid, _catalog),
        throwsFormatException,
      );
      expect(
        () => _fit(
          invalid,
          capabilities: CapabilityManifest(
            builtInFloor: 24,
            requiredLibraries: [],
          ),
        ),
        throwsFormatException,
      );
    }
  });
  test('bounded recursive fallback cannot grant native authority', () {
    final library = _recursiveForwarded(
      const NativeBindingContract(type: 'flutter.Color').reference('absent'),
    );
    expect(
      () => validateModelAgainstCatalog(library, _catalog),
      throwsFormatException,
    );
    expect(
      () => _fit(
        library,
        capabilities: CapabilityManifest(
          builtInFloor: 24,
          requiredLibraries: [],
        ),
      ),
      throwsFormatException,
    );
  });
  test('bounded recursive fallback leaves ordinary data inert', () {
    final library = _recursiveForwarded(
      const NativeBindingContract(type: 'flutter.Color').reference('absent'),
      ordinary: true,
    );
    expect(validateModelAgainstCatalog(library, _catalog), isEmpty);
    final capabilities = _capability(library);
    expect(capabilities.builtInFloor, lessThan(24));
    expect(
      _fit(library, capabilities: capabilities).requiredContext.inputs,
      isEmpty,
    );
  });
  for (final entry in <String, Object?>{
    'wrong nominal type': const NativeBindingContract(
      type: 'flutter.Key',
    ).reference('wrong'),
    'undeclared binding': const NativeBindingContract(
      type: 'flutter.Color',
    ).reference('absent'),
    'orphan local': {
      'kind': 'nativeLocal',
      'slot': 'absent',
      'type': 'flutter.Color',
      'nullable': false,
    },
  }.entries) {
    test(
      'bounded native forwarding refuses ${entry.key} after projection exhaustion',
      () {
        final shallow = _forwarded(entry.value, 3);
        if (entry.key != 'undeclared binding') {
          expect(
            () => validateModelAgainstCatalog(shallow, _catalog),
            throwsFormatException,
          );
        }
        expect(
          () => _fit(
            shallow,
            capabilities: CapabilityManifest(
              builtInFloor: 24,
              requiredLibraries: [],
            ),
          ),
          throwsFormatException,
        );
        final deep = _forwarded(entry.value, 60);
        expect(
          () => validateModelAgainstCatalog(deep, _catalog),
          throwsFormatException,
        );
        expect(
          () => _fit(
            deep,
            capabilities: CapabilityManifest(
              builtInFloor: 24,
              requiredLibraries: [],
            ),
          ),
          throwsFormatException,
        );
      },
    );
    test('deep ordinary forwarding keeps ${entry.key} inert', () {
      final library = _forwarded(entry.value, 60, ordinary: true);
      expect(validateModelAgainstCatalog(library, _catalog), isEmpty);
      final capabilities = _capability(library);
      expect(capabilities.builtInFloor, lessThan(24));
      expect(
        _fit(library, capabilities: capabilities).requiredContext.inputs,
        isEmpty,
      );
    });
  }
  test(
    'shallow native forwarding keeps valid binding and formal reference proof',
    () {
      const native = NativeBindingContract(type: 'flutter.Color');
      final library = _forwarded(native.reference('color'), 3);
      final context = SurfaceScreenHostDataSchema({
        'color': const SurfaceScreenHostDataNativeBindingShapeV1(native),
      });
      expect(validateModelAgainstCatalog(library, _catalog), isEmpty);
      expect(
        _fit(
          library,
          capabilities: _capability(library),
          context: context,
        ).requiredContext.inputs.keys,
        ['color'],
      );
    },
  );
  test('ordinary control fixture qualifies its complete publication', () {
    final library = _library(
      'widget Paywall = DataCard(data: {label: "application-value"}, onTap: event "send" {value: {label: "application-value"}});',
    );
    expect(validateModelAgainstCatalog(library, _catalog), isEmpty);
    final fit = _fit(library, capabilities: _capability(library));
    expect(fit.requiredContext.inputs, isEmpty);
  });
  test(
    'legacy scalar programs and JSON context colors keep their existing route',
    () {
      const scalar = ValueProgram(
        nodes: [ValueNode('literal', ValueType.integer, value: 4279383126)],
        root: 0,
      );
      final computed = _body(
        rfw.ConstructorCall('ColoredBox', {'color': _program(scalar, {})}),
      );
      expect(validateModelAgainstCatalog(computed, _catalog), isEmpty);
      expect(
        _fit(
          computed,
          capabilities: _capability(computed),
        ).requiredContext.inputs,
        isEmpty,
      );
      expect(nativeBindingsNeedInstalledHost(computed, _catalog), isFalse);
      final referenced = _body(
        rfw.ConstructorCall('ColoredBox', {
          'color': rfw.DataReference(['context', 'argb']),
        }),
      );
      final context = SurfaceScreenHostDataSchema({
        'argb': const SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.integer,
        ),
      });
      expect(validateModelAgainstCatalog(referenced, _catalog), isEmpty);
      final fit = _fit(
        referenced,
        capabilities: _capability(referenced),
        context: context,
      );
      expect(
        fit.requiredContext.inputs['argb']!.toJson(),
        context.inputs['argb']!.toJson(),
      );
    },
  );

  test(
    'native programs must return the native type of their actual consumer',
    () {
      const type = ValueType.native('flutter.Key');
      const program = ValueProgram(
        nodes: [ValueNode('capture', type, name: 'key')],
        root: 0,
        captures: {'key': type},
      );
      final library = _body(
        rfw.ConstructorCall('ColoredBox', {
          'color': _program(program, {
            'key': const NativeBindingContract(
              type: 'flutter.Key',
            ).reference('key'),
          }),
        }),
      );
      expect(
        () => validateModelAgainstCatalog(library, _catalog),
        throwsFormatException,
      );
    },
  );

  test(
    'malformed actual native slots fail catalog validation before publication',
    () {
      final library = _body(
        rfw.ConstructorCall('ColoredBox', {
          'color': const NativeBindingContract(
            type: 'flutter.Key',
          ).reference('wrong'),
        }),
      );
      expect(
        () => validateModelAgainstCatalog(library, _catalog),
        throwsFormatException,
      );
    },
  );
  test(
    'actual native consumers retain exact structure nominal type and host authority',
    () {
      const native = NativeBindingContract(type: 'flutter.Color');
      final good = _body(
        rfw.ConstructorCall('ColoredBox', {'color': native.reference('color')}),
      );
      final context = SurfaceScreenHostDataSchema({
        'color': const SurfaceScreenHostDataNativeBindingShapeV1(native),
      });
      expect(validateModelAgainstCatalog(good, _catalog), isEmpty);
      expect(
        _fit(
          good,
          capabilities: _capability(good),
          context: context,
        ).requiredContext.inputs.keys,
        ['color'],
      );
      expect(
        () => _fit(good, capabilities: _capability(good)),
        throwsFormatException,
      );
      for (final bad in [
        {...native.reference('color'), 'extra': 1},
        const NativeBindingContract(type: 'flutter.Key').reference('color'),
        {
          'kind': 'nativeLocal',
          'slot': 'color',
          'type': 'flutter.Color',
          'nullable': false,
        },
      ]) {
        final library = _body(
          rfw.ConstructorCall('ColoredBox', {'color': bad}),
        );
        expect(
          () => validateModelAgainstCatalog(library, _catalog),
          throwsFormatException,
        );
        expect(
          () => _fit(
            library,
            capabilities: CapabilityManifest(
              builtInFloor: 24,
              requiredLibraries: [],
            ),
            context: context,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'typed native collection visits every sibling and rejects conflicting bindings',
    () {
      const native = NativeBindingContract(type: 'flutter.Color');
      final first = native.reference('first');
      for (final second in [
        {...native.reference('second'), 'extra': 1},
        const NativeBindingContract(type: 'flutter.Key').reference('second'),
        native.reference('second'),
      ]) {
        final library = _body(
          rfw.ConstructorCall('TextRich', {
            'textSpan': {
              'text': 'Hi',
              'style': {
                'color': first,
                'background': {'color': second},
              },
            },
          }),
        );
        final context = SurfaceScreenHostDataSchema({
          'first': const SurfaceScreenHostDataNativeBindingShapeV1(native),
        });
        if (second.containsKey('extra') || second['type'] != 'flutter.Color') {
          expect(
            () => validateModelAgainstCatalog(library, _catalog),
            throwsFormatException,
          );
        }
        expect(
          () => _fit(
            library,
            capabilities: CapabilityManifest(
              builtInFloor: 24,
              requiredLibraries: [],
            ),
            context: context,
          ),
          throwsFormatException,
        );
      }
      final conflict = _body(
        rfw.ConstructorCall('TextRich', {
          'textSpan': {
            'text': 'Hi',
            'style': {'color': first},
            'recognizer': {
              'borrowed': const NativeBindingContract(
                type: 'flutter.GestureRecognizer',
              ).reference('first'),
            },
          },
        }),
      );
      expect(
        () => validateModelAgainstCatalog(conflict, _catalog),
        throwsFormatException,
      );
    },
  );

  test(
    'nominal native captures and ordinary records keep distinct authority',
    () {
      const native = NativeBindingContract(type: 'flutter.Color');
      for (final list in [false, true]) {
        final aggregate = list
            ? const ValueType('list', item: ValueType.native('flutter.Color'))
            : const ValueType(
                'record',
                fields: {'value': ValueType.native('flutter.Color')},
              );
        final nodes = <ValueNode>[
          ValueNode('capture', aggregate, name: 'aggregate'),
        ];
        if (list) {
          nodes.add(const ValueNode('literal', ValueType.integer, value: 0));
          nodes.add(
            const ValueNode(
              'index',
              ValueType.native('flutter.Color'),
              inputs: [0, 1],
            ),
          );
        } else {
          nodes.add(
            const ValueNode(
              'field',
              ValueType.native('flutter.Color'),
              inputs: [0],
              name: 'value',
            ),
          );
        }
        final program = ValueProgram(
          nodes: nodes,
          root: nodes.length - 1,
          captures: {'aggregate': aggregate},
        );
        for (final valid in [false, true]) {
          final reference = valid
              ? native.reference('color')
              : const NativeBindingContract(
                  type: 'flutter.Key',
                ).reference('color');
          final library = _body(
            rfw.ConstructorCall('ColoredBox', {
              'color': _program(program, {
                'aggregate': list ? [reference] : {'value': reference},
              }),
            }),
          );
          expect(
            () => validateModelAgainstCatalog(library, _catalog),
            throwsFormatException,
          );
        }
      }
      const nativeProgram = ValueProgram(
        nodes: [
          ValueNode(
            'capture',
            ValueType.native('flutter.Color'),
            name: 'color',
          ),
        ],
        root: 0,
        captures: {'color': ValueType.native('flutter.Color')},
      );
      final nativeLibrary = _body(
        rfw.ConstructorCall('ColoredBox', {
          'color': _program(nativeProgram, {
            'color': native.reference('color'),
          }),
        }),
      );
      expect(validateModelAgainstCatalog(nativeLibrary, _catalog), isEmpty);
      expect(
        _fit(
          nativeLibrary,
          capabilities: _capability(nativeLibrary),
          context: SurfaceScreenHostDataSchema({
            'color': const SurfaceScreenHostDataNativeBindingShapeV1(native),
          }),
        ).requiredContext.inputs.keys,
        ['color'],
      );
      const ordinary = ValueType(
        'record',
        fields: {
          'kind': ValueType.string,
          'key': ValueType.string,
          'type': ValueType.string,
          'nullable': ValueType.boolean,
        },
      );
      const program = ValueProgram(
        nodes: [
          ValueNode('capture', ordinary, name: 'data'),
          ValueNode('field', ValueType.string, inputs: [0], name: 'key'),
        ],
        root: 1,
        captures: {'data': ordinary},
      );
      final library = _body(
        rfw.ConstructorCall('Text', {
          'text': _program(program, {'data': native.reference('ordinary')}),
        }),
      );
      expect(validateModelAgainstCatalog(library, _catalog), isEmpty);
      expect(
        _fit(
          library,
          capabilities: _capability(library),
        ).requiredContext.inputs,
        isEmpty,
      );
    },
  );

  test('native local forwarding retains each original lexical occurrence', () {
    final shared = {
      'kind': 'nativeLocal',
      'slot': 'color',
      'type': 'flutter.Color',
      'nullable': false,
    };
    final forwarding = rfw.WidgetDeclaration(
      'Forward',
      null,
      rfw.ConstructorCall('ColoredBox', {
        'color': rfw.ArgsReference(['color']),
      }),
    );
    final child = rfw.ConstructorCall('Forward', {'color': shared});
    final validBuilder = rfw.ConstructorCall('LayoutBuilder', {
      'builder': _nativeBuilder(child),
    });
    final invalidBuilder = rfw.ConstructorCall('LayoutBuilder', {
      'builder': _nativeBuilder(child, slot: 'other'),
    });
    final ordinary = rfw.ConstructorCall('DataCard', {'data': shared});
    final valid = _body(
      rfw.ConstructorCall('Column', {
        'children': [ordinary, validBuilder],
      }),
      locals: [forwarding],
    );
    expect(validateModelAgainstCatalog(valid, _catalog), isEmpty);
    expect(
      _fit(
        valid,
        capabilities: _capability(valid),
        context: SurfaceScreenHostDataSchema({
          'color': const SurfaceScreenHostDataNativeBindingShapeV1(
            NativeBindingContract(type: 'flutter.Color'),
          ),
        }),
      ).requiredContext.inputs.keys,
      ['color'],
    );
    for (final children in [
      [validBuilder, invalidBuilder],
      [invalidBuilder, validBuilder],
    ]) {
      final library = _body(
        rfw.ConstructorCall('Column', {'children': children}),
        locals: [forwarding],
      );
      expect(
        () => validateModelAgainstCatalog(library, _catalog),
        throwsFormatException,
      );
    }
  });

  test(
    'native event host signatures are qualified by the actual event slot',
    () {
      const native = NativeBindingContract(type: kNativeVoidCallbackType);
      final library = _body(
        rfw.ConstructorCall('DataCard', {
          'onTap': {'nativeEvent': native.reference('callback')},
        }),
      );
      expect(validateModelAgainstCatalog(library, _catalog), isEmpty);
      final capabilities = _capability(library);
      expect(capabilities.builtInFloor, 24);
      expect(
        _fit(
          library,
          capabilities: capabilities,
          context: SurfaceScreenHostDataSchema({
            'callback': const SurfaceScreenHostDataNativeBindingShapeV1(native),
          }),
        ).requiredContext.inputs.keys,
        ['callback'],
      );
      expect(
        () => _fit(
          library,
          capabilities: capabilities,
          context: SurfaceScreenHostDataSchema({
            'callback': const SurfaceScreenHostDataNativeBindingShapeV1(
              NativeBindingContract(type: '(int)->void'),
            ),
          }),
        ),
        throwsFormatException,
      );
    },
  );

  const values = [
    '{kind: "nativeBinding", key: "ordinary", type: "record", nullable: false}',
    '{kind: "nativeLocal", slot: "ordinary", type: "record", nullable: false}',
    '{nativeEvent: "application-value"}',
    '{kind: "nativeBinding", description: "application-value"}',
    '{kind: "nativeLocal", description: "application-value"}',
  ];
  for (final (location, emit) in <(String, String Function(String))>[
    (
      'event arguments',
      (value) =>
          'widget Paywall = DataCard(onTap: event "send" {value: $value});',
    ),
    ('custom data', (value) => 'widget Paywall = DataCard(data: $value);'),
    (
      'initial state',
      (value) => 'widget Paywall {payload: $value} = DataCard();',
    ),
    (
      'unused span field',
      (value) =>
          'widget Paywall = TextRich(textSpan: {text: "Hi", unused: $value});',
    ),
    (
      'forwarded custom data',
      (value) =>
          'widget Card = DataCard(data: args.payload); widget Paywall = Card(payload: $value);',
    ),
  ]) {
    for (final value in values) {
      test('$location preserves ordinary map $value', () {
        final library = _library(emit(value));
        final control = _library(emit('{label: "application-value"}'));
        expect(validateModelAgainstCatalog(library, _catalog), isEmpty);
        final expected = _capability(control);
        final actual = _capability(library);
        expect(actual.toJson(), expected.toJson());
        expect(nativeBindingsNeedInstalledHost(library, _catalog), isFalse);
        final fit = _fit(library, capabilities: expected);
        expect(fit.requiredContext.inputs, isEmpty);
        expect(fit.capabilities.toJson(), expected.toJson());
      });
    }
  }
}
