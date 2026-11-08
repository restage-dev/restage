// #docregion readable-screen-source
import 'package:flutter/material.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/restage.dart';
import 'package:restage/widgetbook.dart' as wb;

part 'restage.generated/welcome_screen.restage.g.dart';

/// An onboarding screen with a Continue action.
@a2ui.Config.usage('Use for the first screen of a native onboarding flow.')
@Screen(id: 'welcome_screen', surface: Surface.onboarding)
final class WelcomeScreen extends StatelessWidget {
  /// Creates the screen.
  const WelcomeScreen({
    super.key,
    required this.title,
    this.tone = WelcomeScreenTone.calm,
  });

  /// Event fired by the Continue action.
  static const continueEvent = SurfaceEvent<String>('continue');

  /// The screen title.
  final String title;

  /// The screen's tone. Widgetbook previews each value.
  @wb.Config.allValues()
  final WelcomeScreenTone tone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: surfaceEvent(continueEvent, 'welcome'),
        child: Text(title),
      ),
    );
  }
}

/// The tone of a [WelcomeScreen].
enum WelcomeScreenTone { calm, urgent }
// #enddocregion readable-screen-source
