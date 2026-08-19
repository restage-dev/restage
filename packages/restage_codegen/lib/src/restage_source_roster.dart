// Internal package ownership model. Every member here is reached through the
// documented builders rather than directly, so the public-API doc lint does
// not apply.
// ignore_for_file: public_member_api_docs, prefer_asserts_with_message

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart'
    show FlowDeliveryMode, Surface;

/// The source kinds understood by the package roster.
///
/// This remains an internal codegen algebra even though the scanner now admits
/// canonical SDK annotations. Public authoring meaning is resolved by the
/// analyzer frontend before it reaches this ownership model.
@internal
enum RestageRosterSourceKind {
  screen,
  paywall,
  flow,
}

extension RestageRosterSourceKindName on RestageRosterSourceKind {
  /// Stable JSON spelling used by the build-owned roster.
  String get wireName => switch (this) {
        RestageRosterSourceKind.screen => 'screen',
        RestageRosterSourceKind.paywall => 'paywall',
        RestageRosterSourceKind.flow => 'flowGraph',
      };
}

/// A source span retained by package ownership diagnostics.
@immutable
@internal
final class RestageSourceSpan {
  /// Creates a source span.  Line and column numbers are one-based.
  const RestageSourceSpan({
    required this.path,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
  })  : assert(path != ''),
        assert(startLine > 0),
        assert(startColumn > 0),
        assert(endLine > 0),
        assert(endColumn > 0);

  /// Package-relative source path containing the declaration.
  final String path;

  /// Inclusive start line.
  final int startLine;

  /// Inclusive start column.
  final int startColumn;

  /// Exclusive end line.
  final int endLine;

  /// Exclusive end column.
  final int endColumn;

  /// Compact source location used in build diagnostics.
  String get location => '$path@$startLine:$startColumn';

  Map<String, Object> toJson() => {
        'path': path,
        'start': {'line': startLine, 'column': startColumn},
        'end': {'line': endLine, 'column': endColumn},
      };
}

/// One namespace-scoped identity claim owned by a declaration.
///
/// The roster validates claims only inside the namespace supplied by the
/// admission adapter. It does not invent a publication identity: canonical
/// adapters add `(surface, slug)` claims only for independently published
/// declarations, while neutral reusable declarations and physical output
/// namespaces remain independent claims.
@immutable
@internal
final class RestageIdentityClaim {
  /// Creates an identity claim.
  const RestageIdentityClaim({
    required this.namespace,
    required this.key,
  })  : assert(namespace != ''),
        assert(key != '');

  /// Namespace whose collision domain owns [key].
  final String namespace;

  /// Stable key within [namespace].
  final String key;

  /// Qualified display form; this is not a wire/publication identity.
  String get qualifiedKey => '$namespace:$key';

  Map<String, String> toJson() => {
        'namespace': namespace,
        'key': key,
      };
}

/// One generated output owned by a source declaration.
@immutable
@internal
final class RestageOutputClaim {
  /// Creates an output claim.
  const RestageOutputClaim({
    required this.path,
    required this.role,
    required this.builder,
    this.ownershipKey,
  })  : assert(path != ''),
        assert(role != ''),
        assert(builder != '');

  /// Package-relative generated output path.
  final String path;

  /// Semantic role within the source's output family.
  final String role;

  /// Build-runner builder that physically owns this output.
  final String builder;

  /// Optional stable owner for an output shared by declarations in one
  /// library or by a semantic publication identity.
  ///
  /// A generated part is library-owned even when several annotated classes
  /// contribute declarations to it.  Artifact outputs are publication-owned,
  /// so an explicit ID remains stable when its source file moves.  Keeping
  /// this owner separate from the declaration identity prevents either case
  /// from looking like a collision or producing a stale artifact on a move.
  final String? ownershipKey;

  Map<String, String> toJson() => {
        'path': path,
        'role': role,
        'builder': builder,
        if (ownershipKey != null) 'ownershipKey': ownershipKey!,
      };
}

