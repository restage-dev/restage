Map<String, Object?> snapshotWireMap(
  Map<String, Object?> source, {
  required String argumentName,
}) {
  rejectCredentialFields(source, argumentName: argumentName);
  return Map<String, Object?>.unmodifiable(
    source.map(
      (key, value) => MapEntry<String, Object?>(
        key,
        snapshotWireValue(value, argumentName: argumentName),
      ),
    ),
  );
}

Object? snapshotWireValue(
  Object? value, {
  required String argumentName,
}) {
  if (value is Map<Object?, Object?>) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(
          key,
          argumentName,
          'object keys must be strings',
        );
      }
      result[key] = snapshotWireValue(
        entry.value,
        argumentName: argumentName,
      );
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(
      value.map(
        (child) => snapshotWireValue(
          child,
          argumentName: argumentName,
        ),
      ),
    );
  }
  if (value == null || value is bool || value is String) {
    return value;
  }
  if (value is num && value.isFinite) return value;
  throw ArgumentError.value(
    value,
    argumentName,
    'must contain only finite JSON values',
  );
}

const Set<String> _credentialKeys = <String>{
  'auth',
  'csrftoken',
  'privatekey',
  'dashboardstate',
  'apikey',
  'sessionkey',
  'jwt',
  'bearer',
  'token',
  'accesstoken',
  'refreshtoken',
  'authorization',
  'authorizationheader',
  'authheader',
  'authtoken',
  'idtoken',
  'apitoken',
  'sessiontoken',
  'bearertoken',
  'cookie',
  'cookies',
  'sessioncookie',
  'authcookie',
  'credential',
  'credentials',
  'authcredential',
  'authcredentials',
  'usercredential',
  'password',
  'currentpassword',
  'newpassword',
  'secret',
  'clientsecret',
  'apisecret',
  'signingsecret',
};

void rejectCredentialFields(
  Object? value, {
  required String argumentName,
}) {
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        rejectCredentialFieldName(key, argumentName: argumentName);
      }
      rejectCredentialFields(entry.value, argumentName: argumentName);
    }
  } else if (value is List<Object?>) {
    for (final child in value) {
      rejectCredentialFields(child, argumentName: argumentName);
    }
  }
}

/// Rejects one name using the render seam's normalized credential vocabulary.
///
/// Exact normalized matches are denied; ordinary words that merely contain
/// one of those names, such as `tokenization`, remain valid.
void rejectCredentialFieldName(
  String name, {
  required String argumentName,
}) {
  final normalized = name.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (_credentialKeys.contains(normalized)) {
    throw ArgumentError.value(
      name,
      argumentName,
      'credential-shaped fields are not allowed',
    );
  }
}
