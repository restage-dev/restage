// Internal build-owned Measurement documents are consumed through builders.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Fixed build-owned source containing Measurement ledger and draft state.
const String kRestageMeasurementCompilerOutputPath =
    'lib/src/measurement/restage.measurement.compiler.json';

/// Compiler-maintained committed source used as the next build's prior state.
///
/// This path is intentionally distinct from [kRestageMeasurementCompilerOutputPath].
/// A `package:build` builder cannot consume the same asset it declares as an
/// output. The aggregate compiler is the sole writer and only advances this
/// source after a valid complete compilation.
const String kRestageMeasurementCompilerLedgerSourcePath =
    'restage_measurement.compiler.json';

/// Fixed package-wide tooling index for target-neutral Measurement drafts.
const String kRestageMeasurementOutputIndexFileName =
    'restage.measurement.index.json';

/// Builder option names for the immutable Measurement policy input.
const String kMeasurementMinimumClientOption = 'measurement_minimum_client';
const String kMeasurementPrivacyPolicyRevisionOption =
    'measurement_privacy_policy_revision_id';
const String kMeasurementCollectionBudgetRevisionOption =
    'measurement_collection_budget_revision_id';

/// Explicit build-owned policy authority for automatic Measurement output.
final class MeasurementCompilerPolicyInput {
  const MeasurementCompilerPolicyInput({
    required this.minimumMeasurementClient,
    required this.privacyPolicyRevisionId,
    required this.collectionBudgetRevisionId,
  });

  factory MeasurementCompilerPolicyInput.fromJson(Object? value) {
    final json = _object(value, 'policy');
    _exactKeys(
      json,
      const {
        'collectionBudgetRevisionId',
        'minimumMeasurementClient',
        'privacyPolicyRevisionId',
      },
      'policy',
    );
    return MeasurementCompilerPolicyInput(
      minimumMeasurementClient: _integer(
        json,
        'minimumMeasurementClient',
        'policy',
      ),
      privacyPolicyRevisionId: AuthorityRevisionId(
        _string(json, 'privacyPolicyRevisionId', 'policy'),
      ),
      collectionBudgetRevisionId: AuthorityRevisionId(
        _string(json, 'collectionBudgetRevisionId', 'policy'),
      ),
    );
  }

  /// Parses an all-or-nothing policy from merged builder options.
  static MeasurementCompilerPolicyInput? fromBuilderOptions(
    BuilderOptions options,
  ) {
    final config = options.config;
    final values = <Object?>[
      config[kMeasurementMinimumClientOption],
      config[kMeasurementPrivacyPolicyRevisionOption],
      config[kMeasurementCollectionBudgetRevisionOption],
    ];
    if (values.every((value) => value == null)) return null;
    if (values.any((value) => value == null)) {
      throw const FormatException(
        'Measurement policy options are all-or-nothing: '
        '$kMeasurementMinimumClientOption, '
        '$kMeasurementPrivacyPolicyRevisionOption, and '
        '$kMeasurementCollectionBudgetRevisionOption are required together.',
      );
    }
    final minimumClient = values[0];
    if (minimumClient is! int || minimumClient <= 0) {
      throw const FormatException(
        '$kMeasurementMinimumClientOption must be a positive integer.',
      );
    }
    final privacy = values[1];
    final budget = values[2];
    if (privacy is! String || privacy.isEmpty) {
      throw const FormatException(
        '$kMeasurementPrivacyPolicyRevisionOption must be a non-empty '
        'Measurement authority revision ID.',
      );
    }
    if (budget is! String || budget.isEmpty) {
      throw const FormatException(
        '$kMeasurementCollectionBudgetRevisionOption must be a non-empty '
        'Measurement authority revision ID.',
      );
    }
    return MeasurementCompilerPolicyInput(
      minimumMeasurementClient: minimumClient,
      privacyPolicyRevisionId: AuthorityRevisionId(privacy),
      collectionBudgetRevisionId: AuthorityRevisionId(budget),
    );
  }

  final int minimumMeasurementClient;
  final AuthorityRevisionId privacyPolicyRevisionId;
  final AuthorityRevisionId collectionBudgetRevisionId;

