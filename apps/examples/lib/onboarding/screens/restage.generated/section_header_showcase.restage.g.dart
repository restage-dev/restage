part of '../section_header_showcase.dart';

const sectionHeaderShowcaseScreenRef = NeutralFlowScreenRef(
  id: 'section_header_showcase',
  artifactPath: 'section_header_showcase.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use sectionHeaderShowcaseScreenRef')
abstract final class SectionHeaderShowcaseScreenDescriptor {
  const SectionHeaderShowcaseScreenDescriptor._();

  static const NeutralFlowScreenRef ref = sectionHeaderShowcaseScreenRef;
}
