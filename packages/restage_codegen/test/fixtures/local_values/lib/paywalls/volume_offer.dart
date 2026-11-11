import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/volume_offer.restage.g.dart';

@Paywall()
class VolumeOffer extends StatefulWidget {
  const VolumeOffer({super.key});

  @override
  State<VolumeOffer> createState() => _VolumeOfferState();
}

class _VolumeOfferState extends State<VolumeOffer> {
  bool reminders = true;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Switch(
            value: reminders,
            onChanged: (on) => setState(() => reminders = on),
          ),
          TextButton(
            onPressed: context.surfaceEvent(_Events.continueEvent, {'reminders': reminders}),
            child: const Text('Continue'),
          ),
        ],
      );
}

abstract final class _Events {
  static const continueEvent = SurfaceEvent<Map<String, Object?>>('continue');
}