  Map<String, Object?> toJson() => {
        'collectionBudgetRevisionId': collectionBudgetRevisionId.value,
        'minimumMeasurementClient': minimumMeasurementClient,
        'privacyPolicyRevisionId': privacyPolicyRevisionId.value,
      };

  String get cacheKey => utf8.decode(CanonicalJsonCodec.encode(toJson()));
}

/// Exact target-neutral selector for one publication line.
final class MeasurementPublicationSelectorV1 {
  MeasurementPublicationSelectorV1({
    required this.surface,
    required this.slug,
    required this.sourceKind,
    this.contractVersion,
  }) {
    if (slug.isEmpty || slug.trim() != slug || slug.contains('\u0000')) {
      throw ArgumentError.value(slug, 'slug');
    }
    if (sourceKind == SurfaceSourceKind.screen) {
      if (contractVersion == null || contractVersion! <= 0) {
        throw ArgumentError.value(contractVersion, 'contractVersion');
      }
    } else if (contractVersion != null) {
      throw ArgumentError(
        'Only a screen Measurement selector has a contract version.',
      );
    }
  }

  factory MeasurementPublicationSelectorV1.fromPublication(
    SurfacePublication publication,
  ) =>
      MeasurementPublicationSelectorV1(
        surface: publication.surface,
        slug: publication.slug,
        sourceKind: publication.sourceKind,
        contractVersion: publication.contractVersion,
      );

  factory MeasurementPublicationSelectorV1.fromJson(Object? value) {
    final json = _object(value, 'publication selector');
    final sourceKind = SurfaceSourceKind.values.singleWhere(
      (candidate) =>
          candidate.wireName ==
          _string(json, 'sourceKind', 'publication selector'),
      orElse: () => throw const FormatException(
        'Unsupported Measurement publication sourceKind.',
      ),
    );
    final expected = <String>{'slug', 'sourceKind', 'surface'};
    if (sourceKind == SurfaceSourceKind.screen) {
      expected.add('contractVersion');
    }
    _exactKeys(json, expected, 'publication selector');
    return MeasurementPublicationSelectorV1(
      surface: Surface.values.singleWhere(
        (candidate) =>
            candidate.wireName ==
            _string(json, 'surface', 'publication selector'),
        orElse: () => throw const FormatException(
          'Unsupported Measurement publication surface.',
        ),
      ),
      slug: _string(json, 'slug', 'publication selector'),
      sourceKind: sourceKind,
      contractVersion: sourceKind == SurfaceSourceKind.screen
          ? _integer(json, 'contractVersion', 'publication selector')
          : null,
    );
  }

  final Surface surface;
  final String slug;
  final SurfaceSourceKind sourceKind;
  final int? contractVersion;

  String get key => '${surface.wireName}\u0000$slug\u0000'
      '${sourceKind.wireName}\u0000${contractVersion ?? ''}';

  /// Stable Measurement identity derived from the frozen publication line.
  SurfaceId get stableSurfaceId {
    final line = <String, Object?>{
      'kind': 'publicationLine',
      'schemaVersion': 1,
      'slug': slug,
      'sourceKind': sourceKind.wireName,
      'surface': surface.wireName,
      if (sourceKind == SurfaceSourceKind.screen)
        'contractVersion': contractVersion,
    };
    final bytes = <int>[
      ...utf8.encode('restage-surface-publication-line-v1\u0000'),
      ...CanonicalJsonCodec.encode(line),
    ];
    return SurfaceId('surface.v1.${crypto.sha256.convert(bytes)}');
  }

  Map<String, Object?> toJson() => {
        if (sourceKind == SurfaceSourceKind.screen)
          'contractVersion': contractVersion,
        'slug': slug,
        'sourceKind': sourceKind.wireName,
        'surface': surface.wireName,
      };
}

/// Persistent compiler identity for one resolved source event slot.
final class MeasurementCompilerLedgerEvent {
  const MeasurementCompilerLedgerEvent({
    required this.resolvedEventLocator,
    required this.sourceEventIdentity,
    required this.generatedReferenceId,
    required this.lineageId,
    required this.dartSymbol,
    required this.displayMetadataRef,
    required this.active,
  });

