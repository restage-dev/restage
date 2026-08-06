import 'package:flutter/widgets.dart';

/// Recursive data used to prove constrained rich-list `$defs` projection.
final class ConstraintRecursiveItem {
  const ConstraintRecursiveItem({required this.label, required this.children});

  final String label;
  final List<ConstraintRecursiveItem> children;
}

/// One real widget covering the constrained scalar/list projection seams.
final class ConstraintParityFixture extends StatelessWidget {
  const ConstraintParityFixture({
    required this.count,
    required this.tags,
    required this.ratio,
    required this.code,
    required this.items,
    required this.legacyCount,
    required this.legacyMode,
    required this.legacyCode,
    required this.onCountChanged,
    super.key,
  });

  final int? count;
  final List<String>? tags;
  final double ratio;
  final String code;
  final List<ConstraintRecursiveItem>? items;
  final double legacyCount;
  final String legacyMode;
  final String legacyCode;
  final ValueChanged<int?> onCountChanged;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Real constructor surface for every typed and legacy accepted pattern case.
final class PatternCorpusFixture extends StatelessWidget {
  const PatternCorpusFixture({
    required String typedPattern,
    required String legacyPattern,
    super.key,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
