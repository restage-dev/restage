// #docregion complete-screen-source
import 'package:flutter/material.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/restage.dart';
import 'package:restage/widgetbook.dart' as wb;

part 'opaque_screen_proof.rsscreen.g.dart';

/// Native screen used to verify opaque A2UI and Widgetbook integration.
///
/// One authored class feeds RFW, A2UI, and Widgetbook in the normal build.
@a2ui.Config.usage('Use for the final action in a native onboarding flow.')
@ScreenSource(id: 'opaque_screen_proof')
final class OpaqueScreenProof extends StatelessWidget {
  /// Creates the proof screen.
  const OpaqueScreenProof({
    super.key,
    required this.title,
    this.enabled = true,
    this.tone = OpaqueScreenProofTone.calm,
    this.data = 'Customer data',
    this.context = 'Customer context',
    this.itemContext = 'Customer item context',
    this.restageA2uiStatus = OpaqueScreenProofTone.calm,
    this.description = 'Customer description',
    this.usage = 'Customer usage',
  });

  /// Event fired by the proof action.
  static const continueEvent = SurfaceEvent<String>('continue');

  /// Constructor-bound title retained by native targets.
  final String title;

  /// Constructor-bound state retained by native targets.
  @wb.Config.values([false])
  final bool enabled;

  /// Typed preview state retained by native targets.
  @wb.Config.allValues()
  final OpaqueScreenProofTone tone;

  /// Customer data retained under its exact Dart name.
  final String data;

  /// Customer context retained under its exact Dart name.
  final String context;

  /// Customer item context retained under its exact Dart name.
  final String itemContext;

  /// Customer enum retained despite matching a generated-local prefix.
  final OpaqueScreenProofTone restageA2uiStatus;

  /// Editable customer description shown beside Restage metadata.
  final String description;

  /// Editable customer usage shown beside Restage metadata.
  final String usage;

  // #docregion ordinary-flutter-composition
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        key: const ValueKey('opaque-screen-proof-action'),
        onPressed: surfaceEvent(continueEvent, 'preview'),
        child: const Text('Opaque screen proof'),
      ),
    );
  }

  // #enddocregion ordinary-flutter-composition
}

/// Typed state used to prove generated Widgetbook expansion.
enum OpaqueScreenProofTone { calm, urgent }

// #enddocregion complete-screen-source
