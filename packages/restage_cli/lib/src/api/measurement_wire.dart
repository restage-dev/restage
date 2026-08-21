/// The exact wire surface this tool needs from the canonical mutation and
/// activation routes.
///
/// Those routes speak a vocabulary this package does not depend on. What the
/// tool needs from it is small and stable — a byte ceiling, the target a
/// request addresses, and the outcome a response reports — so it is declared
/// here and adapted at the boundary, in the same way this package declares its
/// own runtime-plane enum rather than borrowing one.
///
/// This tool therefore proves three things about bytes before forwarding them:
/// that they are within the ceiling, that they are the canonical byte
/// representation rather than an equivalent spelling, and that they address the
/// route they were sent to. The authority validates everything else, and says
/// so in a result this tool reads for its outcome and hands back verbatim.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

/// Maximum canonical bytes admitted on one programmatic mutation request or
/// response.
const int kMaximumProgrammaticMutationWireBytes = 72 * 1024 * 1024;

/// Maximum canonical bytes admitted on one activation command or result.
const int kMaximumExperimentActivationWireBytes = 16 * 1024 * 1024;

/// Every request kind the canonical mutation route accepts.
const Set<String> kProgrammaticMutationRequestKinds = {
  'programmaticOpenOrImportDraftRequest',
  'programmaticPublishDraftRequest',
  'programmaticReadDraftRequest',
  'programmaticReplaceDraftRequest',
  'programmaticResolveSealedRevisionRequest',
  'programmaticSealDraftRequest',
  'programmaticTransferDraftOwnershipRequest',
  'programmaticValidateDraftRequest',
};

/// Every response kind the route returns, and the result kind each reports.
///
/// The mapping is the tool's own declaration of the outcome vocabulary it
/// surfaces to callers. It is exhaustive over the route's response kinds:
/// every kind the route can return appears here exactly once.
const Map<String, String> kProgrammaticMutationResponseResultKinds = {
  'programmaticAuditFailureResponse': 'auditFailure',
  'programmaticDraftImportedResponse': 'draftImported',
  'programmaticDraftNotFoundResponse': 'draftNotFound',
  'programmaticDraftOwnershipTransferredResponse': 'draftOwnershipTransferred',
  'programmaticDraftReadResponse': 'draftRead',
  'programmaticDraftReplacedResponse': 'draftReplaced',
  'programmaticDraftSealedResponse': 'draftSealed',
  'programmaticDraftValidatedResponse': 'draftValidated',
  'programmaticOwnershipConflictResponse': 'ownershipConflict',
  'programmaticPublicationAuthorizationRequiredResponse':
      'publicationAuthorizationRequired',
  'programmaticPublicationCommittedResponse': 'publicationCommitted',
  'programmaticReferenceConflictResponse': 'referenceConflict',
  'programmaticRejectedResponse': 'rejected',
  'programmaticSealedRevisionNotFoundResponse': 'sealedRevisionNotFound',
  'programmaticSealedRevisionResolvedResponse': 'sealedRevisionResolved',
  'programmaticStaleDraftConflictResponse': 'staleDraftConflict',
  'programmaticValidationBlockedResponse': 'validationBlocked',
};

/// The accepted activation outcome.
const String kExperimentActivationAcceptedKind = 'accepted';

/// The rejected activation outcome.
const String kExperimentActivationRejectedKind = 'rejected';

/// One canonical programmatic mutation request, read for the fields this tool
/// sends on.
@experimental
@immutable
final class ProgrammaticMutationRequestWireV1 {
  const ProgrammaticMutationRequestWireV1._({
    required this.canonicalBytes,
    required this.kind,
    required this.target,
  });

  /// Reads one bounded, byte-exact canonical request.
  ///
  /// Throws [measurement.CanonicalFormatException] when the bytes are outside
  /// the ceiling, are not the canonical representation, or do not carry a
  /// request kind with a decodable target.
  factory ProgrammaticMutationRequestWireV1.fromCanonicalBytes(
    List<int> bytes,
  ) {
    _requireWireBytes(
      bytes,
      limit: kMaximumProgrammaticMutationWireBytes,
      label: 'programmatic mutation request',
    );
    final json = measurement.decodeCanonicalObject(bytes);
    final kind = _requireString(json['kind'], 'programmaticRequest.kind');
    if (!kProgrammaticMutationRequestKinds.contains(kind)) {
      throw measurement.CanonicalFormatException(
        'Unknown programmatic mutation-request kind "$kind"',
      );
    }
    final coordinate = _requireObject(
      json['coordinate'],
      'programmaticRequest.coordinate',
    );
    return ProgrammaticMutationRequestWireV1._(
      canonicalBytes: Uint8List.fromList(bytes),
      kind: kind,
      target: measurement.TargetCoordinate.fromJson(
        _requireObject(
          coordinate['target'],
          'programmaticRequest.coordinate.target',
        ),
      ),
    );
  }

