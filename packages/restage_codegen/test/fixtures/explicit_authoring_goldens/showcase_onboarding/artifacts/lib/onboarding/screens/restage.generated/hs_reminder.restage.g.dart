part of '../hs_reminder.dart';

const hsReminderScreenRef = NeutralFlowScreenRef(
  id: 'hs_reminder',
  artifactPath: 'hs_reminder.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use hsReminderScreenRef')
abstract final class HsReminderScreenDescriptor {
  const HsReminderScreenDescriptor._();

  static const NeutralFlowScreenRef ref = hsReminderScreenRef;
}
