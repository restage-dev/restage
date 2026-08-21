part of '../apex_drop.dart';

const apexDropScreenRef = NeutralFlowScreenRef(
  id: 'apex_drop',
  artifactPath: 'apex_drop.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use apexDropScreenRef')
abstract final class ApexDropScreenDescriptor {
  const ApexDropScreenDescriptor._();

  static const NeutralFlowScreenRef ref = apexDropScreenRef;
}
