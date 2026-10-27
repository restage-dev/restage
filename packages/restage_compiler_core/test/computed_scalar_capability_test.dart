import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _custom = WidgetLibrary.custom('example.scalar');
final _detail = WireIdRef(library: _custom.namespace, wireId: WireId('s0001'));
final _svgTheme = WireIdRef(library: 'restage.svg', wireId: WireId('s0003'));
final _style = WireIdRef(library: 'restage.core', wireId: WireId('s0002'));
PropertyEntry _property(String name, PropertyType type, {WireIdRef? ref}) =>
    PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: name,
        type: type,
        description: name,
        structuredRef: ref);
final _catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      _custom: const LibraryInfo(version: '1', capabilityVersion: 1)
    },
    widgets: [
      WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'Probe',
          library: _custom,
          category: WidgetCategory.decoration,
          description: 'Probe',
          flutterType: 'package:example/probe.dart#Probe',
          childrenSlot: ChildrenSlot.none,
          properties: [
            _property('text', PropertyType.string),
            _property('details', PropertyType.structured, ref: _detail),
            _property('style', PropertyType.structured, ref: _style),
            _property('svgTheme', PropertyType.structured, ref: _svgTheme),
            _property('insets', PropertyType.edgeInsets),
            _property('raw', PropertyType.dataReference)
          ])
    ],
    structuredTypes: [
      StructuredEntry(
          wireId: _svgTheme.wireId,
          name: 'SvgTheme',
          library: const WidgetLibrary.custom('restage.svg'),
          description: 'SvgTheme',
          sourceType: 'package:flutter_svg/src/loaders.dart#SvgTheme',
          fields: const [],
          variants: const []),
      StructuredEntry(
          wireId: _detail.wireId,
          name: 'Details',
          library: _custom,
          description: 'Details',
          sourceType: 'package:example/probe.dart#Details',
          fields: [
            const StructuredField(
                wireId: WireId.unallocatedProperty,
                name: 'label',
                type: PropertyType.string,
                description: 'Label')
          ],
          variants: const []),
      StructuredEntry(
          wireId: _style.wireId,
          name: 'TextStyle',
          library: WidgetLibrary.core,
          description: 'TextStyle',
          sourceType: 'package:flutter/src/painting/text_style.dart#TextStyle',
          fields: const [],
          variants: const [])
    ]);
Map<String, Object?> _envelope() {
  final program = ValueProgram(nodes: [
    const ValueNode('capture', ValueType.integer, name: 'count'),
    const ValueNode('literal', ValueType.string, value: 'items'),
    const ValueNode('intl.plural', ValueType.string, inputs: [
      0,
      1
    ], value: {
      'arguments': ['other']
    })
  ], captures: const {
    'count': ValueType.integer
  }, root: 2);
  return {
    'version': 1,
    'program': program.encode(),
    'captures': {'count': 2}
  };
}

SurfaceCapabilityDerivation _derive(List<rfw.WidgetDeclaration> widgets) =>
    deriveSurfaceCapability(
        rfw.RemoteWidgetLibrary(const [], widgets), _catalog);
BlobRenderVerdict _gate(SurfaceCapabilityDerivation result, int generated) =>
    BlobRenderCapabilityGate.evaluate(
        required: CapabilityManifest(
            builtInFloor: result.builtInFloor,
            requiredLibraries: result.requiredLibraries),
        installed: InstalledCapability(
            builtInCatalogVersion: 23,
            installedLibraries: [
              InstalledLibrary(
                  namespace: _custom.namespace,
                  version: 1,
                  generated: generated)
            ]));

