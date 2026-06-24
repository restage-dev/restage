import 'package:analyzer/dart/element/element.dart' show ClassElement;
import 'package:analyzer/dart/element/type.dart' show InterfaceType;
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/policy/union_registry.dart';
import 'package:rfw_catalog_compiler/src/walker/union_resolver.dart';
import 'package:rfw_catalog_compiler/src/walker/walker_issue_codes.dart'
    as issue_codes;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../policy/fakes/fake_dart_types.dart' as fakes;

/// Fully-qualified names for the gradient hierarchy used across the
/// resolver tests.
const _gradientLib = 'package:flutter/src/painting/gradient.dart';
const _gradientFqn = '$_gradientLib#Gradient';
const _linearFqn = '$_gradientLib#LinearGradient';
const _radialFqn = '$_gradientLib#RadialGradient';
const _sweepFqn = '$_gradientLib#SweepGradient';

void main() {
  group('resolveUnion', () {
    // The built-in ledger lists `Gradient` as an abstract base and its
    // three members in the union registry; `resolveUnion` extends the
    // walk policy with the registered member identifiers itself, so the
    // built-in ledger works end to end with no test-local extension.
    const policy = PolicyLedger.builtIn();

    /// Builds the abstract base element for `Gradient`.
    ClassElement gradientBase() => fakes.fakeClassElement(
          'Gradient',
          libraryIdentifier: _gradientLib,
          isAbstract: true,
        );

    /// An `InterfaceType` standing in for the abstract `Gradient` base,
    /// used to populate a member's supertype list.
    InterfaceType gradientSupertype() => fakes.fakeInterfaceType(
          'Gradient',
          libraryIdentifier: _gradientLib,
        ) as InterfaceType;

    /// Builds a concrete gradient member element that declares `Gradient`
    /// as a supertype, so the resolver's subtype check accepts it.
    ClassElement gradientMember(String name) => fakes.fakeClassElement(
          name,
          libraryIdentifier: _gradientLib,
          allSupertypes: [gradientSupertype()],
        );

    /// A member resolver that maps each gradient member FQN to a fresh
    /// fake class element.
    ClassElement? resolveAllMembers(String fqn) {
      switch (fqn) {
        case _linearFqn:
          return gradientMember('LinearGradient');
        case _radialFqn:
          return gradientMember('RadialGradient');
        case _sweepFqn:
          return gradientMember('SweepGradient');
        default:
          return null;
      }
    }

    test('resolves a registered abstract base into a union with members', () {
      final resolution = resolveUnion(
        abstractElement: gradientBase(),
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#Gradient',
        resolveMember: resolveAllMembers,
      );

      expect(resolution, isNotNull);
      final unionIr = resolution!.unionIr;
      expect(unionIr.name, 'Gradient');
      expect(unionIr.members, hasLength(3));
      expect(
        resolution.memberStructured.map((ir) => ir.name),
        containsAll(<String>[
          'LinearGradient',
          'RadialGradient',
          'SweepGradient',
        ]),
      );
      expect(unionIr.discriminator.field, '_s');
      expect(unionIr.discriminator.values, hasLength(3));
    });

    test('carries the abstract base FQN and index-aligned member FQNs', () {
      final resolution = resolveUnion(
        abstractElement: gradientBase(),
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#Gradient',
        resolveMember: resolveAllMembers,
      );

      final unionIr = resolution!.unionIr;
      expect(unionIr.sourceType, _gradientFqn);
      expect(
        unionIr.memberSourceTypes,
        [_linearFqn, _radialFqn, _sweepFqn],
      );
      // memberSourceTypes is index-aligned with members.
      expect(unionIr.memberSourceTypes, hasLength(unionIr.members.length));
    });

    test('returns null for an unregistered abstract type', () {
      final widget = fakes.fakeClassElement(
        'Widget',
        libraryIdentifier: 'package:flutter/src/widgets/framework.dart',
      );

      final resolution = resolveUnion(
        abstractElement: widget,
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#Widget',
        resolveMember: resolveAllMembers,
      );

      expect(resolution, isNull);
    });

    test('records a diagnostic when a member fails to resolve', () {
      ClassElement? resolveWithoutRadial(String fqn) {
        if (fqn == _radialFqn) return null;
        return resolveAllMembers(fqn);
      }

      final resolution = resolveUnion(
        abstractElement: gradientBase(),
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#Gradient',
        resolveMember: resolveWithoutRadial,
      );

      expect(resolution, isNotNull);
      final unionIr = resolution!.unionIr;
      expect(unionIr.members, hasLength(2));
      expect(resolution.memberStructured, hasLength(2));
      expect(unionIr.discriminator.values, hasLength(2));
      expect(unionIr.memberSourceTypes, [_linearFqn, _sweepFqn]);
      expect(
        unionIr.diagnostics.map((d) => d.code),
        contains(issue_codes.unionMemberUnresolved),
      );
    });

    test('skips a member that resolves to an abstract class', () {
      ClassElement? resolveWithAbstractRadial(String fqn) {
        if (fqn == _radialFqn) {
          return fakes.fakeClassElement(
            'RadialGradient',
            libraryIdentifier: _gradientLib,
            isAbstract: true,
            allSupertypes: [gradientSupertype()],
          );
        }
        return resolveAllMembers(fqn);
      }

      final resolution = resolveUnion(
        abstractElement: gradientBase(),
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#Gradient',
        resolveMember: resolveWithAbstractRadial,
      );

      final unionIr = resolution!.unionIr;
      expect(unionIr.members, hasLength(2));
      expect(unionIr.memberSourceTypes, [_linearFqn, _sweepFqn]);
      expect(unionIr.discriminator.values, hasLength(2));
      expect(
        unionIr.diagnostics.map((d) => d.code),
        contains(issue_codes.unionMemberInvalid),
      );
    });

    test('skips a member that is not a subtype of the abstract base', () {
      ClassElement? resolveWithNonSubtype(String fqn) {
        if (fqn == _sweepFqn) {
          // Resolves to the right FQN and is concrete, but declares no
          // supertype relationship with Gradient.
          return fakes.fakeClassElement(
            'SweepGradient',
            libraryIdentifier: _gradientLib,
          );
        }
        return resolveAllMembers(fqn);
      }

      final resolution = resolveUnion(
        abstractElement: gradientBase(),
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#Gradient',
        resolveMember: resolveWithNonSubtype,
      );

      final unionIr = resolution!.unionIr;
      expect(unionIr.members, hasLength(2));
      expect(unionIr.memberSourceTypes, [_linearFqn, _radialFqn]);
      expect(
        unionIr.diagnostics.map((d) => d.code),
        contains(issue_codes.unionMemberInvalid),
      );
    });

    test('skips a member whose resolved FQN differs from the request', () {
      ClassElement? resolveWithWrongFqn(String fqn) {
        if (fqn == _linearFqn) {
          // Resolves to an element living in a different library.
          return fakes.fakeClassElement(
            'LinearGradient',
            libraryIdentifier: 'package:other/gradient.dart',
            allSupertypes: [gradientSupertype()],
          );
        }
        return resolveAllMembers(fqn);
      }

      final resolution = resolveUnion(
        abstractElement: gradientBase(),
        library: WidgetLibrary.core,
        policy: policy,
        location: 'test#Gradient',
        resolveMember: resolveWithWrongFqn,
      );

      final unionIr = resolution!.unionIr;
      expect(unionIr.members, hasLength(2));
      expect(unionIr.memberSourceTypes, [_radialFqn, _sweepFqn]);
      expect(
        unionIr.diagnostics.map((d) => d.code),
        contains(issue_codes.unionMemberInvalid),
      );
    });

    test('walks a structured type shared by two members for each member', () {
      // A structured type reachable from more than one union member must
      // be walked fully for every member rather than collapsed to a cycle
      // placeholder on the second visit. `BorderRadius` is a built-in
      // concrete structured type; both members carry it as a field.
      const customLib = 'package:custom/style.dart';
      const baseFqn = '$customLib#CustomStyle';
      const memberAFqn = '$customLib#StyleA';
      const memberBFqn = '$customLib#StyleB';
      const borderRadiusFqn =
          'package:flutter/src/painting/border_radius.dart#BorderRadius';

      final customPolicy = policy.extend(
        unionRegistry: UnionRegistry.of({
          baseFqn: UnionRegistryEntry.of(
            abstractType: baseFqn,
            members: const [memberAFqn, memberBFqn],
            discriminatorField: '_s',
            description: 'A custom style union.',
          ),
        }),
      );

      ClassElement styleMember(String name) {
        final borderRadius = fakes.fakeClassElement(
          'BorderRadius',
          libraryIdentifier: 'package:flutter/src/painting/border_radius.dart',
        );
        return fakes.fakeClassElement(
          name,
          libraryIdentifier: customLib,
          allSupertypes: [
            fakes.fakeInterfaceType(
              'CustomStyle',
              libraryIdentifier: customLib,
            ) as InterfaceType,
          ],
          fields: [
            fakes.fakeFieldElement('radius', borderRadius.thisType),
          ],
        );
      }

      ClassElement? resolveCustom(String fqn) {
        switch (fqn) {
          case memberAFqn:
            return styleMember('StyleA');
          case memberBFqn:
            return styleMember('StyleB');
          default:
            return null;
        }
      }

      final resolution = resolveUnion(
        abstractElement: fakes.fakeClassElement(
          'CustomStyle',
          libraryIdentifier: customLib,
          isAbstract: true,
        ),
        library: WidgetLibrary.core,
        policy: customPolicy,
        location: 'test#CustomStyle',
        resolveMember: resolveCustom,
      );

      expect(resolution, isNotNull);
      final descendants = resolution!.descendants;
      // The shared BorderRadius descendant is discovered once per member
      // walk because each walk gets a fresh cycle set.
      final borderRadiusWalks = descendants
          .where((ir) => ir.provenance.flutterType == borderRadiusFqn)
          .toList();
      expect(borderRadiusWalks, hasLength(2));
      // Neither walk degraded into a cycle placeholder.
      for (final ir in borderRadiusWalks) {
        expect(
          ir.diagnostics.map((d) => d.code),
          isNot(contains(issue_codes.structuredCycle)),
        );
      }
      // Sanity: the diagnostic surface stays free of cycle noise.
      expect(
        resolution.unionIr.diagnostics
            .map((d) => d.code)
            .where((c) => c == issue_codes.structuredCycle),
        isEmpty,
      );
    });
  });
}