/// A normalized source declaration supplied to the package roster.
///
/// [explicitId] is nullable on purpose. A null value represents the
/// filename-derived, one-per-library implicit declaration. Deprecated legacy
/// `*Source` annotations are normalized by the scanner with a non-null ID.
@immutable
@internal
final class RestageSourceDeclaration {
  /// Creates a normalized declaration from already immutable/const lists.
  ///
  /// The constructor is intentionally const-valid.  Runtime adapters should
  /// use [RestageSourceDeclaration.frozen] when their input lists are mutable.
  const RestageSourceDeclaration({
    required this.kind,
    required this.libraryIdentity,
    required this.libraryPath,
    required this.declarationIdentity,
    required this.sourcePath,
    required this.explicitId,
    required this.span,
    required this.identityClaims,
    required this.outputs,
    this.surface,
    this.version = 1,
    this.minClient = 1,
    this.delivery,
    this.isCanonical = false,
  });

  /// Creates an immutable declaration by defensively freezing both lists.
  RestageSourceDeclaration.frozen({
    required this.kind,
    required this.libraryIdentity,
    required this.libraryPath,
    required this.declarationIdentity,
    required this.sourcePath,
    required this.explicitId,
    required this.span,
    required List<RestageIdentityClaim> identityClaims,
    required List<RestageOutputClaim> outputs,
    this.surface,
    this.version = 1,
    this.minClient = 1,
    this.delivery,
    this.isCanonical = false,
  })  : identityClaims = List.unmodifiable(identityClaims),
        outputs = List.unmodifiable(outputs);

  /// Source kind.
  final RestageRosterSourceKind kind;

  /// Canonical analyzer library identity.
  final String libraryIdentity;

  /// Package-relative path of the owning library input.
  final String libraryPath;

  /// Canonical analyzer declaration identity.
  final String declarationIdentity;

  /// Package-relative path of the declaration itself.  This can be a part
  /// path, while [libraryPath] remains the importable library entrypoint.
  final String sourcePath;

  /// Explicit authored ID, or null for the roster's implicit-ID capability.
  final String? explicitId;

  /// Declaration source span.
  final RestageSourceSpan span;

  /// Identity claims whose collision domains are owned by the caller.
  final List<RestageIdentityClaim> identityClaims;

  /// Complete generated output family owned by this declaration.
  final List<RestageOutputClaim> outputs;

  /// Code-level surface authority. Legacy declarations retain the directory
  /// value here after normalization; neutral `@Screen()` declarations leave
  /// it null.
  final Surface? surface;

  /// Authored contract/descriptor version.
  final int version;

  /// Authored minimum client/catalog version.
  final int minClient;

  /// Flow delivery mode, when the declaration is a flow.
  final FlowDeliveryMode? delivery;

  /// Whether the declaration came from a canonical annotation rather than a
  /// deprecated compatibility frontend.
  final bool isCanonical;

  /// Whether this declaration uses the future implicit-ID form.
  bool get hasImplicitId => explicitId == null;

  /// The owning library's filename-derived ID.
  String get implicitId {
    final slash = libraryPath.lastIndexOf('/');
    final filename =
        slash == -1 ? libraryPath : libraryPath.substring(slash + 1);
    return filename.endsWith('.dart')
        ? filename.substring(0, filename.length - '.dart'.length)
        : filename;
  }

  /// The ID used by package ownership and collision checks.
  String get effectiveId => explicitId ?? implicitId;

  /// Stable owner key used by the output roster.
  String get ownerKey => declarationIdentity;

  Map<String, Object> toJson() => {
        'kind': kind.wireName,
        'id': effectiveId,
        'idMode': hasImplicitId ? 'implicit' : 'explicit',
        'identity': declarationIdentity,
        'identityClaims': [
          for (final claim in identityClaims) claim.toJson(),
        ],
        'library': libraryIdentity,
        'libraryPath': libraryPath,
        'source': sourcePath,
        if (surface != null) 'surface': surface!.wireName,
        'version': version,
        'minClient': minClient,
        if (delivery != null) 'deliveryMode': delivery!.wireName,
        'authoring': isCanonical ? 'canonical' : 'legacy',
        'span': span.toJson(),
        'outputs': [for (final output in outputs) output.toJson()],
      };
}

/// The deterministic package source index plus output ownership ledger.
@immutable
@internal
final class RestageSourceRoster {
  /// Creates an assembled roster.
  RestageSourceRoster({
    required List<RestageSourceDeclaration> declarations,
    required List<Issue> issues,
    List<RestageOwnedOutput> fixedOutputs = const [],
  })  : declarations = List.unmodifiable(declarations),
        issues = List.unmodifiable(issues),
        outputs = List.unmodifiable(
          <RestageOwnedOutput>[
            ..._flattenOutputs(declarations),
            ...fixedOutputs,
          ]..sort(_compareOwnedOutputs),
        );

