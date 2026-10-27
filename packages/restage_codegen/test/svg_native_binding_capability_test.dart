import 'package:restage_codegen/src/optional_native_values.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _svg = WidgetLibrary.custom('restage.svg');
const _bundleSource =
    'package:flutter/src/services/asset_bundle.dart#AssetBundle';
const _clientSource = 'package:http/src/client.dart#Client';
const _mapperSource = 'package:flutter_svg/src/loaders.dart#ColorMapper';
const _loaderSource = 'package:vector_graphics/src/loader.dart#BytesLoader';
const _fileSource = 'dart:io#File';
typedef _Route = ({String source, String widget, String slot});
const _routes = <_Route>[
  (source: _bundleSource, widget: 'SvgPictureAsset', slot: 'bundle'),
  (source: _clientSource, widget: 'SvgPictureNetwork', slot: 'httpClient'),
  (source: _mapperSource, widget: 'SvgPictureString', slot: 'colorMapper'),
  (source: _loaderSource, widget: 'SvgPicture', slot: 'bytesLoader'),
  (source: _fileSource, widget: 'SvgPictureFile', slot: 'file'),
  (
    source: 'package:flutter_svg/src/utilities/_file_none.dart#File',
    widget: 'SvgPictureFile',
    slot: 'file'
  ),
  (
    source: 'package:flutter_svg/svg.dart#SvgErrorWidgetBuilder',
    widget: 'SvgPictureString',
    slot: 'errorBuilder'
  ),
  (
    source: 'package:flutter_svg/svg.dart#SvgImageWidgetBuilder',
    widget: 'SvgPictureString',
    slot: 'imageBuilder'
  ),
  (
    source: 'dart:ui#ColorFilter',
    widget: 'SvgPictureString',
    slot: 'colorFilter'
  ),
  (
    source: 'dart:typed_data#Uint8List',
    widget: 'SvgPictureMemory',
    slot: 'bytes'
  ),
  (
    source: 'package:flutter_svg/src/loaders.dart#SvgTheme',
    widget: 'SvgPictureString',
    slot: 'theme'
  ),
  (source: 'dart:core#Map', widget: 'SvgPictureNetwork', slot: 'headers'),
];

Catalog _catalog(_Route route, {WidgetLibrary library = _svg}) {
  final ref = WireIdRef(library: library.namespace, wireId: WireId('s0001'));
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      library: const LibraryInfo(version: '0.1.0', capabilityVersion: 2),
    },
    widgets: [
      WidgetEntry(
        wireId: WireId('w0001'),
        name: route.widget,
        library: library,
        category: WidgetCategory.decoration,
        description: 'SVG consumer',
        flutterType: 'package:flutter_svg/svg.dart#SvgPicture',
        childrenSlot: ChildrenSlot.none,
        properties: [
          PropertyEntry(
            wireId: WireId('p0001'),
            name: route.slot,
            type: PropertyType.structured,
            description: 'Native SVG value',
            structuredRef: ref,
          ),
        ],
      ),
    ],
    structuredTypes: [
      StructuredEntry(
        wireId: ref.wireId,
        name: 'NativeSvgValue',
        library: library,
        description: 'Closed native value',
        sourceType: route.source,
        fields: const [],
        variants: const [],
      ),
    ],
  );
}

NativeBindingContract _contract(String source) =>
    NativeBindingContract(type: optionalNativeBindingTypes[source]!);
Map<String, Object?> _requiredArguments(_Route route) => switch (route.widget) {
      'SvgPictureAsset' => {'assetName': 'icon.svg'},
      'SvgPictureNetwork' => {'url': 'https://example.com/icon.svg'},
      'SvgPictureString' => {'string': '<svg/>'},
      _ => {},
    };

rfw.RemoteWidgetLibrary _library(
  _Route route,
  Object? value, {
  WidgetLibrary library = _svg,
}) =>
    rfw.RemoteWidgetLibrary(
      [rfw.Import(rfw.LibraryName(library.namespace.split('.')))],
      [
        rfw.WidgetDeclaration(
          'Root',
          null,
          rfw.ConstructorCall(
            route.widget,
            {..._requiredArguments(route), route.slot: value},
          ),
        ),
      ],
    );

