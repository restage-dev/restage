import 'package:flutter/material.dart';

/// The resolver the frozen registrations call; removed from restage_core.
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
      return IconTheme.of(context).color;
    case 'iconTheme.size':
      return IconTheme.of(context).size;
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
