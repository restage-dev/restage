part of '../section_header_showcase.dart';

// ignore_for_file: type=lint, unnecessary_cast

const sectionHeaderShowcaseScreenRef = NeutralFlowScreenRef(
  id: 'section_header_showcase',
  artifactPath: 'section_header_showcase.rfw',
  version: 1,
  minClient: 17,
);

@Deprecated('Use sectionHeaderShowcaseScreenRef')
abstract final class SectionHeaderShowcaseScreenDescriptor {
  const SectionHeaderShowcaseScreenDescriptor._();

  static const NeutralFlowScreenRef ref = sectionHeaderShowcaseScreenRef;
}
