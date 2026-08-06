enum SeamMode { compact, expanded }

final class EnumSeamFixture {
  const EnumSeamFixture({
    required this.typedMode,
    required this.legacyMode,
  });

  final SeamMode typedMode;
  final SeamMode legacyMode;
}
