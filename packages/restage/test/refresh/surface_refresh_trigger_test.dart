import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  tearDown(Restage.debugReset);

  test('precedence: widget override > per-surface override > global > empty',
      () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      liveRefresh: {SurfaceRefreshTrigger.appResume},
      liveRefreshOverrides: {
        'promo_card': {SurfaceRefreshTrigger.updateChannel},
        'checkout': <SurfaceRefreshTrigger>{},
      },
    );
    // Global fallback.
    expect(Restage.effectiveLiveRefreshTriggers('other'),
        {SurfaceRefreshTrigger.appResume});
    // Per-surface override replaces wholesale.
    expect(Restage.effectiveLiveRefreshTriggers('promo_card'),
        {SurfaceRefreshTrigger.updateChannel});
    expect(Restage.effectiveLiveRefreshTriggers('checkout'), isEmpty);
    // Widget override wins over everything.
    expect(
      Restage.effectiveLiveRefreshTriggers('promo_card',
          widgetOverride: {SurfaceRefreshTrigger.appResume}),
      {SurfaceRefreshTrigger.appResume},
    );
  });

  test('unconfigured default is empty (off)', () {
    Restage.configure(apiKey: 'rs_pk_test');
    expect(Restage.effectiveLiveRefreshTriggers('anything'), isEmpty);
  });

  test('debugReset clears the configured live-refresh sets and channel', () {
    Restage.configure(
      apiKey: 'rs_pk_test',
      liveRefresh: {SurfaceRefreshTrigger.appResume},
    );
    Restage.debugReset();
    expect(Restage.effectiveLiveRefreshTriggers('anything'), isEmpty);
    expect(Restage.configuredUpdateChannel, isNull);
  });
}
