import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/placement_presentation.dart';
import 'package:restage/src/runtime/placement_registry.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/placement_delivery_fixture.dart';

void main() {
  testWidgets('only the presented root gets a revocable presented contract',
      (tester) async {
    Restage.debugReset();
    addTearDown(Restage.debugReset);
    late BuildContext hostContext;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      hostContext = context;
      return const Text('Home');
    })));
    final declarations = <String, PlacementDeclaration>{};
    late PlacementPresentationController presentation;
    var built = 0;
    final pending =
        Restage.presentPlacement(hostContext, builder: (context, controller) {
      presentation = controller;
      built++;
      return _ProbeMount(
          id: 'root',
          declarations: declarations,
          child: _ProbeMount(id: 'nested', declarations: declarations));
    });
    await tester.pumpAndSettle();
    expect(declarations['root']!.host.hosting.presentation,
        SurfacePresentationV1.presented);
    expect(declarations['nested']!.host.hosting.presentation,
        SurfacePresentationV1.inline);
    expect(placementHostIsCurrent(declarations['root']!.host), isTrue);
    expect(built, 1);
    presentation.close();
    expect(placementHostIsCurrent(declarations['root']!.host), isFalse);
    await tester.pumpAndSettle();
    await pending;
    expect(find.text('Home'), findsOneWidget);
    expect(placementHostIsCurrent(declarations['nested']!.host), isFalse);
  });

  testWidgets(
      'a returned widget wrapper grants one root lease without nested ownership',
      (tester) async {
    Restage.debugReset();
    addTearDown(Restage.debugReset);
    late BuildContext hostContext;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      hostContext = context;
      return const Text('Home');
    })));
    final declarations = <String, PlacementDeclaration>{};
    late PlacementPresentationController presentation;
    final pending =
        Restage.presentPlacement(hostContext, builder: (context, controller) {
      presentation = controller;
      return _WidgetRoot(
          child: Column(children: [
        _ProbeMount(
            id: 'root',
            declarations: declarations,
            child: _ProbeMount(id: 'nested', declarations: declarations)),
        _ProbeMount(id: 'peer', declarations: declarations),
      ]));
    });
    await tester.pumpAndSettle();
    expect(declarations['root']!.host.hosting.presentation,
        SurfacePresentationV1.presented);
    expect(declarations['nested']!.host.hosting.presentation,
        SurfacePresentationV1.inline);
    expect(declarations['peer']!.host.hosting.presentation,
        SurfacePresentationV1.inline);
    expect(placementHostIsCurrent(declarations['root']!.host), isTrue);
    presentation.close();
    expect(placementHostIsCurrent(declarations['root']!.host), isFalse);
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('fresh equal declarations keep currency until their name changes',
      (tester) async {
    final declarations = <PlacementDeclaration>[];
    await tester.pumpWidget(MaterialApp(
        home: _DiscoveryProbeMount(name: 'first', declarations: declarations)));
    final original = declarations.last;
    expect(placementHostIsCurrent(original.host), isTrue);
    await tester.pumpWidget(MaterialApp(
        home: _DiscoveryProbeMount(name: 'first', declarations: declarations)));
    expect(declarations.last, same(original));
    expect(placementHostIsCurrent(original.host), isTrue);
    await tester.pumpWidget(MaterialApp(
        home:
            _DiscoveryProbeMount(name: 'changed', declarations: declarations)));
    expect(declarations.last.mount.key.slug, 'changed');
    expect(declarations.last, isNot(same(original)));
    expect(placementHostIsCurrent(original.host), isFalse);
    expect(placementHostIsCurrent(declarations.last.host), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(placementHostIsCurrent(declarations.last.host), isFalse);
  });

  testWidgets(
      'closing a covered presentation leaves the later route owned by its caller',
      (tester) async {
    late BuildContext hostContext;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      hostContext = context;
      return const Text('Home');
    })));
    late PlacementPresentationController presentation;
    final pending =
        Restage.presentPlacement(hostContext, builder: (context, controller) {
      presentation = controller;
      return _ProbeMount(id: 'root', declarations: {});
    });
    await tester.pumpAndSettle();
    final navigator = Navigator.of(hostContext);
    final other = navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('Other route')));
    await tester.pumpAndSettle();
    presentation.close();
    await tester.pumpAndSettle();
    await pending;
    expect(find.text('Other route'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    await other;
    expect(find.text('Home'), findsOneWidget);
  });
}

final class _WidgetRoot extends StatelessWidget {
  const _WidgetRoot({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

GeneratedPlacementDefinition _probeDefinition() => _probeDefinitionValue;
final _probeDefinitionValue = GeneratedPlacementDefinition(
    defaultSurface: const PaywallRef('probe'),
    defaultSurfaceLocator: DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('paywall'),
        slug: 'probe',
        family: const DeliveryFamilySelectorV1.general()),
    key: PlacementKeyV1.generatedDefault(
        surfaceType: DeliverySurfaceTypeId('paywall'), slug: 'probe'),
    hostContract: _ProbeMount._host,
    vocabulary: SurfaceVocabulary.none);

final class _DiscoveryProbeMount extends StatefulWidget
    implements RestagePlacementMount {
  const _DiscoveryProbeMount({required this.name, required this.declarations});
  final String name;
  final List<PlacementDeclaration> declarations;
  @override
  PlacementMountBinding get placementBinding =>
      PlacementMountBinding(definition: _probeDefinition, name: name);
  @override
  State<_DiscoveryProbeMount> createState() => _DiscoveryProbeMountState();
}

final class _DiscoveryProbeMountState extends State<_DiscoveryProbeMount> {
  final discovery = PlacementHostDiscovery(
      configurationGeneration: () => 0, discovery: () => null);
  @override
  Widget build(BuildContext context) {
    widget.declarations
        .add(discovery.capture(widget.placementBinding, widget, context)!);
    return const Text('Probe');
  }

  @override
  void dispose() {
    discovery.dispose();
    super.dispose();
  }
}

final class _ProbeMount extends StatelessWidget
    implements RestagePlacementMount {
  _ProbeMount({required this.id, required this.declarations, this.child})
      : placementBinding = PlacementMountBinding.request(
            mount: PlacementMountRequestV1(
                key: PlacementKeyV1.named(slug: id),
                hostContractHash: _host.contentHash),
            hostContract: _host);
  static SurfaceHostContractV1 get _host => readPlacementDeliveryFixture()
      .request
      .buildContract
      .contractsByHash
      .values
      .first;
  final String id;
  final Map<String, PlacementDeclaration> declarations;
  final Widget? child;
  @override
  final PlacementMountBinding placementBinding;
  @override
  Widget build(BuildContext context) {
    declarations[id] =
        capturePlacementDeclaration(placementBinding, this, context);
    return child ?? Text(id);
  }
}
