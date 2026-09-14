part of '../lumen_reminder.dart';

const lumenReminderScreenRef = NeutralFlowScreenRef(
  id: 'lumen_reminder',
  artifactPath: 'lumen_reminder.rfw',
  version: 1,
  minClient: 6,
);

@Deprecated('Use lumenReminderScreenRef')
abstract final class LumenReminderScreenDescriptor {
  const LumenReminderScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenReminderScreenRef;
}
