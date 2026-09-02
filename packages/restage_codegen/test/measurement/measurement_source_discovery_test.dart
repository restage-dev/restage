import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/restage_codegen.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('MeasurementSourceDiscovery', () {
    test(
        'discovers resolved ordinary Flutter slots in ScreenSource and '
        'PaywallSource roots', () async {
      final screen = await _resolveFixture(
        _ordinarySource(),
      );
      final paywall = await _resolveFixture(
        _ordinarySource(
          annotation: 'PaywallSource',
          className: 'Upgrade',
          sourceId: 'upgrade',
        ),
        assetPath: 'lib/paywalls/upgrade.dart',
      );

      final screenDiscovery = _discover(
        screen,
        authority: MeasurementSourceAuthority.screen,
      );
      final paywallDiscovery = _discover(
        paywall,
        authority: MeasurementSourceAuthority.paywall,
      );

      for (final discovery in [screenDiscovery, paywallDiscovery]) {
        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.accepted,
          reason: discovery.rejectionReason,
        );
        expect(discovery.events, hasLength(2));
        expect(
          discovery.events.map(
            (event) => event.resolvedEvent.declarationProvenance.memberName,
          ),
          everyElement('onPressed'),
        );
        expect(discovery.nodes, hasLength(5));
      }
      expect(
        screenDiscovery.nodes.first.sourceProvenance.authority,
        MeasurementSourceAuthority.screen,
      );
      expect(
        paywallDiscovery.nodes.first.sourceProvenance.authority,
        MeasurementSourceAuthority.paywall,
      );
      const source =
          'package:apps_examples/onboarding/screens/probe.dart#Welcome';
      const column = 'package:flutter/src/widgets/basic.dart#Column';
      const button =
          'package:flutter/src/material/elevated_button.dart#ElevatedButton';
      const text = 'package:flutter/src/widgets/text.dart#Text';
      const firstPath = '$source|child:$column:$column.children[0]';
      const secondPath = '$source|child:$column:$column.children[1]';
      const firstButton = '$firstPath|widget:$button';
      const secondButton = '$secondPath|widget:$button';
      expect(
        screenDiscovery.nodes
            .map((node) => node.structuralOccurrenceKey)
            .toSet(),
        {
          '$source|widget:$column',
          firstButton,
          '$firstPath|child:$button:$button.child[0]|widget:$text',
          secondButton,
          '$secondPath|child:$button:$button.child[0]|widget:$text',
        },
      );
      const event = '$button|$button.onPressed';
      expect(
        _eventKeys(screenDiscovery).toSet(),
        {'$firstButton|$event', '$secondButton|$event'},
      );
    });

    test(
        'keys, copy, source layout, and argument traversal order do not '
        'author ordinary event identity', () async {
      final baseline = _discover(
        await _resolveFixture(_ordinarySource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        baseline.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: baseline.rejectionReason,
      );

      final variants = [
        _ordinarySource(key: "const ValueKey('renew')"),
        _ordinarySource(key: 'UniqueKey()'),
        _ordinarySource(copy: 'Start your trial'),
        '\n\n\n${_ordinarySource()}',
        _ordinarySource(eventBeforeChild: false),
      ];

      for (final source in variants) {
        final discovery = _discover(
          await _resolveFixture(source),
          authority: MeasurementSourceAuthority.screen,
        );
        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.accepted,
        );
        expect(_eventKeys(discovery), orderedEquals(_eventKeys(baseline)));
      }
    });

    test(
        'keeps repeated ordinary occurrences distinct through static '
        'occurrence edges', () async {
      final discovery = _discover(
        await _resolveFixture(_ordinarySource(copy: 'Same copy')),
        authority: MeasurementSourceAuthority.screen,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      final eventKeys = _eventKeys(discovery);
      expect(eventKeys, hasLength(2));
      expect(eventKeys.first, isNot(eventKeys.last));
      expect(
        discovery.events.map((event) => event.node.structuralOccurrenceKey),
        containsAll([
          contains('children[0]'),
          contains('children[1]'),
        ]),
      );
    });

    test('discovers static collection leaves in deterministic order', () async {
      final fixture = await _resolveFixture(_collectionSource());
      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, isEmpty);
      expect(discovery.nodes, hasLength(5));
      expect(
        discovery.nodes.map((node) => node.structuralOccurrenceKey),
        containsAll([
          contains('children[0]'),
          contains('children[1]'),
          contains('children[2]'),
          contains('children[3]'),
        ]),
      );
      final textKeys = discovery.nodes
          .where((node) => node.resolvedWidgetIdentity.endsWith('#Text'))
          .map((node) => node.structuralOccurrenceKey)
          .toList();
      expect(textKeys.toSet(), hasLength(4));
      expect(
        textKeys,
        containsAll([
          contains(
            'children[0]|collection:listElement[0]|'
            'collection:listElement[0]|collection:loopIteration[0]',
          ),
          contains(
            'children[1]|collection:listElement[0]|'
            'collection:listElement[1]|collection:loopIteration[1]',
          ),
          contains(
            'children[2]|collection:listElement[1]|'
            'collection:selectedThen[0]|source:constDeclaration[0]',
          ),
          contains(
            'children[3]|collection:listElement[2]|'
            'collection:listElement[0]',
          ),
        ]),
      );
    });

    test('discovers one event in a run-time list template', () async {
      final fixture = await _resolveFixture(_runtimeCollectionSource());
      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, hasLength(1));
      const source =
          'package:apps_examples/onboarding/screens/probe.dart#Welcome';
      const column = 'package:flutter/src/widgets/basic.dart#Column';
      const button =
          'package:flutter/src/material/elevated_button.dart#ElevatedButton';
      expect(
        discovery.events.single.node.structuralOccurrenceKey,
        '$source|child:$column:$column.children[0]|'
        'collection:listElement[0]|collection:loopTemplate[0]|widget:$button',
      );
      const eventKey = '$source|child:$column:$column.children[0]|'
          'collection:listElement[0]|collection:loopTemplate[0]|'
          'widget:$button|$button|$button.onPressed';
      expect(
        _eventKeys(discovery),
        orderedEquals([eventKey]),
      );
    });

    test('keeps helper bindings on the established list expression key',
        () async {
      final ordinaryFixture = await _resolveFixture(
        _helperListSource(mixed: false),
        assetPath: 'lib/onboarding/screens/helper_list.dart',
      );
      final ordinary = _discover(
        ordinaryFixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: _catalogForAstNodes([
          ordinaryFixture.rootExpression,
          ordinaryFixture.methodDeclarationFor(
            ordinaryFixture.sourceClass,
            'action',
          ),
        ]),
      );
      final fixture = await _resolveFixture(
        _helperListSource(),
        assetPath: 'lib/onboarding/screens/helper_list.dart',
      );
      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: _catalogForAstNodes([
          fixture.rootExpression,
          fixture.methodDeclarationFor(fixture.sourceClass, 'action'),
        ]),
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(
        ordinary.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: ordinary.rejectionReason,
      );
      const source =
          'package:apps_examples/onboarding/screens/helper_list.dart#Welcome';
      const column = 'package:flutter/src/widgets/basic.dart#Column';
      const button =
          'package:flutter/src/material/elevated_button.dart#ElevatedButton';
      const text = 'package:flutter/src/widgets/text.dart#Text';
      const helper =
          'package:apps_examples/onboarding/screens/helper_list.dart#'
          'Welcome.action';
      const helperPath =
          '$source|child:$column:$column.children[0]|helper:$helper';
      const buttonKey = '$helperPath|widget:$button';
      const selectedTextKey = '$source|child:$column:$column.children[1]|'
          'collection:listElement[1]|collection:selectedThen[0]|widget:$text';
      expect(
        discovery.nodes.map((node) => node.structuralOccurrenceKey).toSet(),
        {
          '$source|widget:$column',
          buttonKey,
          '$helperPath|child:$button:$button.child[0]|widget:$text',
          selectedTextKey,
        },
      );
      const event = '$button|$button.onPressed';
      expect(
        ordinary.nodes.map((node) => node.structuralOccurrenceKey).toSet(),
        {
          '$source|widget:$column',
          buttonKey,
          '$helperPath|child:$button:$button.child[0]|widget:$text',
        },
      );
      expect(_eventKeys(ordinary), ['$buttonKey|$event']);
      expect(_eventKeys(discovery), ['$buttonKey|$event']);
    });

    test('keys a helper-fed widget list through the helper it entered',
        () async {
      final fixture = await _resolveFixture(
        _helperFedListSource(),
        assetPath: 'lib/onboarding/screens/helper_fed_list.dart',
      );
      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: _catalogForAstNodes([
          fixture.rootExpression,
          fixture.methodDeclarationFor(fixture.sourceClass, 'actions'),
        ]),
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      const source =
          'package:apps_examples/onboarding/screens/helper_fed_list.dart'
          '#Welcome';
      const column = 'package:flutter/src/widgets/basic.dart#Column';
      const button =
          'package:flutter/src/material/elevated_button.dart#ElevatedButton';
      const text = 'package:flutter/src/widgets/text.dart#Text';
      const helper =
          'package:apps_examples/onboarding/screens/helper_fed_list.dart#'
          'Welcome.actions';
      // The helper is entered before the slot, so it precedes the slot segment
      // exactly as the emitted translation keys the same element.
      const elementPath =
          '$source|helper:$helper|child:$column:$column.children[0]';
      const buttonKey = '$elementPath|widget:$button';
      expect(
        discovery.nodes.map((node) => node.structuralOccurrenceKey).toSet(),
        {
          '$source|widget:$column',
          buttonKey,
          '$elementPath|child:$button:$button.child[0]|widget:$text',
        },
      );
      expect(
        _eventKeys(discovery),
        ['$buttonKey|$button|$button.onPressed'],
      );
    });

    test('discovers the exact widget behind a helper-bound object receiver',
        () async {
      for (final authority in MeasurementSourceAuthority.values) {
        final annotation = authority == MeasurementSourceAuthority.screen
            ? 'ScreenSource'
            : 'PaywallSource';
        final className = authority == MeasurementSourceAuthority.screen
            ? 'Welcome'
            : 'Upgrade';
        final fixture = await _resolveFixture(
          _boundReceiverCollectionSource(
            annotation: annotation,
            className: className,
          ),
          assetPath: authority == MeasurementSourceAuthority.screen
              ? 'lib/onboarding/screens/bound_receiver.dart'
              : 'lib/paywalls/bound_receiver.dart',
        );
        final discovery = _discover(
          fixture,
          authority: authority,
          catalog: _catalogForAstNodes(
            fixture.resolved.units.map((unit) => unit.unit),
          ),
        );

        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.accepted,
          reason: discovery.rejectionReason,
        );
        expect(discovery.nodes, hasLength(2));
        expect(
          discovery.nodes.map((node) => node.resolvedWidgetIdentity),
          contains(endsWith('#Text')),
        );
      }
    });

    test('rejects a mixed const and runtime object receiver', () async {
      for (final authority in MeasurementSourceAuthority.values) {
        final annotation = authority == MeasurementSourceAuthority.screen
            ? 'ScreenSource'
            : 'PaywallSource';
        final className = authority == MeasurementSourceAuthority.screen
            ? 'Welcome'
            : 'Upgrade';
        final fixture = await _resolveFixture(
          _mixedReceiverCollectionSource(
            annotation: annotation,
            className: className,
          ),
          assetPath: authority == MeasurementSourceAuthority.screen
              ? 'lib/onboarding/screens/mixed_receiver.dart'
              : 'lib/paywalls/mixed_receiver.dart',
        );
        final discovery = _discover(
          fixture,
          authority: authority,
          catalog: _catalogForAstNodes(
            fixture.resolved.units.map((unit) => unit.unit),
          ),
        );

        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.rejected,
        );
        expect(discovery.events, isEmpty);
        expect(
          discovery.rejectionReason,
          contains('A spread of a value known only at run time is unsupported'),
        );
        expect(
          discovery.nodes.map((node) => node.resolvedWidgetIdentity),
          isNot(contains(endsWith('#Text'))),
        );
      }
    });

    test('refuses a targeted virtual collection helper', () async {
      final fixture = await _resolveFixture(
        _targetedVirtualCollectionSource(),
      );
      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: _catalogForAstNodes(
          fixture.resolved.units.map((unit) => unit.unit),
        ),
      );

      final eventIdentities = discovery.events
          .map((event) => event.resolvedEvent.sourceEventIdentity.value)
          .toList();
      expect(eventIdentities, isEmpty);
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
      );
    });

    test('refuses a targeted virtual widget helper', () async {
      final fixture = await _resolveFixture(
        _targetedVirtualWidgetSource(),
      );
      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: _catalogForAstNodes(
          fixture.resolved.units.map((unit) => unit.unit),
        ),
      );

      final eventIdentities = discovery.events
          .map((event) => event.resolvedEvent.sourceEventIdentity.value)
          .toList();
      expect(eventIdentities, isEmpty);
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
      );
    });

    test('accepts one selected callback and refuses repeated callback bodies',
        () async {
      final selected = _discover(
        await _resolveFixture(_selectedCollectionCallbackSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        selected.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: selected.rejectionReason,
      );
      expect(selected.events, hasLength(1));
      expect(
        selected.events.single.node.structuralOccurrenceKey,
        'package:apps_examples/onboarding/screens/probe.dart#Welcome|'
        'child:package:flutter/src/widgets/basic.dart#Column:'
        'package:flutter/src/widgets/basic.dart#Column.children[0]|'
        'collection:listElement[0]|collection:selectedThen[0]|'
        'widget:package:flutter/src/material/elevated_button.dart#ElevatedButton',
      );

      final repeated = _discover(
        await _resolveFixture(_repeatedCollectionCallbackSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        repeated.disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
      );
      expect(
        repeated.rejectionReason,
        contains(
          'A collection-for body that binds a callback is unsupported',
        ),
      );
    });

    test(
      'refuses reused callback sources before route planning',
      () async {
        for (final authority in MeasurementSourceAuthority.values) {
          for (final inlined in [false, true]) {
            final annotation = authority == MeasurementSourceAuthority.screen
                ? 'ScreenSource'
                : 'PaywallSource';
            final className = authority == MeasurementSourceAuthority.screen
                ? 'Welcome'
                : 'Upgrade';
            final assetPath = authority == MeasurementSourceAuthority.screen
                ? 'lib/onboarding/screens/reused.dart'
                : 'lib/paywalls/reused.dart';

            final single = await _resolveFixture(
              _callbackSourceThroughNestedBindings(
                annotation: annotation,
                className: className,
                inlined: inlined,
                reused: false,
              ),
              assetPath: assetPath,
            );
            final repeated = await _resolveFixture(
              _callbackSourceThroughNestedBindings(
                annotation: annotation,
                className: className,
                inlined: inlined,
                reused: true,
              ),
              assetPath: assetPath,
            );

            final singleDiscovery = await _discoverCallbackFixture(
              single,
              authority: authority,
              inlined: inlined,
            );
            final repeatedDiscovery = await _discoverCallbackFixture(
              repeated,
              authority: authority,
              inlined: inlined,
            );
            final routeError = _lateRouteError(
              repeatedDiscovery,
              'reused',
            );

            expect(
              singleDiscovery.disposition,
              MeasurementSourceDiscoveryDisposition.accepted,
              reason: singleDiscovery.rejectionReason,
            );
            expect(singleDiscovery.events, hasLength(1));
            expect(
              repeatedDiscovery.disposition,
              MeasurementSourceDiscoveryDisposition.rejected,
              reason: 'route error: $routeError',
            );
            expect(repeatedDiscovery.events, isEmpty);
            expect(
              repeatedDiscovery.rejectionReason,
              contains('static collection source is reused'),
            );
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'refuses one callback source shared by two slots before route planning',
      () async {
        for (final authority in MeasurementSourceAuthority.values) {
          for (final inlined in [false, true]) {
            final annotation = authority == MeasurementSourceAuthority.screen
                ? 'ScreenSource'
                : 'PaywallSource';
            final className = authority == MeasurementSourceAuthority.screen
                ? 'Welcome'
                : 'Upgrade';
            final fixture = await _resolveFixture(
              _callbackSourceAcrossEventSlots(
                annotation: annotation,
                className: className,
                inlined: inlined,
              ),
              assetPath: authority == MeasurementSourceAuthority.screen
                  ? 'lib/onboarding/screens/shared_slots.dart'
                  : 'lib/paywalls/shared_slots.dart',
            );
            final discovery = await _discoverCallbackFixture(
              fixture,
              authority: authority,
              inlined: inlined,
            );
            final routeError = _lateRouteError(discovery, 'shared-slots');

            expect(
              discovery.disposition,
              MeasurementSourceDiscoveryDisposition.rejected,
              reason: 'late route error: $routeError',
            );
            expect(discovery.events, isEmpty);
            expect(
              discovery.rejectionReason,
              contains('static collection source is reused'),
            );
            expect(routeError, isNull);
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    final ordinaryEntranceCases = <String, ({String source, bool inlined})>{
      'helper root': (
        source: _ordinarySharedCallbackSource(child: false),
        inlined: false,
      ),
      'helper child': (
        source: _ordinarySharedCallbackSource(child: true),
        inlined: false,
      ),
      'inlined custom root': (
        source: _inlinedOrdinarySharedCallbackSource(child: false),
        inlined: true,
      ),
      'inlined custom child': (
        source: _inlinedOrdinarySharedCallbackSource(child: true),
        inlined: true,
      ),
    };
    for (final MapEntry(key: name, value: fixtureCase)
        in ordinaryEntranceCases.entries) {
      test(
        'refuses shared callback slots through ordinary $name entrance',
        () async {
          final fixture = await _resolveFixture(
            fixtureCase.source,
            assetPath:
                'lib/onboarding/screens/${name.replaceAll(' ', '_')}.dart',
          );
          final discovery = await _discoverCallbackFixture(
            fixture,
            authority: MeasurementSourceAuthority.screen,
            inlined: fixtureCase.inlined,
          );
          final routeError = _lateRouteError(
            discovery,
            name.replaceAll(' ', '-'),
          );

          expect(
            discovery.disposition,
            MeasurementSourceDiscoveryDisposition.rejected,
            reason: 'late route error: $routeError',
          );
          expect(discovery.events, isEmpty, reason: name);
          expect(
            discovery.rejectionReason,
            contains('static collection source is reused'),
            reason: name,
          );
          expect(routeError, isNull, reason: name);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }

    test('accepts distinct callbacks at direct root and scalar child',
        () async {
      for (final child in [false, true]) {
        final discovery = _discover(
          await _resolveFixture(
            _ordinaryDistinctCallbackSource(child: child),
            assetPath: child
                ? 'lib/onboarding/screens/distinct_child.dart'
                : 'lib/onboarding/screens/distinct_root.dart',
          ),
          authority: MeasurementSourceAuthority.screen,
        );

        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.accepted,
          reason: discovery.rejectionReason,
        );
        expect(discovery.events, hasLength(2));
        expect(_lateRouteError(discovery, 'distinct-$child'), isNull);
      }
    });

    test(
      'refuses one callback source reused across nested sibling lists',
      () async {
        for (final authority in MeasurementSourceAuthority.values) {
          for (final inlined in [false, true]) {
            final annotation = authority == MeasurementSourceAuthority.screen
                ? 'ScreenSource'
                : 'PaywallSource';
            final className = authority == MeasurementSourceAuthority.screen
                ? 'Welcome'
                : 'Upgrade';
            final fixture = await _resolveFixture(
              _callbackSourceAcrossNestedLists(
                annotation: annotation,
                className: className,
                inlined: inlined,
              ),
              assetPath: authority == MeasurementSourceAuthority.screen
                  ? 'lib/onboarding/screens/nested_actions.dart'
                  : 'lib/paywalls/nested_actions.dart',
            );
            final discovery = await _discoverCallbackFixture(
              fixture,
              authority: authority,
              inlined: inlined,
            );
            final routeError = _lateRouteError(discovery, 'nested');

            expect(
              discovery.disposition,
              MeasurementSourceDiscoveryDisposition.rejected,
              reason: 'late route error: $routeError',
            );
            expect(discovery.events, isEmpty);
            expect(
              discovery.rejectionReason,
              contains('static collection source is reused'),
            );
            expect(routeError, isNull);
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('enumerates callbacks after the first source in one occurrence',
        () async {
      final fixture = await _resolveFixture(
        _laterReusedCallbackSource(),
        assetPath: 'lib/onboarding/screens/multiple_actions.dart',
      );
      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: _catalogForAstNodes(
          fixture.resolved.units.map((unit) => unit.unit),
        ),
      );
      final routeError = _lateRouteError(discovery, 'multiple');

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
        reason: 'late route error: $routeError',
      );
      expect(discovery.events, isEmpty);
      expect(
        discovery.rejectionReason,
        contains('static collection source is reused'),
      );
      expect(routeError, isNull);
    });

    test('keeps callback identity separate between discovery roots', () async {
      final fixture = await _resolveFixture(
        _callbackSourceThroughNestedBindings(
          annotation: 'ScreenSource',
          className: 'Welcome',
          inlined: false,
          reused: false,
        ),
        assetPath: 'lib/onboarding/screens/separate_actions.dart',
      );

      final first = await _discoverCallbackFixture(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        inlined: false,
      );
      final second = await _discoverCallbackFixture(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        inlined: false,
      );

      expect(
        first.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: first.rejectionReason,
      );
      expect(first.events, hasLength(1));
      expect(
        second.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: second.rejectionReason,
      );
      expect(second.events, hasLength(1));
      expect(
        second.events.single.sourceExpression,
        same(first.events.single.sourceExpression),
      );
    });

    test('discovers collection leaves inside an inlined custom widget',
        () async {
      final fixture = await _resolveFixture(_inlinedCollectionSource());
      final repeatedLabels = fixture.classNamed('RepeatedLabels');
      final catalog = _catalogForExpressions([
        fixture.rootExpression,
        fixture.buildExpressionFor(repeatedLabels),
      ]);
      final classification = await classifyReferencedCustomWidgets(
        rootExpressions: [fixture.rootExpression],
        catalog: catalog,
        astNodeFor: fixture.astNodeFor,
      );
      expect(
        classification.blueprints,
        contains(_classIdentity(repeatedLabels)),
      );

      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: catalog,
        inlinedCustomWidgetBlueprints: classification.blueprints,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, isEmpty);
      expect(
        discovery.nodes
            .where((node) => node.resolvedWidgetIdentity.endsWith('#Text')),
        hasLength(2),
      );
    });

    test(
        'keeps each supported callback slot on one canonical node as a '
        'distinct occurrence and generated reference', () async {
      final discovery = _discover(
        await _resolveFixture(_multiSlotSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      expect(discovery.events, hasLength(2));
      expect(
        discovery.events
            .map((event) => event.node.structuralOccurrenceKey)
            .toSet(),
        hasLength(1),
      );
      expect(
        discovery.events
            .map((event) => event.resolvedEvent.sourceEventIdentity.value)
            .toSet(),
        {'onTap', 'onDoubleTap'},
      );

      final codeIdentityId = CodeIdentityId('code.source-discovery.multi');
      final boundaryInput = _boundaryInputFor(
        discovery.events,
        codeIdentityId: codeIdentityId,
      );
      final result = MeasurementCompilerBoundary.produceDiscoveredBoundaryV1(
        MeasurementDiscoveredBoundaryInput(
          boundaryInput: boundaryInput,
          discovery: discovery,
          nodeBindings: [
            MeasurementDiscoveredNodeBinding(
              structuralOccurrenceKey:
                  discovery.nodes.single.structuralOccurrenceKey,
              codeIdentityId: codeIdentityId,
            ),
          ],
        ),
      );

      expect(
        result.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      final manifest = CompleteMeasurementManifestV1.fromCanonicalBytes(
        result.documents['completeMeasurementManifest']!,
      );
      final points = manifest.points;
      expect(points, hasLength(2));
      expect(points.map((point) => point.occurrenceId).toSet(), hasLength(2));
      expect(
        points.map((point) => point.sourceEventIdentity?.value).toSet(),
        {'onTap', 'onDoubleTap'},
      );
      expect(points.map((point) => point.lineageId).toSet(), hasLength(2));
    });

    test(
        'discovers each statically inlined custom-widget body at its exact '
        'call-site occurrence', () async {
      final fixture = await _resolveFixture(_inlinedCustomSource());
      final actionButton = fixture.classNamed('ActionButton');
      final catalog = _catalogForExpressions([
        fixture.rootExpression,
        fixture.buildExpressionFor(actionButton),
      ]);
      final classification = await classifyReferencedCustomWidgets(
        rootExpressions: [fixture.rootExpression],
        catalog: catalog,
        astNodeFor: fixture.astNodeFor,
      );
      final actionButtonKey = _classIdentity(actionButton);
      expect(classification.blueprints, contains(actionButtonKey));

      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: catalog,
        inlinedCustomWidgetBlueprints: classification.blueprints,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      expect(discovery.events, hasLength(2));
      expect(
        discovery.events
            .map((event) => event.node.structuralOccurrenceKey)
            .toSet(),
        hasLength(2),
      );
      expect(
        discovery.events
            .map((event) => event.node.inlinedCustomWidgetIdentities)
            .expand((identities) => identities),
        everyElement(actionButtonKey),
      );
    });

    test(
        'retains resolved outer bindings through nested static custom-widget '
        'inlining', () async {
      final fixture = await _resolveFixture(_nestedInlinedCustomSource());
      final outer = fixture.classNamed('OuterAction');
      final inner = fixture.classNamed('InnerAction');
      final catalog = _catalogForExpressions([
        fixture.rootExpression,
        fixture.buildExpressionFor(outer),
        fixture.buildExpressionFor(inner),
      ]);
      final classification = await classifyReferencedCustomWidgets(
        rootExpressions: [fixture.rootExpression],
        catalog: catalog,
        astNodeFor: fixture.astNodeFor,
      );

      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: catalog,
        inlinedCustomWidgetBlueprints: classification.blueprints,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, hasLength(2));
      expect(
        discovery.events
            .map((event) => event.node.inlinedCustomWidgetIdentities),
        everyElement(
          orderedEquals([
            _classIdentity(outer),
            _classIdentity(inner),
          ]),
        ),
      );
      expect(
        discovery.events
            .map((event) => event.node.structuralOccurrenceKey)
            .toSet(),
        hasLength(2),
      );
    });

    test('follows the existing inlined local and helper element bindings',
        () async {
      final fixture = await _resolveFixture(_inlinedHelperSource());
      final actionButton = fixture.classNamed('ActionButton');
      final catalog = _catalogForAstNodes([
        fixture.rootExpression,
        fixture.methodDeclarationFor(actionButton, 'build'),
        fixture.methodDeclarationFor(actionButton, '_button'),
      ]);
      final classification = await classifyReferencedCustomWidgets(
        rootExpressions: [fixture.rootExpression],
        catalog: catalog,
        astNodeFor: fixture.astNodeFor,
      );

      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: catalog,
        inlinedCustomWidgetBlueprints: classification.blueprints,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, hasLength(1));
      expect(discovery.nodes, hasLength(3));
      expect(
        discovery.events.single.node.structuralOccurrenceKey,
        contains('helper:'),
      );
    });

    test(
        'discovers exact registered opaque catalog slots without traversing '
        'the private implementation', () async {
      final registeredFixture = await _resolveFixture(
        _opaqueCustomSource(className: 'OpaqueAction'),
      );
      final opaqueClass = registeredFixture.classNamed('OpaqueAction');
      final registeredDiscovery = _discover(
        registeredFixture,
        authority: MeasurementSourceAuthority.screen,
        catalog: _catalogWithRegisteredOpaqueCustom(
          _catalogFor(registeredFixture.rootExpression),
          opaqueClass,
        ),
      );
      expect(
        registeredDiscovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: registeredDiscovery.rejectionReason,
      );
      expect(
        registeredDiscovery.events
            .map((event) => event.resolvedEvent.sourceEventIdentity.value),
        ['onActivate'],
      );
      expect(registeredDiscovery.nodes, hasLength(1));
      expect(
        registeredDiscovery.events.single.resolvedEvent,
        isA<MeasurementResolvedOpaqueCustomWidgetEvent>(),
      );
      expect(
        registeredDiscovery.events
            .map((event) => event.resolvedEvent.sourceEventIdentity.value),
        isNot(contains('onPressed')),
        reason: 'the opaque widget private body is outside source discovery',
      );

      final codeIdentityId = CodeIdentityId('code.source-discovery.opaque');
      final result = MeasurementCompilerBoundary.produceDiscoveredBoundaryV1(
        MeasurementDiscoveredBoundaryInput(
          boundaryInput: _boundaryInputFor(
            registeredDiscovery.events,
            codeIdentityId: codeIdentityId,
          ),
          discovery: registeredDiscovery,
          nodeBindings: [
            MeasurementDiscoveredNodeBinding(
              structuralOccurrenceKey:
                  registeredDiscovery.nodes.single.structuralOccurrenceKey,
              codeIdentityId: codeIdentityId,
            ),
          ],
        ),
      );
      expect(
        result.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      final manifest = CompleteMeasurementManifestV1.fromCanonicalBytes(
        result.documents['completeMeasurementManifest']!,
      );
      expect(manifest.points, hasLength(1));
      expect(manifest.points.single.sourceEventIdentity?.value, 'onActivate');

      final unregisteredDiscovery = _discover(
        await _resolveFixture(_opaqueCustomSource(className: 'Unregistered')),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        unregisteredDiscovery.disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
      );
      expect(unregisteredDiscovery.events, isEmpty);
    });

    test(
        'FlowSource closes already-resolved static screen artifacts without '
        'inventing a widget body in buildFlow', () async {
      final fixture = await _resolveFixture(_flowAndScreenSource());
      final screen = fixture.classNamed('FlowScreen');
      final flow = fixture.classNamed('WelcomeFlow');
      final screenDiscovery = MeasurementSourceDiscovery.discover(
        MeasurementSourceDiscoveryInput(
          authority: MeasurementSourceAuthority.screen,
          sourceClass: screen,
          rootExpression: fixture.buildExpressionFor(screen),
          catalog: _catalogFor(fixture.buildExpressionFor(screen)),
        ),
      );
      final flowClosure = MeasurementSourceDiscovery.closeFlowSourceV1(
        MeasurementFlowSourceClosureInput(
          flowSourceClass: flow,
          staticArtifactDiscoveries: [screenDiscovery],
        ),
      );

      expect(
        flowClosure.disposition,
        MeasurementFlowSourceClosureDisposition.accepted,
      );
      expect(
        flowClosure.events.map(_eventKey),
        orderedEquals(screenDiscovery.events.map(_eventKey)),
      );
    });

    test('fails closed for local source/widget/custom-marker lookalikes',
        () async {
      final fakeSource = _discover(
        await _resolveFixture(_fakeSourceAnnotation()),
        authority: MeasurementSourceAuthority.screen,
      );
      final fakeWidget = _discover(
        await _resolveFixture(_fakeFlutterWidget()),
        authority: MeasurementSourceAuthority.screen,
      );
      final fakeCustom = _discover(
        await _resolveFixture(_fakeCustomWidget()),
        authority: MeasurementSourceAuthority.screen,
      );

      for (final discovery in [fakeSource, fakeWidget, fakeCustom]) {
        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.rejected,
        );
        expect(discovery.nodes, isEmpty);
        expect(discovery.events, isEmpty);
      }
    });

    test('fails closed for dynamic and unresolved widget constructs', () async {
      final dynamicDiscovery = _discover(
        await _resolveFixture(_dynamicWidgetSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      final unresolvedDiscovery = _discover(
        await _resolveFixture(_unresolvedWidgetSource()),
        authority: MeasurementSourceAuthority.screen,
      );

      for (final discovery in [dynamicDiscovery, unresolvedDiscovery]) {
        expect(
          discovery.disposition,
          MeasurementSourceDiscoveryDisposition.rejected,
        );
        expect(discovery.events, isEmpty);
      }
    });

    test('rejects Flutter State method tear-offs as non-carrier callbacks',
        () async {
      final fixture = await _resolveFixture(_stateMethodSource());
      final sourceClass = fixture.classNamed('Welcome');
      final rootExpression =
          fixture.buildExpressionFor(fixture.classNamed('_WelcomeState'));

      final discovery = MeasurementSourceDiscovery.discover(
        MeasurementSourceDiscoveryInput(
          authority: MeasurementSourceAuthority.screen,
          sourceClass: sourceClass,
          rootExpression: rootExpression,
          catalog: _catalogFor(rootExpression),
        ),
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
      );
      expect(discovery.nodes, isEmpty);
      expect(discovery.events, isEmpty);
      expect(
        discovery.rejectionReason,
        contains('Flutter State method tear-off'),
      );
    });

    test('does not reject a non-Flutter class named State', () async {
      final fixture = await _resolveFixture(_localStateNameSource());
      final discovery = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
      );

      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: discovery.rejectionReason,
      );
      expect(discovery.events, hasLength(1));
    });

    test(
        'validates discovered nodes and slots before delegating to the '
        'unchanged production boundary', () async {
      final discovery = _discover(
        await _resolveFixture(_singleButtonSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      final codeIdentityId = CodeIdentityId('code.source-discovery.button');
      final boundaryInput = _boundaryInputFor(
        [discovery.events.single],
        codeIdentityId: codeIdentityId,
      );

      final direct = MeasurementCompilerBoundary.produceBoundaryV1(
        boundaryInput,
      );
      final bridged = MeasurementCompilerBoundary.produceDiscoveredBoundaryV1(
        MeasurementDiscoveredBoundaryInput(
          boundaryInput: boundaryInput,
          discovery: discovery,
          nodeBindings: [
            MeasurementDiscoveredNodeBinding(
              structuralOccurrenceKey:
                  discovery.nodes.single.structuralOccurrenceKey,
              codeIdentityId: codeIdentityId,
            ),
          ],
        ),
      );

      expect(
        direct.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      expect(
        bridged.disposition,
        MeasurementCompilerBoundaryDisposition.accepted,
      );
      expect(bridged.productionEntrypoint, direct.productionEntrypoint);
      expect(bridged.documents.keys, orderedEquals(direct.documents.keys));
      for (final key in direct.documents.keys) {
        expect(bridged.documents[key], orderedEquals(direct.documents[key]!));
      }

      final missingBinding =
          MeasurementCompilerBoundary.produceDiscoveredBoundaryV1(
        MeasurementDiscoveredBoundaryInput(
          boundaryInput: boundaryInput,
          discovery: discovery,
          nodeBindings: const [],
        ),
      );
      expect(
        missingBinding.disposition,
        MeasurementCompilerBoundaryDisposition.rejected,
      );
      expect(missingBinding.documents, isEmpty);
    });

    test('prohibited discovered events never receive an emission marker',
        () async {
      final discovery = _discover(
        await _resolveFixture(_singleButtonSource()),
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        discovery.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
      );
      final discovered = discovery.events.single;
      final codeIdentityId = CodeIdentityId('code.source-prohibited');
      final lineageId = PointLineageId('lineage.source-prohibited');
      final generatedReferenceId = GeneratedReferenceId(
        'reference.source-prohibited',
      );
      final edge = ArtifactOccurrenceEdgeToken('edge.source-prohibited');
      final routePlan = MeasurementPublicationRoutePlanV1(
        surfaceId: SurfaceId('surface.source-prohibited'),
        analyticsSurfaceKey: AnalyticsSurfaceKey('source-prohibited'),
        deliverySurfaceType: DeliverySurfaceTypeId('general'),
        minimumMeasurementClient: 1,
        completeManifestId: MeasurementManifestId(
          'manifest.source-prohibited',
        ),
        privacyPolicyRevisionId: AuthorityRevisionId(
          'privacy.source-prohibited',
        ),
        collectionBudgetRevisionId: AuthorityRevisionId(
          'budget.source-prohibited',
        ),
        artifacts: [
          MeasurementPublicationRouteArtifactV1(
            artifactId: ArtifactId('artifact.source-prohibited'),
            artifactKind: ArtifactKindId('rfw.blob'),
            occurrenceEdgeToken: edge,
            localManifestId: MeasurementManifestId(
              'manifest.source-prohibited.local',
            ),
          ),
        ],
        codeIdentityBindings: [
          CodeIdentityBindingV1(
            codeIdentityId: codeIdentityId,
            canonicalNodeTokenId: NodeTokenId('node.source-prohibited'),
          ),
        ],
        nodes: [
          MeasurementPublicationDraftNodeV1(
            codeIdentityId: codeIdentityId,
            artifactOccurrenceEdgeToken: edge,
          ),
        ],
        events: [
          MeasurementPublicationDraftEventV1(
            nodeCodeIdentityId: codeIdentityId,
            sourceEventIdentity: discovered.resolvedEvent.sourceEventIdentity,
            lineageId: lineageId,
            generatedReferenceId: generatedReferenceId,
            dartSymbol: GeneratedDartSymbol('sourceProhibited'),
            displayMetadataRef: DisplayMetadataRef(
              'display.source-prohibited',
            ),
            normalizedInteractionKind: NormalizedInteractionKind.activate,
            privacyClass: MeasurementPrivacyClass.prohibited,
            semanticValueClass: SemanticValueClass.activityOnly,
            collectionClass: MeasurementCollectionClass.prohibited,
          ),
        ],
        routeSeeds: const [],
        lineageIntents: [
          MeasurementPublicationLineageIntentV1(
            transitionId: LineageTransitionId(
              'transition.source-prohibited',
            ),
            operation: LineageOperation.create,
            authority: LineageTransitionAuthority.exactToken,
            next: [
              MeasurementPublicationCurrentEndpointIntentV1(
                generatedReferenceId: generatedReferenceId,
                lineageId: lineageId,
              ),
            ],
          ),
        ],
      );

      final emission = MeasurementRouteEmissionPlan.fromDiscovery(
        discovery: discovery,
        routePlan: routePlan,
        codeIdentityByStructuralOccurrenceKey: {
          discovered.node.structuralOccurrenceKey: codeIdentityId,
        },
      );

      expect(
        emission.markerFor(discovered.emissionOccurrence),
        isNull,
      );
      expect(routePlan.routes, isEmpty);
    });

    test('discovers a measured slot on a widget held in a build() local',
        () async {
      final fixture = await _resolveFixture(_preludeWidgetSource());
      final bindings = fixture.rootLocalBindings;
      expect(bindings, hasLength(1));

      final seeded = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
        rootLocalBindings: bindings,
      );

      expect(
        seeded.disposition,
        MeasurementSourceDiscoveryDisposition.accepted,
        reason: seeded.rejectionReason,
      );
      expect(
        seeded.events.map(
          (event) => event.resolvedEvent.declarationProvenance.memberName,
        ),
        ['onPressed'],
      );

      final unseeded = _discover(
        fixture,
        authority: MeasurementSourceAuthority.screen,
      );
      expect(
        unseeded.disposition,
        MeasurementSourceDiscoveryDisposition.rejected,
      );
    });

    test(
      'a locally held widget list matches its literal twin',
      () async {
        final local = await _resolveFixture(
          _widgetListSource(heldInLocal: true),
        );
        final literal = await _resolveFixture(
          _widgetListSource(heldInLocal: false),
        );
        final localDiscovery = _discover(
          local,
          authority: MeasurementSourceAuthority.screen,
          rootLocalBindings: local.rootLocalBindings,
        );
        final literalDiscovery = _discover(
          literal,
          authority: MeasurementSourceAuthority.screen,
        );

        expect(
          localDiscovery.disposition,
          MeasurementSourceDiscoveryDisposition.accepted,
          reason: localDiscovery.rejectionReason,
        );
        expect(
          literalDiscovery.disposition,
          MeasurementSourceDiscoveryDisposition.accepted,
          reason: literalDiscovery.rejectionReason,
        );
        expect(
          _eventKeys(localDiscovery),
          orderedEquals(_eventKeys(literalDiscovery)),
        );
        expect(
          localDiscovery.events.single.node.structuralOccurrenceKey,
          contains('children[1]'),
        );
        expect(
          localDiscovery.nodes.map((node) => node.resolvedWidgetIdentity),
          orderedEquals(
            literalDiscovery.nodes.map((node) => node.resolvedWidgetIdentity),
          ),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

MeasurementSourceDiscoveryResult _discover(
  _ResolvedFixture fixture, {
  required MeasurementSourceAuthority authority,
  Catalog? catalog,
  Map<String, CustomWidgetBlueprint> inlinedCustomWidgetBlueprints = const {},
  Map<String, String> inlinedCustomWidgetCollectionRefusals = const {},
  Map<Element, Expression> rootLocalBindings = const {},
}) =>
    MeasurementSourceDiscovery.discover(
      MeasurementSourceDiscoveryInput(
        authority: authority,
        sourceClass: fixture.sourceClass,
        rootExpression: fixture.rootExpression,
        catalog: catalog ??
            _catalogForExpressions([
              fixture.rootExpression,
              ...rootLocalBindings.values,
            ]),
        inlinedCustomWidgetBlueprints: inlinedCustomWidgetBlueprints,
        inlinedCustomWidgetCollectionRefusals:
            inlinedCustomWidgetCollectionRefusals,
        rootLocalBindings: rootLocalBindings,
      ),
    );

Future<MeasurementSourceDiscoveryResult> _discoverCallbackFixture(
  _ResolvedFixture fixture, {
  required MeasurementSourceAuthority authority,
  required bool inlined,
}) async {
  final catalog = _catalogForAstNodes(
    fixture.resolved.units.map((unit) => unit.unit),
  );
  if (!inlined) {
    return _discover(fixture, authority: authority, catalog: catalog);
  }
  final classification = await classifyReferencedCustomWidgets(
    rootExpressions: [fixture.rootExpression],
    catalog: catalog,
    astNodeFor: fixture.astNodeFor,
  );
  return _discover(
    fixture,
    authority: authority,
    catalog: catalog,
    inlinedCustomWidgetBlueprints: classification.blueprints,
    inlinedCustomWidgetCollectionRefusals: classification.collectionRefusals,
  );
}

Object? _lateRouteError(
  MeasurementSourceDiscoveryResult discovery,
  String identity,
) {
  if (discovery.disposition != MeasurementSourceDiscoveryDisposition.accepted) {
    return null;
  }
  try {
    MeasurementRouteEmissionPlan([
      for (final (index, event) in discovery.events.indexed)
        MeasurementRouteEmissionBinding(
          occurrence: event.emissionOccurrence,
          generatedReferenceId: GeneratedReferenceId(
            'reference.$identity.$index',
          ),
        ),
    ]);
  } on Object catch (error) {
    return error;
  }
  return null;
}

List<String> _eventKeys(MeasurementSourceDiscoveryResult discovery) =>
    discovery.events.map(_eventKey).toList();

String _eventKey(MeasurementDiscoveredEvent event) =>
    '${event.node.structuralOccurrenceKey}|'
    '${event.resolvedEvent.resolvedSemanticIdentity}';

Catalog _catalogFor(Expression rootExpression) {
  return _catalogForExpressions([rootExpression]);
}

Catalog _catalogForExpressions(Iterable<Expression> rootExpressions) {
  return _catalogForAstNodes(rootExpressions);
}

Catalog _catalogForAstNodes(Iterable<AstNode> roots) {
  final collector = _FlutterCreationCollector();
  roots.forEach(collector.collect);
  return catalogWith([
    for (final widgetEntry in collector.entries.values)
      entry(
        name: widgetEntry.$1.name!,
        flutterType: widgetEntry.$2,
        properties: _eventPropertiesFor(widgetEntry.$1.name),
      ),
  ]);
}

Catalog _catalogWithRegisteredOpaqueCustom(
  Catalog base,
  ClassElement customClass,
) {
  const opaqueLibrary = WidgetLibrary.custom('fixture.opaque');
  return Catalog(
    schemaVersion: base.schemaVersion,
    generatedAt: base.generatedAt,
    libraries: {
      ...base.libraries,
      opaqueLibrary: const LibraryInfo(version: '0.1.0'),
    },
    widgets: [
      ...base.widgets,
      entry(
        name: customClass.name!,
        flutterType: _classIdentity(customClass),
        library: opaqueLibrary,
        properties: [prop('onActivate', PropertyType.event)],
      ),
    ],
  );
}

List<PropertyEntry> _eventPropertiesFor(String? className) {
  switch (className) {
    case 'ElevatedButton':
      return [prop('onPressed', PropertyType.event)];
    case 'GestureDetector':
      return [
        prop('onTap', PropertyType.event),
        prop('onDoubleTap', PropertyType.event),
      ];
    default:
      return const [];
  }
}

final class _FlutterCreationCollector extends RecursiveAstVisitor<void> {
  final Map<String, (InterfaceElement, String)> entries = {};

  void collect(AstNode node) => node.accept(this);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final element = node.constructorName.type.element;
    if (element is InterfaceElement &&
        element.library.identifier.startsWith('package:flutter/')) {
      final name = element.name;
      if (name != null && name.isNotEmpty) {
        final constructorName = node.constructorName.name?.name;
        final suffix = constructorName == null || constructorName.isEmpty
            ? ''
            : '.$constructorName';
        final flutterType = '${element.library.identifier}#$name$suffix';
        entries[flutterType] = (element, flutterType);
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

Future<_ResolvedFixture> _resolveFixture(
  String source, {
  String assetPath = 'lib/onboarding/screens/probe.dart',
}) async {
  final assetId = AssetId('apps_examples', assetPath);
  late final LibraryElement library;
  late final ResolvedLibraryResult resolved;
  await resolveSources(
    {assetId.toString(): source},
    (resolver) async {
      library = await resolver.libraryFor(assetId);
      final result = await library.session.getResolvedLibraryByElement(library);
      if (result is! ResolvedLibraryResult) {
        throw StateError('Fixture did not resolve.');
      }
      resolved = result;
    },
    resolverFor: assetId.toString(),
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
  return _ResolvedFixture(library: library, resolved: resolved);
}

final class _ResolvedFixture {
  const _ResolvedFixture({required this.library, required this.resolved});

  final LibraryElement library;
  final ResolvedLibraryResult resolved;

  ClassElement get sourceClass => classNamed(
        library.classes.map((element) => element.name).contains('Welcome')
            ? 'Welcome'
            : library.classes.map((element) => element.name).contains('Upgrade')
                ? 'Upgrade'
                : library.classes
                        .map((element) => element.name)
                        .contains('DynamicScreen')
                    ? 'DynamicScreen'
                    : library.classes
                            .map((element) => element.name)
                            .contains('UnresolvedScreen')
                        ? 'UnresolvedScreen'
                        : library.classes
                                .map((element) => element.name)
                                .contains('FakeSource')
                            ? 'FakeSource'
                            : library.classes
                                    .map((element) => element.name)
                                    .contains('FakeWidget')
                                ? 'FakeWidget'
                                : library.classes
                                        .map((element) => element.name)
                                        .contains('FakeCustomScreen')
                                    ? 'FakeCustomScreen'
                                    : library.classes.single.name!,
      );

  Expression get rootExpression => buildExpressionFor(sourceClass);

  Map<Element, Expression> get rootLocalBindings =>
      extractInlinableBuildBody(
        methodDeclarationFor(sourceClass, 'build').body,
      )?.localBindings ??
      const {};

  ClassElement classNamed(String name) =>
      library.classes.singleWhere((element) => element.name == name);

  Expression buildExpressionFor(ClassElement element) {
    return methodExpressionFor(element, 'build');
  }

  Expression methodExpressionFor(ClassElement element, String methodName) {
    final node = methodDeclarationFor(element, methodName);
    final body = node.body;
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody && body.block.statements.isNotEmpty) {
      final statement = body.block.statements.last;
      if (statement is ReturnStatement && statement.expression != null) {
        return statement.expression!;
      }
    }
    throw StateError('Fixture $methodName() did not return one expression.');
  }

  MethodDeclaration methodDeclarationFor(
    ClassElement element,
    String methodName,
  ) {
    final build = element.methods.firstWhere(
      (method) =>
          method.name == methodName && method.enclosingElement == element,
    );
    final node = resolved.getFragmentDeclaration(build.firstFragment)?.node;
    if (node is! MethodDeclaration) {
      throw StateError('Could not resolve ${element.name}.$methodName.');
    }
    return node;
  }

  Future<AstNode?> astNodeFor(Fragment fragment) async =>
      resolved.getFragmentDeclaration(fragment)?.node;
}

String _classIdentity(ClassElement element) =>
    '${element.library.identifier}#${element.name}';

MeasurementCompilerBoundaryInput _boundaryInputFor(
  Iterable<MeasurementDiscoveredEvent> events, {
  required CodeIdentityId codeIdentityId,
}) {
  final discoveredEvents = events.toList(growable: false);
  String eventSuffix(MeasurementDiscoveredEvent event) =>
      _testIdentifierSuffix(event.resolvedEvent.sourceEventIdentity.value);
  if (discoveredEvents.isEmpty) {
    throw ArgumentError.value(events, 'events', 'must not be empty');
  }
  final target = TargetCoordinate(
    organizationId: OrganizationId(1),
    appId: ApplicationId(2),
    environmentTargetId: EnvironmentTargetId(3),
    namedEnvironmentId: NamedEnvironmentId(4),
    runtimePlane: RuntimePlane.sandbox,
  );
  final surfaceId = SurfaceId('surface.source-discovery');
  final revisionId = SurfaceRevisionId('surface.source-discovery.v2');
  final artifact = MeasurementArtifactInput(
    artifactId: ArtifactId('artifact.source-discovery'),
    artifactKind: ArtifactKindId('rfw.blob'),
    contentHash: CanonicalDigest('a' * 64),
    occurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.source-discovery'),
    localManifestId: MeasurementManifestId('manifest.source-discovery.local'),
  );
  return MeasurementCompilerBoundaryInput(
    target: target,
    surfaceId: surfaceId,
    surfaceRevisionId: revisionId,
    revisionOrdinal: 2,
    analyticsSurfaceKey: AnalyticsSurfaceKey('source-discovery'),
    deliverySurfaceType: DeliverySurfaceTypeId('fixture.surface'),
    minimumMeasurementClient: 1,
    completeManifestId: MeasurementManifestId('manifest.source-discovery'),
    privacyPolicyRevisionId: AuthorityRevisionId('privacy.source-discovery'),
    collectionBudgetRevisionId: AuthorityRevisionId('budget.source-discovery'),
    artifacts: [artifact],
    codeIdentityLedger: CodeIdentityLedgerV1(
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: target,
        surfaceId: surfaceId,
      ),
      bindings: [
        CodeIdentityBindingV1(
          codeIdentityId: codeIdentityId,
          canonicalNodeTokenId: NodeTokenId('node.source-discovery'),
        ),
      ],
    ),
    nodes: [
      MeasurementCompilerNodeInput(
        codeIdentityId: codeIdentityId,
        artifactOccurrenceEdgeToken: artifact.occurrenceEdgeToken,
      ),
    ],
    events: [
      for (final event in discoveredEvents)
        MeasurementCompilerEventInput(
          nodeCodeIdentityId: codeIdentityId,
          resolvedEvent: event.resolvedEvent,
          lineageId: PointLineageId(
            'lineage.source-discovery.'
            '${eventSuffix(event)}',
          ),
          generatedReferenceId: GeneratedReferenceId(
            'reference.source-discovery.'
            '${eventSuffix(event)}',
          ),
          dartSymbol: GeneratedDartSymbol(
            'sourceDiscovery'
            '${event.resolvedEvent.declarationProvenance.memberName}',
          ),
          displayMetadataRef: DisplayMetadataRef(
            'display.source-discovery.'
            '${eventSuffix(event)}',
          ),
          normalizedInteractionKind: NormalizedInteractionKind.activate,
          privacyClass: MeasurementPrivacyClass.nonSensitive,
          semanticValueClass: SemanticValueClass.activityOnly,
          collectionClass: MeasurementCollectionClass.tier1KeepAll,
        ),
    ],
    priorActiveLedger: PriorActiveLineageLedgerV1(
      surfaceId: surfaceId,
      surfaceRevisionId: SurfaceRevisionId('surface.source-discovery.v1'),
      endpoints: const [],
    ),
    lineageTransitions: [
      for (final event in discoveredEvents)
        MeasurementLineageTransitionDraft(
          transitionId: LineageTransitionId(
            'transition.source-discovery.'
            '${eventSuffix(event)}',
          ),
          operation: LineageOperation.create,
          authority: LineageTransitionAuthority.exactToken,
          next: [
            MeasurementCurrentEndpointClaim(
              codeIdentityId: codeIdentityId,
              lineageId: PointLineageId(
                'lineage.source-discovery.'
                '${eventSuffix(event)}',
              ),
              sourceEventIdentity: event.resolvedEvent.sourceEventIdentity,
            ),
          ],
        ),
    ],
  );
}

String _testIdentifierSuffix(String sourceEventIdentity) =>
    sourceEventIdentity.toLowerCase();

String _ordinarySource({
  String annotation = 'ScreenSource',
  String className = 'Welcome',
  String sourceId = 'welcome',
  String? key,
  String copy = 'Subscribe',
  bool eventBeforeChild = true,
}) {
  final firstArgs = eventBeforeChild
      ? '''
          ${key == null ? '' : 'key: $key,'}
          onPressed: () {},
          child: Text('$copy'),
        '''
      : '''
          child: Text('$copy'),
          ${key == null ? '' : 'key: $key,'}
          onPressed: () {},
        ''';
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@$annotation(id: '$sourceId')
final class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ElevatedButton(
            $firstArgs
          ),
          ElevatedButton(
            onPressed: () {},
            child: Text('$copy'),
          ),
        ],
      );
}
''';
}

String _collectionSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'labels')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const third = Text('third');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final label in const ['first', 'second']) Text(label),
          if (true) third,
          ...const [Text('fourth')],
        ],
      );
}
''';

String _runtimeCollectionSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'dynamic_labels')
final class Welcome extends StatelessWidget {
  const Welcome({required this.labels, super.key});
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final label in labels)
            ElevatedButton(
              onPressed: () {},
              child: Text(label),
            ),
        ],
      );
}
''';

String _helperListSource({bool mixed = true}) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'helper_list')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  Widget action(VoidCallback onActivate) => ElevatedButton(
        onPressed: onActivate,
        child: const Text('Activate'),
      );

  @override
  Widget build(BuildContext context) => Column(
        children: [
          action(() {}),
          ${mixed ? "if (true) const Text('Extra')," : ''}
        ],
      );
}
''';

String _helperFedListSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'helper_fed_list')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  List<Widget> actions(VoidCallback onActivate) => [
        ElevatedButton(
          onPressed: onActivate,
          child: const Text('Activate'),
        ),
      ];

  @override
  Widget build(BuildContext context) => Column(children: actions(() {}));
}
''';

String _selectedCollectionCallbackSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'selected_action')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (true)
            ElevatedButton(
              onPressed: () {},
              child: const Text('Activate'),
            ),
        ],
      );
}
''';

String _repeatedCollectionCallbackSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'repeated_action')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final label in const ['first', 'second'])
            ElevatedButton(
              onPressed: () {},
              child: Text(label),
            ),
        ],
      );
}
''';

String _boundReceiverCollectionSource({
  required String annotation,
  required String className,
}) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

final class ActionSet {
  const ActionSet(this.widget);
  final Widget widget;
}

@$annotation(id: 'bound_receiver')
final class $className extends StatelessWidget {
  const $className({super.key});
  static const set = ActionSet(Text('accepted'));

  List<Widget> select(ActionSet source) => [if (true) source.widget];

  @override
  Widget build(BuildContext context) =>
      Column(children: [...select(set)]);
}
''';

String _mixedReceiverCollectionSource({
  required String annotation,
  required String className,
}) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

final class WidgetSet {
  const WidgetSet(this.widgets);
  final List<Widget> widgets;
}

@$annotation(id: 'mixed_receiver')
final class $className extends StatelessWidget {
  const $className({required this.selectConstant, super.key});
  final bool selectConstant;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ...(selectConstant
            ? const WidgetSet(<Widget>[Text('constant')])
            : WidgetSet(<Widget>[const Text('runtime')]))
          .widgets,
    ],
  );
}
''';

String _targetedVirtualCollectionSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

class Provider {
  List<Widget> actions() => [
        ElevatedButton(
          onPressed: () {},
          child: const Text('base'),
        ),
      ];
}

class DerivedProvider extends Provider {
  @override
  List<Widget> actions() => [
        GestureDetector(
          onTap: () {},
          child: const Text('derived'),
        ),
      ];
}

Provider provider() => DerivedProvider();

@ScreenSource(id: 'targeted_collection')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [...provider().actions()]);
}
''';

String _targetedVirtualWidgetSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

class Provider {
  Widget action() => ElevatedButton(
        onPressed: () {},
        child: const Text('base'),
      );
}

class DerivedProvider extends Provider {
  @override
  Widget action() => GestureDetector(
        onTap: () {},
        child: const Text('derived'),
      );
}

Provider provider() => DerivedProvider();

@ScreenSource(id: 'targeted_widget')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => provider().action();
}
''';

String _callbackSourceAcrossNestedLists({
  required String annotation,
  required String className,
  required bool inlined,
}) {
  if (inlined) {
    return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class BoundActions extends StatelessWidget {
  const BoundActions({super.key});
  static void activate() {}

  List<Widget> actions() => [
        ElevatedButton(
          onPressed: activate,
          child: const Text('Activate'),
        ),
      ];

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(children: [...actions()]),
          Row(children: [...actions()]),
        ],
      );
}

@$annotation(id: 'nested_actions')
final class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => const BoundActions();
}
''';
  }
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@$annotation(id: 'nested_actions')
final class $className extends StatelessWidget {
  const $className({super.key});
  static void activate() {}

  List<Widget> actions() => [
        ElevatedButton(
          onPressed: activate,
          child: const Text('Activate'),
        ),
      ];

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(children: [...actions()]),
          Row(children: [...actions()]),
        ],
      );
}
''';
}

String _laterReusedCallbackSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'multiple_actions')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static void first() {}
  static void second() {}
  static void shared() {}

  Widget action(Widget leading) => Column(
        children: [
          leading,
          ElevatedButton(
            onPressed: shared,
            child: const Text('Shared'),
          ),
        ],
      );

  List<Widget> actions(Widget leading) => [action(leading)];

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            children: [
              ...actions(
                ElevatedButton(
                  onPressed: first,
                  child: const Text('First'),
                ),
              ),
            ],
          ),
          Row(
            children: [
              ...actions(
                ElevatedButton(
                  onPressed: second,
                  child: const Text('Second'),
                ),
              ),
            ],
          ),
        ],
      );
}
''';