void main() {
  test(
      'computed scalars retain custom factory floor through scoped typed paths',
      () {
    final envelope = _envelope();
    for (final destination in [
      {
        'text': const rfw.ArgsReference(['value'])
      },
      {
        'details': {
          'label': const rfw.ArgsReference(['value'])
        }
      },
      {
        'details': const rfw.ArgsReference(['details'])
      },
      {
        'style': {
          'fontFamily': const rfw.ArgsReference(['value'])
        }
      },
    ]) {
      final result = _derive([
        rfw.WidgetDeclaration(
            'Root',
            null,
            rfw.ConstructorCall('Wrapper', {
              'value': envelope,
              'details': {'label': envelope}
            })),
        rfw.WidgetDeclaration(
            'Wrapper', null, rfw.ConstructorCall('Probe', destination))
      ]);
      expect(result.builtInFloor, 23);
      expect(result.requiredLibraries.single.minGenerated, 3,
          reason: '$destination');
      expect(_gate(result, 2).accepted, isFalse);
      expect(_gate(result, 3).accepted, isTrue);
    }
    final direct = _derive([
      rfw.WidgetDeclaration(
          'Root', null, rfw.ConstructorCall('Probe', {'text': envelope}))
    ]);
    expect(direct.requiredLibraries.single.minGenerated, 3);
  });
  test('native opaque scalar and geometry paths retain scoped computed values',
      () {
    final envelope = {
      'version': 1,
      'program': ValueProgram(
              nodes: [const ValueNode('literal', ValueType.real, value: 12.5)],
              root: 0)
          .encode(),
      'captures': <String, Object?>{}
    };
    for (final args in [
      {
        'svgTheme': {
          'fontSize': const rfw.ArgsReference(['value'])
        }
      },
      {
        'style': {
          'fontSize': const rfw.ArgsReference(['value'])
        }
      },
      {
        'insets': {
          'kind': 'physical',
          'top': const rfw.ArgsReference(['value'])
        }
      },
    ]) {
      final result = _derive([
        rfw.WidgetDeclaration(
            'Root', null, rfw.ConstructorCall('Wrapper', {'value': envelope})),
        rfw.WidgetDeclaration(
            'Wrapper', null, rfw.ConstructorCall('Probe', args))
      ]);
      expect(result.requiredLibraries.single.minGenerated, 3, reason: '$args');
      expect(_gate(result, 2).accepted, isFalse);
    }
  });
  test('computed scalars survive finite recursive and bounded local fallback',
      () {
    for (final depth in [1, 70]) {
      final result = _derive([
        rfw.WidgetDeclaration(
            'Root',
            null,
            rfw.ConstructorCall(
                'Wrapper', {'value': _envelope(), 'again': true})),
        rfw.WidgetDeclaration(
            'Wrapper',
            null,
            rfw.Switch(const rfw.ArgsReference(['again']), {
              true: const rfw.ConstructorCall('Wrapper', {
                'value': rfw.ArgsReference(['value']),
                'again': false
              }),
              false: const rfw.ConstructorCall('Local0', {
                'value': rfw.ArgsReference(['value'])
              })
            })),
        for (var i = 0; i < depth; i++)
          rfw.WidgetDeclaration(
              'Local$i',
              null,
              rfw.ConstructorCall(i + 1 == depth ? 'Probe' : 'Local${i + 1}', {
                i + 1 == depth ? 'text' : 'value':
                    const rfw.ArgsReference(['value'])
              }))
      ]);
      expect(result.requiredLibraries.single.minGenerated, 3,
          reason: 'depth $depth');
      expect(_gate(result, 2).accepted, isFalse);
    }
  });
  test('static unused and unrelated maps retain their installed factory floor',
      () {
    for (final args in [
      {'text': 'static'},
      {
        'raw': const rfw.ArgsReference(['unused'])
      },
      {
        'details': {
          'ignored': const rfw.ArgsReference(['unused'])
        }
      },
      {
        'style': {
          'ignored': const rfw.ArgsReference(['unused'])
        }
      },
    ]) {
      final result = _derive([
        rfw.WidgetDeclaration('Root', null,
            rfw.ConstructorCall('Wrapper', {'unused': _envelope()})),
        rfw.WidgetDeclaration(
            'Wrapper', null, rfw.ConstructorCall('Probe', args))
      ]);
      expect(result.requiredLibraries.single.minGenerated, 2, reason: '$args');
      expect(_gate(result, 2).accepted, isTrue);
    }
  });
}
