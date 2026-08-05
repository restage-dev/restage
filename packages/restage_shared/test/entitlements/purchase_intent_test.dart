import 'dart:convert';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _purchaseIntentId = '550e8400-e29b-41d4-a716-446655440000';
const _appAnonymousToken = '6ba7b810-9dad-41d1-80b4-00c04fd430c8';
final int _maxSignedInt64 = int.parse('9223372036854775807');

Map<String, Object?> _requiredRequestJson() => {
      'purchaseIntentId': _purchaseIntentId,
      'store': 'appStore',
      'appAnonymousToken': _appAnonymousToken,
      'storeProductId': 'com.example.app.pro_monthly',
    };

Map<String, Object?> _experimentRequestJson({int epoch = 1}) => {
      ..._requiredRequestJson(),
      'paywallId': 'upgrade',
      'experimentId': 'upgrade-copy',
      'experimentVariantId': 'concise',
      'experimentEpoch': epoch,
    };

Map<String, dynamic> _requestWithRawNumericField(
  Map<String, Object?> json,
  String field,
  String rawValue,
) {
  final encoded = jsonEncode({...json, field: 0});
  final withRawValue = encoded.replaceFirst(
    '"$field":0',
    '"$field":$rawValue',
  );
  return (jsonDecode(withRawValue) as Map).cast<String, dynamic>();
}

