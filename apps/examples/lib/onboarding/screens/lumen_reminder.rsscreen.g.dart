part of 'lumen_reminder.dart';

abstract final class LumenReminderScreenDescriptor {
  const LumenReminderScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'lumen_reminder',
    artifactPath: 'lumen_reminder.rfw',
    version: 1,
    minClient: 1,
  );
}