  factory MeasurementCompilerLedgerEvent.fromJson(Object? value) {
    final json = _object(value, 'ledger event');
    _exactKeys(
      json,
      const {
        'active',
        'dartSymbol',
        'displayMetadataRef',
        'generatedReferenceId',
        'lineageId',
        'resolvedEventLocator',
        'sourceEventIdentity',
      },
      'ledger event',
    );
    return MeasurementCompilerLedgerEvent(
      resolvedEventLocator: _string(
        json,
        'resolvedEventLocator',
        'ledger event',
      ),
      sourceEventIdentity: SourceEventIdentity(
        _string(json, 'sourceEventIdentity', 'ledger event'),
      ),
      generatedReferenceId: GeneratedReferenceId(
        _string(json, 'generatedReferenceId', 'ledger event'),
      ),
      lineageId: PointLineageId(
        _string(json, 'lineageId', 'ledger event'),
      ),
      dartSymbol: GeneratedDartSymbol(
        _string(json, 'dartSymbol', 'ledger event'),
      ),
      displayMetadataRef: DisplayMetadataRef(
        _string(json, 'displayMetadataRef', 'ledger event'),
      ),
      active: _boolean(json, 'active', 'ledger event'),
    );
  }

  final String resolvedEventLocator;
  final SourceEventIdentity sourceEventIdentity;
  final GeneratedReferenceId generatedReferenceId;
  final PointLineageId lineageId;
  final GeneratedDartSymbol dartSymbol;
  final DisplayMetadataRef displayMetadataRef;
  final bool active;

  MeasurementCompilerLedgerEvent copyWith({bool? active}) =>
      MeasurementCompilerLedgerEvent(
        resolvedEventLocator: resolvedEventLocator,
        sourceEventIdentity: sourceEventIdentity,
        generatedReferenceId: generatedReferenceId,
        lineageId: lineageId,
        dartSymbol: dartSymbol,
        displayMetadataRef: displayMetadataRef,
        active: active ?? this.active,
      );

  Map<String, Object?> toJson() => {
        'active': active,
        'dartSymbol': dartSymbol.value,
        'displayMetadataRef': displayMetadataRef.value,
        'generatedReferenceId': generatedReferenceId.value,
        'lineageId': lineageId.value,
        'resolvedEventLocator': resolvedEventLocator,
        'sourceEventIdentity': sourceEventIdentity.value,
      };
}

/// Persistent source-locator reconciliation entry for one canonical node.
final class MeasurementCompilerLedgerNode {
  MeasurementCompilerLedgerNode({
    required this.structuralOccurrenceKey,
    required this.parentStructuralOccurrenceKey,
    required this.reconciliationFingerprint,
    required this.codeIdentityId,
    required this.canonicalNodeTokenId,
    required this.active,
    required Iterable<MeasurementCompilerLedgerEvent> events,
  }) : events = List.unmodifiable(
          events.toList()
            ..sort(
              (left, right) => left.resolvedEventLocator.compareTo(
                right.resolvedEventLocator,
              ),
            ),
        );

  factory MeasurementCompilerLedgerNode.fromJson(Object? value) {
    final json = _object(value, 'ledger node');
    _exactKeys(
      json,
      const {
        'active',
        'canonicalNodeTokenId',
        'codeIdentityId',
        'events',
        'parentStructuralOccurrenceKey',
        'reconciliationFingerprint',
        'structuralOccurrenceKey',
      },
      'ledger node',
    );
    return MeasurementCompilerLedgerNode(
      structuralOccurrenceKey: _string(
        json,
        'structuralOccurrenceKey',
        'ledger node',
      ),
      parentStructuralOccurrenceKey: _nullableString(
        json,
        'parentStructuralOccurrenceKey',
        'ledger node',
      ),
      reconciliationFingerprint: _string(
        json,
        'reconciliationFingerprint',
        'ledger node',
      ),
      codeIdentityId: CodeIdentityId(
        _string(json, 'codeIdentityId', 'ledger node'),
      ),
      canonicalNodeTokenId: NodeTokenId(
        _string(json, 'canonicalNodeTokenId', 'ledger node'),
      ),
      active: _boolean(json, 'active', 'ledger node'),
      events: [
        for (final event in _list(json, 'events', 'ledger node'))
          MeasurementCompilerLedgerEvent.fromJson(event),
      ],
    );
  }

