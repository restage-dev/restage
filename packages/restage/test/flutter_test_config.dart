import 'dart:async';

import 'package:restage/restage.dart';

/// Installs the whole built-in widget catalog for every test in this package,
/// so a test that mounts a surface renders the widgets that surface names.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  await testMain();
}
