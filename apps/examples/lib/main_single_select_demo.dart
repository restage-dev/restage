// Device smoke for the compiled single-select pair — RestageRadioGroup and
// RestageDropdown rendered directly with live selection state. These are the
// exact compiled widgets a delivered RadioGroup / DropdownButton blob builds,
// so this validates the on-device render + interaction (radio tap, dropdown
// overlay) without the build-time lowering step (which the e2e tests cover).
import 'package:flutter/material.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_material/restage_material.dart';

const _plans = <RestageSelectionOption>[
  RestageSelectionOption(value: 'basic', label: r'Basic — $4.99 / mo'),
  RestageSelectionOption(value: 'pro', label: r'Pro — $9.99 / mo'),
  RestageSelectionOption(value: 'team', label: r'Team — $19.99 / mo'),
];

const _regions = <RestageSelectionOption>[
  RestageSelectionOption(value: 'us', label: 'United States'),
  RestageSelectionOption(value: 'eu', label: 'Europe'),
  RestageSelectionOption(value: 'apac', label: 'Asia-Pacific'),
];

void main() => runApp(const _SingleSelectDemoApp());

class _SingleSelectDemoApp extends StatelessWidget {
  const _SingleSelectDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Single-select smoke',
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
  String? _plan = 'pro';
  String? _region = 'us';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('RestageRadioGroup + RestageDropdown')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text('Choose a plan', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RestageRadioGroup<String>(
            items: _plans,
            selected: _plan,
            onChanged: (v) => setState(() => _plan = v),
          ),
          const SizedBox(height: 28),
          Text('Region', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RestageDropdown<String>(
            items: _regions,
            selected: _region,
            isExpanded: true,
            onChanged: (v) => setState(() => _region = v),
          ),
          const SizedBox(height: 32),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Selected → plan: ${_plan ?? "—"}   region: ${_region ?? "—"}',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
