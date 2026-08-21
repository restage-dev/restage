import 'dart:convert';

import 'package:restage_measurement_schema/src/canonical.dart';

/// Shared behavior for integer identities issued by the hosted control plane.
abstract base class PositivePortableIntegerIdentifier {
  /// Creates a positive ID that remains exact in every supported Dart runtime.
  PositivePortableIntegerIdentifier(this.value) {
    if (value <= 0 || value > kMaximumPortableJsonInteger) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected a positive portable JSON integer',
      );
    }
  }

  /// The exact integer identity issued by the hosted control plane.
  final int value;

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is PositivePortableIntegerIdentifier &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$value';
}

/// An organization's integer identity, issued by the hosted control plane.
final class OrganizationId extends PositivePortableIntegerIdentifier {
  /// Creates an organization identity.
  OrganizationId(super.value);
}

/// An application's integer identity, issued by the hosted control plane.
final class ApplicationId extends PositivePortableIntegerIdentifier {
  /// Creates an application identity.
  ApplicationId(super.value);
}

/// Exact resolved environment-target authority from `EnvironmentTargetRef`.
final class EnvironmentTargetId extends PositivePortableIntegerIdentifier {
  /// Creates an exact environment-target identity.
  EnvironmentTargetId(super.value);
}

/// Exact resolved named-environment authority from `EnvironmentTargetRef`.
final class NamedEnvironmentId extends PositivePortableIntegerIdentifier {
  /// Creates an exact named-environment identity.
  NamedEnvironmentId(super.value);
}

/// Shared behavior for category-safe measurement identifiers.
abstract base class MeasurementIdentifier {
  /// Creates a validated lowercase identifier.
  MeasurementIdentifier(this.value) {
    if (!_identifierPattern.hasMatch(value) || value.length > 128) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected 1..128 lowercase identifier characters',
      );
    }
  }

  static final RegExp _identifierPattern = RegExp(
    r'^[a-z0-9][a-z0-9._:-]*$',
  );

  /// Stable wire value.
  final String value;

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is MeasurementIdentifier &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class SurfaceId extends MeasurementIdentifier {
  SurfaceId(super.value);
}

final class SurfaceRevisionId extends MeasurementIdentifier {
  SurfaceRevisionId(super.value);
}

final class ArtifactId extends MeasurementIdentifier {
  ArtifactId(super.value);
}

/// Registered delivery-surface adapter identity.
///
/// Registration and adapter behavior are outside this schema package.
final class DeliverySurfaceTypeId extends MeasurementIdentifier {
  /// Creates a bounded lowercase registered-adapter identity.
  DeliverySurfaceTypeId(super.value);
}

/// Registered published-artifact kind identity.
///
/// Registration and artifact behavior are outside this schema package.
final class ArtifactKindId extends MeasurementIdentifier {
  /// Creates a bounded lowercase registered-artifact identity.
  ArtifactKindId(super.value);
}

final class ArtifactOccurrenceEdgeToken extends MeasurementIdentifier {
  ArtifactOccurrenceEdgeToken(super.value);
}

final class NodeTokenId extends MeasurementIdentifier {
  NodeTokenId(super.value);
}

final class CodeIdentityId extends MeasurementIdentifier {
  CodeIdentityId(super.value);
}

final class PointLineageId extends MeasurementIdentifier {
  PointLineageId(super.value);
}

final class LineageTransitionId extends MeasurementIdentifier {
  LineageTransitionId(super.value);
}

final class MeasurementManifestId extends MeasurementIdentifier {
  MeasurementManifestId(super.value);
}

/// Registered external publication-authority adapter identity.
///
/// The authority's vocabulary and persistence are deliberately outside the
/// Measurement schema package.
final class MeasurementPublicationAuthorityId extends MeasurementIdentifier {
  MeasurementPublicationAuthorityId(super.value);
}

final class GeneratedReferenceId extends MeasurementIdentifier {
  GeneratedReferenceId(super.value);
}

final class AuthorityRevisionId extends MeasurementIdentifier {
  AuthorityRevisionId(super.value);
}

/// Immutable processing-purpose policy revision.
final class PurposePolicyRevisionId extends MeasurementIdentifier {
  PurposePolicyRevisionId(super.value);
}

final class SubjectPolicyId extends MeasurementIdentifier {
  SubjectPolicyId(super.value);
}

final class SubjectPolicyRevisionId extends MeasurementIdentifier {
  SubjectPolicyRevisionId(super.value);
}

final class DisplayMetadataRef extends MeasurementIdentifier {
  DisplayMetadataRef(super.value);
}

/// Open analytics surface key preserved exactly across canonical wire codecs.
///
/// Values are not normalized or restricted to a known-value registry.
final class AnalyticsSurfaceKey {
  /// Creates a non-empty, well-formed key of at most 128 UTF-8 bytes.
  AnalyticsSurfaceKey(this.value) {
    try {
      CanonicalJsonCodec.encode(value);
    } on CanonicalFormatException {
      throw ArgumentError.value(
        value,
        'value',
        'Expected well-formed Unicode',
      );
    }
    if (value.isEmpty || utf8.encode(value).length > 128) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected 1..128 UTF-8 bytes',
      );
    }
  }

  /// Exact unknown-preserving wire value.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsSurfaceKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// One generated public Dart symbol that references a measurement point.
final class GeneratedDartSymbol {
  /// Creates a bounded generated symbol identity.
  GeneratedDartSymbol(this.value) {
    if (!_isPublicDartMemberIdentifier(value) || value.length > 128) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected a public generated Dart symbol',
      );
    }
  }

  /// Exact generated source spelling.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is GeneratedDartSymbol && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Exact Dart callback property identity; never an alias or normalized kind.
final class SourceEventIdentity {
  /// Creates the public Dart member identity admitted by catalog compilation.
  SourceEventIdentity(this.value) {
    if (!_isPublicDartMemberIdentifier(value) || value.length > 128) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected a public Dart member identifier',
      );
    }
  }

  /// Exact source property name.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is SourceEventIdentity && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

// Mirrors the existing public member-selector boundary used by catalog
// compilation. `$` is a legal Dart identifier character; a leading `_` is
// deliberately absent because it would name a library-private member.
bool _isPublicDartMemberIdentifier(String value) =>
    _publicDartMemberPattern.hasMatch(value) &&
    !_dartHardKeywords.contains(value);

final RegExp _publicDartMemberPattern = RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$');

const Set<String> _dartHardKeywords = {
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'rethrow',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
};
