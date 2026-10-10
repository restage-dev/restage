import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/sheet_notice.restage.g.dart';

@Screen(id: 'sheet_notice', surface: Surface.general)
final class SheetNotice extends StatelessWidget {
  const SheetNotice({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isDismissible: true,
              builder: (_) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('Choose your plan'),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ],
      );
}
