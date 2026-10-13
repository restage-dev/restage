import 'dart:async';

import 'authoring_refusal_diagnostic.dart';

final Object _refusalZoneKey = Object();

({T? dispatcher, AuthoringRefusalKind? refusal, String? detail})
    captureAuthoringDispatcherAccess<T extends Object>(T? Function() capture) {
  AuthoringRefusalKind? refusal;
  String? detail;
  final dispatcher = runZoned<T?>(
    capture,
    zoneValues: <Object, Object?>{
      _refusalZoneKey: (AuthoringRefusalKind value, String? why) {
        if (refusal != null) return;
        refusal = value;
        detail = why;
      },
    },
  );
  return (dispatcher: dispatcher, refusal: refusal, detail: detail);
}

void recordAuthoringDispatcherRefusal(
  AuthoringRefusalKind refusal, {
  String? detail,
}) {
  final record = Zone.current[_refusalZoneKey];
  if (record is void Function(AuthoringRefusalKind, String?)) {
    record(refusal, detail);
  }
}
