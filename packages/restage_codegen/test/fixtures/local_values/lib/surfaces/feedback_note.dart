import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/feedback_note.restage.g.dart';

@Screen(id: 'feedback_note', surface: Surface.general)
final class FeedbackNote extends StatefulWidget {
  const FeedbackNote({super.key});

  static const send = SurfaceEvent<Map<String, Object?>>('send');

  @override
  State<FeedbackNote> createState() => _FeedbackNoteState();
}

final class _FeedbackNoteState extends State<FeedbackNote> {
  String note = '';

  void clear() => setState(() => note = '');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(onChanged: (value) => setState(() => note = value)),
          Text(note),
          TextButton(onPressed: clear, child: const Text('Clear')),
          FilledButton(
            onPressed: surfaceEvent(FeedbackNote.send, {'note': note}),
            child: const Text('Send'),
          ),
        ],
      );
}