Map<String, Object?> _nativeCapture(_Route route) {
  final type = ValueType.native(_contract(route.source).type);
  return {
    'version': 1,
    'program': ValueProgram(
      nodes: [ValueNode('capture', type, name: 'native')],
      root: 0,
      captures: {'native': type},
    ).encode(),
    'captures': {'native': _contract(route.source).reference('native')},
  };
}

rfw.RemoteWidgetLibrary _nativeFrame(
  _Route route, {
  required bool computed,
  bool nested = false,
}) {
  final type = ValueType.native(_contract(route.source).type);
  final program = BuilderProgram(
    values: ValueProgram(
      nodes: [
        ValueNode('capture', type, name: 'native'),
        ValueNode('local.write', type, inputs: [0], name: 'native'),
      ],
      root: 1,
      captures: {'native': type},
      locals: {'native': type},
    ),
    result: const BuilderResult.let(1, BuilderResult.body(0)),
    bodyCount: 1,
  );
  final value = computed
      ? {
          'version': 1,
          'program': ValueProgram(
            nodes: [ValueNode('local.read', type, name: 'native')],
            root: 0,
            outerLocals: {'native': type},
          ).encode(),
          'captures': <String, Object?>{},
        }
      : {
          'kind': 'nativeLocal',
          'slot': 'native',
          'type': type.nativeType,
          'nullable': type.nullable,
        };
  final bodyRoute = nested
      ? (source: _loaderSource, widget: 'SvgPicture', slot: 'bytesLoader')
      : route;
  final bodyValue = nested
      ? {'kind': 'SvgAssetLoader', 'value': 'icon.svg', 'assetBundle': value}
      : value;
  return rfw.RemoteWidgetLibrary([
    const rfw.Import(rfw.LibraryName(['restage', 'svg'])),
  ], [
    rfw.WidgetDeclaration(
      'Root',
      null,
      rfw.ConstructorCall(kBuilderContinuationWidgetName, {
        'version': 1,
        'program': program.encode(),
        'captures': {'native': _contract(route.source).reference('native')},
        'bodies': [
          rfw.WidgetBuilderDeclaration(
            'frame',
            rfw.ConstructorCall(bodyRoute.widget, {
              ..._requiredArguments(bodyRoute),
              bodyRoute.slot: bodyValue,
            }),
          ),
        ],
      }),
    ),
  ]);
}

