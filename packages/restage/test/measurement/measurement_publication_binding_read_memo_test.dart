import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admitted_bundled_publication_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final entry = AdmittedBundledPublicationFixture.build().entry;
  final acceptedBody = jsonEncode({
    'bindingCanonicalBase64': _carrier(entry.binding.canonicalBytes),
    'registeredPublicationAttestationCanonicalBase64':
        _carrier(entry.registeredPublicationAttestation.canonicalBytes),
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
  });
  tearDown(Restage.debugReset);

  RestageRpcClient client(List<int> statuses, void Function() onRead,
      {String baseUrl = 'https://surfaces.example.com',
      String apiKey = 'rs_pk_memo'}) {
    var index = 0;
    return RestageRpcClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient((request) async {
        onRead();
        final status = statuses[index++];
        return http.Response(status == 200 ? acceptedBody : '', status);
      }),
    );
  }

  test('an accepted read is reused by its own client only', () async {
    var firstReads = 0;
    var secondReads = 0;
    final first = client([200], () => firstReads++);
    final second = client([200], () => secondReads++);
    for (var i = 0; i < 2; i++) {
      expect(
          await first.readMeasurementPublicationBindingExact(entry.reference),
          isA<MeasurementPublicationBindingReadRpcAccepted>());
    }
    expect(await second.readMeasurementPublicationBindingExact(entry.reference),
        isA<MeasurementPublicationBindingReadRpcAccepted>());
    expect(firstReads, 1);
    expect(secondReads, 1);
  });

  test('a failed read is not kept', () async {
    var reads = 0;
    final rpc = client([503, 404, 200], () => reads++);
    expect(await rpc.readMeasurementPublicationBindingExact(entry.reference),
        isA<MeasurementPublicationBindingReadRpcUnavailable>());
    expect(await rpc.readMeasurementPublicationBindingExact(entry.reference),
        isA<MeasurementPublicationBindingReadRpcAbsent>());
    for (var i = 0; i < 2; i++) {
      expect(await rpc.readMeasurementPublicationBindingExact(entry.reference),
          isA<MeasurementPublicationBindingReadRpcAccepted>());
    }
    expect(reads, 3);
  });

  test('identity reset and reconfigure drop held reads', () async {
    Restage.configure(
        apiKey: 'rs_pk_memo', baseUrl: 'https://surfaces.example.com');
    var reads = 0;
    final stub = client([200, 200], () => reads++);
    Restage.debugRestageRpcClient = stub;
    await stub.readMeasurementPublicationBindingExact(entry.reference);
    Restage.reset();
    await Restage.activeRpcClient!
        .readMeasurementPublicationBindingExact(entry.reference);
    expect(reads, 2);

    Restage.configure(
        apiKey: 'rs_pk_memo', baseUrl: 'https://surfaces.example.com');
    expect(Restage.activeRpcClient, isNot(same(stub)));
  });
}

String _carrier(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
