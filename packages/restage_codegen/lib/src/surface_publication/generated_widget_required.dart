import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/islands/islands.dart';
import 'package:restage_codegen/src/issue.dart';

/// What first needs the generated widget in a build: a value the build
/// computes, an app widget the design places, a wrapper or a State the
/// generated widget keeps; null when the design needs none of them.
({String need, String? location})? generatedWidgetNeed({
  required List<HoistedValue> hoisted,
  required List<Island> islands,
  required MountSplit? split,
}) {
  for (final value in hoisted) {
    if (value.kind == HoistValueKind.itemIndex) continue;
    return (need: readableSource(value.label), location: value.location);
  }
  for (final island in islands) {
    return (need: island.widget, location: island.location);
  }
  for (final node in split?.shell ?? const []) {
    return (need: node.widget, location: node.location);
  }
  if (split?.state case final state?) {
    return (need: state.name, location: state.location);
  }
  return null;
}

/// Why a surface has no generated widget.
sealed class GeneratedWidgetMissing {
  const GeneratedWidgetMissing();
}

/// [file] has no `part` line for [partPath].
final class MissingPartLine extends GeneratedWidgetMissing {
  /// Creates the reason.
  const MissingPartLine(this.file, this.partPath);

  /// The library without the line.
  final String file;

  /// The generated part the line names.
  final String partPath;
}

/// A deprecated [annotation], whose replacement is [replacement].
final class LegacyAnnotation extends GeneratedWidgetMissing {
  /// Creates the reason.
  const LegacyAnnotation(this.annotation, this.replacement);

  /// The deprecated annotation, such as `@PaywallSource`.
  final String annotation;

  /// The annotation to use instead, such as `@Paywall`.
  final String replacement;
}

/// Refuses [screen], whose build needs [widget], which [missing] keeps from
/// being generated; null when nothing needs it.
Issue? generatedWidgetRequiredIssue({
  required IssueCode code,
  required String screen,
  required String widget,
  required GeneratedWidgetMissing missing,
  required String location,
  required List<HoistedValue> hoisted,
  required List<Island> islands,
  required MountSplit? split,
}) {
  final need = generatedWidgetNeed(
    hoisted: hoisted,
    islands: islands,
    split: split,
  );
  if (need == null) return null;
  final at = need.location ?? location;
  return Issue(
    code: code,
    message: switch (missing) {
      MissingPartLine(:final file, :final partPath) =>
        '`${need.need}` in `$screen` ($at) runs app code, which needs the '
            "generated `$widget`, and $file has no `part '$partPath';` "
            'line. Try adding that line to $file.',
      LegacyAnnotation(:final annotation, :final replacement) =>
        '`${need.need}` in `$screen` ($at) runs app code, which needs a '
            "generated widget, and `$annotation` doesn't generate one. Try "
            'annotating `$screen` with `$replacement` instead.',
    },
    location: at,
  );
}
