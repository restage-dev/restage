/// Deepest nesting a message may carry, matching the browser transports.
const int renderWireMaxDepth = 64;

/// Most values a message may carry, matching the browser transports.
const int renderWireMaxNodes = 100000;

/// Snapshots one outbound message and enforces the transport's JSON budget.
///
/// Throws when the message nests deeper than [renderWireMaxDepth], carries more
/// than [renderWireMaxNodes] values, or holds a value no transport can encode.
/// A sender that carries values it does not control checks here first, so the
/// transport never throws from inside the code that produced them.
Map<String, Object?> boundedWireMessage(Map<String, Object?> payload) {
  var nodes = 0;

  Object? bound(Object? value, int depth) {
    nodes += 1;
    if (depth > renderWireMaxDepth || nodes > renderWireMaxNodes) {
      throw const FormatException('Message exceeds the wire budget.');
    }
    if (value == null || value is bool || value is String) return value;
    if (value is num) {
      if (!value.isFinite) {
        throw const FormatException('Message numbers must be finite.');
      }
      return value;
    }
    if (value is List<Object?>) {
      return List<Object?>.unmodifiable(
        value.map((child) => bound(child, depth + 1)),
      );
    }
    if (value is Map<Object?, Object?>) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('Message object keys must be strings.');
        }
        result[key] = bound(entry.value, depth + 1);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    throw const FormatException('Message must contain only JSON values.');
  }

  return bound(payload, 0)! as Map<String, Object?>;
}

Map<String, Object?> snapshotWireMap(
  Map<String, Object?> source, {
  required String argumentName,
}) {
  rejectCredentialFields(source, argumentName: argumentName);
  return snapshotWireObject(source, argumentName: argumentName);
}

/// Snapshots one map of wire values without the credential-name gate.
Map<String, Object?> snapshotWireObject(
  Map<String, Object?> source, {
  required String argumentName,
}) {
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
