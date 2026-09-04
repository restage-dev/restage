import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_publication_planner.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/onboarding/screen_builder.dart';
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';

const _sourceAsset = 'apps_examples|lib/features/measured.dart';
const _catalogAsset = 'apps_examples|lib/src/widget_catalog/catalog.json';
const _policyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
});
const _bundledPolicyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
  'bundled_runtime': true,
});

const _source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/measured.restage.g.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.measurement'),
  capabilityVersion: 1,
)
const measurementLibrary = 0;

@RestageWidget(
  name: 'InlineAction',
  library: WidgetLibrary.custom('acme.measurement'),
  category: WidgetCategory.input,
  description: 'Inline action.',
)
final class InlineAction extends StatelessWidget {
  const InlineAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        child: const Text('Inline'),
      );
}

@RestageWidget(
  name: 'OpaqueAction',
  library: WidgetLibrary.custom('acme.measurement'),
  category: WidgetCategory.input,
  description: 'App-backed action.',
)
final class OpaqueAction extends StatelessWidget {
  const OpaqueAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ActionPainter());
}

final class _ActionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

@Screen(id: 'measured', surface: Surface.general)
final class MeasuredScreen extends StatelessWidget {
  const MeasuredScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');
  static const inspect = SurfaceEvent<void>('inspect');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: surfaceEvent(activate),
            child: const Text('Ordinary'),
          ),
          InlineAction(onPressed: surfaceEvent(activate)),
          OpaqueAction(onPressed: surfaceEvent(activate)),
          FilledButton(
            key: UniqueKey(),
            onPressed: surfaceEvent(activate),
            child: const Text('Repeated A'),
          ),
          FilledButton(
            onPressed: surfaceEvent(activate),
            child: const Text('Repeated B'),
          ),
          GestureDetector(
            onTap: surfaceEvent(activate),
            onDoubleTap: surfaceEvent(inspect),
            child: const Text('Multi-slot'),
          ),
        ],
      );
}
''';

const _preludeSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/measured.restage.g.dart';

@Screen(id: 'measured', surface: Surface.general)
final class MeasuredScreen extends StatelessWidget {
  const MeasuredScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) {
    final action = FilledButton(
      onPressed: surfaceEvent(activate),
      child: const Text('Go'),
    );
    return Column(children: [action]);
  }
}
''';

const _widgetListPreludeSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/measured.restage.g.dart';

@Screen(id: 'measured', surface: Surface.general)
final class MeasuredScreen extends StatelessWidget {
  const MeasuredScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      const Text('First'),
      FilledButton(
        onPressed: surfaceEvent(activate),
        child: const Text('Activate'),
      ),
      const Text('Last'),
    ];
    return Column(children: children);
  }
}
''';

const _widgetListHelperSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/measured.restage.g.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.helperlist'),
  capabilityVersion: 1,
)
const helperListLibrary = 0;

@RestageWidget(
  name: 'InlineActions',
  library: WidgetLibrary.custom('acme.helperlist'),
  category: WidgetCategory.input,
  description: 'Inline actions.',
)
final class InlineActions extends StatelessWidget {
  const InlineActions({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  List<Widget> _actions(VoidCallback callback) => <Widget>[
        const Text('First'),
        FilledButton(onPressed: callback, child: const Text('Inline')),
        const Text('Last'),
      ];

  @override
  Widget build(BuildContext context) => Column(children: _actions(onPressed));
}

@Screen(id: 'measured', surface: Surface.general)
final class MeasuredScreen extends StatelessWidget {
  const MeasuredScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) =>
      InlineActions(onPressed: surfaceEvent(activate));
}
''';

const _widgetListLiteralSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/measured.restage.g.dart';

@Screen(id: 'measured', surface: Surface.general)
final class MeasuredScreen extends StatelessWidget {
  const MeasuredScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          const Text('First'),
          FilledButton(
            onPressed: surfaceEvent(activate),
            child: const Text('Activate'),
          ),
          const Text('Last'),
        ],
      );
}
''';

const _occurrenceSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/measured.restage.g.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.occurrence'),
  capabilityVersion: 1,
)
const occurrenceLibrary = 0;

@RestageWidget(
  name: 'InlineAction',
  library: WidgetLibrary.custom('acme.occurrence'),
  category: WidgetCategory.input,
  description: 'Inline action.',
)
final class InlineAction extends StatelessWidget {
  const InlineAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  Widget _button(VoidCallback callback) => FilledButton(
        onPressed: callback,
        child: const Text('Inline'),
      );

  @override
  Widget build(BuildContext context) => _button(onPressed);
}

@RestageWidget(
  name: 'OpaqueAction',
  library: WidgetLibrary.custom('acme.occurrence'),
  category: WidgetCategory.input,
  description: 'App-backed action.',
)
final class OpaqueAction extends StatelessWidget {
  const OpaqueAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ActionPainter());
}

final class _ActionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

@Screen(id: 'measured', surface: Surface.general)
final class MeasuredScreen extends StatelessWidget {
  const MeasuredScreen({super.key});

  static const direct = SurfaceEvent<void>('direct');
  static const repeated = SurfaceEvent<void>('repeated');
  static const local = SurfaceEvent<void>('local');
  static const localTwice = SurfaceEvent<void>('localTwice');
  static const aliased = SurfaceEvent<void>('aliased');

  @override
  Widget build(BuildContext context) {
    final callback = surfaceEvent(aliased);
    final oneLocal = FilledButton(
      onPressed: surfaceEvent(local),
      child: const Text('One local'),
    );
    final firstTwiceLocal = FilledButton(
      onPressed: surfaceEvent(localTwice),
      child: const Text('First twice local'),
    );
    final secondTwiceLocal = FilledButton(
      onPressed: surfaceEvent(localTwice),
      child: const Text('Second twice local'),
    );
    final children = <Widget>[
      FilledButton(
        onPressed: surfaceEvent(direct),
        child: const Text('Direct'),
      ),
      FilledButton(
        onPressed: surfaceEvent(repeated),
        child: const Text('Repeated A'),
      ),
      FilledButton(
        onPressed: surfaceEvent(repeated),
        child: const Text('Repeated B'),
      ),
      oneLocal,
      firstTwiceLocal,
      secondTwiceLocal,
      FilledButton(onPressed: callback, child: const Text('Alias A')),
      FilledButton(
        onPressed: surfaceEvent(aliased),
        child: const Text('Alias B'),
      ),
      GestureDetector(
        onTap: surfaceEvent(aliased),
        onDoubleTap: surfaceEvent(aliased),
        child: const Text('Two slots'),
      ),
      InlineAction(onPressed: surfaceEvent(aliased)),
      OpaqueAction(onPressed: surfaceEvent(aliased)),
    ];
    return Column(children: children);
  }
}
''';

const _aliasSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/measured.restage.g.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.alias'),
  capabilityVersion: 1,
)
const aliasLibrary = 0;

@RestageWidget(
  name: 'AliasCatalogMarker',
  library: WidgetLibrary.custom('acme.alias'),
  category: WidgetCategory.decoration,
  description: 'Catalog contributor for alias coverage.',
)
final class AliasCatalogMarker {
  const AliasCatalogMarker();
}

@Screen(id: 'measured', surface: Surface.general)
final class MeasuredScreen extends StatelessWidget {
  const MeasuredScreen({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          PageView(children: const [SizedBox()]),
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            builder: (context, scrollController) => SingleChildScrollView(
              controller: scrollController,
              child: const SizedBox(),
            ),
          ),
          DropdownButton<String>(
            value: 'usd',
            items: const [
              DropdownMenuItem<String>(value: 'usd', child: Text('US Dollar')),
            ],
          ),
          ToggleButtons(
            isSelected: const [true],
            children: const [Text('Bold')],
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'day', label: Text('Day')),
            ],
            selected: const {'day'},
          ),
        ],
      );
}
''';

const _frozenWitnessPaywallSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'witness_offer')
final class WitnessOffer extends StatelessWidget {
  const WitnessOffer({super.key});

  @override
  Widget build(BuildContext context) => const Text('Offer');
}
''';

