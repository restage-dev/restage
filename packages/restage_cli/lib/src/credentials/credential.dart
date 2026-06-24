import 'package:meta/meta.dart';

/// Credential discriminator used by the on-disk format.
///
/// Currently only [authKey] is emitted; the field exists so additional
/// credential kinds (such as a future user-bound API key) can be added
/// without breaking pre-existing files.
@experimental
class CredentialKind {
  CredentialKind._();

  /// `<keyId>:<key>` pair returned by the auth-server's sign-in flow.
  /// Sent on the wire as `Authorization: basic <base64(authToken)>`.
  static const authKey = 'authKey';
}

/// One stored credential, persisted as JSON in the user's config
/// directory.
///
/// The on-disk shape is intentionally schemaless beyond what is named
/// here: readers tolerate unknown fields (forward-compat) and absent
/// [kind] (defaults to [CredentialKind.authKey]).
@experimental
@immutable
class Credential {
  /// Construct a credential with the given fields.
  const Credential({
    required this.endpoint,
    required this.kind,
    required this.authToken,
  });

  /// Backend origin the credential authenticates against.
  final String endpoint;

  /// Credential discriminator — see [CredentialKind]. The auth-header
  /// builder switches on this value when constructing the
  /// `Authorization` header for outbound requests.
  final String kind;

  /// Bearer payload. For [CredentialKind.authKey] this is the
  /// `<keyId>:<key>` pair from `AuthenticationResponse`.
  final String authToken;

  /// Encode as a JSON-shaped map for persistence.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'endpoint': endpoint,
    'kind': kind,
    'authToken': authToken,
  };

  /// Decode from a JSON-shaped map. Falls back to
  /// [CredentialKind.authKey] when `kind` is missing — the on-disk
  /// format is forward-compatible.
  factory Credential.fromJson(Map<String, dynamic> json) => Credential(
    endpoint: json['endpoint']! as String,
    kind: (json['kind'] as String?) ?? CredentialKind.authKey,
    authToken: json['authToken']! as String,
  );

  @override
  bool operator ==(Object other) =>
      other is Credential &&
      other.endpoint == endpoint &&
      other.kind == kind &&
      other.authToken == authToken;

  @override
  int get hashCode => Object.hash(endpoint, kind, authToken);
}
