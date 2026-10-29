import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Android refuses sockets to an app without the INTERNET permission: EPERM
// since Android 10, EACCES before it.
const _forbidden = {1, 13};

bool _checked = false;

/// Whether the platform enforces a network permission on sockets.
@visibleForTesting
bool Function() debugSocketsNeedPermission = () => Platform.isAndroid;

/// Opens and closes a loopback socket, which needs no network.
@visibleForTesting
Future<void> Function() debugOpenLocalSocket = () async =>
    (await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0)).close();

/// Lets a test check again.
@visibleForTesting
void debugResetNetworkAccessCheck() => _checked = false;

void noteRequestFailedBeforeResponse() {
  if (_checked || !debugSocketsNeedPermission()) return;
  _checked = true;
  unawaited(_check());
}

// Offline and forbidden fail the same host lookup; only a local socket
// separates them.
Future<void> _check() async {
  try {
    await debugOpenLocalSocket();
  } on Object catch (error) {
    if (error is! SocketException ||
        !_forbidden.contains(error.osError?.errorCode)) {
      return;
    }
    debugPrint(
      "[restage] This app can't open network connections. Android release "
      'builds need the INTERNET permission in '
      'android/app/src/main/AndroidManifest.xml.',
    );
  }
}