  final String structuralOccurrenceKey;
  final String? parentStructuralOccurrenceKey;
  final String reconciliationFingerprint;
  final CodeIdentityId codeIdentityId;
  final NodeTokenId canonicalNodeTokenId;
  final bool active;
  final List<MeasurementCompilerLedgerEvent> events;

  MeasurementCompilerLedgerNode copyWith({
    String? structuralOccurrenceKey,
    String? parentStructuralOccurrenceKey,
    bool clearParent = false,
    String? reconciliationFingerprint,
    bool? active,
    Iterable<MeasurementCompilerLedgerEvent>? events,
  }) =>
      MeasurementCompilerLedgerNode(
        structuralOccurrenceKey:
            structuralOccurrenceKey ?? this.structuralOccurrenceKey,
        parentStructuralOccurrenceKey: clearParent
            ? null
            : parentStructuralOccurrenceKey ??
                this.parentStructuralOccurrenceKey,
        reconciliationFingerprint:
            reconciliationFingerprint ?? this.reconciliationFingerprint,
        codeIdentityId: codeIdentityId,
        canonicalNodeTokenId: canonicalNodeTokenId,
        active: active ?? this.active,
        events: events ?? this.events,
      );

  Map<String, Object?> toJson() => {
        'active': active,
        'canonicalNodeTokenId': canonicalNodeTokenId.value,
        'codeIdentityId': codeIdentityId.value,
        'events': [for (final event in events) event.toJson()],
        'parentStructuralOccurrenceKey': parentStructuralOccurrenceKey,
        'reconciliationFingerprint': reconciliationFingerprint,
        'structuralOccurrenceKey': structuralOccurrenceKey,
      };
}

/// Explicit reviewed relocation from a prior locator to its current locator.
final class MeasurementCompilerLedgerRelocation {
  const MeasurementCompilerLedgerRelocation({
    required this.fromStructuralOccurrenceKey,
    required this.toStructuralOccurrenceKey,
    required this.codeIdentityId,
  });

  factory MeasurementCompilerLedgerRelocation.fromJson(Object? value) {
    final json = _object(value, 'ledger relocation');
    _exactKeys(
      json,
      const {
        'codeIdentityId',
        'fromStructuralOccurrenceKey',
        'toStructuralOccurrenceKey',
      },
      'ledger relocation',
    );
    return MeasurementCompilerLedgerRelocation(
      fromStructuralOccurrenceKey: _string(
        json,
        'fromStructuralOccurrenceKey',
        'ledger relocation',
      ),
      toStructuralOccurrenceKey: _string(
        json,
        'toStructuralOccurrenceKey',
        'ledger relocation',
      ),
      codeIdentityId: CodeIdentityId(
        _string(json, 'codeIdentityId', 'ledger relocation'),
      ),
    );
  }

  final String fromStructuralOccurrenceKey;
  final String toStructuralOccurrenceKey;
  final CodeIdentityId codeIdentityId;

  Map<String, Object?> toJson() => {
        'codeIdentityId': codeIdentityId.value,
        'fromStructuralOccurrenceKey': fromStructuralOccurrenceKey,
        'toStructuralOccurrenceKey': toStructuralOccurrenceKey,
      };
}

/// Non-authoritative continuity proposal emitted for review.
final class MeasurementCompilerLedgerProposal {
  MeasurementCompilerLedgerProposal({
    required this.toStructuralOccurrenceKey,
    required Iterable<String> candidatePriorStructuralOccurrenceKeys,
  }) : candidatePriorStructuralOccurrenceKeys = List.unmodifiable(
          candidatePriorStructuralOccurrenceKeys.toList()..sort(),
        ) {
    if (toStructuralOccurrenceKey.isEmpty ||
        this.candidatePriorStructuralOccurrenceKeys.isEmpty ||
        this.candidatePriorStructuralOccurrenceKeys.toSet().length !=
            this.candidatePriorStructuralOccurrenceKeys.length) {
      throw ArgumentError(
        'A Measurement reconciliation proposal requires one target and a '
        'non-empty unique candidate set.',
      );
    }
  }

