import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/stray_offer.restage.g.dart';

@Paywall(completesOn: [StrayOffer.subscribe])
class StrayOffer extends StatelessWidget {
  const StrayOffer({super.key});

  static const subscribe = SurfaceEvent<Map<String, Object?>>('subscribe');

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(_Events.close),
        child: const Text('Not now'),
      );
}

abstract final class _Events {
  static const close = SurfaceEvent<void>('close');
}
