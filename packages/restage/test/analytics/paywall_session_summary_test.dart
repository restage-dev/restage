import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/analytics/paywall_session_summary.dart';

void main() {
  const summary = PaywallSessionSummary(
    sectionDwellMs: {'hero': 1200, 'plans': 800},
    maxScrollDepthPct: 80,
    tapCounts: {'cta': 2},
    sessionDurationMs: 4200,
    sectionsViewed: ['hero', 'plans'],
    instrumentationVersion: 1,
  );

  test('toProperties emits the exact Tier-2 property map', () {
    expect(summary.toProperties(), {
      'sectionDwellMs': {'hero': 1200, 'plans': 800},
      'maxScrollDepthPct': 80,
      'tapCounts': {'cta': 2},
      'sessionDurationMs': 4200,
      'sectionsViewed': ['hero', 'plans'],
      'instrumentationVersion': 1,
    });
  });

  test('fromProperties round-trips toProperties', () {
    expect(
      PaywallSessionSummary.fromProperties(summary.toProperties()),
      summary,
    );
  });

  test('fromProperties tolerates missing keys with safe defaults', () {
    final parsed = PaywallSessionSummary.fromProperties(const {});
    expect(parsed.sectionDwellMs, isEmpty);
    expect(parsed.maxScrollDepthPct, 0);
    expect(parsed.tapCounts, isEmpty);
    expect(parsed.sessionDurationMs, 0);
    expect(parsed.sectionsViewed, isEmpty);
    expect(parsed.instrumentationVersion, 0);
  });

  test('fromProperties coerces numeric + collection cell types', () {
    final parsed = PaywallSessionSummary.fromProperties(const {
      'sectionDwellMs': {'hero': 10},
      'maxScrollDepthPct': 55,
      'tapCounts': {'cta': 1},
      'sessionDurationMs': 999,
      'sectionsViewed': ['hero'],
      'instrumentationVersion': 2,
    });
    expect(parsed.sectionDwellMs['hero'], 10);
    expect(parsed.sectionsViewed, ['hero']);
    expect(parsed.instrumentationVersion, 2);
  });

  test('value equality + hashCode', () {
    const a = PaywallSessionSummary(
      sectionDwellMs: {'hero': 1},
      maxScrollDepthPct: 1,
      tapCounts: {'cta': 1},
      sessionDurationMs: 1,
      sectionsViewed: ['hero'],
      instrumentationVersion: 1,
    );
    const b = PaywallSessionSummary(
      sectionDwellMs: {'hero': 1},
      maxScrollDepthPct: 1,
      tapCounts: {'cta': 1},
      sessionDurationMs: 1,
      sectionsViewed: ['hero'],
      instrumentationVersion: 1,
    );
    const c = PaywallSessionSummary(
      sectionDwellMs: {'hero': 2},
      maxScrollDepthPct: 1,
      tapCounts: {'cta': 1},
      sessionDurationMs: 1,
      sectionsViewed: ['hero'],
      instrumentationVersion: 1,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