  factory MeasurementCompilerLedgerProposal.fromJson(Object? value) {
    final json = _object(value, 'ledger proposal');
    _exactKeys(
      json,
      const {
        'candidatePriorStructuralOccurrenceKeys',
        'toStructuralOccurrenceKey',
      },
      'ledger proposal',
    );
    return MeasurementCompilerLedgerProposal(
      toStructuralOccurrenceKey: _string(
        json,
        'toStructuralOccurrenceKey',
        'ledger proposal',
      ),
      candidatePriorStructuralOccurrenceKeys: [
        for (final candidate in _list(
          json,
          'candidatePriorStructuralOccurrenceKeys',
          'ledger proposal',
        ))
          _requireString(candidate, 'ledger proposal candidate'),
      ],
    );
  }

  final String toStructuralOccurrenceKey;
  final List<String> candidatePriorStructuralOccurrenceKeys;

  Map<String, Object?> toJson() => {
        'candidatePriorStructuralOccurrenceKeys':
            candidatePriorStructuralOccurrenceKeys,
        'toStructuralOccurrenceKey': toStructuralOccurrenceKey,
      };
}

/// One final target-neutral Measurement draft selected by one publication line.
final class MeasurementCompilerPublication {
  MeasurementCompilerPublication({
    required this.selector,
    required this.routePlan,
    required this.draft,
  }) {
    if (draft.routePlan.canonicalDigest != routePlan.canonicalDigest) {
      throw ArgumentError(
        'Compiler publication route plan and final draft disagree.',
      );
    }
    if (draft.surfaceId != selector.stableSurfaceId) {
      throw ArgumentError(
        'Compiler publication SurfaceId does not match its publication '
        'selector.',
      );
    }
  }

  factory MeasurementCompilerPublication.fromJson(Object? value) {
    final json = _object(value, 'compiler publication');
    _exactKeys(
      json,
      const {'draftBase64', 'routePlanBase64', 'selector'},
      'compiler publication',
    );
    final routePlan = MeasurementPublicationRoutePlanV1.fromCanonicalBytes(
      _base64(
        _string(json, 'routePlanBase64', 'compiler publication'),
        'compiler publication.routePlanBase64',
      ),
    );
    final draft = MeasurementPublicationDraftV1.fromCanonicalBytes(
      _base64(
        _string(json, 'draftBase64', 'compiler publication'),
        'compiler publication.draftBase64',
      ),
    );
    final selector = MeasurementPublicationSelectorV1.fromJson(
      json['selector'],
    );
    if (draft.routePlan.canonicalDigest != routePlan.canonicalDigest ||
        draft.surfaceId != selector.stableSurfaceId) {
      throw const FormatException(
        'Compiler publication does not match its route plan and publication '
        'selector.',
      );
    }
    return MeasurementCompilerPublication(
      selector: selector,
      routePlan: routePlan,
      draft: draft,
    );
  }

  final MeasurementPublicationSelectorV1 selector;
  final MeasurementPublicationRoutePlanV1 routePlan;
  final MeasurementPublicationDraftV1 draft;

  Map<String, Object?> toJson() => {
        'draftBase64': _encodeBase64(draft.canonicalBytes),
        'routePlanBase64': _encodeBase64(routePlan.canonicalBytes),
        'selector': selector.toJson(),
      };
}