String _callbackSourceThroughNestedBindings({
  required String annotation,
  required String className,
  required bool inlined,
  required bool reused,
}) {
  final children = reused ? '[...values, ...values]' : '[...values]';
  if (inlined) {
    return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class BoundActions extends StatelessWidget {
  const BoundActions({super.key, required this.onActivate});
  final VoidCallback onActivate;

  List<Widget> select(VoidCallback callback) => [
        ElevatedButton(
          onPressed: callback,
          child: const Text('Activate'),
        ),
      ];

  List<Widget> actions() => select(onActivate);

  @override
  Widget build(BuildContext context) {
    final values = actions();
    return Column(children: $children);
  }
}

@$annotation(id: 'bound_actions')
final class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => BoundActions(onActivate: () {});
}
''';
  }
  final rootChildren =
      reused ? '[...actions(), ...actions()]' : '[...actions()]';
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

final class ActionSet {
  const ActionSet(this.widget);
  final Widget widget;
}

@$annotation(id: 'bound_actions')
final class $className extends StatelessWidget {
  const $className({super.key});
  static void activate() {}
  static const action = ElevatedButton(
    onPressed: activate,
    child: Text('Activate'),
  );
  static const set = ActionSet(action);

  List<Widget> select(Widget value) => [value];
  List<Widget> actions() => select(set.widget);

  @override
  Widget build(BuildContext context) => Column(children: $rootChildren);
}
''';
}

