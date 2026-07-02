import 'dart:convert';

import 'package:restage_cli/src/api/surface_models.dart';
import 'package:test/test.dart';

void main() {
  group('SurfaceStatusResult', () {
    test('fromJson decodes status + versions', () {
      final result = SurfaceStatusResult.fromJson({
        'surfaceType': 'paywall',
        'surfaceSlug': 'pro',
        'environmentSlug': 'production',
        'liveVersion': 2,
        'locked': false,
        'deliveryShape': 'blob',
        'versions': [
          {
            'version': 2,
            'publishedAt': '2026-06-25T00:00:00.000Z',
            'contentHash': 'abc',
            'isActive': true,
          },
          {
            'version': 1,
            'publishedAt': '2026-06-24T00:00:00.000Z',
            'contentHash': 'def',
            'isActive': false,
          },
        ],
        '__className__': 'SurfaceStatusView',
      });
      expect(result.liveVersion, 2);
      expect(result.locked, isFalse);
      expect(result.deliveryShape, 'blob');
      expect(result.versions, hasLength(2));
      expect(result.versions.first.isActive, isTrue);
    });

    test('decodes a flow surface with a null liveVersion', () {
      final result = SurfaceStatusResult.fromJson({
        'surfaceType': 'onboarding',
        'surfaceSlug': 'welcome',
        'environmentSlug': 'production',
        'liveVersion': null,
        'locked': true,
        'deliveryShape': 'flow',
        'versions': <dynamic>[],
      });
      expect(result.deliveryShape, 'flow');
      expect(result.liveVersion, isNull);
    });
  });

  group('RollbackPreflightResult', () {
    RollbackPreflightResult decode(
      String classification, {
      List<String> blockingChanges = const [],
    }) => RollbackPreflightResult.fromJson({
      'surfaceType': 'onboarding',
      'surfaceSlug': 'welcome',
      'environmentSlug': 'production',
      'toVersion': 1,
      'classification': classification,
      'blockingChanges': blockingChanges,
      '__className__': 'RollbackPreflightView',
    });

    test('fromJson round-trips each known classification', () {
      expect(
        decode('compatible').classification,
        RollbackPreflightClassification.compatible,
      );
      expect(
        decode('contractChange').classification,
        RollbackPreflightClassification.contractChange,
      );
      expect(
        decode('unsupportedTargetShape').classification,
        RollbackPreflightClassification.unsupportedTargetShape,
      );
      expect(
        decode('noActiveBaseline').classification,
        RollbackPreflightClassification.noActiveBaseline,
      );
    });

    test('an unknown classification decodes to unknown (forward-compat)', () {
      expect(
        decode('somethingNew').classification,
        RollbackPreflightClassification.unknown,
      );
    });

    test('blockingChanges + scalars decode', () {
      final result = decode(
        'contractChange',
        blockingChanges: const ['a', 'b'],
      );
      expect(result.toVersion, 1);
      expect(result.blockingChanges, ['a', 'b']);
    });

    test('absent blockingChanges decodes to empty', () {
      final result = RollbackPreflightResult.fromJson({
        'surfaceType': 'onboarding',
        'surfaceSlug': 'welcome',
        'environmentSlug': 'production',
        'toVersion': 2,
        'classification': 'compatible',
      });
      expect(result.blockingChanges, isEmpty);
    });
  });

  group('decodeSurfaceTypedException', () {
    test('decodes SurfaceNotFoundException', () {
      final body = jsonEncode({
        'className': 'SurfaceNotFoundException',
        'data': {
          '__className__': 'SurfaceNotFoundException',
          'surfaceSlug': 'first_run',
        },
      });

      final decoded = decodeSurfaceTypedException(body);

      expect(decoded, isA<SurfaceNotFound>());
      expect((decoded! as SurfaceNotFound).surfaceSlug, 'first_run');
    });

    test('decodes SurfacePublishConflictException', () {
      final body = jsonEncode({
        'className': 'SurfacePublishConflictException',
        'data': {
          '__className__': 'SurfacePublishConflictException',
          'surfaceSlug': 'first_run',
          'environmentSlug': 'dev',
        },
      });

      final decoded = decodeSurfaceTypedException(body);

      expect(decoded, isA<SurfacePublishConflict>());
      final conflict = decoded! as SurfacePublishConflict;
      expect(conflict.surfaceSlug, 'first_run');
      expect(conflict.environmentSlug, 'dev');
    });

    test('decodes EnvironmentNotFoundException', () {
      final body = jsonEncode({
        'className': 'EnvironmentNotFoundException',
        'data': {
          '__className__': 'EnvironmentNotFoundException',
          'environmentSlug': 'qa',
        },
      });

      final decoded = decodeSurfaceTypedException(body);

      expect(decoded, isA<SurfaceEnvironmentNotFound>());
      expect((decoded! as SurfaceEnvironmentNotFound).environmentSlug, 'qa');
    });

    test('decodes SurfaceRollbackUnsupportedException', () {
      final body = jsonEncode({
        'className': 'SurfaceRollbackUnsupportedException',
        'data': {
          '__className__': 'SurfaceRollbackUnsupportedException',
          'surfaceSlug': 'welcome',
        },
      });
      final decoded = decodeSurfaceTypedException(body);
      expect(decoded, isA<SurfaceRollbackUnsupported>());
      expect((decoded! as SurfaceRollbackUnsupported).surfaceSlug, 'welcome');
    });

    test('decodes SurfaceVersionNotFoundException', () {
      // Wire key is 'version', not 'toVersion' — mirrors the real backend body.
      final body = jsonEncode({
        'className': 'SurfaceVersionNotFoundException',
        'data': {
          '__className__': 'SurfaceVersionNotFoundException',
          'surfaceSlug': 'pro',
          'environmentSlug': 'production',
          'version': 5,
        },
      });
      final decoded = decodeSurfaceTypedException(body);
      expect(decoded, isA<SurfaceVersionNotFound>());
      final e = decoded! as SurfaceVersionNotFound;
      expect(e.surfaceSlug, 'pro');
      expect(e.toVersion, 5); // CLI field is toVersion; wire field is version
    });

    test('SurfaceVersionNotFoundException with missing fields returns null '
        '(defensive)', () {
      // Missing 'version' field — decoder must return null, not throw.
      final body = jsonEncode({
        'className': 'SurfaceVersionNotFoundException',
        'data': {
          '__className__': 'SurfaceVersionNotFoundException',
          'surfaceSlug': 'pro',
          // 'version' intentionally absent
        },
      });
      expect(decodeSurfaceTypedException(body), isNull);
    });

    test('returns null for a paywall className (does not overload)', () {
      final body = jsonEncode({
        'className': 'PaywallNotFoundException',
        'data': {
          '__className__': 'PaywallNotFoundException',
          'paywallSlug': 'missing',
        },
      });
      expect(decodeSurfaceTypedException(body), isNull);
    });

    test('returns null for an unknown className', () {
      final body = jsonEncode({
        'className': 'BananaException',
        'data': {'__className__': 'BananaException', 'foo': 'bar'},
      });
      expect(decodeSurfaceTypedException(body), isNull);
    });

    test('returns null for a non-JSON body', () {
      expect(decodeSurfaceTypedException('not json'), isNull);
    });

    test('returns null for a JSON body without className', () {
      expect(decodeSurfaceTypedException('{"foo":"bar"}'), isNull);
    });

    test('returns null for an empty body', () {
      expect(decodeSurfaceTypedException(''), isNull);
    });
  });

  group('surface audit DTOs', () {
    test('SurfaceAuditLogEntry.fromJson decodes a timeline row', () {
      final entry = SurfaceAuditLogEntry.fromJson({
        '__className__': 'SurfaceAuditLogEntryView',
        'action': 'surfacePublished',
        'actorType': 'human',
        'actorEmail': 'owner@example.com',
        'outcome': 'success',
        'severity': 'notice',
        'targetType': 'surface',
        'targetId': '42',
        'occurredAt': '2026-06-29T18:17:51.000Z',
        'reason': 'demo publish',
        'context': {
          'surfaceSlug': 'pro',
          'surfaceType': 'paywall',
          'environmentSlug': 'staging',
          'publishedVersion': '2',
        },
        'chainState': 'chained',
        'chainVerified': true,
        'entryId': 99,
      });

      expect(entry.action, 'surfacePublished');
      expect(entry.actorEmail, 'owner@example.com');
      expect(entry.context['surfaceSlug'], 'pro');
      expect(entry.chainVerified, isTrue);
      expect(entry.entryId, 99);
      expect(entry.toJson()['reason'], 'demo publish');
    });

    test('SurfaceComplianceExportRow.fromJson decodes a flat export row', () {
      final row = SurfaceComplianceExportRow.fromJson({
        '__className__': 'SurfaceComplianceExportRow',
        'occurredAt': '2026-06-29T18:17:51.000Z',
        'action': 'surfaceKilled',
        'surfaceSlug': 'pro',
        'surfaceType': 'paywall',
        'environmentSlug': 'production',
        'version': 2,
        'actorEmail': 'admin@example.com',
        'reason': 'incident',
        'chainState': 'pendingChain',
        'chainVerified': false,
        'entryId': 100,
      });

      expect(row.action, 'surfaceKilled');
      expect(row.environmentSlug, 'production');
      expect(row.version, 2);
      expect(row.chainState, 'pendingChain');
      expect(row.chainVerified, isFalse);
      expect(row.toJson()['surfaceSlug'], 'pro');
    });

    test('SurfaceChainVerdictResult.fromJson decodes optional fields', () {
      final verdict = SurfaceChainVerdictResult.fromJson({
        '__className__': 'SurfaceChainVerdict',
        'status': 'broken',
        'verifiedThroughEntryId': 7,
        'verifiedThroughOccurredAt': '2026-06-29T18:00:00.000Z',
        'failedEntryId': 8,
        'failedCheck': 'hashMismatch',
        'lastRunAt': '2026-06-29T18:30:00.000Z',
      });

      expect(verdict.status, 'broken');
      expect(verdict.verifiedThroughEntryId, 7);
      expect(verdict.failedEntryId, 8);
      expect(verdict.failedCheck, 'hashMismatch');
      expect(verdict.toJson()['lastRunAt'], '2026-06-29T18:30:00.000Z');
    });
  });

  group('exception toString', () {
    test('SurfaceNotFound surfaces the slug', () {
      const e = SurfaceNotFound(surfaceSlug: 'first_run');
      expect(e.toString(), contains('first_run'));
    });

    test('SurfacePublishConflict surfaces both fields', () {
      const e = SurfacePublishConflict(
        surfaceSlug: 'first_run',
        environmentSlug: 'dev',
      );
      expect(e.toString(), contains('first_run'));
      expect(e.toString(), contains('dev'));
    });

    test('SurfaceEnvironmentNotFound surfaces the slug', () {
      const e = SurfaceEnvironmentNotFound(environmentSlug: 'qa');
      expect(e.toString(), contains('qa'));
    });

    test('SurfaceRollbackUnsupported surfaces the slug', () {
      const e = SurfaceRollbackUnsupported(surfaceSlug: 'welcome');
      expect(e.toString(), contains('welcome'));
    });

    test('SurfaceVersionNotFound surfaces slug + version', () {
      const e = SurfaceVersionNotFound(surfaceSlug: 'pro', toVersion: 5);
      expect(e.toString(), contains('pro'));
      expect(e.toString(), contains('5'));
    });
  });
}
