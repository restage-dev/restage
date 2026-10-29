import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/bounded_http_client.dart';
import 'package:restage/src/restage_rpc_client/network_access_check_io.dart';

const _line =
    "[restage] This app can't open network connections. Android release "
    'builds need the INTERNET permission in '
    'android/app/src/main/AndroidManifest.xml.';

void main() {
  late List<String?> printed;
  late int probes;
  final original = debugPrint;

  setUp(() {
    printed = [];
    probes = 0;
    debugPrint = (message, {wrapWidth}) => printed.add(message);
    debugResetNetworkAccessCheck();
    debugSocketsNeedPermission = () => true;
  });

  tearDown(() => debugPrint = original);

  Future<void> fail(BoundedHttpClient client) async {
    await expectLater(
      client.get(Uri.parse('https://a.example/x')),
      throwsA(anything),
    );
    await pumpEventQueue();
  }

  final lookupFailed = BoundedHttpClient(
    MockClient((_) async => throw const SocketException(
          "Failed host lookup: 'a.example'",
          osError: OSError('No address associated with hostname', 7),
        )),
  );

  for (final (name, socket, expected) in <(String, Object?, List<String>)>[
    (
      'a socket refused since Android 10 says so once',
      const SocketException('', osError: OSError('Operation not permitted', 1)),
      [_line],
    ),
    (
      'a socket refused before Android 10 says so once',
      const SocketException('', osError: OSError('Permission denied', 13)),
      [_line],
    ),
    ('an open socket says nothing', null, []),
    ('a probe that fails some other way says nothing', StateError('x'), []),
    (
      'another socket failure says nothing',
      const SocketException('',
          osError: OSError('Network is unreachable', 101)),
      [],
    ),
  ]) {
    test(name, () async {
      debugOpenLocalSocket = () async {
        probes += 1;
        if (socket != null) throw socket;
      };
      await fail(lookupFailed);
      await fail(lookupFailed);
      expect(printed.where((line) => line == _line), expected);
      expect(probes, 1);
    });
  }

  test('a platform without the permission does not check', () async {
    debugSocketsNeedPermission = () => false;
    debugOpenLocalSocket = () async => probes += 1;
    await fail(lookupFailed);
    expect(probes, 0);
  });

  test('a request that times out does not check', () async {
    debugOpenLocalSocket = () async => probes += 1;
    await fail(BoundedHttpClient(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    ));
    expect(probes, 0);
  });
}
