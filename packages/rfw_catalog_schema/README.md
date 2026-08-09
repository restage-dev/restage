# rfw_catalog_schema

[![pub package](https://img.shields.io/pub/v/rfw_catalog_schema.svg)](https://pub.dev/packages/rfw_catalog_schema) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The public schema, annotations, wire-identity types, and JSON codecs for a
[Remote Flutter Widget (RFW)](https://pub.dev/packages/rfw) catalog.

This package describes **what** a catalog looks like: the durable contract
shared between catalog producers (compilers, codegen builders), catalog
consumers (authoring tools, SDK runtimes, backends), and any tooling that decodes
or transmits an RFW-targeted widget catalog.

## What this package contains

- **Catalog data types.** `Catalog`, `WidgetEntry`, `PropertyEntry`,
  `StructuredEntry`, `UnionEntry`, `FactoryVariant`, `DecompositionRecipe`,
  `DesignTokenEntry`, plus the enums and metadata structs they reference.
- **Wire identity.** `WireId` (kind-prefixed, library-scoped, monotonic),
  `WireIdKind`, and `WireIdRef` for cross-library references.
- **Default-value model.** `DefaultValueSource` sealed hierarchy
  (`LiteralDefault`, `TokenRefDefault`, `ThemeBindingDefault`,
  `FlutterCtorDefault`).
- **Annotations.** `@RestageWidget`, the optional shared
  `@RestageProperty` overlay, target-specific `a2ui.Config` and `rfw.Config`,
  `@RestageBuiltinLibrary`, `@RestageLibrary`, `@RestageStructuredType`,
  `@RestageUnionVariant`, `@RestageFactoryVariant`, `@StableWidget`,
  `@StableProperty`, `@RfwIncompatible`, `@RestagePropertyPreview`,
  and `@RestageDataField`.
- **Typed constraints.** `RestageConstraints` carries numeric bounds, allowed
  values, patterns, string lengths, and list lengths on `RestageProperty` and
  `PropertyEntry`, while preserving unknown wire keywords for newer readers.
- **Hand-written JSON codecs.** `encodeCatalog` and `decodeCatalog`.
- **Lifecycle types.** `DeprecationInfo` (two-layer: source vs catalog),
  `CompatRule` for forwarding/breaking changes, `ValidationExpr`.

## Customer widget authoring

The unnamed generative constructor is the source of truth for a customer
widget's catalog inputs. Supported public field formals and resolved super
formals are included automatically, in constructor order. Dart-required
formals are required catalog inputs; `super.key` is excluded as Flutter
plumbing.

Use Dart documentation for widget and property descriptions. Add
`@RestageProperty` only for shared metadata Dart cannot express, such as a
default source or typed constraints:

```dart
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A customer-owned submit button.
@RestageWidget(
  name: 'SubmitButton',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.action,
)
class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key, required this.label, this.emphasized = true});

  /// Visible button label.
  final String label;

  /// Whether to use the emphasized treatment.
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Text(label);
}
```

Target-only A2UI metadata lives in its opt-in entrypoint. RFW event identity is
the callback constructor property's exact Dart name and needs no annotation:

```dart
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@a2ui.Config(
  usage: 'Use for the primary form action.',
  writeBackValues: {'onChanged': 'enabled'},
)
@RestageWidget(
  name: 'SubmitControl',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
)
class SubmitControl extends StatelessWidget {
  const SubmitControl({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether the control is enabled.
  final bool enabled;

  /// Reports changes to [enabled].
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!enabled),
        child: Text(enabled ? 'Enabled' : 'Disabled'),
      );
}
```

RFW callback events require no target annotation. Restage derives the exact
Dart property identity and supported callback shape from the widget
constructor. A2UI-specific usage and write-back metadata remains in
`a2ui.Config`.

Canonical v5 JSON is final-form only. The decoder also accepts v4 catalogs and
migrates their retired callback-admission metadata at the decode boundary.
Internal `WireId.unallocated*`
placeholders are available for transitional pre-allocator tooling, but
`WireId('w0000')` / `p0000` / etc. are not public IDs, `decodeCatalog`
rejects them, and `encodeCatalog` refuses to emit catalogs that still carry
those placeholders.

## What it does NOT contain

- **No compiler logic.** Analysis passes, IR types, the wire-ID allocator,
  and event-log replay live in the companion compiler package.
- **No runtime.** Theme resolution, wire-ID dispatching, and on-wire blob
  decoding live in the SDK runtime.
- **No Flutter dependency.** The package is pure Dart so it can be consumed
  by Dart-only backends and codegen pipelines.

## Stability

`1.0.0`: the public surface is stable. Semver is honored from this
release; breaking changes require a major-version bump.
