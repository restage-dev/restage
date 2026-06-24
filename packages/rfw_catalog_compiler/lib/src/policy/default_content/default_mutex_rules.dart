// packages/rfw_catalog_compiler/lib/src/policy/default_content/default_mutex_rules.dart

/// Built-in mutex sidecar — the canonical case is Container.color ↔
/// Container.decoration (Flutter asserts they are not both non-null).
/// Additional rules can be added by extending the policy ledger.
const Map<String, List<List<String>>> kBuiltInMutexRules = {
  'package:flutter/src/widgets/container.dart#Container': [
    ['color', 'decoration'],
  ],
};
