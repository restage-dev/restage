// #docregion complete-screen-source
import 'package:flutter/material.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/restage.dart';
import 'package:restage/widgetbook.dart' as wb;

part 'restage.generated/get_started_screen.restage.g.dart';

/// An onboarding screen with a Get started action.
///
/// One authored class feeds RFW, A2UI, and Widgetbook in the normal build.
@a2ui.Config.usage('Use for the final action in a native onboarding flow.')
@Screen(id: 'get_started_screen', surface: Surface.onboarding)
final class GetStartedScreen extends StatelessWidget {
  /// Creates the screen.
  const GetStartedScreen({
    super.key,
    required this.title,
    this.enabled = true,
    this.tone = GetStartedScreenTone.calm,
    this.data = 'Example data',
    this.context = 'Example context',
    this.itemContext = 'Example item context',
    this.restageA2uiStatus = GetStartedScreenTone.calm,
    this.description = 'Example description',
    this.usage = 'Example usage',
  });

  /// Event fired by the Get started action.
  static const continueEvent = SurfaceEvent<String>('continue');

  /// Constructor-bound title retained by native targets.
  final String title;

  /// Constructor-bound state retained by native targets.
  @wb.Config.values([false])
  final bool enabled;

  /// Typed preview state retained by native targets.
  @wb.Config.allValues()
  final GetStartedScreenTone tone;

  /// A field named `data`, kept under its exact Dart name.
  final String data;

  /// A field named `context`, kept under its exact Dart name.
  final String context;

  /// A field named `itemContext`, kept under its exact Dart name.
  final String itemContext;

  /// An enum field whose name matches a generated-code prefix; still kept.
  final GetStartedScreenTone restageA2uiStatus;

  /// An editable `description` property shown beside Restage metadata.
  final String description;

  /// An editable `usage` property shown beside Restage metadata.
  final String usage;

  // #docregion ordinary-flutter-composition
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        key: const ValueKey('get-started-action'),
        onPressed: surfaceEvent(continueEvent, 'preview'),
        child: const Text('Get started'),
      ),
    );
  }

  // #enddocregion ordinary-flutter-composition
}

/// Typed state used to prove generated Widgetbook expansion.
enum GetStartedScreenTone { calm, urgent }

// #enddocregion complete-screen-source
