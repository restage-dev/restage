part of '../section_header_showcase.dart';

// ignore_for_file: type=lint

const sectionHeaderShowcaseScreenRef = NeutralFlowScreenRef(
  id: 'section_header_showcase',
  artifactPath: 'section_header_showcase.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use sectionHeaderShowcaseScreenRef')
abstract final class SectionHeaderShowcaseScreenDescriptor {
  const SectionHeaderShowcaseScreenDescriptor._();

  static const NeutralFlowScreenRef ref = sectionHeaderShowcaseScreenRef;
}