  /// Declarations in deterministic kind/ID/identity order.
  final List<RestageSourceDeclaration> declarations;

  /// Flattened output claims in deterministic path/owner/role order.
  final List<RestageOwnedOutput> outputs;

  /// Ownership and admission diagnostics.
  final List<Issue> issues;

  /// Whether the roster can be emitted as authoritative package metadata.
  bool get isValid => issues.isEmpty;

  /// Encodes the package-wide source index.
  String encodeSourceIndex(String packageName) => _encodeJson({
        'schemaVersion': 1,
        'package': packageName,
        'valid': isValid,
        if (!isValid)
          'issues': [for (final issue in issues) _issueToJson(issue)],
        'sources': [for (final source in declarations) source.toJson()],
      });

  /// Encodes the package-wide output ownership ledger.
  String encodeOutputRoster(String packageName) => _encodeJson({
        'schemaVersion': 1,
        'package': packageName,
        'valid': isValid,
        if (!isValid)
          'issues': [for (final issue in issues) _issueToJson(issue)],
        'outputs': [for (final output in outputs) output.toJson()],
      });
}

/// One flattened output claim with its source owner attached.
@immutable
@internal
final class RestageOwnedOutput {
  /// Creates a flattened output claim.
  const RestageOwnedOutput({
    required this.path,
    required this.role,
    required this.builder,
    required this.owner,
    required this.declarationIdentity,
    required this.identities,
    required this.span,
  });

  /// Generated output path.
  final String path;

  /// Output-family role.
  final String role;

  /// Physical builder owner.
  final String builder;

  /// Exact declaration owner key.
  final String owner;

  /// Exact normalized declaration identity.
  ///
  /// This is deliberately not a `kind:id` package identity. Namespace
  /// collision claims are carried separately in [identities], and a later
  /// frontend may add the surface-aware publication claim it owns.
  final String declarationIdentity;

  /// Namespace-scoped identities owned by the declaration.
  final List<RestageIdentityClaim> identities;

  /// Source span of the owner.
  final RestageSourceSpan span;

  Map<String, Object> toJson() => {
        'path': path,
        'role': role,
        'builder': builder,
        'owner': owner,
        'declaration': declarationIdentity,
        'identities': [for (final identity in identities) identity.toJson()],
        'span': span.toJson(),
      };
}

/// Why a previous generated output claim is no longer current.
@internal
enum RestageStaleOutputReason {
  /// The declaration no longer owns any corresponding current output.
  removed,

  /// The same delivery identity still exists, but its physical output moved.
  moved,

  /// A current declaration now occupies the old path with a different owner,
  /// role, builder, or namespace claim.
  replaced,
}

/// One exact previous output claim that must cease to be owned.
@immutable
@internal
final class RestageStaleOutputClaim {
  /// Creates a stale output record.
  const RestageStaleOutputClaim({
    required this.output,
    required this.reason,
  });

  /// The complete previous output claim, including source span and identity
  /// namespaces, rather than only its path.
  final RestageOwnedOutput output;

  /// Classification of the transition from the previous roster.
  final RestageStaleOutputReason reason;

  /// Convenience access to the physical output path.
  String get path => output.path;

  Map<String, Object> toJson() => {
        ...output.toJson(),
        'reason': reason.name,
      };
}

