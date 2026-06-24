import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('AnalyticsSurface', () {
    test('known set is the six blessed surfaces', () {
      expect(
        AnalyticsSurface.known,
        {
          AnalyticsSurface.paywall,
          AnalyticsSurface.onboarding,
          AnalyticsSurface.message,
          AnalyticsSurface.survey,
          AnalyticsSurface.app,
          AnalyticsSurface.billing,
        },
      );
    });

    test('values are canonical snake/lower strings', () {
      expect(AnalyticsSurface.paywall, 'paywall');
      expect(AnalyticsSurface.onboarding, 'onboarding');
      expect(AnalyticsSurface.billing, 'billing');
    });

    test('isKnown preserves (does not reject) unknown values', () {
      expect(AnalyticsSurface.isKnown(AnalyticsSurface.paywall), isTrue);
      // Forward-compat: an unseen surface is simply "not known", not an error.
      expect(AnalyticsSurface.isKnown('hologram'), isFalse);
    });
  });

  group('AnalyticsSource', () {
    test('known set is exactly client + server', () {
      expect(AnalyticsSource.known, {'client', 'server'});
      expect(AnalyticsSource.client, 'client');
      expect(AnalyticsSource.server, 'server');
    });
  });

  group('AnalyticsTier', () {
    test('known set is exactly tier1 + tier2', () {
      expect(AnalyticsTier.known, {'tier1', 'tier2'});
      expect(AnalyticsTier.tier1, 'tier1');
      expect(AnalyticsTier.tier2, 'tier2');
    });
  });

  group('AnalyticsPlatform', () {
    test('known set includes the common platforms; unknown preserved', () {
      expect(AnalyticsPlatform.ios, 'ios');
      expect(AnalyticsPlatform.android, 'android');
      expect(AnalyticsPlatform.known, contains('ios'));
      expect(AnalyticsPlatform.known, contains('android'));
      expect(AnalyticsPlatform.isKnown('toaster'), isFalse);
    });
  });
}
