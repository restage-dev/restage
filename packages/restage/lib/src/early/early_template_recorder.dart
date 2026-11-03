// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../delivery/surface_ref.dart';
import '../runtime/restage.dart';
import 'package:restage_shared/restage_shared.dart' show startupTemplateJson;

import 'early_request.dart';

/// The startup request template this app sends on [platform], recorded from the
/// SDK's own first batch.
///
/// Meant for a build step running under `flutter test`: it configures Restage
/// as the app does, waits for the first startup request, and returns its
/// template without sending anything.
Future<String> recordEarlyTemplate({
  required TargetPlatform platform,
  required String apiKey,
  required String baseUrl,
  required List<RestageSurfaceRef> surfaces,
  void Function()? registerWidgets,
  Duration timeout = const Duration(seconds: 20),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final recorded = Completer<String>();
  Restage.debugReset();
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  EarlyRequest.recorder = (url, key, request) async {
    final template = startupTemplateJson(url, key, request);
    if (template != null && !recorded.isCompleted) recorded.complete(template);
  };
  try {
    registerWidgets?.call();
    Restage.configureWithInstalledCatalog(
      apiKey: apiKey,
      baseUrl: baseUrl,
      surfaces: surfaces,
    );
    return await recorded.future.timeout(timeout);
  } finally {
    EarlyRequest.recorder = null;
    debugDefaultTargetPlatformOverride = previous;
    Restage.debugReset();
  }
}
