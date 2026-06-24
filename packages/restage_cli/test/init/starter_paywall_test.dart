import 'package:restage_cli/src/init/starter_paywall.dart';
import 'package:test/test.dart';

void main() {
  group('starterPaywallSource', () {
    test('emits a valid annotated widget for a single-word slug', () {
      final src = starterPaywallSource('starter');
      expect(src, contains("@PaywallSource(id: 'starter')"));
      expect(src, contains('class StarterPaywall extends StatelessWidget'));
      expect(src, contains("import 'package:flutter/material.dart';"));
      expect(src, contains("import 'package:restage/restage.dart';"));
    });

    test('pascal-cases a slug with dashes', () {
      final src = starterPaywallSource('pro-upgrade');
      expect(src, contains('class ProUpgradePaywall'));
      expect(src, contains("@PaywallSource(id: 'pro-upgrade')"));
    });

    test('pascal-cases a slug with underscores', () {
      final src = starterPaywallSource('hello_world');
      expect(src, contains('class HelloWorldPaywall'));
    });
  });
}
