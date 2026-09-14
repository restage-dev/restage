import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Removes the client's revision report from a captured request body and
/// asserts it was present and decodable, so the caller can compare the rest.
Map<String, dynamic> withoutSupportedPolicyRevisions(
  Object? body,
) {
  expect(body, isA<Map<String, dynamic>>(),
      reason: 'a captured request body is a JSON object');
  final map = (body! as Map).cast<String, dynamic>();
  final carrier = map['sdkSupportedPolicyRevisions'];
  expect(carrier, isA<String>(),
      reason: 'every active request reports its revision support');
  final bytes = base64Url.decode(base64Url.normalize(carrier as String));
  expect(base64UrlEncode(bytes).replaceAll('=', ''), carrier);
  final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  expect(document['kind'], 'sdkSupportedPolicyRevisions');
  expect(document['assignmentApiLevel'], 3);
  final rest = Map<String, dynamic>.of(map)
    ..remove('sdkSupportedPolicyRevisions');
  return rest;
}
