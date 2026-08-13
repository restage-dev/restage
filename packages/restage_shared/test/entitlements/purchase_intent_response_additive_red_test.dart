import 'package:restage_shared/src/entitlements/entitlements.dart';
import 'package:test/test.dart';

const _reportId = '550e8400-e29b-41d4-a716-446655440000';
const _recoveredToken = '8bff9c38-38a5-4e22-9e5f-7496d5f3a6f2';
const _uppercaseRecoveredToken = '8BFF9C38-38A5-4E22-9E5F-7496D5F3A6F2';
const List<({String name, String value})> _compatibleRecoveredTokens = [
  (name: 'lowercase variant 8', value: '8bff9c38-38a5-4e22-8e5f-7496d5f3a6f2'),
  (name: 'lowercase variant 9', value: _recoveredToken),
  (name: 'lowercase variant a', value: '8bff9c38-38a5-4e22-ae5f-7496d5f3a6f2'),
  (name: 'lowercase variant b', value: '8bff9c38-38a5-4e22-be5f-7496d5f3a6f2'),
  (name: 'uppercase variant 9', value: _uppercaseRecoveredToken),
  (name: 'uppercase variant A', value: '8BFF9C38-38A5-4E22-AE5F-7496D5F3A6F2'),
  (name: 'uppercase variant B', value: '8BFF9C38-38A5-4E22-BE5F-7496D5F3A6F2'),
];

void main() {
  group('SECURITY — additive purchase-intent report response', () {
    test(
        'optional field absence preserves pre-chapter server compatibility '
        'and every required key', () {
      final parsed = ReportTransactionResponse.fromJson(_legacyResponseJson());

      expect(parsed.purchaseIntentDisposition, isNull);
      expect(parsed.recoveredAppAnonymousToken, isNull);
      expect(parsed.toJson(), _legacyResponseJson());
      expect(parsed.toJson().keys.toSet(), {
        'accepted',
        'reportId',
        'evidence',
        'attributionDisposition',
        'entitlements',
      });
    });

    test('freezes the coordinator-adjudicated disposition wire values', () {
      const adjudicatedWireValues = {
        'notProvided': PurchaseIntentDisposition.notProvided,
        'associated': PurchaseIntentDisposition.associated,
        'alreadyAssociated': PurchaseIntentDisposition.alreadyAssociated,
        'unmatched': PurchaseIntentDisposition.unmatched,
      };

      expect(
        PurchaseIntentDisposition.values.map((value) => value.name),
        orderedEquals(adjudicatedWireValues.keys),
      );
      for (final entry in adjudicatedWireValues.entries) {
        expect(entry.value.name, entry.key);
        expect(PurchaseIntentDisposition.fromJson(entry.key), entry.value);
      }
    });

    for (final token in _compatibleRecoveredTokens) {
      for (final scenario in const [
        (
          disposition: PurchaseIntentDisposition.associated,
          contract:
              'means a provider-verified eligible intent is first associated',
        ),
        (
          disposition: PurchaseIntentDisposition.alreadyAssociated,
          contract: 'means an exact idempotent association replay',
        ),
      ]) {
        test(
            '${scenario.disposition.name} ${scenario.contract} and '
            'round-trips the exact ${token.name} purchase-intent token', () {
          final intentJson = <String, dynamic>{
            'purchaseIntentId': _reportId,
            'store': 'appStore',
            'appAnonymousToken': token.value,
            'storeProductId': 'premium.monthly',
          };
          final intent = CreatePurchaseIntentRequest.fromJson(intentJson);
          expect(intent.appAnonymousToken, token.value);
          expect(intent.toJson(), intentJson);

          final response = _response(
            disposition: scenario.disposition,
            recoveredToken: intent.appAnonymousToken,
          );
          final expected = {
            ..._legacyResponseJson(),
            'purchaseIntentDisposition': scenario.disposition.name,
            'recoveredAppAnonymousToken': token.value,
          };
          final decoded = ReportTransactionResponse.fromJson(expected);

          expect(response.toJson(), expected);
          expect(decoded, response);
          expect(decoded.recoveredAppAnonymousToken, token.value);
          expect(decoded.toJson(), expected);
        });
      }
    }

    test(
        'associated outcomes fail closed without a canonical-form UUIDv4 '
        'token', () {
      for (final disposition in const [
        PurchaseIntentDisposition.associated,
        PurchaseIntentDisposition.alreadyAssociated,
      ]) {
        for (final recoveredToken in <Object?>[
          null,
          '',
          'not-a-token',
          '550e8400-e29b-11d4-a716-446655440000',
          '{550e8400-e29b-41d4-a716-446655440000}',
          '550e8400-e29b-41d4-a716-446655440000 ',
          '8bff9c3838a54e229e5f7496d5f3a6f2',
          '8bff9c38-38a5-4e22-ce5f-7496d5f3a6f2',
          '8bff9c38-38a5-4e22-9e5f-7496d5f3a6fz',
        ]) {
          final json = {
            ..._legacyResponseJson(),
            'purchaseIntentDisposition': disposition.name,
            if (recoveredToken != null)
              'recoveredAppAnonymousToken': recoveredToken,
          };

          expect(
            () => ReportTransactionResponse.fromJson(json),
            throwsArgumentError,
            reason: '${disposition.name} must authenticate one canonical-form '
                'UUIDv4 before exposing or repairing identity',
          );
        }
      }
    });

    for (final scenario in const [
      (
        disposition: PurchaseIntentDisposition.notProvided,
        contract:
            'means authoritative provider evidence carries no purchase-intent '
                'UUID or binding at all; this is the legacy, out-of-app, or '
                'no-intent path',
      ),
      (
        disposition: PurchaseIntentDisposition.unmatched,
        contract:
            'means a provider-verified UUID or binding is present, the owner '
                'is not cross-owner, but no eligible association is applied '
                'because the eligible intent is missing, expired, has a '
                'same-owner tuple mismatch, or has an attribution mismatch',
      ),
    ]) {
      test(
          '${scenario.disposition.name} ${scenario.contract} and cannot '
          'expose or repair install identity', () {
        final safeJson = {
          ..._legacyResponseJson(),
          'purchaseIntentDisposition': scenario.disposition.name,
        };
        final parsed = ReportTransactionResponse.fromJson(safeJson);

        expect(parsed.purchaseIntentDisposition, scenario.disposition);
        expect(parsed.recoveredAppAnonymousToken, isNull);
        expect(parsed.toJson(), safeJson);

        expect(
          () => ReportTransactionResponse.fromJson({
            ...safeJson,
            'recoveredAppAnonymousToken': _recoveredToken,
          }),
          throwsArgumentError,
          reason: '${scenario.disposition.name} must never expose a token or '
              'authorize identity repair',
        );
      });
    }

    test(
        'unknown disposition text is malformed for this client version and '
        'fails closed', () {
      for (final recoveredToken in <String?>[null, _recoveredToken]) {
        final json = {
          ..._legacyResponseJson(),
          'purchaseIntentDisposition': 'futureAssociationMode',
          if (recoveredToken != null)
            'recoveredAppAnonymousToken': recoveredToken,
        };

        expect(
          () => ReportTransactionResponse.fromJson(json),
          throwsArgumentError,
          reason:
              'unknown disposition text must not become an accepted response '
              'or silently map to a known disposition',
        );
      }
    });

    test('cross-owner is a generic rejection and never a disposition', () {
      expect(
        () => ReportTransactionResponse.fromJson({
          ..._legacyResponseJson(),
          'purchaseIntentDisposition': 'crossOwner',
        }),
        throwsArgumentError,
        reason:
            'cross-owner evidence is a generic rejection, never an accepted '
            'commerce response or a purchase-intent disposition',
      );
    });

    test('a frozen legacy decoder ignores the two additive response keys', () {
      final modernJson = _response(
        disposition: PurchaseIntentDisposition.associated,
        recoveredToken: _recoveredToken,
      ).toJson();

      final legacy = _LegacyReportResponse.fromJson(modernJson);

      expect(legacy.accepted, isTrue);
      expect(legacy.reportId, _reportId);
      expect(legacy.attributionDisposition, 'alreadyApplied');
      expect(legacy.entitlementCount, 0);
    });
  });
}