/// Computes exact deterministic stale output families between rosters.
///
/// Build-runner remains the physical cleanup authority for outputs declared by
/// each tracked artifact builder. This pure transition is the roster-level
/// ownership proof: a previous claim is retained only when its complete owner,
/// role, builder, path, and namespace claims are unchanged. A source removal
/// produces [RestageStaleOutputReason.removed]; a file move with the same
/// namespace identity produces [RestageStaleOutputReason.moved], even though
/// the old physical family is stale; and a path reused by a different owner
/// is [RestageStaleOutputReason.replaced].
@visibleForTesting
List<RestageStaleOutputClaim> computeRestageStaleOutputs(
  RestageSourceRoster previous,
  RestageSourceRoster current,
) {
  final currentByPath = <String, List<RestageOwnedOutput>>{};
  for (final output in current.outputs) {
    currentByPath.putIfAbsent(output.path, () => []).add(output);
  }

  final currentByIdentity = <String, List<RestageOwnedOutput>>{};
  for (final output in current.outputs) {
    for (final identity in output.identities) {
      currentByIdentity
          .putIfAbsent(identity.qualifiedKey, () => [])
          .add(output);
    }
  }

  final stale = <RestageStaleOutputClaim>[];
  for (final previousOutput in previous.outputs) {
    final samePath = currentByPath[previousOutput.path] ?? const [];
    if (samePath.any(
      (currentOutput) => _sameOutputClaim(previousOutput, currentOutput),
    )) {
      continue;
    }

    final hasSameDeliveryIdentity = previousOutput.identities.any(
      (identity) =>
          currentByIdentity[identity.qualifiedKey]?.isNotEmpty ?? false,
    );
    final RestageStaleOutputReason reason;
    if (samePath.isNotEmpty) {
      reason = RestageStaleOutputReason.replaced;
    } else if (hasSameDeliveryIdentity) {
      reason = RestageStaleOutputReason.moved;
    } else {
      reason = RestageStaleOutputReason.removed;
    }
    stale.add(
      RestageStaleOutputClaim(
        output: previousOutput,
        reason: reason,
      ),
    );
  }
  return stale;
}

bool _sameOutputClaim(
  RestageOwnedOutput left,
  RestageOwnedOutput right,
) {
  if (left.path != right.path ||
      left.role != right.role ||
      left.builder != right.builder ||
      left.owner != right.owner ||
      left.declarationIdentity != right.declarationIdentity ||
      left.identities.length != right.identities.length) {
    return false;
  }
  final leftIdentities =
      left.identities.map((identity) => identity.qualifiedKey).toSet();
  final rightIdentities =
      right.identities.map((identity) => identity.qualifiedKey).toSet();
  return leftIdentities.length == rightIdentities.length &&
      leftIdentities.containsAll(rightIdentities);
}

/// Assembles and validates the package-wide source/output roster.
///
/// A library may own one implicit declaration and any number of explicit
/// declarations; every identity claim is unique inside its declared
/// namespace; and every generated output path has exactly one owner. The
/// function is pure so the analyzer/build-step adapter can be tested
/// separately from ownership rules.
@internal
RestageSourceRoster assembleRestageSourceRoster(
  Iterable<RestageSourceDeclaration> input,
) {
  final declarations = input.toList()..sort(_compareDeclarations);
  final issues = <Issue>[];

  final implicitByLibrary = <String, List<RestageSourceDeclaration>>{};
  for (final declaration
      in declarations.where((source) => source.hasImplicitId)) {
    implicitByLibrary
        .putIfAbsent(declaration.libraryIdentity, () => [])
        .add(declaration);
  }
  for (final entry in implicitByLibrary.entries) {
    if (entry.value.length < 2) continue;
    final locations =
        entry.value.map((source) => source.span.location).join(', ');
    issues.add(
      Issue(
        code: IssueCode.invalidScreenSourceCount,
        message: 'Library ${entry.key} declares more than one implicit '
            'Restage source ID. Implicit declarations: $locations. Add an '
            'explicit unique id to every declaration after the first.',
        location: entry.value.first.span.location,
      ),
    );
  }

  final byIdentity = <String, List<RestageSourceDeclaration>>{};
  for (final declaration in declarations) {
    if (declaration.explicitId == '') {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: 'A ${declaration.kind.wireName} source ID must not be '
              'empty.',
          location: declaration.span.location,
        ),
      );
    }
    for (final identity in declaration.identityClaims) {
      byIdentity.putIfAbsent(identity.qualifiedKey, () => []).add(declaration);
    }
  }
  for (final entry in byIdentity.entries) {
    if (entry.value.length < 2) continue;
    final declarationsText = entry.value
        .map(
          (source) => '${source.declarationIdentity} (${source.span.location})',
        )
        .join(', ');
    final explicit = entry.value.every((source) => !source.hasImplicitId);
    issues.add(
      Issue(
        code: IssueCode.duplicateId,
        message: 'Restage identity namespace "${entry.key}" is declared by '
            '${explicit ? 'duplicate explicit IDs' : 'multiple declarations'}: '
            '$declarationsText.',
        location: entry.value.first.span.location,
      ),
    );
  }

  final byOutput = <String, List<RestageOwnedOutput>>{};
  for (final output in _flattenOutputs(declarations)) {
    byOutput.putIfAbsent(output.path, () => []).add(output);
  }
  for (final entry in byOutput.entries) {
    // One library's declarations contribute several roles to the single
    // generated part they share. That is one physical output with one owner
    // and one writing builder, so only a genuinely distinct owner/builder
    // pair at the same path is a collision.
    final claimants = entry.value
        .map((output) => '${output.owner} ${output.builder}')
        .toSet();
    if (claimants.length < 2) continue;
    final owners = entry.value
        .map((output) => '${output.owner} (${output.span.location})')
        .join(', ');
    issues.add(
      Issue(
        code: IssueCode.generatedSymbolCollision,
        message: 'Generated output "${entry.key}" has multiple owners: '
            '$owners.',
        location: entry.value.first.span.location,
      ),
    );
  }

  issues.sort(_compareIssues);
  return RestageSourceRoster(declarations: declarations, issues: issues);
}

