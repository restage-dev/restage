// Device smoke for the compiled segmented control — RestageSegmentedButton
// rendered directly with live selection state. This is the exact compiled
// widget a delivered SegmentedButton blob builds, so it validates the on-device
// render + interaction (segment tap, the settled segment-ordered list onChanged,
// single- and multi-select) without the build-time lowering step (which the e2e
// tests cover). The multi-select group exercises the chapter's first
// list-valued event end to end.
import 'package:flutter/material.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_material/restage_material.dart';

const _plans = <RestageSelectionOption>[
  RestageSelectionOption(value: 'basic', label: 'Basic'),
  RestageSelectionOption(value: 'pro', label: 'Pro'),
  RestageSelectionOption(value: 'team', label: 'Team'),
];

const _filters = <RestageSelectionOption>[
  RestageSelectionOption(value: 'music', label: 'Music'),
  RestageSelectionOption(value: 'podcasts', label: 'Podcasts'),
  RestageSelectionOption(value: 'books', label: 'Books'),
];

void main() => runApp(const _SegmentedButtonDemoApp());

class _SegmentedButtonDemoApp extends StatelessWidget {
  const _SegmentedButtonDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Segmented-button smoke',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  // Single-select: exactly one plan.
  String _plan = 'pro';

  // Multi-select: any subset of filters, reported in segment order.
  List<String> _selectedFilters = <String>['music', 'books'];

  String get _filterSummary =>
      _selectedFilters.isEmpty ? '—' : _selectedFilters.join(', ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('RestageSegmentedButton')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text('Plan (single-select)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RestageSegmentedButton<String>(
            items: _plans,
            selected: <String>[_plan],
            onChanged: (values) => setState(() {
              if (values.isNotEmpty) _plan = values.first;
            }),
          ),
          const SizedBox(height: 28),
          Text('Library filters (multi-select)',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RestageSegmentedButton<String>(
            items: _filters,
            selected: _selectedFilters,
            multiSelectionEnabled: true,
            emptySelectionAllowed: true,
            onChanged: (values) => setState(() => _selectedFilters = values),
          ),
          const SizedBox(height: 32),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Selected → plan: $_plan   filters: $_filterSummary',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
