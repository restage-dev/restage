// @dart=3.13
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../../widgets/plan_badge.dart';

part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const next = OnboardingEvent<void>('next');

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PlanBadge(label: 'New', weight: FontWeight.normal),
        ),
        const PlanNote(text: 'Two minutes'),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton(
            onPressed: onboardingEvent(next),
            child: Text('Continue', textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
