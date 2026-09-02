import 'dart:async';

import 'authoring_refusal_diagnostic.dart';

final Object _refusalZoneKey = Object();

({T? dispatcher, AuthoringRefusalKind? refusal})
    captureAuthoringDispatcherAccess<T extends Object>(T? Function() capture) {
  AuthoringRefusalKind? refusal;
  final dispatcher = runZoned<T?>(
    capture,
    zoneValues: <Object, Object?>{
      _refusalZoneKey: (AuthoringRefusalKind value) => refusal ??= value,
    },
  );
  return (dispatcher: dispatcher, refusal: refusal);
}

void recordAuthoringDispatcherRefusal(AuthoringRefusalKind refusal) {
  final record = Zone.current[_refusalZoneKey];
  if (record is void Function(AuthoringRefusalKind)) record(refusal);
}
