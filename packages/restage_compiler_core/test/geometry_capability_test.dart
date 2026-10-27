import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _custom = WidgetLibrary.custom('example.geometry');
final _details = WireIdRef(library: _custom.namespace, wireId: WireId('s0001'));

Catalog _catalog(PropertyType type,
        {bool nested = false, bool builtIn = false}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        WidgetLibrary.core: const LibraryInfo(version: '1'),
        _custom: const LibraryInfo(version: '1', capabilityVersion: 1),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'Probe',
          library: builtIn ? WidgetLibrary.core : _custom,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:example/probe.dart#Probe',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'value',
                type: nested ? PropertyType.structured : type,
                description: '',
                structuredRef: nested ? _details : null)
          ],
        )
      ],
      structuredTypes: [
        if (nested)
          StructuredEntry(
            wireId: _details.wireId,
            name: 'Details',
            library: _custom,
            description: '',
            sourceType: 'package:example/probe.dart#Details',
            variants: const [],
            fields: [
              StructuredField(
                  wireId: WireId.unallocatedProperty,
                  name: 'geometry',
                  type: type,
                  description: '')
            ],
          )
      ],
    );

SurfaceCapabilityDerivation _derive(PropertyType type, Object? value,
    {bool nested = false,
    bool builtIn = false,
    int depth = 0,
    bool recursive = false}) {
  Object? argument = nested ? {'geometry': value} : value;
  final widgets = <rfw.WidgetDeclaration>[
    rfw.WidgetDeclaration(
        'Root',
        null,
        rfw.ConstructorCall(depth == 0 && !recursive ? 'Probe' : 'Local0',
            {'value': argument})),
    for (var i = 0; i < depth; i++)
      rfw.WidgetDeclaration(
          'Local$i',
          null,
          rfw.ConstructorCall(i + 1 == depth ? 'Probe' : 'Local${i + 1}', {
            'value': const rfw.ArgsReference(['value'])
          })),
    if (recursive)
      rfw.WidgetDeclaration(
          'Local0',
          null,
          rfw.Switch(const rfw.DataReference(['continue']), {
            true: rfw.ConstructorCall('Local0', {
              'value': const rfw.ArgsReference(['value'])
            }),
            false: rfw.ConstructorCall('Probe', {
              'value': const rfw.ArgsReference(['value'])
            }),
          })),
  ];
  return deriveSurfaceCapability(rfw.RemoteWidgetLibrary(const [], widgets),
      _catalog(type, nested: nested, builtIn: builtIn));
}

void _expect(PropertyType type, Object? value, int floor, {int factory = 1}) {
  for (final nested in [false, true]) {
    for (final path in [(0, false), (2, false), (0, true)]) {
      final result = _derive(type, value,
          nested: nested, depth: path.$1, recursive: path.$2);
      final reason = '$type $value nested=$nested path=$path';
      expect(result.builtInFloor, floor, reason: reason);
      expect(result.requiredLibraries.single.minGenerated, factory,
          reason: reason);
      final gate = BlobRenderCapabilityGate.evaluate(
          required: CapabilityManifest(
              builtInFloor: result.builtInFloor,
              requiredLibraries: result.requiredLibraries),
          installed: InstalledCapability(
              builtInCatalogVersion: 16,
              installedLibraries: [
                InstalledLibrary(
                    namespace: _custom.namespace, version: 1, generated: 3),
              ]));
      expect(gate.accepted, floor <= 16, reason: reason);
      final oldFactory = BlobRenderCapabilityGate.evaluate(
          required: CapabilityManifest(
              builtInFloor: result.builtInFloor,
              requiredLibraries: result.requiredLibraries),
          installed: InstalledCapability(
              builtInCatalogVersion: 23,
              installedLibraries: [
                InstalledLibrary(
                    namespace: _custom.namespace, version: 1, generated: 2),
              ]));
      expect(oldFactory.accepted, factory <= 2, reason: reason);
    }
  }
  expect(_derive(type, value, builtIn: true).builtInFloor, floor);
}