void main() {
  group('CreatePurchaseIntentRequest', () {
    test('round-trips the exact complete JSON shape', () {
      const request = CreatePurchaseIntentRequest(
        purchaseIntentId: _purchaseIntentId,
        store: 'playStore',
        appAnonymousToken: _appAnonymousToken,
        storeProductId: 'pro_monthly',
        basePlanId: 'monthly',
        offerId: 'intro',
        paywallId: 'upgrade',
        paywallVariantSlug: 'control',
        paywallPublishedVersion: 7,
        experimentId: 'upgrade-copy',
        experimentVariantId: 'concise',
        experimentEpoch: 1,
      );
      final expected = <String, Object?>{
        'purchaseIntentId': _purchaseIntentId,
        'store': 'playStore',
        'appAnonymousToken': _appAnonymousToken,
        'storeProductId': 'pro_monthly',
        'basePlanId': 'monthly',
        'offerId': 'intro',
        'paywallId': 'upgrade',
        'paywallVariantSlug': 'control',
        'paywallPublishedVersion': 7,
        'experimentId': 'upgrade-copy',
        'experimentVariantId': 'concise',
        'experimentEpoch': 1,
      };

      expect(request.toJson(), expected);
      expect(CreatePurchaseIntentRequest.fromJson(expected), request);
    });

    test('accepts experiment metadata without a paywall variant slug', () {
      final request = CreatePurchaseIntentRequest.fromJson(
        _experimentRequestJson(),
      );

      expect(request.paywallId, 'upgrade');
      expect(request.paywallVariantSlug, isNull);
      expect(request.experimentId, 'upgrade-copy');
      expect(request.experimentVariantId, 'concise');
      expect(request.experimentEpoch, 1);
    });

    test('omits every absent optional field', () {
      final request = CreatePurchaseIntentRequest.fromJson(
        _requiredRequestJson(),
      );

      expect(request.toJson(), _requiredRequestJson());
    });

    test('accepts explicit null for every optional field and omits it', () {
      final json = _requiredRequestJson();
      for (final field in const [
        'basePlanId',
        'offerId',
        'paywallId',
        'paywallVariantSlug',
        'paywallPublishedVersion',
        'experimentId',
        'experimentVariantId',
        'experimentEpoch',
      ]) {
        json[field] = null;
      }

      expect(
        CreatePurchaseIntentRequest.fromJson(json).toJson(),
        _requiredRequestJson(),
      );
    });

    test('requires every required field', () {
      for (final field in const [
        'purchaseIntentId',
        'store',
        'appAnonymousToken',
        'storeProductId',
      ]) {
        final missing = _requiredRequestJson()..remove(field);
        final nullValue = _requiredRequestJson()..[field] = null;

        expect(
          () => CreatePurchaseIntentRequest.fromJson(missing),
          throwsArgumentError,
          reason: '$field must be required',
        );
        expect(
          () => CreatePurchaseIntentRequest.fromJson(nullValue),
          throwsArgumentError,
          reason: '$field must not accept null',
        );
      }
    });

    test('accepts only the two frozen store values', () {
      for (final store in const ['appStore', 'playStore']) {
        final json = _requiredRequestJson()..['store'] = store;
        expect(CreatePurchaseIntentRequest.fromJson(json).store, store);
      }

      for (final store in const ['appstore', 'googlePlay', 'amazonStore', '']) {
        final json = _requiredRequestJson()..['store'] = store;
        expect(
          () => CreatePurchaseIntentRequest.fromJson(json),
          throwsArgumentError,
        );
      }
    });

    test('accepts base plans only for Play Store requests', () {
      final playJson = _requiredRequestJson()
        ..['store'] = 'playStore'
        ..['basePlanId'] = 'monthly';
      expect(
        CreatePurchaseIntentRequest.fromJson(playJson).basePlanId,
        'monthly',
      );

      final appleJson = _requiredRequestJson()..['basePlanId'] = 'monthly';
      expect(
        () => CreatePurchaseIntentRequest.fromJson(appleJson),
        throwsArgumentError,
      );
    });

    test('freezes canonical JSON field order and null omission', () {
      const request = CreatePurchaseIntentRequest(
        purchaseIntentId: _purchaseIntentId,
        store: 'playStore',
        appAnonymousToken: _appAnonymousToken,
        storeProductId: 'pro_monthly',
        basePlanId: 'monthly',
        offerId: 'intro',
        paywallId: 'upgrade',
        paywallVariantSlug: 'control',
        paywallPublishedVersion: 7,
        experimentId: 'upgrade-copy',
        experimentVariantId: 'concise',
        experimentEpoch: 1,
      );

      expect(
        jsonEncode(request.toJson()),
        '{"purchaseIntentId":"$_purchaseIntentId","store":"playStore",'
        '"appAnonymousToken":"$_appAnonymousToken",'
        '"storeProductId":"pro_monthly","basePlanId":"monthly",'
        '"offerId":"intro","paywallId":"upgrade",'
        '"paywallVariantSlug":"control","paywallPublishedVersion":7,'
        '"experimentId":"upgrade-copy","experimentVariantId":"concise",'
        '"experimentEpoch":1}',
      );
    });

    test('requires canonical lowercase UUIDv4 purchase intent IDs', () {
      const invalidUuids = [
        '550E8400-E29B-41D4-A716-446655440000',
        '550e8400-e29b-11d4-a716-446655440000',
        '550e8400-e29b-41d4-c716-446655440000',
        '{550e8400-e29b-41d4-a716-446655440000}',
        'not-a-uuid',
      ];

      for (final uuid in invalidUuids) {
        final json = _requiredRequestJson()..['purchaseIntentId'] = uuid;
        expect(
          () => CreatePurchaseIntentRequest.fromJson(json),
          throwsArgumentError,
          reason: 'purchaseIntentId accepted $uuid',
        );
      }
    });

    test(
      'accepts compatible UUIDv4 anonymous tokens and preserves casing',
      () {
        const compatibleTokens = [
          'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE',
          'AAAAAAAA-BBBB-4CCC-9DDD-EEEEEEEEEEEE',
          'aaaaaaaa-bbbb-4ccc-addd-eeeeeeeeeeee',
          'aaaaaaaa-bbbb-4ccc-bddd-eeeeeeeeeeee',
          'AAAAAAAA-BBBB-4CCC-ADDD-EEEEEEEEEEEE',
          'AAAAAAAA-BBBB-4CCC-BDDD-EEEEEEEEEEEE',
        ];

        for (final token in compatibleTokens) {
          final json = _requiredRequestJson()..['appAnonymousToken'] = token;
          final request = CreatePurchaseIntentRequest.fromJson(json);

          expect(request.appAnonymousToken, token);
          expect(request.toJson()['appAnonymousToken'], token);
        }
      },
    );

    test('rejects malformed anonymous token UUIDs', () {
      const malformedUuids = [
        '550e8400-e29b-11d4-a716-446655440000',
        '550e8400-e29b-41d4-c716-446655440000',
        '550E8400-E29B-41D4-C716-446655440000',
        '550e8400e29b41d4a716446655440000',
        '{550e8400-e29b-41d4-a716-446655440000}',
        '550e8400-e29b-41d4-a716-44665544000z',
        'not-a-uuid',
      ];

      for (final uuid in malformedUuids) {
        final json = _requiredRequestJson()..['appAnonymousToken'] = uuid;
        expect(
          () => CreatePurchaseIntentRequest.fromJson(json),
          throwsArgumentError,
          reason: 'appAnonymousToken accepted $uuid',
        );
      }
    });

    test('rejects empty and unbounded string fields', () {
      final oversized = List.filled(1025, 'x').join();
      for (final field in const [
        'storeProductId',
        'basePlanId',
        'offerId',
        'paywallId',
        'paywallVariantSlug',
      ]) {
        for (final value in ['', oversized]) {
          final json = _requiredRequestJson()
            ..['paywallId'] = 'upgrade'
            ..[field] = value;
          expect(
            () => CreatePurchaseIntentRequest.fromJson(json),
            throwsArgumentError,
            reason: '$field accepted a value of length ${value.length}',
          );
        }
      }

      for (final field in const ['experimentId', 'experimentVariantId']) {
        for (final value in ['', oversized]) {
          final json = _experimentRequestJson()..[field] = value;
          expect(
            () => CreatePurchaseIntentRequest.fromJson(json),
            throwsArgumentError,
            reason: '$field accepted a value of length ${value.length}',
          );
        }
      }
    });

    test('accepts signed 64-bit min and max boundaries', () {
      for (final value in [1, _maxSignedInt64]) {
        final versionJson = _requiredRequestJson()
          ..['paywallId'] = 'upgrade'
          ..['paywallPublishedVersion'] = value;
        expect(
          CreatePurchaseIntentRequest.fromJson(
            versionJson,
          ).paywallPublishedVersion,
          value,
        );

        final experimentJson = _experimentRequestJson(epoch: value);
        expect(
          CreatePurchaseIntentRequest.fromJson(
            experimentJson,
          ).experimentEpoch,
          value,
        );
      }
    });

    test('rejects zero, negative, and oversized bigint values', () {
      for (final value in const [0, -1]) {
        final versionJson = _requiredRequestJson()
          ..['paywallId'] = 'upgrade'
          ..['paywallPublishedVersion'] = value;
        expect(
          () => CreatePurchaseIntentRequest.fromJson(versionJson),
          throwsArgumentError,
          reason: 'paywallPublishedVersion accepted $value',
        );

        final experimentJson = _experimentRequestJson(epoch: value);
        expect(
          () => CreatePurchaseIntentRequest.fromJson(experimentJson),
          throwsArgumentError,
          reason: 'experimentEpoch accepted $value',
        );
      }

      final oversizedVersion = _requestWithRawNumericField(
        {
          ..._requiredRequestJson(),
          'paywallId': 'upgrade',
        },
        'paywallPublishedVersion',
        '9223372036854775808',
      );
      expect(
        () => CreatePurchaseIntentRequest.fromJson(oversizedVersion),
        throwsArgumentError,
      );

      final oversizedEpoch = _requestWithRawNumericField(
        _experimentRequestJson(),
        'experimentEpoch',
        '9223372036854775808',
      );
      expect(
        () => CreatePurchaseIntentRequest.fromJson(oversizedEpoch),
        throwsArgumentError,
      );
    });

    test('rejects noninteger numeric fields', () {
      for (final field in const [
        'paywallPublishedVersion',
        'experimentEpoch',
      ]) {
        for (final value in <Object>[1.0, '1', true]) {
          final json = field == 'experimentEpoch'
              ? _experimentRequestJson()
              : {
                  ..._requiredRequestJson(),
                  'paywallId': 'upgrade',
                  'paywallPublishedVersion': 1,
                };
          json[field] = value;
          expect(
            () => CreatePurchaseIntentRequest.fromJson(json),
            throwsArgumentError,
          );
        }
      }
    });

    test('rejects every partial experiment metadata tuple', () {
      const fields = [
        'experimentId',
        'experimentVariantId',
        'experimentEpoch',
      ];
      const values = <String, Object>{
        'experimentId': 'upgrade-copy',
        'experimentVariantId': 'concise',
        'experimentEpoch': 1,
      };

      for (var mask = 1; mask < 7; mask += 1) {
        final json = _requiredRequestJson()..['paywallId'] = 'upgrade';
        for (var index = 0; index < fields.length; index += 1) {
          if ((mask & (1 << index)) != 0) {
            final field = fields[index];
            json[field] = values[field];
          }
        }

        expect(
          () => CreatePurchaseIntentRequest.fromJson(json),
          throwsArgumentError,
          reason: 'partial experiment metadata mask $mask was accepted',
        );
      }
    });

    test('requires paywall context for nested metadata', () {
      final variantWithoutPaywall = _requiredRequestJson()
        ..['paywallVariantSlug'] = 'control';
      final versionWithoutPaywall = _requiredRequestJson()
        ..['paywallPublishedVersion'] = 1;
      final experimentWithoutPaywall = _experimentRequestJson()
        ..remove('paywallId');

      for (final json in [
        variantWithoutPaywall,
        versionWithoutPaywall,
        experimentWithoutPaywall,
      ]) {
        expect(
          () => CreatePurchaseIntentRequest.fromJson(json),
          throwsArgumentError,
        );
      }
    });

    test('constructor assertions enforce metadata invariants', () {
      CreatePurchaseIntentRequest construct({
        String store = 'appStore',
        String? basePlanId,
        String? paywallId,
        String? paywallVariantSlug,
        int? paywallPublishedVersion,
        String? experimentId,
        String? experimentVariantId,
        int? experimentEpoch,
      }) {
        return CreatePurchaseIntentRequest(
          purchaseIntentId: _purchaseIntentId,
          store: store,
          appAnonymousToken: _appAnonymousToken,
          storeProductId: 'pro_monthly',
          basePlanId: basePlanId,
          paywallId: paywallId,
          paywallVariantSlug: paywallVariantSlug,
          paywallPublishedVersion: paywallPublishedVersion,
          experimentId: experimentId,
          experimentVariantId: experimentVariantId,
          experimentEpoch: experimentEpoch,
        );
      }

      expect(
        () => construct(store: 'playStore', basePlanId: 'monthly'),
        returnsNormally,
      );
      expect(
        () => construct(
          paywallId: 'upgrade',
          paywallPublishedVersion: _maxSignedInt64,
        ),
        returnsNormally,
      );
      expect(
        () => construct(
          paywallId: 'upgrade',
          experimentId: 'upgrade-copy',
          experimentVariantId: 'concise',
          experimentEpoch: _maxSignedInt64,
        ),
        returnsNormally,
      );

      for (final createInvalid in <CreatePurchaseIntentRequest Function()>[
        () => construct(basePlanId: 'monthly'),
        () => construct(paywallVariantSlug: 'control'),
        () => construct(paywallPublishedVersion: 1),
        () => construct(
              experimentId: 'upgrade-copy',
              experimentVariantId: 'concise',
              experimentEpoch: 1,
            ),
        () => construct(
              paywallId: 'upgrade',
              paywallPublishedVersion: 0,
            ),
        () => construct(
              paywallId: 'upgrade',
              paywallPublishedVersion: -1,
            ),
        () => construct(
              paywallId: 'upgrade',
              experimentId: 'upgrade-copy',
              experimentVariantId: 'concise',
              experimentEpoch: 0,
            ),
        () => construct(
              paywallId: 'upgrade',
              experimentId: 'upgrade-copy',
              experimentVariantId: 'concise',
              experimentEpoch: -1,
            ),
      ]) {
        expect(createInvalid, throwsA(isA<AssertionError>()));
      }

      for (var mask = 1; mask < 7; mask += 1) {
        expect(
          () => construct(
            paywallId: 'upgrade',
            experimentId: (mask & (1 << 0)) != 0 ? 'upgrade-copy' : null,
            experimentVariantId: (mask & (1 << 1)) != 0 ? 'concise' : null,
            experimentEpoch: (mask & (1 << 2)) != 0 ? 1 : null,
          ),
          throwsA(isA<AssertionError>()),
          reason: 'partial constructor tuple mask $mask was accepted',
        );
      }
    });

    test('stays strict for unknown and server-owned fields', () {
      for (final field in const [
        'organizationId',
        'appId',
        'environmentId',
        'storeEnvironment',
        'storeAppIdentifier',
        'reportId',
        'unknown',
      ]) {
        final json = _requiredRequestJson()..[field] = 'not-client-owned';
        expect(
          () => CreatePurchaseIntentRequest.fromJson(json),
          throwsArgumentError,
          reason: '$field must not be part of the public request',
        );
      }
    });
  });

  group('CreatePurchaseIntentResponse', () {
    test('round-trips only the echoed UUID and creation result', () {
      const response = CreatePurchaseIntentResponse(
        purchaseIntentId: _purchaseIntentId,
        created: true,
      );
      final expected = <String, Object?>{
        'purchaseIntentId': _purchaseIntentId,
        'created': true,
      };

      expect(response.toJson(), expected);
      expect(CreatePurchaseIntentResponse.fromJson(expected), response);
    });

    test('strictly parses both required response fields', () {
      for (final invalid in <Map<String, Object?>>[
        {'created': true},
        {'purchaseIntentId': _purchaseIntentId},
        {'purchaseIntentId': _purchaseIntentId, 'created': 1},
        {
          'purchaseIntentId': '550E8400-E29B-41D4-A716-446655440000',
          'created': false,
        },
      ]) {
        expect(
          () => CreatePurchaseIntentResponse.fromJson(invalid),
          throwsArgumentError,
        );
      }
    });

    test('ignores unknown response fields and parses the known fields', () {
      for (final field in const [
        'appAnonymousToken',
        'organizationId',
        'metadata',
        'lookupToken',
        'unknown',
      ]) {
        final json = <String, Object?>{
          'purchaseIntentId': _purchaseIntentId,
          'created': false,
          field: 'not-public',
        };
        final response = CreatePurchaseIntentResponse.fromJson(json);

        expect(response.purchaseIntentId, _purchaseIntentId);
        expect(response.created, isFalse);
      }
    });
  });
}
