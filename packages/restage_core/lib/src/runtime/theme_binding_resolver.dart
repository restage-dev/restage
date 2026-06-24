import 'package:flutter/material.dart';

/// Resolves a theme-binding default to a concrete value from the active
/// Flutter theme. [path] is a dot-path naming a known theme location;
/// [context] supplies the active theme.
///
/// Returns `null` for an unrecognized [path] — the caller then falls
/// through to the widget's own constructor default.
///
/// The recognized path set mirrors the catalog's built-in theme-binding
/// seeds. It is a closed switch by design: the runtime never interprets
/// an arbitrary path expression.
Object? resolveThemeBinding(BuildContext context, {required String path}) {
  final theme = Theme.of(context);
  final textStyle = DefaultTextStyle.of(context).style;
  switch (path) {
    // colorScheme family
    case 'colorScheme.primary':
      return theme.colorScheme.primary;
    case 'colorScheme.onPrimary':
      return theme.colorScheme.onPrimary;
    case 'colorScheme.surface':
      return theme.colorScheme.surface;
    // iconTheme family
    case 'iconTheme.color':
      return theme.iconTheme.color;
    case 'iconTheme.size':
      return theme.iconTheme.size;
    // defaultTextStyle family
    case 'defaultTextStyle.color':
      return textStyle.color;
    case 'defaultTextStyle.fontSize':
      return textStyle.fontSize;
    case 'defaultTextStyle.fontWeight':
      return textStyle.fontWeight;
    default:
      return null;
  }
}
