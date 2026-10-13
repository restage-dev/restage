import 'package:restage_codegen/src/emit_utils.dart';

/// Optional version arguments shared by generated widget registrations.
List<String> widgetLibraryVersionArguments({
  int? capabilityVersion,
  int? compatibleSince,
}) =>
    [
      if (capabilityVersion != null) 'capabilityVersion: $capabilityVersion,',
      if (compatibleSince != null && compatibleSince > 1)
        'compatibleSince: $compatibleSince,',
    ];

/// Writes one custom library registration for the startup helper.
void writeWidgetLibraryRegistration(
  StringBuffer buffer, {
  required String library,
  required Map<String, String> builders,
  int? capabilityVersion,
  int? compatibleSince,
}) {
  buffer
    ..writeln('Restage.registerWidgetLibrary(')
    ..writeln('  $library,');
  for (final argument in widgetLibraryVersionArguments(
    capabilityVersion: capabilityVersion,
    compatibleSince: compatibleSince,
  )) {
    buffer.writeln('  $argument');
  }
  buffer.writeln('  widgets: const <RestageWidgetFactory>[');
  for (final entry in builders.entries) {
    buffer.writeln(
      '    RestageWidgetFactory(name: ${dartStringLiteral(entry.key)}, '
      'builder: ${entry.value}),',
    );
  }
  buffer
    ..writeln('  ],')
    ..writeln(');');
}