String _callbackSourceAcrossEventSlots({
  required String annotation,
  required String className,
  required bool inlined,
}) {
  if (inlined) {
    return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class BoundActions extends StatelessWidget {
  const BoundActions({super.key, required this.onActivate});
  final VoidCallback onActivate;

  List<Widget> actions(VoidCallback callback) => [
        GestureDetector(
          onTap: callback,
          onDoubleTap: callback,
          child: const Text('Activate'),
        ),
      ];

  @override
  Widget build(BuildContext context) =>
      Column(children: [...actions(onActivate)]);
}

@$annotation(id: 'shared_slots')
final class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => BoundActions(onActivate: () {});
}
''';
  }
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@$annotation(id: 'shared_slots')
final class $className extends StatelessWidget {
  const $className({super.key});

  List<Widget> actions(VoidCallback callback) => [
        GestureDetector(
          onTap: callback,
          onDoubleTap: callback,
          child: const Text('Activate'),
        ),
      ];

  @override
  Widget build(BuildContext context) =>
      Column(children: [...actions(() {})]);
}
''';
}

String _ordinarySharedCallbackSource({required bool child}) {
  const result = 'action(() {})';
  final root = child ? 'Center(child: $result)' : result;
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'ordinary_shared')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  Widget action(VoidCallback callback) => GestureDetector(
        onTap: callback,
        onDoubleTap: callback,
        child: const Text('Activate'),
      );

  @override
  Widget build(BuildContext context) => $root;
}
''';
}

String _inlinedOrdinarySharedCallbackSource({required bool child}) {
  const result = 'BoundAction(onActivate: () {})';
  final root = child ? 'Center(child: $result)' : result;
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class BoundAction extends StatelessWidget {
  const BoundAction({super.key, required this.onActivate});
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onActivate,
        onDoubleTap: onActivate,
        child: const Text('Activate'),
      );
}

@ScreenSource(id: 'inlined_ordinary_shared')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => $root;
}
''';
}

