import 'package:analyzer/dart/element/element.dart' show ClassElement;
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';
import 'package:rfw_catalog_compiler/src/ir/provenance.dart';
import 'package:rfw_catalog_compiler/src/ir/structured_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/union_ir.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/policy/structured_walk_policy.dart';
import 'package:rfw_catalog_compiler/src/walker/element_fqn.dart';
import 'package:rfw_catalog_compiler/src/walker/structured_walker.dart';
import 'package:rfw_catalog_compiler/src/walker/walker_issue_codes.dart'
    as issue_codes;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Resolves a member FQN to its analyzer class element, or null when the
/// member cannot be located in the resolved element graph.
typedef MemberElementResolver = ClassElement? Function(String memberFqn);

/// The product of resolving one abstract base into a discriminated union.
@immutable
final class UnionResolution {
  /// Creates a union resolution result.
  const UnionResolution({
    required this.unionIr,
    required this.memberStructured,
    required this.descendants,
  });

  /// The resolved union IR.
  final UnionIR unionIr;

  /// Structured IR for each resolved concrete member.
  final List<StructuredIR> memberStructured;

  /// Structured types discovered while walking the members' field graphs.
  final List<StructuredIR> descendants;
}

/// Resolves [abstractElement] into a [UnionResolution] when its FQN is a
/// registered abstract base in [policy]'s union registry; returns null for
/// an unregistered type (the caller keeps its existing fallback).
///
/// Each registered member FQN is resolved to a class element via
/// [resolveMember] and walked through the structured-type walker. Members
/// that fail to resolve, or that resolve to an element which is not a valid
/// concrete subtype of the abstract base, are skipped with a diagnostic so a
/// partial graph still produces a usable union.
///
/// Each member is walked with its own fresh cycle set, so a structured type
/// reachable from two members is walked fully for each rather than collapsed
/// to a cycle placeholder on the second visit. Deduplication of structured
/// entries across the wider catalog walk is the caller's responsibility.
UnionResolution? resolveUnion({
  required ClassElement abstractElement,
  required WidgetLibrary library,
  required PolicyLedger policy,
  required String location,
  required MemberElementResolver resolveMember,
}) {
  final fqn = elementFqn(abstractElement);
  final registryEntry = policy.unionRegistry.lookup(fqn);
  if (registryEntry == null) return null;

  final memberStructured = <StructuredIR>[];
  final descendants = <StructuredIR>[];
  final memberRefs = <WireIdRef>[];
  final memberSourceTypes = <String>[];
  final diagnostics = <DiagnosticIR>[];

  // A registered union member is by definition a concrete structured type
  // the walker must descend INTO — but the union's members are not on the
  // base concrete allowlist (the base policy lists only the abstract base).
  // Extend the walk policy with this union's member identifiers so each
  // member walks successfully without touching the global policy.
  final memberWalkPolicy = policy.extend(
    structuredWalk: StructuredWalkPolicy(
      concreteTypes: {
        ...policy.structuredWalk.concreteTypes,
        ...registryEntry.members,
      },
      abstractTypes: policy.structuredWalk.abstractTypes,
      maxDepth: policy.structuredWalk.maxDepth,
    ),
  );

  for (final memberFqn in registryEntry.members) {
    final memberElement = resolveMember(memberFqn);
    if (memberElement == null) {
      diagnostics.add(
        DiagnosticIR(
          code: issue_codes.unionMemberUnresolved,
          message: 'Union member $memberFqn for ${abstractElement.name} '
              'did not resolve to a class element.',
          location: location,
          severity: DiagnosticSeverity.warning,
          target: abstractElement.name,
        ),
      );
      continue;
    }

    final validationFailure = _validateMember(
      memberElement: memberElement,
      memberFqn: memberFqn,
      abstractFqn: fqn,
    );
    if (validationFailure != null) {
      diagnostics.add(
        DiagnosticIR(
          code: issue_codes.unionMemberInvalid,
          message: 'Union member $memberFqn for ${abstractElement.name} '
              '$validationFailure',
          location: location,
          severity: DiagnosticSeverity.warning,
          target: abstractElement.name,
        ),
      );
      continue;
    }

    // Each member gets its own cycle set. The walker uses this set to
    // detect self-referential graphs within a single walk; sharing one set
    // across members would mistake a structured type shared by two members
    // for a cycle the second time it appears.
    final walk = walkStructuredType(
      element: memberElement,
      library: library,
      policy: memberWalkPolicy,
      location: location,
      visited: <String>{},
      depth: 0,
    );
    final ir = walk.ir;
    if (ir != null) memberStructured.add(ir);
    descendants.addAll(walk.descendants);

    memberSourceTypes.add(memberFqn);

    // The member's wire ID resolves in a later allocator pass. Until then
    // the reference carries the unallocated structured sentinel paired
    // with the owning library namespace — the same convention the
    // structured walker uses for descendant references. Identity is
    // recovered from the index-aligned member source FQN.
    memberRefs.add(
      WireIdRef(
        library: library.namespace,
        wireId: WireId.unallocatedStructured,
      ),
    );
  }

  final unionIr = UnionIR(
    wireId: WireId.unallocatedUnion,
    source: abstractElement,
    name: abstractElement.name ?? '<unnamed>',
    library: library,
    description: registryEntry.description,
    sourceType: fqn,
    memberSourceTypes: List<String>.unmodifiable(memberSourceTypes),
    // `discriminator.values` deliberately mirrors `members`: one ref per
    // member, index-aligned. The allocator reads `members` as the
    // authoritative member list — the mirror is intentional, not an accident.
    discriminator: DiscriminatorSpec(
      field: registryEntry.discriminatorField,
      values: List<WireIdRef>.unmodifiable(memberRefs),
    ),
    members: List<WireIdRef>.unmodifiable(memberRefs),
    stability: Stability.volatile,
    diagnostics: diagnostics,
    provenance: ProvenanceIR(
      flutterType: fqn,
      curationSource: location,
      derivationTrace: const ['union_resolver'],
    ),
    policyTrace: const [],
  );

  return UnionResolution(
    unionIr: unionIr,
    memberStructured: memberStructured,
    descendants: descendants,
  );
}

/// Validates a resolved member element against the union it belongs to.
///
/// Returns a human-readable failure clause when the member is invalid, or
/// null when it is a usable concrete subtype of the abstract base. A member
/// is valid when its own FQN matches the requested name, it is not itself
/// abstract, and it transitively extends or implements the abstract base.
String? _validateMember({
  required ClassElement memberElement,
  required String memberFqn,
  required String abstractFqn,
}) {
  final resolvedFqn = elementFqn(memberElement);
  if (resolvedFqn != memberFqn) {
    return 'resolved to a different type ($resolvedFqn).';
  }
  if (memberElement.isAbstract) {
    return 'resolved to an abstract class and cannot be a concrete member.';
  }
  final isSubtype = memberElement.allSupertypes
      .any((supertype) => interfaceFqn(supertype.element) == abstractFqn);
  if (!isSubtype) {
    return 'is not a subtype of the abstract base.';
  }
  return null;
}
