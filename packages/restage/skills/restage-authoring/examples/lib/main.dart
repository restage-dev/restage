import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'messages/weekly_recap.dart';
import 'onboarding/first_run.dart';
import 'paywalls/pro_upgrade.dart';
import 'restage_surfaces.g.dart';
import 'surveys/mood_check.dart';

const _baseUrl = 'https://api.restage.dev';
// The public SDK key (rs_pk_...) for the environment to serve.
const _apiKey = String.fromEnvironment('RESTAGE_API_KEY');

void main() {
  Restage.configure(
    apiKey: _apiKey.isEmpty ? null : _apiKey,
    baseUrl: _apiKey.isEmpty ? null : _baseUrl,
    // Fetch every surface in the background at startup.
    surfaces: restageSurfaces,
  );
  runApp(const MaterialApp(home: HomePage()));
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          WeeklyRecapSurface(
            name: 'Sam',
            streakDays: 12,
            onEvent: (event) => switch (event) {
              WeeklyRecapDismissEvent() => debugPrint('dismissed'),
              WeeklyRecapOpenStatsEvent(:final value) => debugPrint(
                  'open stats: $value',
                ),
            },
          ),
          MoodCheckSurface(
            onEvent: (event) => switch (event) {
              MoodCheckSubmitEvent(:final arguments) => debugPrint(
                  'mood: ${arguments['mood']}, note: ${arguments['note']}',
                ),
              MoodCheckRemindMeEvent(:final value) =>
                debugPrint('remind: $value'),
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: FirstRunSurface(
                    onComplete: (result) {
                      debugPrint('goal: ${result.goal}');
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
            ),
            child: const Text('Onboarding'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProUpgradePaywallSurface(
                  onEvent: (event) {
                    if (event is PaywallCustomEvent &&
                        event.eventName == 'close') {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
            ),
            child: const Text('Paywall'),
          ),
        ],
      ),
    );
  }
}