String _ordinaryDistinctCallbackSource({required bool child}) {
  const result = '''
GestureDetector(
        onTap: () {},
        onDoubleTap: () {},
        child: const Text('Activate'),
      )''';
  final root = child ? 'Center(child: $result)' : result;
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'ordinary_distinct')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => $root;
}
''';
}

String _inlinedCollectionSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class RepeatedLabels extends StatelessWidget {
  const RepeatedLabels({super.key});

  List<String> labels(String first) => [first, 'second'];

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final label in labels('first')) Text(label),
        ],
      );
}

@ScreenSource(id: 'inline_labels')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => const RepeatedLabels();
}
''';

String _singleButtonSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'single')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
      );
}
''';

String _multiSlotSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'multi_slot')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {},
        onDoubleTap: () {},
      );
}
''';

String _stateMethodSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'state_method')
final class Welcome extends StatefulWidget {
  const Welcome({super.key});

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  bool selected = false;

  void select() => setState(() => selected = true);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: select,
        child: const Text('Select'),
      );
}
''';

String _localStateNameSource() => '''
import 'package:flutter/material.dart' hide State;
import 'package:restage/restage.dart';

final callbacks = State();

final class State {
  void select() {}
}

@ScreenSource(id: 'local_state_name')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: callbacks.select,
        child: const Text('Select'),
      );
}
''';

String _inlinedCustomSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onActivate,
        child: const Text('Activate'),
      );
}

@ScreenSource(id: 'inline')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ActionButton(onActivate: () {}),
          ActionButton(onActivate: () {}),
        ],
      );
}
''';