/// Strict build-owned Measurement compiler state and publication output.
final class RestageMeasurementCompilerOutputV1 {
  RestageMeasurementCompilerOutputV1({
    required this.valid,
    required Iterable<String> errors,
    required this.policy,
    required this.nextIdentitySequence,
    required Iterable<MeasurementCompilerLedgerNode> ledgerNodes,
    required Iterable<MeasurementCompilerLedgerRelocation> acceptedRelocations,
    required Iterable<MeasurementCompilerLedgerProposal> proposals,
    required Iterable<MeasurementCompilerPublication> publications,
  })  : errors = List.unmodifiable(errors.toList()..sort()),
        ledgerNodes = List.unmodifiable(
          ledgerNodes.toList()
            ..sort(
              (left, right) => left.codeIdentityId.value.compareTo(
                right.codeIdentityId.value,
              ),
            ),
        ),
        acceptedRelocations = List.unmodifiable(
          acceptedRelocations.toList()
            ..sort(
              (left, right) => left.toStructuralOccurrenceKey.compareTo(
                right.toStructuralOccurrenceKey,
              ),
            ),
        ),
        proposals = List.unmodifiable(
          proposals.toList()
            ..sort(
              (left, right) => left.toStructuralOccurrenceKey.compareTo(
                right.toStructuralOccurrenceKey,
              ),
            ),
        ),
        publications = List.unmodifiable(
          publications.toList()
            ..sort(
              (left, right) => left.selector.key.compareTo(right.selector.key),
            ),
        ) {
    if (nextIdentitySequence <= 0) {
      throw ArgumentError.value(nextIdentitySequence, 'nextIdentitySequence');
    }
    if (valid != this.errors.isEmpty) {
      throw ArgumentError('Measurement compiler validity must match errors.');
    }
    if (valid && this.proposals.isNotEmpty) {
      throw ArgumentError(
        'A valid Measurement compiler output cannot contain proposals.',
      );
    }
    if (!valid && this.publications.isNotEmpty) {
      throw ArgumentError(
        'An invalid Measurement compiler output cannot contain publications.',
      );
    }
    final structuralKeys = <String>{};
    final codeIdentityIds = <String>{};
    final nodeTokenIds = <String>{};
    final generatedReferenceIds = <String>{};
    final lineageIds = <String>{};
    final dartSymbols = <String>{};
    for (final node in this.ledgerNodes) {
      if (!structuralKeys.add(node.structuralOccurrenceKey) ||
          !codeIdentityIds.add(node.codeIdentityId.value) ||
          !nodeTokenIds.add(node.canonicalNodeTokenId.value)) {
        throw ArgumentError(
          'Measurement ledger locators and canonical identities must be '
          'one-to-one.',
        );
      }
      final eventLocators = <String>{};
      for (final event in node.events) {
        if (!eventLocators.add(event.resolvedEventLocator) ||
            !generatedReferenceIds.add(event.generatedReferenceId.value) ||
            !lineageIds.add(event.lineageId.value) ||
            !dartSymbols.add(event.dartSymbol.value)) {
          throw ArgumentError(
            'Measurement ledger event locators and canonical identities must '
            'be one-to-one.',
          );
        }
      }
    }
    final publicationKeys = <String>{};
    for (final publication in this.publications) {
      if (!publicationKeys.add(publication.selector.key)) {
        throw ArgumentError(
            'Measurement publication selectors must be unique.');
      }
    }
    final relocationSources = <String>{};
    final relocationTargets = <String>{};
    final relocationCodes = <String>{};
    for (final relocation in this.acceptedRelocations) {
      if (!relocationSources.add(relocation.fromStructuralOccurrenceKey) ||
          !relocationTargets.add(relocation.toStructuralOccurrenceKey) ||
          !relocationCodes.add(relocation.codeIdentityId.value)) {
        throw ArgumentError(
          'Measurement relocation sources, targets, and code identities must '
          'be one-to-one.',
        );
      }
    }
  }

  factory RestageMeasurementCompilerOutputV1.empty() =>
      RestageMeasurementCompilerOutputV1(
        valid: true,
        errors: const [],
        policy: null,
        nextIdentitySequence: 1,
        ledgerNodes: const [],
        acceptedRelocations: const [],
        proposals: const [],
        publications: const [],
      );

