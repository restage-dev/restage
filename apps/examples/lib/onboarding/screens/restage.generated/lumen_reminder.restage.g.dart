part of '../lumen_reminder.dart';

abstract final class LumenReminderScreenDescriptor {
  const LumenReminderScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'lumen_reminder',
    artifactPath: 'lumen_reminder.rfw',
    version: 1,
    minClient: 1,
  );
}
