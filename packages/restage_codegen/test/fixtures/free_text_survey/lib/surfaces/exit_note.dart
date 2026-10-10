import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/exit_note.restage.g.dart';

@Screen(id: 'exit_note', surface: Surface.survey)
class ExitNoteScreen extends StatefulWidget {
  static const submit = SurfaceEvent<String>('submit');

  const ExitNoteScreen({super.key});

  @override
  State<ExitNoteScreen> createState() => _ExitNoteScreenState();
}

class _ExitNoteScreenState extends State<ExitNoteScreen> {
  String note = '';

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(
            decoration: const InputDecoration(hintText: 'Anything else?'),
            onChanged: (value) => setState(() => note = value),
          ),
          FilledButton(
            onPressed: surfaceEvent(ExitNoteScreen.submit, note),
            child: const Text('Send'),
          ),
        ],
      );
}
