import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/experiment_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/experiment_fixtures.dart';

Uint8List _decode(Object? raw, {int? maximumBytes}) => decodeByteDataWire(
  raw,
  maximumBytes: maximumBytes,
  malformed: FormatException.new,
);

void main() {
  group('the byte wire form', () {
    test('round-trips bytes with and without a bound', () {
      final bytes = Uint8List.fromList([0, 1, 254, 255]);
      final wire = encodeByteDataWire(bytes);

      expect(wire, "decode('${base64Encode(bytes)}', 'base64')");
      expect(_decode(wire), bytes);
      expect(_decode(wire, maximumBytes: 4), bytes);
    });

    test('refuses anything that is not the wire form', () {
      for (final raw in <Object?>[
        null,
        7,
        <String>['AA=='],
        'AA==',
        "decode('AA==', 'hex')",
        "encode('AA==', 'base64')",
        "decode('AA==', 'base64') ",
      ]) {
        expect(
          () => _decode(raw),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('is not in the wire form'),
            ),
          ),
          reason: '$raw',
        );
      }
    });

    test('refuses an empty payload and one past the bound', () {
      final tooLong = encodeByteDataWire(Uint8List.fromList([1, 2, 3, 4, 5]));

      for (final raw in <String>[encodeByteDataWire(const []), tooLong]) {
        expect(
          () => _decode(raw, maximumBytes: 4),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('is outside its bounded shape'),
            ),
          ),
          reason: raw,
        );
      }

      // The encoded length is checked before the payload is decoded, so an
      // over-long payload is refused for its size rather than its contents.
      expect(
        () => _decode("decode('${'!' * 64}', 'base64')", maximumBytes: 4),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('is outside its bounded shape'),
          ),
        ),
      );

      // Without a bound only the empty payload is refused.
      expect(_decode(tooLong), hasLength(5));
    });

    test('refuses base64 that does not decode', () {
      expect(
        () => _decode("decode('A', 'base64')"),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('is not valid base64'),
          ),
        ),
      );
    });

    test('refuses base64 that decodes but is not the canonical spelling', () {
      final bytes = Uint8List.fromList([255, 255, 255]);
      final canonical = base64Encode(bytes);
      final alternate = base64UrlEncode(bytes);
      expect(alternate, isNot(canonical));

      expect(
        () => _decode("decode('$alternate', 'base64')"),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('is not canonical'),
          ),
        ),
      );
      expect(_decode("decode('$canonical', 'base64')"), bytes);
    });
  });

  group('the clients hold the wire form to the same shape', () {
    test('the experiment client refuses a non-canonical spelling', () async {
      // Refused by the wire form before any document is read, so the bytes
      // need only spell themselves in the other alphabet.
      final alternate = base64UrlEncode(Uint8List.fromList([255, 255, 255]));

      final api = ExperimentApi(
        RestageApi(
          endpoint: Uri.parse('https://api.example.com/api/'),
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode("decode('$alternate', 'base64')"),
              200,
            ),
          ),
        ),
      );

      await expectLater(
        api.execute(
          request: canonicalRequest(
            ExperimentAuthoringOperationV1.listExperiments,
          ),
          target: fixtureTarget,
        ),
        throwsA(
          isA<CanonicalFormatException>().having(
            (e) => e.message,
            'message',
            contains('is not canonical'),
          ),
        ),
      );
    });

    test('loading a surface refuses a bare base64 reply', () async {
      Future<Uint8List> load(Object? reply) =>
          SurfaceApi(_FixedReply(reply)).load(
            project: 'p',
            app: 'a',
            surfaceType: SurfaceType.onboarding,
            surfaceSlug: 'welcome',
          );

      await expectLater(load('AA=='), throwsA(isA<FormatException>()));
      expect(await load("decode('AA==', 'base64')"), hasLength(1));
    });
  });
}

class _FixedReply implements RestageApi {
  _FixedReply(this.reply);

  final Object? reply;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async => reply;

  @override
  void close() {}
}
