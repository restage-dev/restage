import 'dart:convert';

const _reasonKey = 'reason';
const _errorKey = 'error';

/// The bounded reason in an upload refusal body, else its error code.
String? measurementRefusalReason(List<int> body) {
  try {
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map<String, dynamic>) return null;
    return _bounded(decoded[_reasonKey]) ?? _bounded(decoded[_errorKey]);
  } on Object {
    return null;
  }
}

String? _bounded(Object? value) => value is String &&
        value.isNotEmpty &&
        value.length <= 64 &&
        RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value)
    ? value
    : null;

/// The one debug line for a refused upload.
String measurementRefusalLogLine(int status, String? reason) =>
    '[restage] measurement upload refused (HTTP $status): '
    '${reason ?? 'no reason given'}';