void main() {
  test(
    'a measured slot on a widget held in a build() local reaches the route '
    'plan through the production compiler',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final compilation = await testBuilder(
        const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
        const <String, String>{_sourceAsset: _preludeSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        compilation.succeeded,
        isTrue,
        reason: compilation.errors.join('\n'),
      );
      final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
        ),
      );

      expect(output.valid, isTrue);
      final routes = output.publications.single.routePlan.routes;
      expect(routes, hasLength(1));
      expect(routes.single.generatedReferenceId.value, isNotEmpty);
    },
  );

  test(
    'a locally held widget list matches its publication twin',
    () async {
      Future<
          ({
            Uint8List measurementBytes,
            String publicationBundle,
            RestageMeasurementCompilerOutputV1 output,
          })> compile(String source) async {
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        final compilation = await testBuilder(
          const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
          <String, String>{_sourceAsset: source},
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        expect(
          compilation.succeeded,
          isTrue,
          reason: compilation.errors.join('\n'),
        );
        final measurementBytes = readerWriter.testing.readBytes(
          AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
        );
        return (
          measurementBytes: measurementBytes,
          publicationBundle: readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
          output: RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
            measurementBytes,
          ),
        );
      }

      final local = await compile(_widgetListPreludeSource);
      final literal = await compile(_widgetListLiteralSource);

      expect(local.output.valid, isTrue);
      expect(
        local.measurementBytes,
        orderedEquals(literal.measurementBytes),
      );
      expect(local.publicationBundle, literal.publicationBundle);
      expect(local.output.publications.single.routePlan.routes, hasLength(1));
      expect(
        local.output.ledgerNodes
            .expand((node) => node.events)
            .map((event) => event.sourceEventIdentity.value),
        ['onPressed'],
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a measured slot inside a helper feeding a widget list reaches the route '
    'plan through the production compiler',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final catalogBuild = await testBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        const <String, String>{_sourceAsset: _widgetListHelperSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        catalogBuild.succeeded,
        isTrue,
        reason: catalogBuild.errors.join('\n'),
      );
      final compilation = await testBuilder(
        const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
        <String, String>{
          _sourceAsset: _widgetListHelperSource,
          _catalogAsset: readerWriter.testing.readString(
            AssetId.parse(_catalogAsset),
          ),
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        compilation.succeeded,
        isTrue,
        reason: compilation.errors.join('\n'),
      );
      final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
        ),
      );

      expect(output.valid, isTrue);
      expect(output.publications.single.routePlan.routes, hasLength(1));
      expect(
        output.ledgerNodes
            .expand((node) => node.events)
            .map((event) => event.sourceEventIdentity.value),
        ['onPressed'],
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'structural event occurrences survive every supported expansion route',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final catalogBuild = await testBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        const <String, String>{_sourceAsset: _occurrenceSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        catalogBuild.succeeded,
        isTrue,
        reason: catalogBuild.errors.join('\n'),
      );
      final catalog = readerWriter.testing.readString(
        AssetId.parse(_catalogAsset),
      );
      final compilation = await testBuilder(
        const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
        <String, String>{
          _sourceAsset: _occurrenceSource,
          _catalogAsset: catalog,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        compilation.succeeded,
        isTrue,
        reason: compilation.errors.join('\n'),
      );

      final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
        ),
      );
      expect(output.valid, isTrue);
      final publication = output.publications.single;
      expect(publication.routePlan.routes, hasLength(12));
      expect(
        publication.routePlan.routes
            .map((route) => route.generatedReferenceId.value)
            .toSet(),
        hasLength(12),
      );

      final bundle = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ) as Map<String, Object?>,
      );
      final manifestEntry = bundle.manifest!.publications.single;
      final blobPath = manifestEntry.artifacts
          .singleWhere(
            (artifact) =>
                artifact.role == SurfacePublicationArtifactRole.screenBlob,
          )
          .path;
      final decodedBlob = fmt.decodeLibraryBlob(
        Uint8List.fromList(bundle.artifacts[blobPath]!),
      );
      final handlers = _eventHandlers(decodedBlob);
      expect(handlers, hasLength(12));
      final eventCounts = <String, int>{};
      for (final handler in handlers) {
        eventCounts.update(
          handler.eventName,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      expect(
        eventCounts,
        <String, int>{
          'direct': 1,
          'repeated': 2,
          'local': 1,
          'localTwice': 2,
          'aliased': 6,
        },
      );

      final carriersByEvent = <String, List<String>>{};
      for (final handler in handlers) {
        final carrier =
            handler.eventArguments[kMeasurementRouteArgumentKeyV1] as String?;
        expect(carrier, isNotNull);
        carriersByEvent
            .putIfAbsent(handler.eventName, () => <String>[])
            .add(carrier!);
      }
      for (final entry in carriersByEvent.entries) {
        expect(entry.value.toSet(), hasLength(entry.value.length));
      }
      final routesByCarrier = {
        for (final route in publication.routePlan.routes) route.carrier: route,
      };
      final reusedCarriers = carriersByEvent['localTwice']!;
      expect(reusedCarriers, hasLength(2));
      expect(reusedCarriers.toSet(), hasLength(2));
      expect(
        reusedCarriers
            .map(
              (carrier) => routesByCarrier[carrier]!.generatedReferenceId.value,
            )
            .toSet(),
        hasLength(2),
      );
      expect(
        output.ledgerNodes
            .expand((node) => node.events)
            .map((event) => event.sourceEventIdentity.value),
        containsAll(<String>['onTap', 'onDoubleTap']),
      );
      final twoSlotNode = output.ledgerNodes.singleWhere(
        (node) => node.events
            .map((event) => event.sourceEventIdentity.value)
            .toSet()
            .containsAll(<String>{'onTap', 'onDoubleTap'}),
      );
      expect(
        twoSlotNode.events
            .map((event) => event.sourceEventIdentity.value)
            .toSet(),
        <String>{'onTap', 'onDoubleTap'},
      );
      final twoSlotReferences = twoSlotNode.events
          .map((event) => event.generatedReferenceId.value)
          .toSet();
      expect(twoSlotReferences, hasLength(2));
      final twoSlotCarriers = publication.routePlan.routes
          .where(
            (route) =>
                twoSlotReferences.contains(route.generatedReferenceId.value),
          )
          .map((route) => route.carrier)
          .toSet();
      expect(twoSlotCarriers, hasLength(2));
      expect(
        carriersByEvent['aliased']!.toSet(),
        containsAll(twoSlotCarriers),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'default tracked builder emits ordinary, inline, opaque, repeated, and '
    'multi-slot routes before final hashes',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final catalogBuild = await testBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        const {_sourceAsset: _source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(catalogBuild.succeeded, isTrue);
      final catalog = readerWriter.testing.readString(
        AssetId.parse(_catalogAsset),
      );

      final compilerSources = <String, String>{
        _sourceAsset: _source,
        _catalogAsset: catalog,
      };
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
        compilerSources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      final compilerOutput =
          RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      expect(compilerOutput.valid, isTrue);
      expect(compilerOutput.publications, hasLength(1));
      final publication = compilerOutput.publications.single;
      expect(publication.routePlan.routes, hasLength(7));
      expect(publication.routePlan.presentationRoutes, hasLength(11));
      expect(
        publication.routePlan.routes
            .map((route) => route.generatedReferenceId.value)
            .toSet(),
        hasLength(7),
      );

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      expect(handoff.valid, isTrue);
      final manifestEntry = handoff.manifest!.publications.single;
      final blobArtifact = manifestEntry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob,
      );
      final blob = handoff.artifacts[blobArtifact.path]!;
      expect(CapabilitySidecar.hashBlob(blob), blobArtifact.contentHash);
      final decodedBlob = fmt.decodeLibraryBlob(Uint8List.fromList(blob));
      expect(
        _presentationWrappedNames(decodedBlob),
        unorderedEquals([
          'Column',
          'FilledButton',
          'FilledButton',
          'FilledButton',
          'GestureDetector',
          'InlineAction',
          'OpaqueAction',
          'Text',
          'Text',
          'Text',
          'Text',
        ]),
        reason: 'only final RFW catalog occurrences are presented: outer '
            'app-defined calls stay distinct, repeated sibling calls stay '
            'distinct, and the generated InlineAction body remains opaque',
      );
      expect(
        _presentationWrappedNamesForWidget(decodedBlob, 'InlineAction'),
        isEmpty,
        reason:
            'the generated local definition is not an independent presentation '
            'occurrence; only the outer InlineAction call is wrapped',
      );
      final carriers = _eventHandlers(
        decodedBlob,
      )
          .map(
            (handler) => handler.eventArguments[kMeasurementRouteArgumentKeyV1],
          )
          .whereType<String>()
          .toList();
      expect(carriers, hasLength(7));
      expect(carriers.toSet(), hasLength(7));
      expect(
        carriers.toSet(),
        {
          for (final route in publication.routePlan.routes) route.carrier,
        },
      );
      for (final bytes in [
        ...handoff.artifacts.values,
        ...handoff.borrowedArtifacts.values,
        ...handoff.ownedOutputs.values,
      ]) {
        final text = utf8.decode(bytes, allowMalformed: true);
        expect(text, isNot(contains(kMeasurementRouteReferenceMarkerKeyV1)));
        expect(text, isNot(contains(kMeasurementRouteReferenceMarkerPrefixV1)));
      }
      expect(
        publication.draft.artifacts
            .singleWhere(
              (artifact) => artifact.artifactKind.value == 'rfw.blob',
            )
            .contentHash
            .hex,
        blobArtifact.contentHash.substring('sha256:'.length),
      );
      expect(
        compilerOutput.ledgerNodes
            .map((node) => node.codeIdentityId.value)
            .every((identity) => !identity.contains('lib/features')),
        isTrue,
      );

      final generatedPart = utf8.decode(
        handoff.ownedOutputs.values.singleWhere(
          (bytes) => utf8.decode(bytes).contains('SurfaceScreenBundleLocator'),
        ),
      );
      final sidecarArtifact = manifestEntry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.capabilitySidecar,
      );
      final sidecar = handoff.artifacts[sidecarArtifact.path]!;
      expect(generatedPart, contains(blobArtifact.contentHash));
      expect(generatedPart, contains(sidecarArtifact.contentHash));
      expect(generatedPart, contains('byteLength: ${blob.length}'));
      expect(generatedPart, contains('byteLength: ${sidecar.length}'));
      expect(
        generatedPart,
        contains('generatedWithMeasurementPublicationDraftDigest'),
        reason: 'the delivered generated ScreenSource receives only the final '
            'compiler-owned draft closure carrier',
      );
      expect(
        generatedPart,
        contains(publication.draft.canonicalDigest.hex),
        reason:
            'the carrier is derived after final manifest payload and artifact '
            'bytes have been closed',
      );

      final outputsResult = await testBuilder(
        RestageOutputsBuilder(
          const BuilderOptions({'bundled_runtime': true}),
        ),
        compilerSources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        outputsResult.succeeded,
        isTrue,
        reason: outputsResult.errors.join('\n'),
      );
      final measurementIndexBytes = readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'lib/generated/restage.measurement.index.json',
        ),
      );
      expect(
        measurementIndexBytes,
        orderedEquals(compilerOutput.outputIndexBytes('apps_examples')),
      );
      final measurementIndex = jsonDecode(utf8.decode(measurementIndexBytes))
          as Map<String, Object?>;
      expect(
        measurementIndex.keys.toSet(),
        {'entries', 'kind', 'package', 'schemaVersion'},
      );
      expect(
        measurementIndex['kind'],
        'restageMeasurementPublicationIndex',
      );
      final measurementIndexEntry =
          (measurementIndex['entries']! as List<Object?>).single
              as Map<String, Object?>;
      expect(
        measurementIndexEntry.keys.toSet(),
        {
          'draftBase64',
          'draftDigest',
          'routePlanDigest',
          'selector',
          'surfaceId',
        },
      );
      expect(
        _allJsonKeys(measurementIndex).intersection(const {
          'target',
          'surfaceRevisionId',
          'finalRevisionId',
          'publicationRowId',
        }),
        isEmpty,
      );
    },
  );

  test(
    'default tracked builder stamps the shipped policy and emits carriers',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final catalogBuild = await testBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        const {_sourceAsset: _source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(catalogBuild.succeeded, isTrue);
      final catalog = readerWriter.testing.readString(
        AssetId.parse(_catalogAsset),
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        {_sourceAsset: _source, _catalogAsset: catalog},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      final compilerOutput =
          RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      expect(compilerOutput.valid, isTrue);
      expect(compilerOutput.policy, isNotNull);
      expect(compilerOutput.policy!.toJson(), <String, Object?>{
        'collectionBudgetRevisionId':
            kMeasurementDefaultCollectionBudgetRevisionId,
        'minimumMeasurementClient': kMeasurementDefaultMinimumClient,
        'privacyPolicyRevisionId': kMeasurementDefaultPrivacyPolicyRevisionId,
      });
      expect(compilerOutput.publications, isNotEmpty);
      expect(compilerOutput.ledgerNodes, isNotEmpty);

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      final artifactTexts = {
        ...handoff.artifacts,
        ...handoff.borrowedArtifacts,
        ...handoff.ownedOutputs,
      }.values.map((bytes) => utf8.decode(bytes, allowMalformed: true));
      expect(
        artifactTexts.any((text) => text.contains('__restage_measurement_')),
        isTrue,
        reason: 'a stamped policy must put carriers in the emitted artifacts',
      );
    },
  );

  test(
      'records exact alias targets through analyzer translation and frozen '
      'RFW resolution', () async {
    final screen = await _compileAliasOccurrenceScreen();
    final occurrenceSet = screen.rfwCatalogOccurrenceSet;

    const expectedTargets = <String, (String, String)>{
      'RestagePager': ('restage.material', 'w0026'),
      'RestageDraggableSheet': ('restage.material', 'w0041'),
      'RestageDropdownString': ('restage.material', 'w0043'),
      'RestageToggleButtons': ('restage.material', 'w0044'),
      'RestageSegmentedButtonString': ('restage.material', 'w0045'),
    };
    for (final target in expectedTargets.entries) {
      final occurrence = occurrenceSet.occurrences.singleWhere(
        (occurrence) => occurrence.constructorCall.name == target.key,
      );
      expect(
        occurrence.descriptor.catalogLibraryNamespace,
        target.value.$1,
      );
      expect(
        occurrence.descriptor.catalogWidgetWireId.value,
        target.value.$2,
      );
    }
    expect(
      occurrenceSet.occurrences
          .map((occurrence) => occurrence.constructorCall.name),
      isNot(contains('PageView')),
    );
    expect(
      occurrenceSet
          .rebindFinalLibrary(
            fmt.decodeLibraryBlob(screen.blob),
          )
          .bindings,
      hasLength(occurrenceSet.occurrences.length),
    );
  });

  test('final screen emission requires frozen occurrence evidence', () async {
    final result = await _compileScreenWithoutFrozenOccurrenceEvidence();

    expect(result.screens, isEmpty);
    expect(
      result.issues.map((issue) => issue.code),
      contains(IssueCode.missingScreenDescriptor),
    );
    expect(
      result.issues.map((issue) => issue.message).join('\n'),
      contains('frozen RFW occurrence evidence'),
    );
  });

  test('final paywall forms require their own frozen occurrence evidence',
      () async {
    final standalone = await _compilePaywallWithoutFrozenOccurrenceEvidence(
      adapter: false,
    );
    final adapter = await _compilePaywallWithoutFrozenOccurrenceEvidence(
      adapter: true,
    );

    for (final result in [standalone, adapter]) {
      expect(result.paywalls, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.missingScreenDescriptor),
      );
    }
    expect(
      standalone.issues.map((issue) => issue.message).join('\n'),
      contains('standalone paywall'),
    );
    expect(
      adapter.issues.map((issue) => issue.message).join('\n'),
      contains('adapter paywall'),
    );
  });

  test(
    'finalized generated source carriers rebuild byte-identically and track '
    'the exact final draft closure',
    () async {
      final first = await _compileMeasuredScreenSource(_source);
      final rebuilt = await _compileMeasuredScreenSource(_source);
      final changed = await _compileMeasuredScreenSource(
        _source.replaceFirst("Text('Ordinary')", "Text('Ordinary changed')"),
      );

      expect(first.output.valid, isTrue);
      expect(rebuilt.output.valid, isTrue);
      expect(changed.output.valid, isTrue);
      expect(first.output.canonicalBytes, rebuilt.output.canonicalBytes);
      expect(first.handoffJson, rebuilt.handoffJson);

      final firstPublication = first.output.publications.single;
      final changedPublication = changed.output.publications.single;
      expect(
        changedPublication.draft.canonicalDigest,
        isNot(firstPublication.draft.canonicalDigest),
      );
      expect(
        _generatedCarrierPart(first.handoff),
        contains(firstPublication.draft.canonicalDigest.hex),
      );
      expect(
        _generatedCarrierPart(changed.handoff),
        contains(changedPublication.draft.canonicalDigest.hex),
      );
      expect(changed.handoffJson, isNot(first.handoffJson));
    },
  );

  test(
    'paywall standalone and flow forms retain distinct frozen occurrence '
    'ownership through final composition',
    () async {
      const paywall = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/premium.restage.g.dart';

@Paywall(id: 'premium')
final class PremiumPaywall extends StatelessWidget {
  const PremiumPaywall({super.key});

  static const complete = SurfaceEvent<void>('complete');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: paywallEvent('complete'),
        child: const Text('Upgrade'),
      );
}
''';
      const intro = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/intro.restage.g.dart';

@Screen(id: 'intro')
final class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Intro');
}
''';
      const flow = '''
import 'package:restage/restage.dart';

import '../features/intro.dart';
import '../paywalls/premium.dart';

part 'restage.generated/offer.restage.g.dart';

@FlowGraph(id: 'offer', surface: Surface.onboarding)
const offer = FlowDefinition(
  start: IntroScreen,
  transitions: [
    Transition(IntroScreen.next, to: PremiumPaywall),
    Transition.complete(PremiumPaywall.complete),
  ],
);
''';
      final sources = <String, String>{
        'apps_examples|lib/paywalls/premium.dart': paywall,
        'apps_examples|lib/features/intro.dart': intro,
        'apps_examples|lib/journeys/offer.dart': flow,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(_policyOptions),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

      final measurement = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      final paywallPublication = measurement.publications.singleWhere(
        (publication) =>
            publication.selector.sourceKind == SurfaceSourceKind.paywall,
      );
      final flowPublication = measurement.publications.singleWhere(
        (publication) => publication.selector.slug == 'offer',
      );
      expect(paywallPublication.routePlan.routes, hasLength(1));
      expect(flowPublication.routePlan.routes, hasLength(1));
      expect(
        paywallPublication.routePlan.routes.single.generatedReferenceId,
        flowPublication.routePlan.routes.single.generatedReferenceId,
        reason: 'one source event keeps one compiler-ledger reference',
      );
      expect(
        paywallPublication.routePlan.routes.single.carrier,
        isNot(flowPublication.routePlan.routes.single.carrier),
        reason:
            'each publication artifact occurrence has its own complete carrier',
      );

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      final paywallManifestEntry = handoff.manifest!.publications.singleWhere(
        (entry) => entry.publication.sourceKind == SurfaceSourceKind.paywall,
      );
      final flowManifestEntry = handoff.manifest!.publications.singleWhere(
        (entry) => entry.publication.slug == 'offer',
      );
      final paywallBlobArtifact = paywallManifestEntry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob &&
            artifact.id == 'premium',
      );
      final flowBlobArtifact = flowManifestEntry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRole.screenBlob &&
            artifact.id == 'paywall_premium',
      );
      final paywallBlob = handoff.artifacts[paywallBlobArtifact.path] ??
          handoff.borrowedArtifacts[paywallBlobArtifact.path]!;
      final flowBlob = handoff.artifacts[flowBlobArtifact.path] ??
          handoff.borrowedArtifacts[flowBlobArtifact.path]!;
      final paywallBlobEdge = paywallPublication.routePlan.artifacts
          .singleWhere(
            (artifact) =>
                artifact.artifactId ==
                measurementArtifactIdForPublicationArtifactV1(
                  paywallPublication.selector,
                  paywallBlobArtifact,
                ),
          )
          .occurrenceEdgeToken;
      final flowBlobEdge = flowPublication.routePlan.artifacts
          .singleWhere(
            (artifact) =>
                artifact.artifactId ==
                measurementArtifactIdForPublicationArtifactV1(
                  flowPublication.selector,
                  flowBlobArtifact,
                ),
          )
          .occurrenceEdgeToken;
      final paywallPresentationCarriers = _presentationRouteCarriers(
        fmt.decodeLibraryBlob(Uint8List.fromList(paywallBlob)),
      );
      final flowPresentationCarriers = _presentationRouteCarriers(
        fmt.decodeLibraryBlob(Uint8List.fromList(flowBlob)),
      );
      expect(
        paywallPresentationCarriers,
        {
          for (final route
              in paywallPublication.routePlan.presentationRoutes.where(
            (route) => route.artifactOccurrenceEdgeToken == paywallBlobEdge,
          ))
            route.carrier,
        },
      );
      expect(
        flowPresentationCarriers,
        {
          for (final route in flowPublication.routePlan.presentationRoutes
              .where(
                  (route) => route.artifactOccurrenceEdgeToken == flowBlobEdge))
            route.carrier,
        },
      );
      expect(
        paywallPresentationCarriers,
        isNot(equals(flowPresentationCarriers)),
        reason: 'the standalone and flow-adapter blobs must compose their own '
            'frozen RFW occurrence sets, not rebind one form against the other',
      );
      final emittedCarriers = <String>[];
      for (final entry in {
        ...handoff.artifacts,
        ...handoff.borrowedArtifacts,
        ...handoff.ownedOutputs,
      }.entries.where((entry) => entry.key.endsWith('.rfw'))) {
        for (final handler in _eventHandlers(
          fmt.decodeLibraryBlob(Uint8List.fromList(entry.value)),
        )) {
          final carrier =
              handler.eventArguments[kMeasurementRouteArgumentKeyV1];
          if (carrier is String) emittedCarriers.add(carrier);
          expect(
            handler.eventArguments,
            isNot(contains(kMeasurementRouteReferenceMarkerKeyV1)),
          );
        }
      }
      expect(
        emittedCarriers,
        unorderedEquals([
          paywallPublication.routePlan.routes.single.carrier,
          flowPublication.routePlan.routes.single.carrier,
        ]),
      );
    },
  );

  test(
    'unmeasured parent publishes the finalized measured child hash',
    () async {
      const childScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/measured_child_entry.restage.g.dart';

@Screen(id: 'measured_child_entry')
final class MeasuredChildEntry extends StatelessWidget {
  const MeasuredChildEntry({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: surfaceEvent(finish),
        child: const Text('Finish child'),
      );
}
''';
      const childFlow = '''
import 'package:restage/restage.dart';

import '../screens/measured_child_entry.dart';

part 'restage.generated/measured_child.restage.g.dart';

@FlowGraph(id: 'measured_child', surface: Surface.general)
final class MeasuredChild extends RestageFlow {
  const MeasuredChild();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: measuredChildEntryRef,
      states: [
        screen(measuredChildEntryRef)
            .on(MeasuredChildEntry.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
      const parentScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/parent_entry.restage.g.dart';

@Screen(id: 'parent_entry')
final class ParentEntry extends StatelessWidget {
  const ParentEntry({super.key});

  static const advance = SurfaceEvent<void>('advance');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: surfaceEvent(advance),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const Text('Details'),
            ),
            child: const Text('Details'),
          ),
        ],
      );
}
''';
      const parentFlow = '''
import 'package:restage/restage.dart';

import '../screens/parent_entry.dart';

part 'restage.generated/unmeasured_parent.restage.g.dart';

Map<String, Object?> _decodeMeasuredChild(Map<String, Object?> result) =>
    result;

const measuredChildRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'measured_child',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  decodeResult: _decodeMeasuredChild,
);

@FlowGraph(id: 'unmeasured_parent', surface: Surface.general)
final class UnmeasuredParent extends RestageFlow {
  const UnmeasuredParent();

  @override
  FlowDef buildFlow() {
    final child = flowNode('child');
    final done = endState('done');
    return flow(
      initial: parentEntryRef,
      states: [
        screen(parentEntryRef).on(ParentEntry.advance).goTo(child),
        subFlow(
          child,
          flow: measuredChildRef,
          input: const {},
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(fields: {}),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''';
      const sources = <String, String>{
        'apps_examples|lib/screens/measured_child_entry.dart': childScreen,
        'apps_examples|lib/flows/measured_child.dart': childFlow,
        'apps_examples|lib/screens/parent_entry.dart': parentScreen,
        'apps_examples|lib/flows/unmeasured_parent.dart': parentFlow,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final compilerResult = await testBuilder(
        const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        compilerResult.succeeded,
        isTrue,
        reason: compilerResult.errors.join('\n'),
      );

      final measurement = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
        ),
      );
      final childPublication = measurement.publications.singleWhere(
        (publication) => publication.selector.slug == 'measured_child',
      );
      expect(childPublication.routePlan.routes, isNotEmpty);
      expect(
        measurement.publications
            .map((publication) => publication.selector.slug),
        isNot(contains('unmeasured_parent')),
      );

      final publicationBundle = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      final publications = publicationBundle.manifest!.publications;
      final parentPublication = publications.singleWhere(
        (entry) => entry.publication.slug == 'unmeasured_parent',
      );
      const parentDocumentPath =
          'assets/general/flows/unmeasured_parent.flow.json';
      const childDocumentPath = 'assets/general/flows/measured_child.flow.json';
      final parentArtifact = parentPublication.artifacts.singleWhere(
        (artifact) => artifact.path == parentDocumentPath,
      );
      final parentBytes = publicationBundle.artifacts[parentDocumentPath]!;
      final childBytes = publicationBundle.artifacts[childDocumentPath]!;
      final parentDocument = FlowDocumentCodec.decodeJson(
        utf8.decode(parentBytes),
      );
      final childState = parentDocument.states['child']! as SubFlowState;
      expect(childState.contentHash, FlowContentHash.compute(childBytes));
      expect(
        parentArtifact.contentHash,
        CapabilitySidecar.hashBlob(parentBytes),
      );
      expect(
        publicationBundle.artifactLibraryPaths[parentDocumentPath],
        'lib/flows/unmeasured_parent.dart',
      );
      expect(
        () => publicationBundle.manifest!.validateArtifactClosure({
          ...publicationBundle.artifacts,
          ...publicationBundle.borrowedArtifacts,
        }),
        returnsNormally,
      );

      final outputsResult = await testBuilder(
        RestageOutputsBuilder(_bundledPolicyOptions),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        outputsResult.succeeded,
        isTrue,
        reason: outputsResult.errors.join('\n'),
      );
      final emittedBundle = RestageBundleCodec.decode(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            'assets/restage/bundles/lib/flows/unmeasured_parent.rsbundle',
          ),
        ),
      );
      final parentEntry = emittedBundle.entries.singleWhere(
        (entry) => entry.logicalPath == parentDocumentPath,
      );
      expect(parentEntry.bytes, orderedEquals(parentBytes));
      expect(parentEntry.sha256, parentArtifact.contentHash);
    },
  );

  test(
    'legacy FlowSource closes over recompiled ScreenSource artifacts and '
    'their final hashes',
    () async {
      const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const finish = OnboardingEvent<void>('finish');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onboardingEvent(finish),
        child: const Text('Finish'),
      );
}
''';
      const flow = '''
import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'restage.generated/welcome_flow.restage.g.dart';

@FlowSource(id: 'welcome_flow', version: 1, minClient: 1)
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: WelcomeScreenDescriptor.ref,
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
      final sources = <String, String>{
        'apps_examples|lib/onboarding/screens/welcome.dart': screen,
        'apps_examples|lib/onboarding/flows/welcome_flow.dart': flow,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final compilerLogs = <String>[];
      final screenResult = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        screenResult.succeeded,
        isTrue,
        reason: screenResult.errors.join('\n'),
      );
      final flowResult = await testBuilder(
        onboardingFlowBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        flowResult.succeeded,
        isTrue,
        reason: flowResult.errors.join('\n'),
      );
      final compilerResult = await testBuilder(
        const PackageSurfaceCompilerBuilder(_policyOptions),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: (record) => compilerLogs.add(record.message),
      );
      expect(
        compilerResult.succeeded,
        isTrue,
        reason: compilerResult.errors.join('\n'),
      );
      expect(
        compilerLogs.where(
          (message) =>
              message.startsWith('Measurement is unavailable for ') &&
              (message.contains('for welcome:') ||
                  message.contains('for screen/welcome:')),
        ),
        isEmpty,
        reason: 'resolved ScreenSource must not be reported as unavailable',
      );

      final measurement = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      final screenPublication = measurement.publications.singleWhere(
        (publication) =>
            publication.selector.sourceKind == SurfaceSourceKind.screen,
      );
      final flowPublication = measurement.publications.singleWhere(
        (publication) =>
            publication.selector.sourceKind == SurfaceSourceKind.flowGraph,
      );
      expect(screenPublication.routePlan.routes, hasLength(1));
      expect(flowPublication.routePlan.routes, hasLength(1));
      expect(
        screenPublication.routePlan.routes.single.generatedReferenceId,
        flowPublication.routePlan.routes.single.generatedReferenceId,
      );
      expect(
        screenPublication.routePlan.routes.single.carrier,
        isNot(flowPublication.routePlan.routes.single.carrier),
      );

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      expect(
        () => handoff.manifest!.validateArtifactClosure({
          ...handoff.artifacts,
          ...handoff.borrowedArtifacts,
        }),
        returnsNormally,
      );
      final emittedCarriers = <String>[];
      for (final entry in handoff.manifest!.publications) {
        for (final artifact in entry.artifacts.where(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRole.screenBlob,
        )) {
          final blob = handoff.artifacts[artifact.path] ??
              handoff.borrowedArtifacts[artifact.path]!;
          for (final handler in _eventHandlers(
            fmt.decodeLibraryBlob(Uint8List.fromList(blob)),
          )) {
            final carrier =
                handler.eventArguments[kMeasurementRouteArgumentKeyV1];
            if (carrier is String) emittedCarriers.add(carrier);
          }
        }
      }
      expect(
        emittedCarriers,
        unorderedEquals([
          screenPublication.routePlan.routes.single.carrier,
          flowPublication.routePlan.routes.single.carrier,
        ]),
      );
      final generatedParts = [
        for (final entry in handoff.ownedOutputs.entries)
          if (entry.key.endsWith('.g.dart')) utf8.decode(entry.value),
      ];
      expect(generatedParts, hasLength(2));
      expect(
        generatedParts
            .where(
              (part) => part.contains('WelcomeScreenDescriptor'),
            )
            .single,
        allOf(
          contains('generatedWithMeasurementPublicationDraftDigest'),
          contains(screenPublication.draft.canonicalDigest.hex),
        ),
      );
      expect(
        generatedParts
            .where(
              (part) => part.contains('WelcomeFlowDescriptor'),
            )
            .single,
        allOf(
          contains('generatedWithMeasurementPublicationDraftDigest'),
          contains(flowPublication.draft.canonicalDigest.hex),
        ),
      );
    },
  );

  test(
    'presentation-only legacy screen and flow carry finalized draft digests',
    () async {
      const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/quiet.restage.g.dart';

@ScreenSource(id: 'quiet')
final class QuietScreen extends StatelessWidget {
  const QuietScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Quiet');
}
''';
      const flow = '''
import 'package:restage/restage.dart';

import '../screens/quiet.dart';

part 'restage.generated/quiet_flow.restage.g.dart';

@FlowSource(id: 'quiet_flow', version: 1, minClient: 1)
final class QuietFlow extends RestageFlow {
  const QuietFlow();

  @override
  FlowDef buildFlow() {
    return flow(
      initial: QuietScreenDescriptor.ref,
      states: [screen(QuietScreenDescriptor.ref)],
    );
  }
}
''';
      final sources = <String, String>{
        'apps_examples|lib/onboarding/screens/quiet.dart': screen,
        'apps_examples|lib/onboarding/flows/quiet_flow.dart': flow,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final screenResult = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        screenResult.succeeded,
        isTrue,
        reason: screenResult.errors.join('\n'),
      );
      final flowResult = await testBuilder(
        onboardingFlowBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        flowResult.succeeded,
        isTrue,
        reason: flowResult.errors.join('\n'),
      );
      final compilerResult = await testBuilder(
        const PackageSurfaceCompilerBuilder(_policyOptions),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        compilerResult.succeeded,
        isTrue,
        reason: compilerResult.errors.join('\n'),
      );

      final measurement = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        readerWriter.testing.readBytes(
          AssetId(
            'apps_examples',
            kRestageMeasurementCompilerOutputPath,
          ),
        ),
      );
      final screenPublication = measurement.publications.singleWhere(
        (publication) =>
            publication.selector.sourceKind == SurfaceSourceKind.screen,
      );
      final flowPublication = measurement.publications.singleWhere(
        (publication) =>
            publication.selector.sourceKind == SurfaceSourceKind.flowGraph,
      );
      for (final publication in [screenPublication, flowPublication]) {
        expect(publication.routePlan.routes, isEmpty);
        expect(publication.routePlan.presentationRoutes, isNotEmpty);
      }

      final handoff = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );
      final screenManifestEntry = handoff.manifest!.publications.singleWhere(
        (entry) => entry.publication.sourceKind == SurfaceSourceKind.screen,
      );
      final flowManifestEntry = handoff.manifest!.publications.singleWhere(
        (entry) => entry.publication.sourceKind == SurfaceSourceKind.flowGraph,
      );
      Set<String> presentationCarriersFor(
        SurfacePublicationManifestEntry entry,
      ) =>
          {
            for (final artifact in entry.artifacts.where(
              (artifact) =>
                  artifact.role == SurfacePublicationArtifactRole.screenBlob,
            ))
              ..._presentationRouteCarriers(
                fmt.decodeLibraryBlob(
                  Uint8List.fromList(
                    handoff.artifacts[artifact.path] ??
                        handoff.borrowedArtifacts[artifact.path]!,
                  ),
                ),
              ),
          };
      expect(
        presentationCarriersFor(screenManifestEntry),
        {
          for (final route in screenPublication.routePlan.presentationRoutes)
            route.carrier,
        },
      );
      expect(
        presentationCarriersFor(flowManifestEntry),
        {
          for (final route in flowPublication.routePlan.presentationRoutes)
            route.carrier,
        },
      );

      final generatedParts = [
        for (final entry in handoff.ownedOutputs.entries)
          if (entry.key.endsWith('.g.dart')) utf8.decode(entry.value),
      ];
      void expectGeneratedCarrier(
        String descriptor,
        String expectedDigest,
      ) {
        final part =
            generatedParts.where((part) => part.contains(descriptor)).single;
        expect(
          part,
          contains('generatedWithMeasurementPublicationDraftDigest'),
        );
        final embeddedDigests = RegExp(
          'measurementPublicationDraftDigest:\\s*[\'"]([^\'"]+)[\'"],',
        )
            .allMatches(part)
            .map((match) => match.group(1))
            .whereType<String>()
            .toList();
        expect(embeddedDigests, [expectedDigest]);
      }

      expectGeneratedCarrier(
        'QuietScreenDescriptor',
        screenPublication.draft.canonicalDigest.hex,
      );
      expectGeneratedCarrier(
        'QuietFlowDescriptor',
        flowPublication.draft.canonicalDigest.hex,
      );
    },
  );

  test(
    'ordinary parenthesized elements preserve stored measurement identities',
    () async {
      await _expectParenthesizedActionLedgerCompatibility(
        mixed: false,
        fixturePath:
            'test/fixtures/measurement_ledger/parenthesized_action_ordinary.json',
      );
    },
  );

  test(
    'mixed parenthesized elements preserve stored measurement identities',
    () async {
      await _expectParenthesizedActionLedgerCompatibility(
        mixed: true,
        fixturePath:
            'test/fixtures/measurement_ledger/parenthesized_action_mixed.json',
      );
    },
  );

  test('semantic collection entrances retain distinct measurement identities',
      () async {
    final ordinaryInline = await _compileMeasuredScreenSource(
      _semanticEntranceSource(mixed: false, includeHelper: false),
    );
    final expandedInline = await _compileMeasuredScreenSource(
      _semanticEntranceSource(mixed: true, includeHelper: false),
    );
    final compiled = await _compileMeasuredScreenSource(
      _semanticEntranceSource(mixed: true),
    );

    expect(
      (
        compiled.output.valid,
        compiled.output.publications.length,
        compiled.output.proposals.length,
        compiled.output.errors.length,
      ),
      (true, 1, 0, 0),
    );
    expect(
      (
        ordinaryInline.output.valid,
        ordinaryInline.output.publications.length,
        expandedInline.output.valid,
        expandedInline.output.publications.length,
      ),
      (true, 1, true, 1),
    );
    const source = 'package:apps_examples/features/measured.dart#Welcome';
    const column = 'package:flutter/src/widgets/basic.dart#Column';
    const button =
        'package:flutter/src/material/elevated_button.dart#ElevatedButton';
    const custom = 'package:apps_examples/features/measured.dart#InlineAction';
    final eventNodes = compiled.output.ledgerNodes
        .where(
          (node) => node.active && node.events.any((event) => event.active),
        )
        .toList();
    const listRoot = '$source|child:$column:$column.children';
    final distinctLocators = {
      '$listRoot[0]|helper:$source.action|widget:$button',
      '$listRoot[1]|inline:$custom|inlinedBody:$custom|widget:$button',
    };
    const selectedLocator = '$listRoot[2]|collection:listElement[2]|'
        'collection:selectedThen[0]|widget:$button';
    expect(
      eventNodes.map((node) => node.structuralOccurrenceKey).toSet(),
      {
        ...distinctLocators,
        selectedLocator,
      },
    );
    expect(
      eventNodes.map((node) => node.codeIdentityId.value).toSet(),
      hasLength(3),
    );
    const inlineOnlyLocator =
        '$listRoot[0]|inline:$custom|inlinedBody:$custom|widget:$button';
    final ordinaryInlineNode = ordinaryInline.output.ledgerNodes.singleWhere(
      (node) => node.structuralOccurrenceKey == inlineOnlyLocator,
    );
    final expandedInlineNode = expandedInline.output.ledgerNodes.singleWhere(
      (node) => node.structuralOccurrenceKey == inlineOnlyLocator,
    );
    expect(expandedInlineNode.toJson(), ordinaryInlineNode.toJson());
  });

  test(
    'ledger rebuild is stable and an unambiguous in-screen move keeps '
    'identities',
    () async {
      final first = await _compileLedgerSource(_ledgerSource());
      expect(first.result.succeeded, isTrue);
      final rebuilt = await _compileLedgerSource(
        _ledgerSource(),
        priorOutput: first.output,
      );
      expect(rebuilt.result.succeeded, isTrue);
      expect(
        _activeLedgerIdentityProjection(rebuilt.output),
        _activeLedgerIdentityProjection(first.output),
      );
      final settled = await _compileLedgerSource(
        _ledgerSource(),
        priorOutput: rebuilt.output,
      );
      expect(settled.result.succeeded, isTrue);
      expect(settled.output.canonicalBytes, rebuilt.output.canonicalBytes);

      final moved = await _compileLedgerSource(
        _ledgerSource(wrapped: true),
        priorOutput: first.output,
      );
      expect(
        moved.result.succeeded,
        isTrue,
        reason: moved.result.errors.join('\n'),
      );
      expect(moved.output.valid, isTrue);
      expect(moved.output.proposals, isEmpty);
      expect(moved.output.publications, isNotEmpty);

      final firstReference = first.output.ledgerNodes
          .expand((node) => node.events)
          .singleWhere((event) => event.active)
          .generatedReferenceId;
      final movedReference = moved.output.ledgerNodes
          .expand((node) => node.events)
          .singleWhere((event) => event.active)
          .generatedReferenceId;
      expect(movedReference, firstReference);
      Set<String> sourceCodeIdentities(
        RestageMeasurementCompilerOutputV1 output,
      ) =>
          {
            for (final node in output.ledgerNodes)
              if (node.active && node.structuralOccurrenceKey.contains('|'))
                node.codeIdentityId.value,
          };
      expect(
        sourceCodeIdentities(moved.output),
        containsAll(sourceCodeIdentities(first.output)),
      );
    },
  );

  test(
      'ambiguous structural movement proposes candidates and accepts reviewed '
      'relocations', () async {
    final first = await _compileLedgerSource(
      _ledgerSource(repeated: true),
    );
    expect(first.result.succeeded, isTrue);
    final ambiguous = await _compileLedgerSource(
      _ledgerSource(wrapped: true),
      priorOutput: first.output,
    );
    expect(ambiguous.result.succeeded, isFalse);
    expect(ambiguous.output.valid, isFalse);
    expect(ambiguous.output.publications, isEmpty);
    expect(
      ambiguous.output.proposals.any(
        (proposal) =>
            proposal.candidatePriorStructuralOccurrenceKeys.length > 1,
      ),
      isTrue,
    );

    final relocations = <MeasurementCompilerLedgerRelocation>[];
    for (final proposal in ambiguous.output.proposals) {
      final priorLocator =
          proposal.candidatePriorStructuralOccurrenceKeys.first;
      final priorNode = first.output.ledgerNodes.singleWhere(
        (node) => node.structuralOccurrenceKey == priorLocator,
      );
      relocations.add(
        MeasurementCompilerLedgerRelocation(
          fromStructuralOccurrenceKey: priorLocator,
          toStructuralOccurrenceKey: proposal.toStructuralOccurrenceKey,
          codeIdentityId: priorNode.codeIdentityId,
        ),
      );
    }
    final reviewedPrior = RestageMeasurementCompilerOutputV1(
      valid: true,
      errors: const [],
      policy: first.output.policy,
      nextIdentitySequence: first.output.nextIdentitySequence,
      ledgerNodes: first.output.ledgerNodes,
      acceptedRelocations: relocations,
      proposals: const [],
      publications: first.output.publications,
    );
    final accepted = await _compileLedgerSource(
      _ledgerSource(wrapped: true),
      priorOutput: reviewedPrior,
    );
    expect(
      accepted.result.succeeded,
      isTrue,
      reason: accepted.result.errors.join('\n'),
    );
    for (final relocation in relocations) {
      expect(
        accepted.output.ledgerNodes
            .singleWhere(
              (node) =>
                  node.structuralOccurrenceKey ==
                  relocation.toStructuralOccurrenceKey,
            )
            .codeIdentityId,
        relocation.codeIdentityId,
      );
    }
  });

  test('tracked builder rejects malformed committed ledger authority',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(_policyOptions),
      {
        'apps_examples|lib/features/ledger.dart': _ledgerSource(),
        'apps_examples|$kRestageMeasurementCompilerLedgerSourcePath': '{}',
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          kRestageMeasurementCompilerOutputPath,
        ),
      ),
    );
    expect(output.valid, isFalse);
    expect(
      output.errors.join('\n'),
      contains('Measurement compiler state is invalid'),
    );
  });
}

