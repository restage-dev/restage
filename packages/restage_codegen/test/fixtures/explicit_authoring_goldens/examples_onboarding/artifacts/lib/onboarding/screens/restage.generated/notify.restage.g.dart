part of '../notify.dart';

const notifyScreenRef = NeutralFlowScreenRef(
  id: 'notify',
  artifactPath: 'notify.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use notifyScreenRef')
abstract final class NotifyScreenDescriptor {
  const NotifyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = notifyScreenRef;
}
