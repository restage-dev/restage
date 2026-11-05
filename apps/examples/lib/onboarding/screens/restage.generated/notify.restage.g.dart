part of '../notify.dart';

// ignore_for_file: type=lint, unnecessary_cast

const notifyScreenRef = NeutralFlowScreenRef(
  id: 'notify',
  artifactPath: 'notify.rfw',
  version: 1,
  minClient: 17,
);

@Deprecated('Use notifyScreenRef')
abstract final class NotifyScreenDescriptor {
  const NotifyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = notifyScreenRef;
}
