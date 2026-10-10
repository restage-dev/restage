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
      mainAxisAlignment: .center,
      children: [
        Align(
          alignment: .centerLeft,
          child: PlanBadge(label: 'New', weight: .normal),
        ),
        const PlanNote(text: 'Two minutes'),
        Padding(
          padding: const .only(top: 12),
          child: FilledButton(
            onPressed: onboardingEvent(next),
            child: Text('Continue', textAlign: .center),
          ),
        ),
      ],
    );
  }
}
