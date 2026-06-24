import 'package:meta/meta.dart';

/// Source and pass history for one compiler IR entry.
@immutable
final class ProvenanceIR {
  /// Creates provenance metadata.
  const ProvenanceIR({
    required this.flutterType,
    required this.curationSource,
    required this.derivationTrace,
  });

  /// Resolved source type in `'<library URI>#<class>[.<ctor>]'` form.
  final String flutterType;

  /// Location of the curation entry that contributed this IR, if any.
  final String? curationSource;

  /// Ordered analysis passes that produced the IR entry.
  final List<String> derivationTrace;
}
