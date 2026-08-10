import 'package:flutter/material.dart';

typedef SpikeMeta = ({String label, int count});

final class SpikeNode {
  const SpikeNode({required this.label, this.child});

  final String label;
  final SpikeNode? child;
}

final class PropsNamespaceProbe extends StatelessWidget {
  const PropsNamespaceProbe({
    required this.id,
    required this.component,
    required this.catalogId,
    required this.props,
    required this.literalValue,
    required this.pathValue,
    required this.callValue,
    required this.node,
    required this.counts,
    required this.meta,
    required this.leading,
    required this.children,
    required this.enabled,
    required this.onAction,
    required this.onEnabledChanged,
    super.key,
  });

  final String id;
  final String component;
  final String catalogId;
  final String props;
  final String literalValue;
  final String pathValue;
  final String callValue;
  final SpikeNode node;
  final Map<String, int> counts;
  final SpikeMeta meta;
  final Widget leading;
  final List<Widget> children;
  final bool enabled;
  final VoidCallback onAction;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          Text('collisions:$id|$component|$catalogId|$props'),
          Text('bindings:$literalValue|$pathValue|$callValue'),
          Text('recursive:${node.label}|${node.child?.label}'),
          Text(
            'structured:${entries.map((entry) => '${entry.key}:${entry.value}').join(',')}|'
            '${meta.label}:${meta.count}',
          ),
          leading,
          ...children,
          Text('enabled:$enabled'),
          TextButton(
            key: const ValueKey<String>('props-spike-action'),
            onPressed: onAction,
            child: const Text('dispatch'),
          ),
          TextButton(
            key: const ValueKey<String>('props-spike-writeback'),
            onPressed: () => onEnabledChanged(!enabled),
            child: const Text('write back'),
          ),
        ],
      ),
    );
  }
}

final class PropsNamespaceLeaf extends StatelessWidget {
  const PropsNamespaceLeaf({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text('leaf:$label');
}