Map<String, Object?> _activeLedgerIdentityProjection(
  RestageMeasurementCompilerOutputV1 output,
) =>
    {
      for (final node in output.ledgerNodes.where((node) => node.active))
        node.structuralOccurrenceKey: {
          'codeIdentityId': node.codeIdentityId.value,
          'canonicalNodeTokenId': node.canonicalNodeTokenId.value,
          'events': {
            for (final event in node.events.where((event) => event.active))
              event.resolvedEventLocator: {
                'generatedReferenceId': event.generatedReferenceId.value,
                'lineageId': event.lineageId.value,
              },
          },
        },
    };

String _ledgerSource({bool wrapped = false, bool repeated = false}) {
  final button = '''
FilledButton(
  onPressed: surfaceEvent(activate),
  child: const Text('Activate'),
)
''';
  final body = repeated
      ? 'Column(children: [$button, $button])'
      : wrapped
          ? 'Padding(padding: const EdgeInsets.all(8), child: $button)'
          : button;
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/ledger.restage.g.dart';

@Screen(id: 'ledger', surface: Surface.general)
final class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) => $body;
}
''';
}

Future<
    ({
      TestBuilderResult result,
      RestageMeasurementCompilerOutputV1 output,
    })> _compileLedgerSource(
  String source, {
  RestageMeasurementCompilerOutputV1? priorOutput,
  String asset = 'apps_examples|lib/features/ledger.dart',
}) async {
  final sources = <String, String>{
    asset: source,
    if (priorOutput != null)
      'apps_examples|$kRestageMeasurementCompilerLedgerSourcePath':
          priorOutput.encodeCanonicalJson(),
  };
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(_policyOptions),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        kRestageMeasurementCompilerOutputPath,
      ),
    ),
  );
  return (result: result, output: output);
}

Future<void> _expectParenthesizedActionLedgerCompatibility({
  required bool mixed,
  required String fixturePath,
}) async {
  final prior = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    utf8.encode(File(fixturePath).readAsStringSync().trim()),
  );
  final compiled = await _compileLedgerSource(
    _parenthesizedActionSource(mixed: mixed),
    priorOutput: prior,
    asset: 'apps_examples|lib/onboarding/screens/parenthesized_action.dart',
  );
  expect(
    (
      compiled.result.succeeded,
      compiled.output.valid,
      compiled.output.publications.length,
      compiled.output.proposals.length,
      compiled.output.errors.length,
    ),
    (true, true, 1, 0, 0),
    reason: compiled.result.errors.join('\n'),
  );

  const buttonLocator =
      'package:apps_examples/onboarding/screens/parenthesized_action.dart#Welcome|'
      'child:package:flutter/src/widgets/basic.dart#Column:'
      'package:flutter/src/widgets/basic.dart#Column.children[0]|'
      'widget:package:flutter/src/material/elevated_button.dart#ElevatedButton';
  final priorButton = prior.ledgerNodes.singleWhere(
    (node) => node.structuralOccurrenceKey == buttonLocator,
  );
  expect(
    (
      priorButton.reconciliationFingerprint,
      priorButton.codeIdentityId.value,
      priorButton.canonicalNodeTokenId.value,
    ),
    (
      'fingerprint.v1.'
          'c82ea16ca1beff79d4623353a7b58392b'
          'b97bc8c9f81d7058d717d629fa67f63',
      'code.auto.0000000000000002',
      'node.auto.0000000000000002',
    ),
  );
  final currentButton = compiled.output.ledgerNodes.singleWhere(
    (node) => node.structuralOccurrenceKey == buttonLocator,
  );
  expect(currentButton.toJson(), priorButton.toJson());

  const subtree =
      'package:apps_examples/onboarding/screens/parenthesized_action.dart#Welcome|'
      'child:package:flutter/src/widgets/basic.dart#Column:'
      'package:flutter/src/widgets/basic.dart#Column.children[0]|';
  final priorSubtree = {
    for (final node in prior.ledgerNodes.where(
      (node) => node.active && node.structuralOccurrenceKey.startsWith(subtree),
    ))
      node.structuralOccurrenceKey: node.toJson(),
  };
  final currentSubtree = {
    for (final node in compiled.output.ledgerNodes.where(
      (node) => node.active && node.structuralOccurrenceKey.startsWith(subtree),
    ))
      node.structuralOccurrenceKey: node.toJson(),
  };
  expect(currentSubtree, priorSubtree);
}

String _parenthesizedActionSource({required bool mixed}) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/parenthesized_action.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.general)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const activate = SurfaceEvent<void>('activate');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          (ElevatedButton(
            onPressed: surfaceEvent(activate),
            child: const Text('Continue'),
          )),
          ${mixed ? "if (true) const Text('Sentinel')," : ''}
        ],
      );
}
''';