String _nestedInlinedCustomSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class InnerAction extends StatelessWidget {
  const InnerAction({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onActivate,
        child: const Text('Activate'),
      );
}

@RestageWidget()
final class OuterAction extends StatelessWidget {
  const OuterAction({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => InnerAction(onActivate: onActivate);
}

@ScreenSource(id: 'nested_inline')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          OuterAction(onActivate: () {}),
          OuterAction(onActivate: () {}),
        ],
      );
}
''';

String _inlinedHelperSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final label = const Text('Activate');
    return _button(label);
  }

  Widget _button(Widget child) => ElevatedButton(
        onPressed: onActivate,
        child: child,
      );
}

@ScreenSource(id: 'inline_helper')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => ActionButton(onActivate: () {});
}
''';

String _opaqueCustomSource({required String className}) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget()
final class $className extends StatelessWidget {
  const $className({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onActivate,
        child: const Text('Private implementation'),
      );
}

@ScreenSource(id: 'opaque_boundary')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => $className(onActivate: () {});
}
''';

String _flowAndScreenSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'flow_screen')
final class FlowScreen extends StatelessWidget {
  const FlowScreen({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
        child: const Text('Continue'),
      );
}

@FlowSource(id: 'welcome_flow')
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() => throw UnimplementedError();
}
''';

