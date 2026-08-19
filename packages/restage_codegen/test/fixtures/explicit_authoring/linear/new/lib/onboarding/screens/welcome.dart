import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@Screen()
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: surfaceEvent(next),
      child: const Text('Continue'),
    );
  }
}
