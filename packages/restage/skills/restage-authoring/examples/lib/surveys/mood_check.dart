import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/mood_check.restage.g.dart';

/// A one-question survey. The selection lives in the surface's own state.
@Screen(id: 'mood_check', surface: Surface.survey)
final class MoodCheck extends StatefulWidget {
  const MoodCheck({super.key});

  static const submit = SurfaceEvent<String>('submit');
  static const remindMe = SurfaceEvent<bool>('remind_me');

  @override
  State<MoodCheck> createState() => _MoodCheckState();
}

class _MoodCheckState extends State<MoodCheck> {
  bool good = true;

  void pickGood() => setState(() => good = true);
  void pickBad() => setState(() => good = false);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('How was your week?'),
        ListTile(
          title: const Text('Good'),
          leading: Icon(
            good ? Icons.radio_button_checked : Icons.radio_button_off,
          ),
          onTap: pickGood,
        ),
        ListTile(
          title: const Text('Not great'),
          leading: Icon(
            good ? Icons.radio_button_off : Icons.radio_button_checked,
          ),
          onTap: pickBad,
        ),
        SwitchListTile(
          title: const Text('Remind me next week'),
          value: false,
          onChanged: surfaceEvent(MoodCheck.remindMe),
        ),
        FilledButton(
          onPressed: surfaceEvent(MoodCheck.submit, good ? 'good' : 'bad'),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
