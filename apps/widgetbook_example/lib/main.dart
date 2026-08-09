import 'package:flutter/material.dart';
import 'package:restage_widgetbook_example/components.g.dart';
import 'package:widgetbook/widgetbook.dart';

void main() {
  runWidgetbook(
    Config(
      components: components,
      lightTheme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
    ),
  );
}