String _semanticEntranceSource({
  required bool mixed,
  bool includeHelper = true,
}) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/measured.restage.g.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.identity'),
  capabilityVersion: 1,
)
const entranceLibrary = 0;

@RestageWidget(
  name: 'InlineAction',
  library: WidgetLibrary.custom('acme.identity'),
  category: WidgetCategory.input,
  description: 'Inline action.',
)
final class InlineAction extends StatelessWidget {
  const InlineAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onPressed,
        child: const Text('Inline'),
      );
}

@Screen(id: 'welcome', surface: Surface.general)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const activate = SurfaceEvent<void>('activate');

  Widget action() => ElevatedButton(
        onPressed: surfaceEvent(activate),
        child: const Text('Helper'),
      );

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ${includeHelper ? 'action(),' : ''}
          InlineAction(onPressed: surfaceEvent(activate)),
          ${mixed ? '''
if (true)
            ElevatedButton(
              onPressed: surfaceEvent(activate),
              child: const Text('Selected'),
            ),''' : ''}
        ],
      );
}
''';

Future<
    ({
      RestageMeasurementCompilerOutputV1 output,
      RestageSurfacePublicationBundle handoff,
      String handoffJson,
    })> _compileMeasuredScreenSource(String source) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final catalogBuild = await testBuilder(
    const UserCatalogJsonBuilder(BuilderOptions.empty),
    <String, String>{_sourceAsset: source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(
    catalogBuild.succeeded,
    isTrue,
    reason: catalogBuild.errors.join('\n'),
  );
  final catalog = readerWriter.testing.readString(
    AssetId.parse(_catalogAsset),
  );
  final compilation = await testBuilder(
    const PackageSurfaceCompilerBuilder(_bundledPolicyOptions),
    <String, String>{_sourceAsset: source, _catalogAsset: catalog},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(
    compilation.succeeded,
    isTrue,
    reason: compilation.errors.join('\n'),
  );
  final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    readerWriter.testing.readBytes(
      AssetId('apps_examples', kRestageMeasurementCompilerOutputPath),
    ),
  );
  final handoffJson = readerWriter.testing.readString(
    AssetId('apps_examples', kRestageSurfacePublicationCompilerBundlePath),
  );
  return (
    output: output,
    handoff: RestageSurfacePublicationBundle.fromJson(
      jsonDecode(handoffJson) as Map<String, Object?>,
    ),
    handoffJson: handoffJson,
  );
}

Future<CompiledResolvedScreen> _compileAliasOccurrenceScreen() async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  ResolvedScreenInspectionResult? inspection;
  ResolvedScreenCompilationResult? compilation;
  await testBuilder(
    _AliasOccurrenceProbeBuilder((candidateInspection, candidateCompilation) {
      inspection = candidateInspection;
      compilation = candidateCompilation;
    }),
    const <String, String>{_sourceAsset: _aliasSource},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  final resolvedInspection = inspection;
  final resolvedCompilation = compilation;
  if (resolvedInspection == null || resolvedCompilation == null) {
    throw StateError('The alias occurrence probe did not produce a result');
  }
  expect(
    resolvedInspection.issues,
    isEmpty,
    reason: resolvedInspection.issues.map((issue) => issue.message).join('\n'),
  );
  expect(
    resolvedCompilation.issues,
    isEmpty,
    reason: resolvedCompilation.issues.map((issue) => issue.message).join('\n'),
  );
  expect(resolvedCompilation.screens, hasLength(1));
  return resolvedCompilation.screens.single;
}

Future<ResolvedScreenCompilationResult>
    _compileScreenWithoutFrozenOccurrenceEvidence() async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final catalogBuild = await testBuilder(
    const UserCatalogJsonBuilder(BuilderOptions.empty),
    const <String, String>{_sourceAsset: _source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(catalogBuild.succeeded, isTrue,
      reason: catalogBuild.errors.join('\n'));
  ResolvedScreenCompilationResult? compilation;
  await testBuilder(
    _MissingFrozenScreenProbeBuilder((candidate) {
      compilation = candidate;
    }),
    const <String, String>{_sourceAsset: _source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  final resolvedCompilation = compilation;
  if (resolvedCompilation == null) {
    throw StateError('The screen frozen-occurrence probe did not run');
  }
  return resolvedCompilation;
}

Future<ResolvedPaywallCompilationResult>
    _compilePaywallWithoutFrozenOccurrenceEvidence({
  required bool adapter,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  ResolvedPaywallCompilationResult? compilation;
  await testBuilder(
    _MissingFrozenPaywallProbeBuilder(
      adapter: adapter,
      onResult: (candidate) {
        compilation = candidate;
      },
    ),
    const <String, String>{
      'apps_examples|lib/paywalls/witness_offer.dart':
          _frozenWitnessPaywallSource,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  final resolvedCompilation = compilation;
  if (resolvedCompilation == null) {
    throw StateError('The paywall frozen-occurrence probe did not run');
  }
  return resolvedCompilation;
}

final class _AliasOccurrenceProbeBuilder implements Builder {
  _AliasOccurrenceProbeBuilder(this.onResult);

  final void Function(
    ResolvedScreenInspectionResult inspection,
    ResolvedScreenCompilationResult? compilation,
  ) onResult;

  @override
  Map<String, List<String>> get buildExtensions => const <String, List<String>>{
        '.dart': <String>['.alias_occurrence_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path != 'lib/features/measured.dart') return;
    final inspection = await inspectCanonicalScreenDeclarations(
      await buildStep.inputLibrary,
      buildStep.inputId,
    );
    if (inspection.issues.isNotEmpty) {
      onResult(inspection, null);
      return;
    }
    onResult(
      inspection,
      await compileResolvedScreens(buildStep, inspection.screens),
    );
  }
}

final class _MissingFrozenScreenProbeBuilder implements Builder {
  _MissingFrozenScreenProbeBuilder(this.onResult);

  final void Function(ResolvedScreenCompilationResult compilation) onResult;

  @override
  Map<String, List<String>> get buildExtensions => const <String, List<String>>{
        '.dart': <String>['.missing_frozen_screen_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path != 'lib/features/measured.dart') return;
    final inspection = await inspectCanonicalScreenDeclarations(
      await buildStep.inputLibrary,
      buildStep.inputId,
    );
    if (inspection.issues.isNotEmpty) {
      throw StateError('The screen frozen-occurrence probe found bad input');
    }
    final input = inspection.screens.single;
    onResult(
      await compileResolvedScreens(
        buildStep,
        inspection.screens,
        measurementRoutePlans: <String, MeasurementRouteEmissionPlan>{
          input.declarationIdentity: MeasurementRouteEmissionPlan(
              const <MeasurementRouteEmissionBinding>[]),
        },
      ),
    );
  }
}

final class _MissingFrozenPaywallProbeBuilder implements Builder {
  _MissingFrozenPaywallProbeBuilder({
    required this.adapter,
    required this.onResult,
  });

  final bool adapter;
  final void Function(ResolvedPaywallCompilationResult compilation) onResult;

  @override
  Map<String, List<String>> get buildExtensions => const <String, List<String>>{
        '.dart': <String>['.missing_frozen_paywall_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path != 'lib/paywalls/witness_offer.dart') return;
    final library = await buildStep.inputLibrary;
    final visited = await visitPaywallSources(library, buildStep.inputId);
    if (visited.issues.isNotEmpty || visited.sources.length != 1) {
      throw StateError('The paywall frozen-occurrence probe found bad input');
    }
    final source = visited.sources.single;
    final declarationIdentity = '${library.identifier}#${source.className}';
    final routePlans = <String, MeasurementRouteEmissionPlan>{
      declarationIdentity: MeasurementRouteEmissionPlan(
          const <MeasurementRouteEmissionBinding>[]),
    };
    onResult(
      await compileResolvedPaywalls(
        buildStep,
        library: library,
        assetId: buildStep.inputId,
        sources: visited.sources,
        canonicalPaywallIdFor: (_) => source.id,
        measurementRoutePlans: routePlans,
        measurementRouteOwnership: <String,
            MeasurementPaywallRouteEmissionOwnership>{
          declarationIdentity: MeasurementPaywallRouteEmissionOwnership(
            standalone: !adapter,
            adapter: adapter,
          ),
        },
      ),
    );
  }
}

String _generatedCarrierPart(RestageSurfacePublicationBundle handoff) =>
    utf8.decode(
      handoff.ownedOutputs.entries
          .singleWhere(
            (entry) => entry.key.endsWith('.g.dart'),
          )
          .value,
    );

List<fmt.EventHandler> _eventHandlers(fmt.RemoteWidgetLibrary library) {
  final handlers = <fmt.EventHandler>[];

  void visit(Object? value) {
    switch (value) {
      case fmt.RemoteWidgetLibrary library:
        for (final widget in library.widgets) {
          visit(widget);
        }
      case fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case fmt.EventHandler handler:
        handlers.add(handler);
        visit(handler.eventArguments);
      case fmt.ConstructorCall call:
        visit(call.arguments);
      case fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case fmt.Switch switchNode:
        visit(switchNode.input);
        for (final output in switchNode.outputs.values) {
          visit(output);
        }
      case Map<Object?, Object?> map:
        for (final entry in map.entries) {
          visit(entry.value);
        }
      case List<Object?> list:
        for (final item in list) {
          visit(item);
        }
      default:
        break;
    }
  }

  visit(library);
  return handlers;
}

List<String> _presentationWrappedNames(fmt.RemoteWidgetLibrary library) {
  final result = <String>[];

  void visit(Object? value) {
    switch (value) {
      case fmt.RemoteWidgetLibrary library:
        for (final widget in library.widgets) {
          visit(widget);
        }
      case fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case fmt.ConstructorCall call:
        if (call.name == 'MeasurementPresented') {
          var child = call.arguments['child'];
          while (child is fmt.ConstructorCall &&
              child.name == 'MeasurementSourcePresented') {
            child = child.arguments['child'];
          }
          if (child is fmt.ConstructorCall) result.add(child.name);
        }
        visit(call.arguments);
      case fmt.EventHandler handler:
        visit(handler.eventArguments);
      case fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case fmt.Switch switchNode:
        visit(switchNode.input);
        for (final output in switchNode.outputs.values) {
          visit(output);
        }
      case Map<Object?, Object?> map:
        for (final value in map.values) {
          visit(value);
        }
      case List<Object?> list:
        for (final value in list) {
          visit(value);
        }
      default:
        break;
    }
  }

  visit(library);
  return result;
}

List<String> _presentationWrappedNamesForWidget(
  fmt.RemoteWidgetLibrary library,
  String widgetName,
) {
  final declaration = library.widgets.singleWhere(
    (candidate) => candidate.name == widgetName,
  );
  return _presentationWrappedNames(
    fmt.RemoteWidgetLibrary(library.imports, [declaration]),
  );
}

Set<String> _presentationRouteCarriers(fmt.RemoteWidgetLibrary library) {
  final carriers = <String>{};

  void visit(Object? value) {
    switch (value) {
      case fmt.RemoteWidgetLibrary library:
        for (final widget in library.widgets) {
          visit(widget);
        }
      case fmt.WidgetDeclaration declaration:
        visit(declaration.initialState);
        visit(declaration.root);
      case fmt.ConstructorCall call:
        if (call.name == 'MeasurementPresented') {
          final routeCarriers = call.arguments['carriers'];
          if (routeCarriers is List<Object?>) {
            carriers.addAll(routeCarriers.whereType<String>());
          }
        }
        visit(call.arguments);
      case fmt.EventHandler handler:
        visit(handler.eventArguments);
      case fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case fmt.Switch switchNode:
        visit(switchNode.input);
        for (final output in switchNode.outputs.values) {
          visit(output);
        }
      case Map<Object?, Object?> map:
        for (final value in map.values) {
          visit(value);
        }
      case List<Object?> list:
        for (final value in list) {
          visit(value);
        }
      default:
        break;
    }
  }

  visit(library);
  return carriers;
}

Set<String> _allJsonKeys(Object? value) => switch (value) {
      Map<String, Object?>() => {
          ...value.keys,
          for (final child in value.values) ..._allJsonKeys(child),
        },
      List<Object?>() => {
          for (final child in value) ..._allJsonKeys(child),
        },
      _ => const {},
    };