void main() {
  test(
      'geometry forms preserve legacy and require only their actual decoder version',
      () {
    _expect(PropertyType.edgeInsets, [1.0, 2.0, 3.0, 4.0], 1);
    _expect(PropertyType.edgeInsets, {'left': 1.0, 'top': 2.0}, 17);
    _expect(PropertyType.edgeInsets, {'start': 1.0, 'end': 3.0}, 17);
    _expect(
        PropertyType.shapeBorder,
        {
          'type': 'rounded',
          'borderRadius': {'topLeft': 3}
        },
        1);
    _expect(
        PropertyType.shapeBorder, {'type': 'rounded', 'borderRadius': 3}, 1);
    _expect(
        PropertyType.shapeBorder,
        {
          'type': 'rounded',
          'borderRadius': {'topStart': 3}
        },
        17);
    _expect(
        PropertyType.shapeBorder,
        [
          {
            'type': 'beveled',
            'borderRadius': {'bottomEnd': 3}
          }
        ],
        17);
    for (final alignment in [
      {'x': 1, 'y': 0},
      {'x': 1.0, 'y': 0.0}
    ]) {
      _expect(
          PropertyType.decorationImage,
          {
            'image': {'kind': 'asset', 'src': 'a.png'},
            'alignment': alignment
          },
          1);
    }
    _expect(
        PropertyType.decorationImage,
        {
          'image': {'kind': 'asset', 'src': 'a.png'},
          'alignment': {'start': 1.0, 'y': 0.0}
        },
        17);
    _expect(
        PropertyType.gradient,
        {
          'type': 'linear',
          'begin': {'start': 1.0, 'y': 0.0}
        },
        1);
    _expect(PropertyType.gradient,
        {'type': 'radial', 'radius': 1.0, 'focalRadius': 0.0}, 1);
    for (final field in ['radius', 'focalRadius']) {
      _expect(PropertyType.gradient, {'type': 'radial', field: 1}, 17,
          factory: 3);
    }
    for (final field in ['startAngle', 'endAngle']) {
      _expect(PropertyType.gradient, {'type': 'sweep', field: 1}, 17,
          factory: 3);
    }
  });

  test('geometry ignores unread keys and preserves typed uncertainty', () {
    _expect(
        PropertyType.shapeBorder,
        {
          'type': 'circle',
          'borderRadius': {'topStart': 3}
        },
        1);
    _expect(PropertyType.gradient, {'type': 'linear', 'radius': 1}, 1);
    _expect(PropertyType.gradient, {'type': 'custom', 'startAngle': 1}, 1);
    _expect(
        PropertyType.decorationImage,
        {
          'image': {'kind': 'unknown', 'src': 'a.png'},
          'alignment': {'start': 1.0, 'y': 0.0}
        },
        1);
    _expect(
        PropertyType.decorationImage,
        {
          'image': {'kind': 'asset', 'src': 'a.png'},
          'alignment': {'start': 1, 'x': 1, 'y': 0}
        },
        1);
    _expect(PropertyType.unknown, {'left': 1.0, 'topStart': 1.0}, 1);
    expect(
        _derive(PropertyType.edgeInsets, const rfw.DataReference(['insets']))
            .builtInFloor,
        17);
    for (final type in [PropertyType.gradient, PropertyType.shapeBorder]) {
      for (final recursive in [false, true]) {
        final result = _derive(type, const rfw.DataReference(['value']),
            recursive: recursive);
        expect(result.builtInFloor, greaterThanOrEqualTo(17));
        expect(result.requiredLibraries.single.minGenerated,
            recursive || type == PropertyType.gradient ? 3 : 1);
      }
    }
  });

  test(
      'geometry follows catalog lists and selected union fields without scanning maps',
      () {
    final base = _catalog(PropertyType.edgeInsets, nested: true);
    final choice =
        WireIdRef(library: _custom.namespace, wireId: WireId('u0001'));
    final rawRef =
        WireIdRef(library: _custom.namespace, wireId: WireId('s0002'));
    for (final union in [false, true]) {
      final property = PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'value',
          type: PropertyType.structured,
          description: '',
          valueShape: union
              ? UnionShape(
                  propertyType: PropertyType.structured, unionRef: choice)
              : ListShape.opaqueStructured(_details));
      final widget = base.widgets.single;
      final catalog = Catalog(
          schemaVersion: base.schemaVersion,
          generatedAt: base.generatedAt,
          libraries: base.libraries,
          widgets: [
            WidgetEntry(
                wireId: widget.wireId,
                name: widget.name,
                library: widget.library,
                category: widget.category,
                description: '',
                flutterType: widget.flutterType,
                childrenSlot: widget.childrenSlot,
                properties: [property])
          ],
          structuredTypes: [
            ...base.structuredTypes,
            StructuredEntry(
                wireId: rawRef.wireId,
                name: 'Raw',
                library: _custom,
                description: '',
                sourceType: 'package:example/probe.dart#Raw',
                variants: const [],
                fields: [
                  StructuredField(
                      wireId: WireId.unallocatedProperty,
                      name: 'geometry',
                      type: PropertyType.dataReference,
                      description: '')
                ])
          ],
          unions: [
            if (union)
              UnionEntry(
                  wireId: choice.wireId,
                  name: 'Choice',
                  library: _custom,
                  description: '',
                  sourceType: 'package:example/probe.dart#Choice',
                  memberSourceTypes: const [
                    'package:example/probe.dart#Details',
                    'package:example/probe.dart#Raw'
                  ],
                  discriminator: DiscriminatorSpec(
                      field: '_s', values: [_details, rawRef]),
                  members: [_details, rawRef])
          ]);
      for (final physical in [false, true]) {
        final record = {
          '_s': 'Details',
          'geometry': physical ? {'left': 2.0} : [2.0]
        };
        final result = deriveSurfaceCapability(
            rfw.RemoteWidgetLibrary(const [], [
              rfw.WidgetDeclaration(
                  'Root',
                  null,
                  rfw.ConstructorCall('Probe', {
                    'value': union ? record : [record]
                  })),
            ]),
            catalog);
        expect(result.builtInFloor, physical ? 17 : 1);
        expect(result.requiredLibraries.single.minGenerated, 1);
      }
      if (union) {
        final ignored = deriveSurfaceCapability(
            rfw.RemoteWidgetLibrary(const [], [
              rfw.WidgetDeclaration(
                  'Root',
                  null,
                  rfw.ConstructorCall('Probe', {
                    'value': {
                      '_s': 'Raw',
                      'geometry': {'left': 2.0}
                    }
                  })),
            ]),
            catalog);
        expect(ignored.builtInFloor, 1);
      }
    }
    // Paint's shader keeps rfw's decoder internally. The generated gradient
    // property route upgrade must not be attributed to that older helper.
    _expect(
        PropertyType.paint,
        {
          'shader': {'type': 'radial', 'radius': 1}
        },
        1);
  });

  test('recursive geometry changes are qualified inside bounded local fallback',
      () {
    for (final type in [PropertyType.edgeInsets, PropertyType.gradient]) {
      final legacy = type == PropertyType.edgeInsets
          ? <Object?>[1.0]
          : <String, Object?>{'type': 'radial', 'radius': 1.0};
      final modern = type == PropertyType.edgeInsets
          ? <String, Object?>{'left': 1.0}
          : <String, Object?>{'type': 'radial', 'radius': 1};
      final result = deriveSurfaceCapability(
          rfw.RemoteWidgetLibrary(const [], [
            rfw.WidgetDeclaration(
                'Root',
                null,
                rfw.ConstructorCall(
                    'Local', {'value': legacy, 'next': modern})),
            rfw.WidgetDeclaration(
                'Local',
                null,
                rfw.Switch(const rfw.DataReference(['continue']), {
                  true: rfw.ConstructorCall('Local', {
                    'value': const rfw.ArgsReference(['next']),
                    'next': const rfw.ArgsReference(['next']),
                  }),
                  false: rfw.ConstructorCall('Probe', {
                    'value': const rfw.ArgsReference(['value'])
                  }),
                })),
          ]),
          _catalog(type));
      expect(result.builtInFloor, 17);
      expect(result.requiredLibraries.single.minGenerated,
          type == PropertyType.gradient ? 3 : 1);
    }
  });

  test(
      'geometry preserves exact native style and computed factory requirements',
      () {
    _expect(
        PropertyType.gradient,
        {
          'type': 'linear',
          'colors': [
            {'a': 1.0, 'r': 0.1, 'g': 0.2, 'b': 0.3, 'colorSpace': 'displayP3'},
          ]
        },
        19,
        factory: 3);
    final computed = {
      'version': 1,
      'program': const ValueProgram(nodes: [
        ValueNode('literal', ValueType.real, value: 1.0),
      ], root: 0)
          .encode(),
      'captures': <String, Object?>{}
    };
    _expect(PropertyType.edgeInsets, {'left': computed}, 19, factory: 3);
  });
}