  /// The exact bytes read, forwarded unchanged.
  final Uint8List canonicalBytes;

  /// Closed canonical wire spelling of the request kind.
  final String kind;

  /// The control-plane target this request addresses.
  final measurement.TargetCoordinate target;
}

/// One canonical programmatic mutation response, read for the outcome this
/// tool reports.
@experimental
@immutable
final class ProgrammaticMutationResponseWireV1 {
  const ProgrammaticMutationResponseWireV1._({
    required this.canonicalBytes,
    required this.kind,
    required this.resultKind,
  });

  /// Reads one bounded, byte-exact canonical response.
  factory ProgrammaticMutationResponseWireV1.fromCanonicalBytes(
    List<int> bytes,
  ) {
    _requireWireBytes(
      bytes,
      limit: kMaximumProgrammaticMutationWireBytes,
      label: 'programmatic mutation response',
    );
    final json = measurement.decodeCanonicalObject(bytes);
    final kind = _requireString(json['kind'], 'programmaticResponse.kind');
    final resultKind = kProgrammaticMutationResponseResultKinds[kind];
    if (resultKind == null) {
      throw measurement.CanonicalFormatException(
        'Unknown programmatic mutation-response kind "$kind"',
      );
    }
    return ProgrammaticMutationResponseWireV1._(
      canonicalBytes: Uint8List.fromList(bytes),
      kind: kind,
      resultKind: resultKind,
    );
  }

  /// The exact bytes read, returned unchanged.
  final Uint8List canonicalBytes;

  /// Closed canonical wire spelling of the response kind.
  final String kind;

  /// Closed canonical wire spelling of the result the response reports.
  final String resultKind;
}

/// One canonical experiment activation command, read for the fields this tool
/// sends on.
@experimental
@immutable
final class ExperimentActivationCommandWireV1 {
  const ExperimentActivationCommandWireV1._({
    required this.canonicalBytes,
    required this.target,
  });

  /// Reads one bounded, byte-exact canonical command.
  factory ExperimentActivationCommandWireV1.fromCanonicalBytes(
    List<int> bytes,
  ) {
    _requireWireBytes(
      bytes,
      limit: kMaximumExperimentActivationWireBytes,
      label: 'experiment activation command',
    );
    final json = measurement.decodeCanonicalObject(bytes);
    return ExperimentActivationCommandWireV1._(
      canonicalBytes: Uint8List.fromList(bytes),
      target: measurement.TargetCoordinate.fromJson(
        _requireObject(json['target'], 'experimentActivationCommand.target'),
      ),
    );
  }

  /// The exact bytes read, forwarded unchanged.
  final Uint8List canonicalBytes;

  /// The control-plane target this command addresses.
  final measurement.TargetCoordinate target;
}

/// One canonical experiment activation result, read for the outcome this tool
/// reports.
@experimental
@immutable
final class ExperimentActivationResultWireV1 {
  const ExperimentActivationResultWireV1._({
    required this.canonicalBytes,
    required this.outcome,
  });

  /// Reads one bounded, byte-exact canonical result.
  factory ExperimentActivationResultWireV1.fromCanonicalBytes(List<int> bytes) {
    _requireWireBytes(
      bytes,
      limit: kMaximumExperimentActivationWireBytes,
      label: 'experiment activation result',
    );
    final json = measurement.decodeCanonicalObject(bytes);
    final outcome = _requireString(
      json['kind'],
      'experimentActivationResult.kind',
    );
    if (outcome != kExperimentActivationAcceptedKind &&
        outcome != kExperimentActivationRejectedKind) {
      throw measurement.CanonicalFormatException(
        'Unknown experiment activation result "$outcome"',
      );
    }
    return ExperimentActivationResultWireV1._(
      canonicalBytes: Uint8List.fromList(bytes),
      outcome: outcome,
    );
  }

  /// The exact bytes read, returned unchanged.
  final Uint8List canonicalBytes;

  /// Either [kExperimentActivationAcceptedKind] or
  /// [kExperimentActivationRejectedKind].
  final String outcome;

  /// Whether the authority accepted the command.
  bool get isAccepted => outcome == kExperimentActivationAcceptedKind;
}

Map<String, Object?> _requireObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw measurement.CanonicalFormatException('$path must be an object');
  }
  return value;
}

String _requireString(Object? value, String path) {
  if (value is! String) {
    throw measurement.CanonicalFormatException('$path must be a string');
  }
  return value;
}

void _requireWireBytes(
  List<int> bytes, {
  required int limit,
  required String label,
}) {
  final length = bytes.length;
  if (length < 1 || length > limit) {
    throw measurement.CanonicalFormatException(
      '$label must contain 1..$limit bytes',
    );
  }
}
