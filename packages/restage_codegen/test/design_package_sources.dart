/// Synthetic stand-ins for the design-system packages that carry copies of the
/// framework's material / cupertino layers.
///
/// These are not mocks of convenience: the library URIs, the class names, and
/// the named constructors below were read off the real published packages
/// (`material_ui 1.0.0` / `cupertino_ui 1.0.0`) with the analyzer, and every
/// URI here appears verbatim in `test/fixtures/design_package_compat/`.
/// Everything the toolchain reads from one of these constructions — the
/// defining library URI, the class name, the constructor name — is therefore
/// identical to what the real packages produce.
///
/// They exist as sources rather than as a dependency because the real packages
/// cannot join this workspace's resolution: they pull a localization package
/// that pins a version a workspace sibling disagrees with. See the fixture
/// README.
library;

import 'package:build/build.dart';

/// The synthetic design-package sources, keyed by asset id.
final Map<AssetId, String> kDesignPackageSources = {
  for (final entry in _sources.entries) AssetId.parse(entry.key): entry.value,
};

/// Whether any of [sources] imports one of the design packages, so the helper
/// seeds these sources only for the tests that need them.
bool importsDesignPackages(Iterable<String> sources) => sources.any(
      (source) =>
          source.contains('package:material_ui/') ||
          source.contains('package:cupertino_ui/'),
    );

const Map<String, String> _sources = {
  'material_ui|lib/material_ui.dart': '''
export 'package:flutter/widgets.dart';

export 'src/button_style.dart';
export 'src/card.dart';
export 'src/color_scheme.dart';
export 'src/filled_button.dart';
export 'src/scaffold.dart';
export 'src/snack_bar_theme.dart';
export 'src/theme.dart';
export 'src/theme_data.dart';
''',
  'material_ui|lib/src/scaffold.dart': '''
import 'package:flutter/widgets.dart';

class Scaffold extends StatefulWidget {
  const Scaffold({super.key, this.backgroundColor, this.body});

  final Color? backgroundColor;
  final Widget? body;

  @override
  State<Scaffold> createState() => ScaffoldState();
}

class ScaffoldState extends State<Scaffold> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
  'material_ui|lib/src/card.dart': '''
import 'package:flutter/widgets.dart';

class Card extends StatelessWidget {
  const Card({super.key, this.child});

  const Card.filled({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => child ?? const SizedBox();
}
''',
  'material_ui|lib/src/filled_button.dart': '''
import 'package:flutter/widgets.dart';

import 'button_style.dart';

class FilledButton extends StatelessWidget {
  const FilledButton({super.key, this.onPressed, this.child, this.style});

  const FilledButton.tonal({
    super.key,
    this.onPressed,
    this.child,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget? child;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) => child ?? const SizedBox();
}
''',
  'material_ui|lib/src/button_style.dart': '''
import 'package:flutter/widgets.dart';

class ButtonStyle {
  const ButtonStyle({this.backgroundColor, this.elevation});

  // Shaped like the real one: the field types are framework state properties,
  // so this class is admissible only as a FRAMEWORK value type — never as a
  // customer structured type. That is what makes it exercise the catalog's
  // structured-type join rather than customer structured discovery.
  final WidgetStateProperty<Color?>? backgroundColor;
  final WidgetStateProperty<double?>? elevation;
}
''',
  'material_ui|lib/src/snack_bar_theme.dart': '''
enum SnackBarBehavior { fixed, floating }
''',
  'material_ui|lib/src/color_scheme.dart': '''
import 'package:flutter/widgets.dart';

class ColorScheme {
  const ColorScheme({required this.surface, required this.primary});

  final Color surface;
  final Color primary;
}
''',
  'material_ui|lib/src/theme_data.dart': '''
import 'color_scheme.dart';

class ThemeData {
  const ThemeData({required this.colorScheme});

  final ColorScheme colorScheme;
}
''',
  'material_ui|lib/src/theme.dart': '''
import 'package:flutter/widgets.dart';

import 'color_scheme.dart';
import 'theme_data.dart';

class Theme extends StatelessWidget {
  const Theme({required this.data, required this.child, super.key});

  final ThemeData data;
  final Widget child;

  static ThemeData of(BuildContext context) => const ThemeData(
        colorScheme: ColorScheme(
          surface: Color(0xFF000000),
          primary: Color(0xFF000000),
        ),
      );

  @override
  Widget build(BuildContext context) => child;
}
''',
  'cupertino_ui|lib/cupertino_ui.dart': '''
export 'package:flutter/widgets.dart';

export 'src/button.dart';
''',
  'cupertino_ui|lib/src/button.dart': '''
import 'package:flutter/widgets.dart';

class CupertinoButton extends StatelessWidget {
  const CupertinoButton({required this.onPressed, this.child, super.key});

  final VoidCallback? onPressed;
  final Widget? child;

  @override
  Widget build(BuildContext context) => child ?? const SizedBox();
}
''',
};