  factory RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
    List<int> bytes,
  ) {
    final canonical = CanonicalJsonCodec.decode(bytes);
    if (canonical is! Map<String, Object?>) {
      throw const FormatException(
        'Measurement compiler output must be a canonical object.',
      );
    }
    final json = canonical;
    _exactKeys(
      json,
      const {
        'acceptedRelocations',
        'errors',
        'kind',
        'ledgerNodes',
        'nextIdentitySequence',
        'policy',
        'proposals',
        'publications',
        'schemaVersion',
        'valid',
      },
      'measurement compiler output',
    );
    if (_string(json, 'kind', 'measurement compiler output') !=
            'restageMeasurementCompilerOutput' ||
        _integer(json, 'schemaVersion', 'measurement compiler output') != 1) {
      throw const FormatException(
        'Unsupported Measurement compiler output contract.',
      );
    }
    final output = RestageMeasurementCompilerOutputV1(
      valid: _boolean(json, 'valid', 'measurement compiler output'),
      errors: [
        for (final error in _list(
          json,
          'errors',
          'measurement compiler output',
        ))
          _requireString(error, 'measurement compiler error'),
      ],
      policy: json['policy'] == null
          ? null
          : MeasurementCompilerPolicyInput.fromJson(json['policy']),
      nextIdentitySequence: _integer(
        json,
        'nextIdentitySequence',
        'measurement compiler output',
      ),
      ledgerNodes: [
        for (final node in _list(
          json,
          'ledgerNodes',
          'measurement compiler output',
        ))
          MeasurementCompilerLedgerNode.fromJson(node),
      ],
      acceptedRelocations: [
        for (final relocation in _list(
          json,
          'acceptedRelocations',
          'measurement compiler output',
        ))
          MeasurementCompilerLedgerRelocation.fromJson(relocation),
      ],
      proposals: [
        for (final proposal in _list(
          json,
          'proposals',
          'measurement compiler output',
        ))
          MeasurementCompilerLedgerProposal.fromJson(proposal),
      ],
      publications: [
        for (final publication in _list(
          json,
          'publications',
          'measurement compiler output',
        ))
          MeasurementCompilerPublication.fromJson(publication),
      ],
    );
    if (!_bytesEqual(output.canonicalBytes, bytes)) {
      throw const FormatException(
        'Measurement compiler output is not byte-canonical.',
      );
    }
    return output;
  }

  final bool valid;
  final List<String> errors;
  final MeasurementCompilerPolicyInput? policy;
  final int nextIdentitySequence;
  final List<MeasurementCompilerLedgerNode> ledgerNodes;
  final List<MeasurementCompilerLedgerRelocation> acceptedRelocations;
  final List<MeasurementCompilerLedgerProposal> proposals;
  final List<MeasurementCompilerPublication> publications;

  Map<String, Object?> toJson() => {
        'acceptedRelocations': [
          for (final relocation in acceptedRelocations) relocation.toJson(),
        ],
        'errors': errors,
        'kind': 'restageMeasurementCompilerOutput',
        'ledgerNodes': [for (final node in ledgerNodes) node.toJson()],
        'nextIdentitySequence': nextIdentitySequence,
        'policy': policy?.toJson(),
        'proposals': [for (final proposal in proposals) proposal.toJson()],
        'publications': [
          for (final publication in publications) publication.toJson(),
        ],
        'schemaVersion': 1,
        'valid': valid,
      };

  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  String encodeCanonicalJson() => utf8.decode(canonicalBytes);

  /// Emits the separate strict draft-only index consumed by tooling.
  Uint8List outputIndexBytes(String packageName) => CanonicalJsonCodec.encode({
        'entries': [
          for (final publication in publications)
            {
              'draftBase64': _encodeBase64(publication.draft.canonicalBytes),
              'draftDigest': publication.draft.canonicalDigest.hex,
              'routePlanDigest':
                  publication.routePlan.routeDraftClosureDigest.hex,
              'selector': publication.selector.toJson(),
              'surfaceId': publication.draft.surfaceId.value,
            },
        ],
        'kind': 'restageMeasurementPublicationIndex',
        'package': packageName,
        'schemaVersion': 1,
      });
}

String _encodeBase64(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

Uint8List _base64(String value, String path) {
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (_encodeBase64(bytes) != value) {
      throw FormatException('$path must use canonical unpadded base64url.');
    }
    return Uint8List.fromList(bytes);
  } on FormatException {
    rethrow;
  } on Object {
    throw FormatException('$path must use canonical unpadded base64url.');
  }
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) throw FormatException('$path must be an object.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _exactKeys(Map<String, Object?> json, Set<String> keys, String path) {
  final actual = json.keys.toSet();
  if (actual.length != keys.length || !actual.containsAll(keys)) {
    throw FormatException('$path has unsupported or missing fields.');
  }
}

String _string(Map<String, Object?> json, String key, String path) =>
    _requireString(json[key], '$path.$key');

String? _nullableString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  return value == null ? null : _requireString(value, '$path.$key');
}

String _requireString(Object? value, String path) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$path must be a non-empty string.');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('$path.$key must be a positive integer.');
  }
  return value;
}

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean.');
  return value;
}

List<Object?> _list(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List) throw FormatException('$path.$key must be a list.');
  return List<Object?>.of(value);
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
