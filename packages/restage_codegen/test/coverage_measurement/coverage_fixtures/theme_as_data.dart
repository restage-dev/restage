// Theme-as-data coverage fixtures — exercise the `Theme.of(context).…`
// recognition path that lowers to `data.theme.*` references. These
// fixtures import real `package:flutter/material.dart` so the
// classifier's element-resolution gate (which requires the resolved
// `Theme` to come from `package:flutter/`) fires.
//
// Local stub widgets (`Box`) act as catalog widgets — declared with a
// non-Flutter name so they don't conflict with Flutter's `Container`.
//
// ignore_for_file: annotate_overrides
// The fixture imports real `package:flutter/material.dart` for the
// theme-of resolution path; it is not declared in `restage_codegen`'s
// pubspec because the file resolves under `apps_examples`'s deps via
// the test harness's reader, not under `restage_codegen` itself.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Box extends StatelessWidget {
  const Box({this.child, this.color, super.key});
  final Widget? child;
  final Color? color;
  Widget build(BuildContext context) => const SizedBox();
}

// ─── inlinable / + theme-as-data ──────────────────────────────────────
// A standalone `Theme.of(context).colorScheme.primary` read.
@RestageWidget(
  name: 'ThemePill',
  library: WidgetLibrary.custom('coverage.theme'),
  category: WidgetCategory.decoration,
  description: 'pill — colourScheme.primary read',
)
class ThemePill extends StatelessWidget {
  const ThemePill({super.key});
  Widget build(BuildContext context) =>
      Box(color: Theme.of(context).colorScheme.primary);
}
