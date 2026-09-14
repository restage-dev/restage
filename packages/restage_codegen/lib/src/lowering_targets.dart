/// The catalog entries a compiled surface names for source that spells
/// something else — an interpolated `Text` as the rich-text entry, a `PageView`
/// as the pager, a sheet call as the declarative sheet.
///
/// The single place those pairings live. The surface compiler resolves the
/// entry it emits through them, and the app-vocabulary walk reads the same
/// tables so an app's over-the-air headroom stays closed under lowering. The
/// mapping runs source to entries and is one-to-many; the walk
/// over-approximates on purpose, because naming a spare entry costs one
/// builder while missing one blanks a delivered surface.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One catalog entry a lowering emits, and how the catalog is searched for it.
@immutable
final class LoweringTarget {
  /// Names the entry called [name], falling back to one whose `flutterType`
  /// ends with [flutterTypeSuffix].
  const LoweringTarget(this.name, {this.flutterTypeSuffix});

  /// The catalog entry name the emitted surface references.
  final String name;

  /// The `#`-qualified Flutter type to fall back to, for an entry whose
  /// catalog name derives differently from the constructor source spells.
  final String? flutterTypeSuffix;

  /// Every entry in [catalog] this target names, in catalog order. A caller
  /// needing exactly one picks from the list.
  List<WidgetEntry> resolve(Catalog catalog) {
    final byName = <WidgetEntry>[
      for (final widget in catalog.widgets)
        if (widget.name == name) widget,
    ];
    final suffix = flutterTypeSuffix;
    if (byName.isNotEmpty || suffix == null) return byName;
    return <WidgetEntry>[
      for (final widget in catalog.widgets)
        if (widget.flutterType.endsWith(suffix)) widget,
    ];
  }
}

/// The rich-text entry, whose catalog name derives from `Text.rich`.
const LoweringTarget kTextRichLowering =
    LoweringTarget('Text.rich', flutterTypeSuffix: '#Text.rich');

/// The entry a `Text` wrapping an `intl` currency format is rewritten to.
const LoweringTarget kPriceLowering = LoweringTarget('RestagePrice');

/// The entry a `Text` wrapping a plain `intl` number format is rewritten to.
const LoweringTarget kFormattedNumberLowering =
    LoweringTarget('RestageFormattedNumber');

/// The paged-surface entry a `PageView` is emitted as.
const LoweringTarget kPagerLowering = LoweringTarget('RestagePager');

/// The draggable-surface entry a `DraggableScrollableSheet` is emitted as.
const LoweringTarget kDraggableSheetLowering =
    LoweringTarget('RestageDraggableSheet');

/// The declarative sheet entry a Flutter sheet call is emitted as.
const LoweringTarget kModalSheetLowering = LoweringTarget('RestageModalSheet');

/// The single-select entry a `RadioGroup` is emitted as.
const LoweringTarget kRadioGroupLowering =
    LoweringTarget('RestageRadioGroupString');

/// The single-select entry a `DropdownButton` is emitted as.
const LoweringTarget kDropdownLowering =
    LoweringTarget('RestageDropdownString');

/// The multi-toggle entry a `ToggleButtons` is emitted as.
const LoweringTarget kToggleButtonsLowering =
    LoweringTarget('RestageToggleButtons');

/// The segmented-button entry a `SegmentedButton` is emitted as.
const LoweringTarget kSegmentedButtonLowering =
    LoweringTarget('RestageSegmentedButtonString');

/// Catalog entries a Flutter widget with no catalog entry of its own is
/// emitted as, keyed by the class name source spells. Every construction of
/// one of these lowers or is refused, so the whole row applies; callers gate
/// on the resolved framework identity so a look-alike does not.
const Map<String, List<LoweringTarget>> kAliasedWidgetLowerings = {
  'PageView': [kPagerLowering],
  'DraggableScrollableSheet': [kDraggableSheetLowering],
  'RadioGroup': [kRadioGroupLowering],
  'DropdownButton': [kDropdownLowering],
  'ToggleButtons': [kToggleButtonsLowering],
  'SegmentedButton': [kSegmentedButtonLowering],
};

/// Catalog entries a top-level Flutter call is emitted as, keyed by the
/// function name. `modalSheetFunctionOf` applies the framework-identity gate.
const Map<String, List<LoweringTarget>> kCallLowerings = {
  'showModalBottomSheet': [kModalSheetLowering],
  'showCupertinoSheet': [kModalSheetLowering],
};

/// Whether a `Text` construction is emitted as [kTextRichLowering]: the `rich`
/// constructor carries an inline-span tree, and an interpolated first argument
/// is rewritten into one. A `Text` also reaches [kPriceLowering] /
/// [kFormattedNumberLowering] when it wraps a recognised `intl` number format.
bool textLowersToRichText(InstanceCreationExpression expr) {
  if (instanceCreationMemberName(expr) == 'rich') return true;
  for (final argument in expr.argumentList.arguments) {
    if (argument is NamedExpression) continue;
    return argument is StringInterpolation;
  }
  return false;
}

/// Whether [invocation] spells the `Text.rich` constructor. A named
/// constructor stays a call where the analyzer has not rewritten it, so both
/// spellings are recognised.
bool isTextRichInvocation(MethodInvocation invocation) {
  final target = invocation.target;
  return target is SimpleIdentifier &&
      target.name == 'Text' &&
      invocation.methodName.name == 'rich';
}

/// The class name a construction spells. Analyzer 10+ moves the class onto the
/// import prefix and lifts the member onto the type name for a `const` named
/// constructor, so both spellings are read.
String instanceCreationTypeName(InstanceCreationExpression expr) {
  final prefix = expr.constructorName.type.importPrefix?.name.lexeme;
  if (prefix != null && expr.constructorName.name == null) return prefix;
  return expr.constructorName.type.name.lexeme;
}

/// The named-constructor name a construction spells, or `null` for the unnamed
/// constructor. Reads the same shift as [instanceCreationTypeName].
String? instanceCreationMemberName(InstanceCreationExpression expr) {
  final prefix = expr.constructorName.type.importPrefix?.name.lexeme;
  if (prefix != null && expr.constructorName.name == null) {
    return expr.constructorName.type.name.lexeme;
  }
  return expr.constructorName.name?.name;
}