ReportTransactionResponse _response({
  required PurchaseIntentDisposition disposition,
  String? recoveredToken,
}) {
  return ReportTransactionResponse(
    accepted: true,
    reportId: _reportId,
    evidence: const AppleAcceptedStoreEvidence(
      submittedTransactionId: '2000000000000001',
      acceptedTransactionId: '2000000000000001',
      originalTransactionId: '1000000000000001',
    ),
    attributionDisposition: AttributionDisposition.alreadyApplied,
    purchaseIntentDisposition: disposition,
    recoveredAppAnonymousToken: recoveredToken,
  );
}

Map<String, dynamic> _legacyResponseJson() => {
      'accepted': true,
      'reportId': _reportId,
      'evidence': {
        'store': 'appStore',
        'submittedTransactionId': '2000000000000001',
        'acceptedTransactionId': '2000000000000001',
        'originalTransactionId': '1000000000000001',
      },
      'attributionDisposition': 'alreadyApplied',
      'entitlements': <Object?>[],
    };

/// A minimal copy of the previously published reader: it consumes the required
/// response fields and deliberately ignores fields it does not understand.
final class _LegacyReportResponse {
  const _LegacyReportResponse({
    required this.accepted,
    required this.reportId,
    required this.attributionDisposition,
    required this.entitlementCount,
  });

  factory _LegacyReportResponse.fromJson(Map<String, dynamic> json) {
    final accepted = json['accepted'];
    final reportId = json['reportId'];
    final evidence = json['evidence'];
    final attributionDisposition = json['attributionDisposition'];
    final entitlements = json['entitlements'];
    if (accepted is! bool ||
        reportId is! String ||
        evidence is! Map ||
        attributionDisposition is! String ||
        entitlements is! List) {
      throw const FormatException('Malformed legacy report response');
    }
    return _LegacyReportResponse(
      accepted: accepted,
      reportId: reportId,
      attributionDisposition: attributionDisposition,
      entitlementCount: entitlements.length,
    );
  }

  final bool accepted;
  final String reportId;
  final String attributionDisposition;
  final int entitlementCount;
}