String _fakeSourceAnnotation() => '''
import 'package:flutter/material.dart';

class ScreenSource {
  const ScreenSource({required this.id});
  final String id;
}

@ScreenSource(id: 'fake')
final class FakeSource extends StatelessWidget {
  const FakeSource({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
        child: const Text('Continue'),
      );
}
''';

String _fakeFlutterWidget() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

class ElevatedButton extends Widget {
  const ElevatedButton({this.onPressed});

  final VoidCallback? onPressed;
}

@ScreenSource(id: 'fake_widget')
final class FakeWidget extends StatelessWidget {
  const FakeWidget({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: () {});
}
''';

String _fakeCustomWidget() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart' hide RestageWidget;

class RestageWidget {
  const RestageWidget();
}

@RestageWidget()
final class LocalAction extends StatelessWidget {
  const LocalAction({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () {},
        child: const Text('Activate'),
      );
}

@ScreenSource(id: 'fake_custom')
final class FakeCustomScreen extends StatelessWidget {
  const FakeCustomScreen({super.key});

  @override
  Widget build(BuildContext context) => const LocalAction();
}
''';

String _dynamicWidgetSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'dynamic')
final class DynamicScreen extends StatelessWidget {
  const DynamicScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
''';

String _unresolvedWidgetSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'unresolved')
final class UnresolvedScreen extends StatelessWidget {
  const UnresolvedScreen({super.key});

  @override
  Widget build(BuildContext context) => MissingButton(onPressed: () {});
}
''';

String _preludeWidgetSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'prelude_widget')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    final action = ElevatedButton(
      onPressed: () {},
      child: const Text('Continue'),
    );
    return Column(children: [action]);
  }
}
''';

String _widgetListSource({required bool heldInLocal}) {
  const children = '''
[
          const Text('First'),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Activate'),
          ),
          const Text('Last'),
        ]
''';
  final body = heldInLocal
      ? '''
{
    final children = $children;
    return Column(children: children);
  }
'''
      : '=> Column(children: $children);';
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'widget_list')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) $body
}
''';
}
