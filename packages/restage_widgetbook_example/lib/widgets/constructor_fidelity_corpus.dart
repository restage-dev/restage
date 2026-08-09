import 'package:flutter/material.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show ignore;

/// Finite customer state used by the constructor-fidelity corpus.
enum ConstructorCorpusMode {
  /// The fixture is ready.
  ready,

  /// The fixture is processing.
  processing,
}

/// Nested customer-owned immutable data.
class ConstructorCorpusNestedData {
  /// Creates nested corpus data.
  const ConstructorCorpusNestedData({required this.label});

  /// Nested label.
  final String label;
}

/// Customer-owned structured data with one nested object.
class ConstructorCorpusData {
  /// Creates structured corpus data.
  const ConstructorCorpusData({required this.nested, required this.count});

  /// Nested customer object.
  final ConstructorCorpusNestedData nested;

  /// Customer-owned scalar nested beside the object.
  final int count;
}

/// Public constants whose defining identities must survive reconstruction.
abstract final class ConstructorCorpusDefaults {
  /// Public static Flutter constant.
  static const Color publicColor = Color(0xFF224466);

  /// Public static customer-structured constant.
  static const ConstructorCorpusData publicData = ConstructorCorpusData(
    nested: ConstructorCorpusNestedData(label: 'nested-default'),
    count: 2,
  );
}

/// Generic super-formal source used to prove resolved substitution.
abstract class ConstructorCorpusBase<T> extends StatelessWidget {
  /// Creates a generic corpus base.
  const ConstructorCorpusBase({super.key, required this.value});

  /// Generic value inherited by the concrete customer widget.
  final T value;
}

/// Broad reusable fixture for accepted named constructor shapes.
@a2ui.Config(
  usage: 'Use to verify accepted constructor, default, and callback families.',
  writeBackValues: <String, String>{
    'whenEnabledChanges': 'enabled',
    'reportCount': 'count',
  },
)
@RestageWidget(
  name: 'ConstructorFidelityCorpus',
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  category: WidgetCategory.input,
)
class ConstructorFidelityCorpus extends ConstructorCorpusBase<String> {
  /// Creates the broad named-shape corpus.
  const ConstructorFidelityCorpus({
    super.key,
    required super.value,
    // This ordinary one-to-one binding is an intentional corpus witness.
    required String ordinaryLabel,
    required this.requiredNamed,
    // The explicit spelling distinguishes this from an implicit null default.
    // ignore: avoid_init_to_null
    this.nullableText = null,
    this.nullableSeed = 'nullable-default',
    this.enabled = true,
    this.count = 7,
    this.mode = ConstructorCorpusMode.ready,
    this.directColor = const Color(0xFF112233),
    this.publicColor = ConstructorCorpusDefaults.publicColor,
    this.data = ConstructorCorpusDefaults.publicData,
    required this.resetProof,
    required this.whenEnabledChanges,
    required this.reportCount,
    this.focusNode,
    @ignore this.localOnly = 'local-only',
    // ignore: prefer_initializing_formals
  }) : ordinaryLabel = ordinaryLabel;

  /// Ordinary one-to-one constructor binding.
  final String ordinaryLabel;

  /// Required named field formal.
  final String requiredNamed;

  /// Explicit nullable null default.
  final String? nullableText;

  /// Nullable input with a non-null constructor default.
  final String? nullableSeed;

  /// Scalar constructor default and write-back candidate.
  final bool enabled;

  /// Integer constructor default and second write-back candidate.
  final int count;

  /// Enum constructor default.
  final ConstructorCorpusMode mode;

  /// Direct const invocation default.
  final Color directColor;

  /// Public static constant reference default.
  final Color publicColor;

  /// Nested customer-structured default.
  final ConstructorCorpusData data;

  /// Arbitrarily named zero-argument callback.
  final VoidCallback resetProof;

  /// Arbitrarily named one-argument boolean callback.
  final ValueChanged<bool> whenEnabledChanges;

  /// Arbitrarily named one-argument integer callback.
  final ValueChanged<int> reportCount;

  /// Optional host plumbing, automatically excluded by every target.
  final FocusNode? focusNode;

  /// Decodable app-owned input explicitly omitted by the author.
  final String localOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value|$ordinaryLabel|$requiredNamed'),
        Text(
          '$nullableText|$nullableSeed|$enabled|$count|${mode.name}|'
          '${data.nested.label}|${data.count}',
        ),
        TextButton(onPressed: resetProof, child: const Text('Reset corpus')),
        TextButton(
          onPressed: () => whenEnabledChanges(!enabled),
          child: const Text('Toggle corpus'),
        ),
        TextButton(
          onPressed: () => reportCount(count + 1),
          child: const Text('Increment corpus'),
        ),
      ],
    );
  }
}

/// Positional-key base proving positional `super.key` by resolved forwarding.
abstract class ConstructorPositionalBase extends StatelessWidget {
  /// Creates the positional base and forwards [key] to Flutter.
  const ConstructorPositionalBase([Key? key]) : super(key: key);
}

/// Reusable positional-hole fixture.
@RestageWidget(
  name: 'ConstructorPositionalCorpus',
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  category: WidgetCategory.layout,
)
class ConstructorPositionalCorpus extends ConstructorPositionalBase {
  /// Creates a positional corpus with two independently optional slots.
  const ConstructorPositionalCorpus(
    this.requiredLabel, [
    this.leading = 'leading-default',
    this.trailing = 'trailing-default',
    super.key,
  ]);

  /// Required positional value.
  final String requiredLabel;

  /// Earlier optional positional value.
  final String leading;

  /// Later optional positional value used to prove hole preservation.
  final String trailing;

  @override
  Widget build(BuildContext context) => Text(
    '$requiredLabel|$leading|$trailing',
    textDirection: TextDirection.ltr,
  );
}
