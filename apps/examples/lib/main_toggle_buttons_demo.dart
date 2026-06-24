// Device smoke for the compiled multi-toggle — RestageToggleButtons rendered
// directly with live isSelected state. This is the exact compiled widget a
// delivered ToggleButtons blob builds, so it validates the on-device render +
// interaction (toggle tap, the settled onPressed index, the selection update)
// without the build-time lowering step (which the e2e tests cover).
import 'package:flutter/material.dart';
import 'package:restage_material/restage_material.dart';

void main() => runApp(const _ToggleButtonsDemoApp());

class _ToggleButtonsDemoApp extends StatelessWidget {
  const _ToggleButtonsDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toggle-buttons smoke',
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
  // A multi-select formatting toolbar — any number of toggles can be on.
  static const _styleLabels = <String>['Bold', 'Italic', 'Underline'];
  final List<bool> _style = <bool>[true, false, false];

  // A single-select size picker — exactly one toggle on at a time.
  static const _sizeLabels = <String>['S', 'M', 'L', 'XL'];
  final List<bool> _size = <bool>[false, true, false, false];

  String get _styleSummary {
    final on = <String>[
      for (var i = 0; i < _style.length; i++)
        if (_style[i]) _styleLabels[i],
    ];
    return on.isEmpty ? '—' : on.join(', ');
  }

  String get _sizeSummary {
    final i = _size.indexWhere((on) => on);
    return i == -1 ? '—' : _sizeLabels[i];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('RestageToggleButtons')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text('Text style (multi-select)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RestageToggleButtons(
            isSelected: _style,
            onPressed: (i) => setState(() => _style[i] = !_style[i]),
            children: [
              for (final label in _styleLabels)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(label),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Size (single-select)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RestageToggleButtons(
            isSelected: _size,
            onPressed: (i) => setState(() {
              for (var j = 0; j < _size.length; j++) {
                _size[j] = j == i;
              }
            }),
            children: [
              for (final label in _sizeLabels)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(label),
                ),
            ],
          ),
          const SizedBox(height: 32),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Selected → style: $_styleSummary   size: $_sizeSummary',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
