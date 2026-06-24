import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/auth_api.dart';
import 'package:restage_cli/src/api/auth_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:test/test.dart';

void main() {
  group('AuthApi', () {
    test('startDeviceAuthorization decodes the wire payload into a typed '
        'DeviceAuthorizationStart', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(<String, dynamic>{
            '__className__': 'DeviceAuthorizationStart',
            'deviceCode': 'dc-abc',
            'userCode': 'ABCD-EFGH',
            'verificationUri': 'https://dash.example.com/device',
            'expiresInSeconds': 600,
            'pollIntervalSeconds': 5,
          }),
          200,
        ),
      );
      final api = AuthApi(
        RestageApi(
          endpoint: Uri.parse('https://api.example.com/'),
          httpClient: client,
        ),
      );
      final result = await api.startDeviceAuthorization();
      expect(result.deviceCode, 'dc-abc');
      expect(result.userCode, 'ABCD-EFGH');
      expect(result.verificationUri, 'https://dash.example.com/device');
      expect(result.expiresInSeconds, 600);
      expect(result.pollIntervalSeconds, 5);
    });

    test('exchangeDeviceCode parses the status field as an enum', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(<String, dynamic>{
            '__className__': 'DeviceAuthorizationResult',
            'status': 'pending',
            'pollIntervalSeconds': 5,
          }),
          200,
        ),
      );
      final api = AuthApi(
        RestageApi(
          endpoint: Uri.parse('https://api.example.com/'),
          httpClient: client,
        ),
      );
      final result = await api.exchangeDeviceCode('dc-abc');
      expect(result.status, DeviceAuthorizationStatus.pending);
      expect(result.pollIntervalSeconds, 5);
      expect(result.keyId, isNull);
    });

    test(
      'exchangeDeviceCode decodes a nested userInfo on the success status',
      () async {
        final client = MockClient(
          (request) async => http.Response(
            jsonEncode(<String, dynamic>{
              '__className__': 'DeviceAuthorizationResult',
              'status': 'success',
              'keyId': 42,
              'key': 'secret-xyz',
              'userInfo': <String, dynamic>{
                'id': 7,
                'email': 'jane@example.com',
              },
            }),
            200,
          ),
        );
        final api = AuthApi(
          RestageApi(
            endpoint: Uri.parse('https://api.example.com/'),
            httpClient: client,
          ),
        );
        final result = await api.exchangeDeviceCode('dc-abc');
        expect(result.status, DeviceAuthorizationStatus.success);
        expect(result.keyId, 42);
        expect(result.key, 'secret-xyz');
        expect(result.userInfo, isNotNull);
        expect(result.userInfo!.email, 'jane@example.com');
        expect(result.userInfo!.id, 7);
      },
    );

    test('whoami returns null on an empty / null backend response', () async {
      final client = MockClient((_) async => http.Response('null', 200));
      final api = AuthApi(
        RestageApi(
          endpoint: Uri.parse('https://api.example.com/'),
          httpClient: client,
        ),
      );
      expect(await api.whoami(), isNull);
    });

    test('whoami returns a CliUserInfo on a populated response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(<String, dynamic>{
            '__className__': 'UserInfo',
            'id': 7,
            'email': 'jane@example.com',
          }),
          200,
        ),
      );
      final api = AuthApi(
        RestageApi(
          endpoint: Uri.parse('https://api.example.com/'),
          httpClient: client,
        ),
      );
      final result = await api.whoami();
      expect(result, isNotNull);
      expect(result!.email, 'jane@example.com');
    });

    test('DeviceAuthorizationStatus.parse rejects an unknown status', () {
      expect(
        () => DeviceAuthorizationStatus.parse('mystery'),
        throwsFormatException,
      );
    });
  });
}
