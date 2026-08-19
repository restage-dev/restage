import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/categorized_screens.restage.g.dart';

@Screen(id: 'onboarding_welcome', surface: Surface.onboarding)
final class OnboardingWelcome extends StatelessWidget {
  const OnboardingWelcome({super.key});

  static const continueFlow = SurfaceEvent<void>('continue');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: surfaceEvent(continueFlow),
        child: const Text('Continue'),
      );
}

@Screen(id: 'message_notice', surface: Surface.message)
final class MessageNotice extends StatelessWidget {
  const MessageNotice({super.key});

  static const openOffer = SurfaceEvent<void>('open_offer');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: surfaceEvent(openOffer),
        child: const Text('Open offer'),
      );
}

@Screen(id: 'general_status', surface: Surface.general)
final class GeneralStatus extends StatelessWidget {
  const GeneralStatus({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: surfaceEvent(finish),
        child: const Text('Done'),
      );
}
