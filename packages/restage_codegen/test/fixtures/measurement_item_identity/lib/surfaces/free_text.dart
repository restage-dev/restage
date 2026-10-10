import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/free_text.restage.g.dart';

@Screen(id: 'free_text', surface: Surface.general)
final class FreeText extends StatelessWidget {
  const FreeText({super.key});

  static const typed = SurfaceEvent<String>('typed');
  static const sent = SurfaceEvent<String>('sent');
  static const done = SurfaceEvent<void>('done');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(
            onChanged: surfaceEvent(typed),
            onSubmitted: surfaceEvent(sent),
          ),
          CupertinoTextField(
            onChanged: surfaceEvent(typed),
            onSubmitted: surfaceEvent(sent),
          ),
          FilledButton(
            onPressed: surfaceEvent(done),
            child: const Text('Done'),
          ),
        ],
      );
}
