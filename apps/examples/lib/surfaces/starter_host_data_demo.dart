import 'package:flutter/material.dart';

import 'starter_host_data.dart';

/// Gallery host for the host-data starter.
///
/// The app owns the rows. It passes them to the generated
/// `StarterChecklistSurface` like any other widget arguments, and when a row
/// is tapped it updates its own list and passes the new one in. Only the row
/// that changed is rebuilt in the delivered surface.
class StarterHostDataDemo extends StatefulWidget {
  /// Creates the host-data gallery host.
  const StarterHostDataDemo({super.key});

  @override
  State<StarterHostDataDemo> createState() => _StarterHostDataDemoState();
}

class _StarterHostDataDemoState extends State<StarterHostDataDemo> {
  static const _tasks = <(String, String)>[
    ('profile', 'Fill in your profile'),
    ('invite', 'Invite a teammate'),
    ('sync', 'Turn on sync'),
  ];
  final _done = <String>{};

  @override
  Widget build(BuildContext context) {
    return StarterChecklistSurface(
      owner: 'Sam',
      items: [
        for (final (id, title) in _tasks)
          ChecklistItem(
            id: id,
            title: title,
            status: _done.contains(id) ? 'Done' : 'To do',
          ),
      ],
      onEvent: (event) {
        if (event is StarterChecklistToggleEvent) {
          setState(() {
            if (!_done.remove(event.value)) _done.add(event.value);
          });
        }
      },
    );
  }
}
