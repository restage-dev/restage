import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'messages/weekly_recap.dart';
import 'onboarding/first_run.dart';
import 'paywalls/pro_upgrade.dart';
import 'restage_surfaces.g.dart';
import 'surveys/mood_check.dart';
import 'user_factories.g.dart';

void main() {
  Restage.configure(
    // Carries api_key, base_url and delivery_keys from build.yaml.
    registerWidgets: kRestageWidgetRegistration,
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
          // The default placement needs no name. Until delivered content is
          // available, the mount renders WeeklyRecap's own build.
          WeeklyRecapSurface(
            name: 'Sam',
            streakDays: 12,
            onEvent: (event) => switch (event) {
              WeeklyRecapSurfaceDismissEvent() => debugPrint('dismissed'),
              WeeklyRecapSurfaceOpenStatsEvent(:final value) => debugPrint(
                  'open stats: $value',
                ),
            },
          ),
          MoodCheckSurface(
            onEvent: (event) => switch (event) {
              MoodCheckSurfaceSubmitEvent(:final arguments) => debugPrint(
                  'mood: ${arguments['mood']}, note: ${arguments['note']}',
                ),
              MoodCheckSurfaceRemindMeEvent(:final value) =>
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
                  onClose: () => Navigator.of(context).pop(),
                  // Your store call; true once the trial started.
                  onStartTrial: () async => true,
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