void main() {
  test('SVG source bindings use one fixed namespace-owned identity table', () {
    expect(optionalNativeBindingTypes, same(kSvgNativeBindingTypes));
    for (final entry in optionalNativeBindingTypes.entries) {
      expect(
        svgNativeBindingType(entry.key, namespace: 'restage.svg'),
        entry.value,
      );
      expect(svgNativeBindingType(entry.key, namespace: 'example.svg'), isNull);
    }
    expect(
      svgNativeBindingType(
        'package:example/asset.dart#AssetBundle',
        namespace: 'restage.svg',
      ),
      isNull,
    );
  });

  test('opaque SVG binding references qualify their actual fixed consumer', () {
    expect(
      _routes.map((route) => route.source).toSet(),
      optionalNativeBindingTypes.keys.toSet(),
    );
    for (final route in _routes) {
      final catalog = _catalog(route);
      final library =
          _library(route, _contract(route.source).reference('native'));
      expect(
        deriveSurfaceCapability(library, catalog).builtInFloor,
        24,
        reason: route.source,
      );
      expect(
        nativeBindingsNeedInstalledHost(library, catalog),
        isTrue,
        reason: route.source,
      );
    }
  });

  test('literal opaque SVG references keep conservative preview refusal', () {
    for (final route in _routes) {
      expect(
        nativeBindingsNeedInstalledHost(
          _library(route, _contract(route.source).reference('native')),
          _catalog(route),
        ),
        isTrue,
        reason: route.source,
      );
    }
  });

  test('missing opaque SVG context requires its installed native scope', () {
    const route =
        (source: _bundleSource, widget: 'SvgPictureAsset', slot: 'bundle');
    expect(
      nativeBindingsNeedInstalledHost(
        _library(route, const rfw.DataReference(['context', 'native'])),
        _catalog(route),
      ),
      isTrue,
    );
  });

  test('native SVG capture programs require installed preview bindings', () {
    for (final route in _routes) {
      final catalog = _catalog(route);
      final envelope = _nativeCapture(route);
      final library = _library(route, envelope);
      final forwarded = rfw.RemoteWidgetLibrary(library.imports, [
        rfw.WidgetDeclaration(
          'Leaf',
          null,
          rfw.ConstructorCall(route.widget, {
            ..._requiredArguments(route),
            route.slot: const rfw.ArgsReference(['value']),
          }),
        ),
        rfw.WidgetDeclaration(
          'Root',
          null,
          rfw.ConstructorCall('Leaf', {'value': envelope}),
        ),
      ]);
      expect(
        nativeBindingsNeedInstalledHost(forwarded, catalog),
        isTrue,
        reason: '${route.source} forwarded program',
      );
      const foreign = WidgetLibrary.custom('example.svg');
      expect(
        nativeBindingsNeedInstalledHost(
          _library(route, envelope, library: foreign),
          _catalog(route, library: foreign),
        ),
        isFalse,
      );
      expect(
        deriveSurfaceCapability(library, catalog).builtInFloor,
        24,
        reason: route.source,
      );
      expect(
        nativeBindingsNeedInstalledHost(library, catalog),
        isTrue,
        reason: route.source,
      );
      expect(
        nativeBindingsNeedInstalledHost(
          _library(route, const rfw.DataReference(['context', 'native'])),
          catalog,
          context: {'native': envelope},
        ),
        isTrue,
        reason: '${route.source} recorded program',
      );
    }
  });
  test('native SVG locals and computed locals retain their lexical frames', () {
    for (final route in _routes) {
      for (final computed in [false, true]) {
        final library = _nativeFrame(route, computed: computed);
        expect(
          deriveSurfaceCapability(library, _catalog(route)).builtInFloor,
          24,
          reason: '${route.source} computed=$computed',
        );
        expect(
          nativeBindingsNeedInstalledHost(library, _catalog(route)),
          isTrue,
          reason: '${route.source} computed=$computed',
        );
      }
    }
  });
  test('nested SVG native programs use only admitted loader fields', () {
    for (final computed in [false, true]) {
      final library =
          _nativeFrame(_routes.first, computed: computed, nested: true);
      const route =
          (source: _loaderSource, widget: 'SvgPicture', slot: 'bytesLoader');
      expect(
        nativeBindingsNeedInstalledHost(library, _catalog(route)),
        isTrue,
        reason: 'nested local computed=$computed',
      );
    }
    const loader =
        (source: _loaderSource, widget: 'SvgPicture', slot: 'bytesLoader');
    for (final (kind, field, source, value) in [
      ('SvgAssetLoader', 'assetBundle', _bundleSource, 'icon.svg'),
      (
        'SvgNetworkLoader',
        'httpClient',
        _clientSource,
        'https://example.com/icon.svg'
      ),
      ('SvgStringLoader', 'colorMapper', _mapperSource, '<svg/>'),
      ('SvgBytesLoader', 'value', 'dart:typed_data#Uint8List', null),
      ('SvgFileLoader', 'value', _fileSource, null),
    ]) {
      final route = _routes.firstWhere((route) => route.source == source);
      final library = _library(loader, {
        'kind': kind,
        if (value != null) 'value': value,
        field: _nativeCapture(route),
      });
      expect(
        deriveSurfaceCapability(library, _catalog(loader)).builtInFloor,
        24,
      );
      expect(
        nativeBindingsNeedInstalledHost(library, _catalog(loader)),
        isTrue,
        reason: '$kind.$field',
      );
    }
    final ignored = _library(loader, {
      'kind': 'SvgStringLoader',
      'value': '<svg/>',
      'assetBundle': _nativeCapture(_routes.first),
    });
    expect(nativeBindingsNeedInstalledHost(ignored, _catalog(loader)), isFalse);
    const scalar = ValueProgram(
      nodes: [ValueNode('literal', ValueType.string, value: '<svg/>')],
      root: 0,
    );
    final ordinary = _library(loader, {
      'kind': 'SvgStringLoader',
      'value': {
        'version': 1,
        'program': scalar.encode(),
        'captures': <String, Object?>{},
      },
    });
    expect(
      nativeBindingsNeedInstalledHost(ordinary, _catalog(loader)),
      isFalse,
    );
  });
  test('native SVG call outputs fail closed without installed operations', () {
    const route =
        (source: _bundleSource, widget: 'SvgPictureAsset', slot: 'bundle');
    const contract = NativeBindingContract(
      type: 'installed.bundle',
      call: NativeCallContract(
        inputs: [],
        result: ValueType.native('flutter.AssetBundle'),
        implementation: 'bundle-v1',
      ),
    );
    final operations = {
      'native.call': NativeCallValueOperation({'makeBundle': contract}),
    };
    final program = ValueProgram(
      nodes: [
        ValueNode(
          'native.call',
          contract.call!.result,
          value: {
            'binding': 'makeBundle',
            'contract': contract.toJson(),
            'captures': <String, String>{},
          },
        ),
      ],
      root: 0,
    );
    final library = _library(route, {
      'version': 1,
      'program': program.encode(),
      'captures': <String, Object?>{},
    });
    expect(
      deriveSurfaceCapability(
        library,
        _catalog(route),
        operations: operations,
      ).builtInFloor,
      24,
    );
    expect(
      () => nativeBindingsNeedInstalledHost(library, _catalog(route)),
      throwsFormatException,
    );
  });

  test('nested SVG loader references qualify actual native fields', () {
    const route =
        (source: _loaderSource, widget: 'SvgPicture', slot: 'bytesLoader');
    for (final (kind, field, source, value) in [
      ('SvgAssetLoader', 'assetBundle', _bundleSource, 'icon.svg'),
      (
        'SvgNetworkLoader',
        'httpClient',
        _clientSource,
        'https://example.com/icon.svg'
      ),
      ('SvgStringLoader', 'colorMapper', _mapperSource, '<svg/>'),
      (
        'SvgBytesLoader',
        'colorMapper',
        _mapperSource,
        <Object?>[60, 115, 118, 103, 47, 62]
      ),
      ('SvgFileLoader', 'value', _fileSource, null),
    ]) {
      final recipe = <String, Object?>{
        'kind': kind,
        if (value != null) 'value': value,
        field: _contract(source).reference('native'),
      };
      final library = _library(route, recipe);
      expect(
        deriveSurfaceCapability(library, _catalog(route)).builtInFloor,
        24,
        reason: '$kind.$field',
      );
      expect(
        nativeBindingsNeedInstalledHost(library, _catalog(route)),
        isTrue,
        reason: '$kind.$field',
      );
    }
  });
  test(
      'declared and forwarded SVG context references '
      'retain exact host requirements', () {
    for (final route in _routes) {
      final catalog = _catalog(route);
      final context = SurfaceScreenHostDataSchema({
        'native':
            SurfaceScreenHostDataNativeBindingShapeV1(_contract(route.source)),
      });
      final library = rfw.RemoteWidgetLibrary([
        const rfw.Import(rfw.LibraryName(['restage', 'svg'])),
      ], [
        rfw.WidgetDeclaration(
          'Leaf',
          null,
          rfw.ConstructorCall(route.widget, {
            ..._requiredArguments(route),
            route.slot: const rfw.ArgsReference(['payload']),
          }),
        ),
        const rfw.WidgetDeclaration(
          'Forward',
          null,
          rfw.ConstructorCall('Leaf', {
            'payload': rfw.ArgsReference(['payload']),
          }),
        ),
        const rfw.WidgetDeclaration(
          'Root',
          null,
          rfw.ConstructorCall('Forward', {
            'payload': rfw.DataReference(['context', 'native']),
          }),
        ),
      ]);
      final required =
          deriveSurfaceCapability(library, catalog, hostDataContract: context);
      expect(required.builtInFloor, 24, reason: route.source);
      expect(required.requiredLibraries.single.namespace, 'restage.svg');
      expect(required.requiredLibraries.single.minVersion, 2);
      expect(
        nativeBindingsNeedInstalledHost(library, catalog),
        isTrue,
        reason: route.source,
      );
      for (final sdk in [23, 24]) {
        expect(
          BlobRenderCapabilityGate.evaluate(
            required: CapabilityManifest(
              builtInFloor: required.builtInFloor,
              requiredLibraries: required.requiredLibraries,
            ),
            installed: InstalledCapability(
              builtInCatalogVersion: sdk,
              installedLibraries: const [
                InstalledLibrary(
                  namespace: 'restage.svg',
                  version: 2,
                  generated: 3,
                ),
              ],
            ),
          ).accepted,
          sdk == 24,
        );
      }
      expect(
        deriveSurfaceCapability(
          _library(route, null),
          catalog,
          hostDataContract: context,
        ).builtInFloor,
        lessThan(24),
      );
    }
  });

  test('nested SVG contexts follow only the loader fields the runtime reads',
      () {
    const route =
        (source: _loaderSource, widget: 'SvgPicture', slot: 'bytesLoader');
    final catalog = _catalog(route);
    for (final (kind, field, source, value) in [
      ('SvgAssetLoader', 'assetBundle', _bundleSource, 'icon.svg'),
      (
        'SvgNetworkLoader',
        'httpClient',
        _clientSource,
        'https://example.com/icon.svg'
      ),
      ('SvgStringLoader', 'colorMapper', _mapperSource, '<svg/>'),
      ('SvgBytesLoader', 'value', 'dart:typed_data#Uint8List', null),
      ('SvgFileLoader', 'value', _fileSource, null),
    ]) {
      final library = _library(route, {
        'kind': kind,
        if (value != null) 'value': value,
        field: const rfw.DataReference(['context', 'native']),
      });
      final schema = SurfaceScreenHostDataSchema({
        'native': SurfaceScreenHostDataNativeBindingShapeV1(_contract(source)),
      });
      expect(
        deriveSurfaceCapability(library, catalog, hostDataContract: schema)
            .builtInFloor,
        24,
        reason: '$kind.$field',
      );
      expect(
        nativeBindingsNeedInstalledHost(library, catalog),
        isTrue,
        reason: '$kind.$field',
      );
      expect(
        nativeBindingsNeedInstalledHost(
          library,
          catalog,
          context: {'native': _contract(source).reference('native')},
        ),
        isTrue,
        reason: '$kind.$field recorded metadata',
      );
    }
    for (final kind in [
      'SvgStringLoader',
      'SvgBytesLoader',
      'SvgAssetLoader',
      'SvgNetworkLoader',
      'SvgFileLoader',
    ]) {
      for (final (field, source) in [
        ('theme', 'package:flutter_svg/src/loaders.dart#SvgTheme'),
        ('colorMapper', _mapperSource),
      ]) {
        final library = _library(route, {
          'kind': kind,
          'value': kind == 'SvgBytesLoader'
              ? [60, 62]
              : kind == 'SvgFileLoader'
                  ? _contract(_fileSource).reference('file')
                  : '<svg/>',
          field: _contract(source).reference('native'),
        });
        expect(deriveSurfaceCapability(library, catalog).builtInFloor, 24);
        expect(nativeBindingsNeedInstalledHost(library, catalog), isTrue);
      }
    }
    final headers = _library(route, {
      'kind': 'SvgNetworkLoader',
      'value': 'https://example.com/icon.svg',
      'headers': _contract('dart:core#Map').reference('headers'),
    });
    expect(deriveSurfaceCapability(headers, catalog).builtInFloor, 24);
  });

  test(
      'ordinary SVG recipes nulls and ignored fields '
      'keep their prior interpretation', () {
    const route =
        (source: _loaderSource, widget: 'SvgPicture', slot: 'bytesLoader');
    final catalog = _catalog(route);
    for (final recipe in <Object?>[
      null,
      {'kind': 'SvgStringLoader', 'value': '<svg/>'},
      {
        'kind': 'SvgBytesLoader',
        'value': [60, 115, 118, 103, 47, 62],
      },
      {
        'kind': 'SvgAssetLoader',
        'value': 'icon.svg',
        'theme': {'currentColor': 4278190080},
      },
      {
        'kind': 'SvgNetworkLoader',
        'value': 'https://example.com/icon.svg',
        'headers': [
          {'key': 'accept', 'value': 'image/svg+xml'},
        ],
      },
      {
        'kind': 'SvgStringLoader',
        'value': '<svg/>',
        'assetBundle': _contract(_bundleSource).reference('ignored'),
      },
      {
        'kind': 'SvgAssetLoader',
        'value': 'icon.svg',
        'httpClient': _contract(_clientSource).reference('ignored'),
      },
      {
        'kind': 'Unknown',
        'value': '<svg/>',
        'colorMapper': _contract(_mapperSource).reference('ignored'),
      },
    ]) {
      final library = _library(route, recipe);
      expect(
        deriveSurfaceCapability(library, catalog).builtInFloor,
        lessThan(24),
        reason: '$recipe',
      );
      expect(
        nativeBindingsNeedInstalledHost(library, catalog),
        isFalse,
        reason: '$recipe',
      );
    }
    for (final route in _routes) {
      expect(
        deriveSurfaceCapability(_library(route, null), _catalog(route))
            .builtInFloor,
        lessThan(24),
      );
      expect(
        nativeBindingsNeedInstalledHost(
          _library(route, null),
          _catalog(route),
        ),
        isFalse,
      );
    }
    for (final (source, ordinary) in <(String, Object)>[
      (
        'dart:core#Map',
        [
          {'key': 'accept', 'value': 'image/svg+xml'},
        ]
      ),
      ('dart:typed_data#Uint8List', [60, 62]),
      (
        'package:flutter_svg/src/loaders.dart#SvgTheme',
        {'fontSize': 14.0, 'currentColor': 4278190080}
      ),
      (
        'dart:ui#ColorFilter',
        {'kind': 'mode', 'color': 4278190080, 'blendMode': 'srcIn'}
      ),
    ]) {
      final route = _routes.singleWhere((route) => route.source == source);
      final library =
          _library(route, const rfw.DataReference(['context', 'native']));
      expect(
        nativeBindingsNeedInstalledHost(
          library,
          _catalog(route),
          context: {'native': ordinary},
        ),
        isFalse,
      );
      expect(
        nativeBindingsNeedInstalledHost(
          library,
          _catalog(route),
          context: {'native': null},
        ),
        isFalse,
      );
    }
  });

  test(
      'unrelated namespaces with identical SVG source names '
      'are not SVG decoders', () {
    const foreign = WidgetLibrary.custom('example.svg');
    for (final route in _routes) {
      final catalog = _catalog(route, library: foreign);
      final library = _library(
        route,
        _contract(route.source).reference('native'),
        library: foreign,
      );
      expect(
        deriveSurfaceCapability(library, catalog).builtInFloor,
        lessThan(24),
        reason: route.source,
      );
      expect(
        nativeBindingsNeedInstalledHost(
          _library(
            route,
            const rfw.DataReference(['context', 'native']),
            library: foreign,
          ),
          catalog,
        ),
        isFalse,
        reason: route.source,
      );
    }
  });
}