List<RestageOwnedOutput> _flattenOutputs(
  Iterable<RestageSourceDeclaration> declarations,
) {
  final grouped = <String, _OwnedOutputAccumulator>{};
  for (final declaration in declarations) {
    for (final output in declaration.outputs) {
      final owner = output.ownershipKey ?? declaration.ownerKey;
      final key =
          [output.path, output.role, output.builder, owner].join('\u0000');
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = _OwnedOutputAccumulator(
          path: output.path,
          role: output.role,
          builder: output.builder,
          owner: owner,
          declarationIdentity:
              output.ownershipKey ?? declaration.declarationIdentity,
          span: declaration.span,
          identities: declaration.identityClaims,
        );
      } else {
        existing.addIdentities(declaration.identityClaims);
      }
    }
  }
  final outputs = <RestageOwnedOutput>[
    ...grouped.values.map(
      (output) => RestageOwnedOutput(
        path: output.path,
        role: output.role,
        builder: output.builder,
        owner: output.owner,
        identities: output.identities,
        declarationIdentity: output.declarationIdentity,
        span: output.span,
      ),
    ),
  ]..sort(_compareOwnedOutputs);
  return outputs;
}

final class _OwnedOutputAccumulator {
  _OwnedOutputAccumulator({
    required this.path,
    required this.role,
    required this.builder,
    required this.owner,
    required this.declarationIdentity,
    required this.span,
    required Iterable<RestageIdentityClaim> identities,
  }) : _identities = {
          for (final identity in identities) identity.qualifiedKey: identity,
        };

  final String path;
  final String role;
  final String builder;
  final String owner;
  final String declarationIdentity;
  final RestageSourceSpan span;
  final Map<String, RestageIdentityClaim> _identities;

  void addIdentities(Iterable<RestageIdentityClaim> identities) {
    for (final identity in identities) {
      _identities[identity.qualifiedKey] = identity;
    }
  }

  List<RestageIdentityClaim> get identities => (_identities.values.toList()
    ..sort(
      (left, right) => left.qualifiedKey.compareTo(right.qualifiedKey),
    ));
}

int _compareOwnedOutputs(RestageOwnedOutput left, RestageOwnedOutput right) {
  final byPath = left.path.compareTo(right.path);
  if (byPath != 0) return byPath;
  final byOwner = left.owner.compareTo(right.owner);
  if (byOwner != 0) return byOwner;
  return left.role.compareTo(right.role);
}

int _compareDeclarations(
  RestageSourceDeclaration left,
  RestageSourceDeclaration right,
) {
  final byKind = left.kind.index.compareTo(right.kind.index);
  if (byKind != 0) return byKind;
  final byId = left.effectiveId.compareTo(right.effectiveId);
  if (byId != 0) return byId;
  final byIdentity =
      left.declarationIdentity.compareTo(right.declarationIdentity);
  if (byIdentity != 0) return byIdentity;
  return left.span.location.compareTo(right.span.location);
}

int _compareIssues(Issue left, Issue right) {
  final byLocation = left.location.compareTo(right.location);
  if (byLocation != 0) return byLocation;
  final byCode = left.code.name.compareTo(right.code.name);
  return byCode != 0 ? byCode : left.message.compareTo(right.message);
}

String _encodeJson(Map<String, Object> value) =>
    const JsonEncoder.withIndent('  ').convert(value);

Map<String, String> _issueToJson(Issue issue) => {
      'code': issue.code.name,
      'message': issue.message,
      'location': issue.location,
    };
