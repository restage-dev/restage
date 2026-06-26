import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// A customer `@RestageWidget` toggle: a `bool value` controlled component with
/// a `ValueChanged<bool> onChanged` callback.
Catalog _toggleCatalog({
  bool valueRequired = true,
  bool callbackRequired = true,
  bool callbackPositional = false,
}) =>
    catalogWith([
      entry(
        name: 'Toggle',
        flutterType: 'package:fixture/fixture.dart#Toggle',
        properties: [
          prop('value', PropertyType.boolean, required: valueRequired),
          prop(
            'onChanged',
            PropertyType.event,
            required: callbackRequired,
            positional: callbackPositional,
          ),
        ],
      ),
    ]);

A2uiEventSeam _writeBackSeam(
  A2uiScalarType type, {
  String widget = 'Toggle',
  String callback = 'onChanged',
  bool nullable = false,
}) =>
    <(String, String), A2uiCallbackSignature>{
      (widget, callback):
          A2uiCallbackWriteBack(type, nullable: nullable, isList: false),
    };

void main() {
  group('event seam — byte-neutral without a seam', () {
    test('an event property with NO seam keeps the catalog omit/drop path', () {
      // A required event property drops the widget; an optional one omits the
      // field — exactly as before the seam existed (the built-in catalogs carry
      // no seam, so they are byte-neutral by construction).
      final requiredEvent = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Button',
            properties: [prop('onTap', PropertyType.event, required: true)],
          ),
        ]),
      );
      expect(requiredEvent.widgets, isEmpty);
      expect(
        requiredEvent.coverage.droppedWidgets.single.reason,
        A2uiDartCoverageReason.eventProperty,
      );

      final optionalEvent = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Button',
            properties: [
              prop('label', PropertyType.string),
              prop('onTap', PropertyType.event),
            ],
          ),
        ]),
      );
      expect(optionalEvent.widgets.single.fields, hasLength(1));
      expect(
        optionalEvent.coverage.omittedFields.single.reason,
        A2uiDartCoverageReason.eventProperty,
      );
    });
  });

  group('write-back lowering — auto single-pair', () {
    test('a ValueChanged<bool> + bool value pair lowers to a write-back', () {
      final source = emitA2uiCatalogDart(
        _toggleCatalog(),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean),
      );

      // The value prop's READ is rewritten to a data-model path (not the raw
      // value), so the Bound* is subscribed to the exact path the callback
      // writes — the genui controlled-component pattern.
      expect(source, contains("value: {'path': _restageA2uiPath_value}"));
      expect(source, isNot(contains("value: data['value']")));

      // The path is derived at runtime: the producer's `{path}` binding when
      // supplied, else the Restage self-scoped allocation rule
      // (`${itemContext.id}.<valuePropertyName>`).
      expect(source, contains("final _restageA2uiRef_value = data['value'];"));
      expect(source, contains("_restageA2uiRef_value.containsKey('path')"));
      expect(source, contains("_restageA2uiRef_value['path'] as String"));
      expect(source, contains(r"'${itemContext.id}.value'"));

      // The callback writes the new value back into the data model at the same
      // path (inert: a path + the runtime value). The formatter may wrap the
      // long expression, so assert its two stable halves.
      expect(source, contains('onChanged: (_restageA2uiNext) =>'));
      expect(
        source,
        contains(
          'update(DataPath(_restageA2uiPath_value), _restageA2uiNext)',
        ),
      );

      // The callback is behaviour, not producer-supplied data — it never enters
      // the data schema.
      expect(source, isNot(contains("'onChanged':")));

      // The pair is fully wired — no coverage omission/drop.
      final plan = classifyA2uiCatalogDart(
        _toggleCatalog(),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean),
      );
      expect(plan.widgets, hasLength(1));
      expect(plan.coverage.droppedWidgets, isEmpty);
      expect(plan.coverage.omittedFields, isEmpty);
    });

    test('the write-back value prop schema is the genui value-reference shape',
        () {
      // genui's `A2uiSchemas.booleanReference()` shape (a2ui_schemas.dart:
      // 299-356): a value that is a literal OR a `{path}` data binding OR a
      // `{call}` function-call value source. We track genui (replicated raw,
      // genui-free) so the generated catalog matches genui-native semantics.
      final source = emitA2uiCatalogDart(
        _toggleCatalog(),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean),
      );
      // The plain `'value': S.boolean()` is replaced by the reference shape.
      expect(source, isNot(contains("'value': S.boolean()")));
      expect(source, contains('oneOf:'));
      // the literal option (a bool), the {path} binding option, the {call}
      // function-call option.
      expect(source, contains('S.boolean()'));
      expect(source, contains("'path': S.string()"));
      expect(source, contains("required: <String>['path']"));
      // the {call} function-call value source (the formatter may wrap its
      // `required` list, so assert its stable parts).
      expect(source, contains("'call': S.string("));
      expect(source, contains('additionalProperties: true'));
    });

    test('the self-scoped path uses the value property name (allocation rule)',
        () {
      final source = emitA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Picker',
            flutterType: 'package:fixture/fixture.dart#Picker',
            properties: [
              prop('selected', PropertyType.string, required: true),
              prop('onSelected', PropertyType.event, required: true),
            ],
          ),
        ]),
        eventSeam: _writeBackSeam(
          A2uiScalarType.string,
          widget: 'Picker',
          callback: 'onSelected',
        ),
      );
      // `${itemContext.id}.<valuePropertyName>`, not a hardcoded `.value`.
      expect(source, contains(r"'${itemContext.id}.selected'"));
      expect(source, contains("value: {'path': _restageA2uiPath_selected}"));
    });
  });

  group('list write-back lowering — auto single-pair', () {
    /// A customer `@RestageWidget` chip group: a `List<String> selected`
    /// controlled component with a `ValueChanged<List<String>> onSelected`.
    Catalog chipsCatalog() => catalogWith([
          entry(
            name: 'Chips',
            flutterType: 'package:fixture/fixture.dart#Chips',
            properties: [
              prop('selected', PropertyType.stringList, required: true),
              prop('onSelected', PropertyType.event, required: true),
            ],
          ),
        ]);

    A2uiEventSeam listSeam() => <(String, String), A2uiCallbackSignature>{
          ('Chips', 'onSelected'): const A2uiCallbackWriteBack(
            A2uiScalarType.string,
            nullable: false,
            isList: true,
          ),
        };

    test('a ValueChanged<List<String>> + stringList value pair lowers', () {
      final source = emitA2uiCatalogDart(chipsCatalog(), eventSeam: listSeam());

      // The list value prop's `BoundList` READ is rewritten to the data path
      // (not the raw value) — the genui controlled-component pattern.
      expect(source, contains("value: {'path': _restageA2uiPath_selected}"));
      expect(source, isNot(contains("value: data['selected']")));

      // The path is derived at runtime exactly as for a scalar (the producer's
      // `{path}` binding, else the self-scoped allocation rule).
      expect(source, contains(r"'${itemContext.id}.selected'"));

      // The callback writes the SETTLED list back into the data model at the
      // same path (inert: a path + the runtime list value).
      expect(source, contains('onSelected: (_restageA2uiNext) =>'));
      expect(
        source,
        contains(
          'update(DataPath(_restageA2uiPath_selected), _restageA2uiNext)',
        ),
      );

      // The callback is behaviour, not data — it never enters the data schema.
      expect(source, isNot(contains("'onSelected':")));

      // Fully wired — no coverage omission/drop.
      final plan =
          classifyA2uiCatalogDart(chipsCatalog(), eventSeam: listSeam());
      expect(plan.widgets, hasLength(1));
      expect(plan.coverage.droppedWidgets, isEmpty);
      expect(plan.coverage.omittedFields, isEmpty);
    });

    test('the list value prop schema is the genui list value-reference shape',
        () {
      // genui's `A2uiSchemas.listOrReference(items:)` / `stringArrayReference()`
      // shape (a2ui_schemas.dart:418-428, 522-531): a value that is a literal
      // list OR a `{path}` data binding OR a `{call}` function-call value
      // source. Tracked raw (genui-free) so the catalog matches genui-native
      // list-reference semantics.
      final source = emitA2uiCatalogDart(chipsCatalog(), eventSeam: listSeam());
      // The plain `'selected': S.list(items: S.string())` is replaced by the
      // reference shape.
      expect(source, contains('oneOf:'));
      // the literal-list option, the {path} binding option, the {call} option.
      expect(source, contains('S.list(items: S.string())'));
      expect(source, contains("'path': S.string()"));
      expect(source, contains("required: <String>['path']"));
      expect(source, contains("'call': S.string("));
      expect(source, contains('additionalProperties: true'));
    });
  });

  group('event-dispatch lowering', () {
    /// A customer `@RestageWidget` icon button: a required `VoidCallback
    /// onPressed` that dispatches an outward action (no value to control).
    Catalog buttonCatalog({bool callbackRequired = true}) => catalogWith([
          entry(
            name: 'IconButton',
            flutterType: 'package:fixture/fixture.dart#IconButton',
            properties: [
              prop('icon', PropertyType.string, required: true),
              prop('onPressed', PropertyType.event, required: callbackRequired),
            ],
          ),
        ]);

    A2uiEventSeam dispatchSeam() => <(String, String), A2uiCallbackSignature>{
          ('IconButton', 'onPressed'): const A2uiCallbackDispatch(),
        };

    test('a VoidCallback lowers to a compile-fixed dispatchEvent', () {
      final source =
          emitA2uiCatalogDart(buttonCatalog(), eventSeam: dispatchSeam());

      // The callback dispatches an outward event whose name is COMPILE-FIXED
      // from the callback property name — the producer cannot repoint it
      // (load-bearing for inertness). The formatter may wrap the long
      // expression, so assert its stable parts.
      expect(source, contains('onPressed: () => itemContext.dispatchEvent('));
      expect(source, contains('UserActionEvent('));
      expect(source, contains("name: 'onPressed'"));
      expect(source, contains('sourceComponentId: itemContext.id'));

      // No genui `action()` schema / `functionCall` action is emitted — we wire
      // dispatchEvent directly (more inert than genui's own Button).
      expect(source, isNot(contains('A2uiSchemas')));

      // The callback is behaviour, not data — it never enters the data schema.
      expect(source, isNot(contains("'onPressed':")));

      // Fully wired — no coverage omission/drop (the required callback no longer
      // drops the widget).
      final plan =
          classifyA2uiCatalogDart(buttonCatalog(), eventSeam: dispatchSeam());
      expect(plan.widgets, hasLength(1));
      expect(plan.coverage.droppedWidgets, isEmpty);
      expect(plan.coverage.omittedFields, isEmpty);
    });

    test('a POSITIONAL dispatch callback falls through (cannot be slotted)',
        () {
      // A positional callback cannot be wired without risking a positional
      // shift, so it keeps the catalog-fed event path (drop required / omit
      // optional) — same posture as a positional write-back.
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'IconButton',
            flutterType: 'package:fixture/fixture.dart#IconButton',
            properties: [
              prop('icon', PropertyType.string),
              prop('onPressed', PropertyType.event, positional: true),
            ],
          ),
        ]),
        eventSeam: <(String, String), A2uiCallbackSignature>{
          ('IconButton', 'onPressed'): const A2uiCallbackDispatch(),
        },
      );
      expect(plan.widgets.single.dispatches, isEmpty);
      expect(
        plan.coverage.omittedFields.single.reason,
        A2uiDartCoverageReason.eventProperty,
      );
    });
  });

  group('interactive census — unsupported callback (#sig / #L)', () {
    Catalog widgetWith({required bool callbackRequired}) => catalogWith([
          entry(
            name: 'Widget',
            flutterType: 'package:fixture/fixture.dart#Widget',
            properties: [
              prop('label', PropertyType.string),
              prop('onMulti', PropertyType.event, required: callbackRequired),
            ],
          ),
        ]);

    A2uiEventSeam unsupportedSeam() =>
        <(String, String), A2uiCallbackSignature>{
          ('Widget', 'onMulti'): const A2uiCallbackUnsupported(
            'void Function(int, int) is neither a 0-argument dispatch callback '
            'nor a single-value ValueChanged',
          ),
        };

    test('an OPTIONAL unsupported callback omits the field, loud + distinct',
        () {
      // An unsupported-signature callback (#sig: multi-arg; or #L: a non-scalar
      // list element) scopes out LOUD with a DISTINCT reason — never the
      // generic `eventProperty`, never a silent drop, never a mis-lowering.
      final plan = classifyA2uiCatalogDart(
        widgetWith(callbackRequired: false),
        eventSeam: unsupportedSeam(),
      );
      expect(plan.widgets, hasLength(1));
      expect(plan.widgets.single.writeBacks, isEmpty);
      expect(plan.widgets.single.dispatches, isEmpty);
      expect(
        plan.coverage.omittedFields.single.reason,
        A2uiDartCoverageReason.unsupportedInteractiveCallback,
      );
    });

    test('a REQUIRED unsupported callback drops the widget, loud + distinct',
        () {
      final plan = classifyA2uiCatalogDart(
        widgetWith(callbackRequired: true),
        eventSeam: unsupportedSeam(),
      );
      expect(plan.widgets, isEmpty);
      expect(
        plan.coverage.droppedWidgets.single.reason,
        A2uiDartCoverageReason.unsupportedInteractiveCallback,
      );
    });
  });

  group('write-back lowering — fail-closed-LOUD census', () {
    /// The omission/drop reason recorded for [callback] on [widget].
    A2uiDartCoverageReason? reasonFor(
      A2uiDartCatalogPlan plan,
      String widget,
      String callback,
    ) {
      for (final omission in plan.coverage.omittedFields) {
        if (omission.widgetName == widget && omission.fieldName == callback) {
          return omission.reason;
        }
      }
      for (final drop in plan.coverage.droppedWidgets) {
        if (drop.widgetName == widget && drop.fieldName == callback) {
          return drop.reason;
        }
      }
      return null;
    }

    test('#pair — two matching value props → ambiguous, no write-back', () {
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Toggle',
            flutterType: 'package:fixture/fixture.dart#Toggle',
            properties: [
              prop('value', PropertyType.boolean),
              prop('other', PropertyType.boolean),
              // optional callback so the widget survives and the field omits.
              prop('onChanged', PropertyType.event),
            ],
          ),
        ]),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean),
      );
      expect(
        reasonFor(plan, 'Toggle', 'onChanged'),
        A2uiDartCoverageReason.ambiguousWritePairing,
      );
      // The value properties classify normally — never write-back-bound.
      final fields = plan.widgets.single.fields;
      for (final field in fields) {
        expect((field.emission as A2uiDataField).writeBack, isFalse);
      }
      expect(plan.widgets.single.writeBacks, isEmpty);
    });

    test('#pair — two write-back callbacks → ambiguous', () {
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Toggle',
            flutterType: 'package:fixture/fixture.dart#Toggle',
            properties: [
              prop('value', PropertyType.boolean),
              prop('onA', PropertyType.event),
              prop('onB', PropertyType.event),
            ],
          ),
        ]),
        eventSeam: <(String, String), A2uiCallbackSignature>{
          ('Toggle', 'onA'): const A2uiCallbackWriteBack(
            A2uiScalarType.boolean,
            nullable: false,
            isList: false,
          ),
          ('Toggle', 'onB'): const A2uiCallbackWriteBack(
            A2uiScalarType.boolean,
            nullable: false,
            isList: false,
          ),
        },
      );
      expect(
        reasonFor(plan, 'Toggle', 'onA'),
        A2uiDartCoverageReason.ambiguousWritePairing,
      );
      expect(
        reasonFor(plan, 'Toggle', 'onB'),
        A2uiDartCoverageReason.ambiguousWritePairing,
      );
      expect(plan.widgets.single.writeBacks, isEmpty);
    });

    test('#uncontrolled — no matching value property → fail-closed', () {
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Stepper',
            flutterType: 'package:fixture/fixture.dart#Stepper',
            properties: [
              // a String label — no bool value to control.
              prop('label', PropertyType.string),
              prop('onChanged', PropertyType.event),
            ],
          ),
        ]),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean, widget: 'Stepper'),
      );
      expect(
        reasonFor(plan, 'Stepper', 'onChanged'),
        A2uiDartCoverageReason.uncontrolledInteractiveWidget,
      );
      expect(plan.widgets.single.writeBacks, isEmpty);
    });

    test('#lit — the matching value prop is not a bindable leaf', () {
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Toggle',
            flutterType: 'package:fixture/fixture.dart#Toggle',
            properties: [
              // a synthetic bool: type-matches the callback but is not a
              // bindable data leaf, so its read cannot be rewritten.
              const PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'value',
                type: PropertyType.boolean,
                description: '',
                synthetic: 'computed',
              ),
              prop('onChanged', PropertyType.event),
            ],
          ),
        ]),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean),
      );
      expect(
        reasonFor(plan, 'Toggle', 'onChanged'),
        A2uiDartCoverageReason.writeBackValueNotBound,
      );
      expect(plan.widgets.single.writeBacks, isEmpty);
    });

    test('#lit — a write-back value prop in richShapes is not a bindable leaf',
        () {
      // A value prop that is analyzer-fed-rich (in richShapes) is reconstructed
      // raw in the prelude, NOT `Bound*`-wrapped — so the `{path:P}`
      // read-rewrite (rich:false-only) could never apply and the write-back
      // could not round-trip. Fail closed: a richShapes value prop is not a
      // catalog-fed bindable leaf. (Mutually exclusive by construction: a
      // write-back value is a scalar/List<scalar>, never a richShapes entry.)
      final plan = classifyA2uiCatalogDart(
        _toggleCatalog(callbackRequired: false),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean),
        richShapes: <(String, String), A2uiSchemaNode>{
          ('Toggle', 'value'): const ScalarNode(A2uiScalarType.boolean),
        },
      );
      expect(plan.widgets.single.writeBacks, isEmpty);
      expect(
        reasonFor(plan, 'Toggle', 'onChanged'),
        A2uiDartCoverageReason.writeBackValueNotBound,
      );
    });

    test('a required scoped-out write-back callback drops the widget', () {
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Stepper',
            flutterType: 'package:fixture/fixture.dart#Stepper',
            properties: [
              prop('label', PropertyType.string),
              prop('onChanged', PropertyType.event, required: true),
            ],
          ),
        ]),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean, widget: 'Stepper'),
      );
      expect(plan.widgets, isEmpty);
      expect(
        reasonFor(plan, 'Stepper', 'onChanged'),
        A2uiDartCoverageReason.uncontrolledInteractiveWidget,
      );
    });
  });

  group('explicit @RestageProperty pairing — multi-control', () {
    A2uiDartCoverageReason? reasonFor(
      A2uiDartCatalogPlan plan,
      String widget,
      String callback,
    ) {
      for (final o in plan.coverage.omittedFields) {
        if (o.widgetName == widget && o.fieldName == callback) return o.reason;
      }
      for (final d in plan.coverage.droppedWidgets) {
        if (d.widgetName == widget && d.fieldName == callback) return d.reason;
      }
      return null;
    }

    /// A multi-control widget: two int controls, each with its own value prop
    /// and `ValueChanged<int>` callback. Auto single-pair fails (>1 callback).
    /// The callbacks are optional in the scope-out tests so the widget survives
    /// and each callback's omission reason can be inspected (a scoped-out
    /// REQUIRED callback drops the whole widget at the first one).
    Catalog rangeCatalog({bool callbackRequired = true}) => catalogWith([
          entry(
            name: 'Range',
            flutterType: 'package:fixture/fixture.dart#Range',
            properties: [
              prop('low', PropertyType.integer, required: true),
              prop('high', PropertyType.integer, required: true),
              prop('onLow', PropertyType.event, required: callbackRequired),
              prop('onHigh', PropertyType.event, required: callbackRequired),
            ],
          ),
        ]);

    A2uiEventSeam rangeSeam() => <(String, String), A2uiCallbackSignature>{
          ('Range', 'onLow'): const A2uiCallbackWriteBack(
            A2uiScalarType.integer,
            nullable: false,
            isList: false,
          ),
          ('Range', 'onHigh'): const A2uiCallbackWriteBack(
            A2uiScalarType.integer,
            nullable: false,
            isList: false,
          ),
        };

    test('two explicit pairings → two write-backs with distinct paths', () {
      final catalog = rangeCatalog();
      final seam = rangeSeam();
      final pairing = <(String, String), String>{
        ('Range', 'onLow'): 'low',
        ('Range', 'onHigh'): 'high',
      };
      final source = emitA2uiCatalogDart(
        catalog,
        eventSeam: seam,
        pairingSeam: pairing,
      );
      expect(source, contains("value: {'path': _restageA2uiPath_low}"));
      expect(source, contains("value: {'path': _restageA2uiPath_high}"));
      expect(source, contains('onLow: (_restageA2uiNext) =>'));
      expect(source, contains('onHigh: (_restageA2uiNext) =>'));
      expect(
        source,
        contains('update(DataPath(_restageA2uiPath_low), _restageA2uiNext)'),
      );
      expect(
        source,
        contains('update(DataPath(_restageA2uiPath_high), _restageA2uiNext)'),
      );

      final plan = classifyA2uiCatalogDart(
        catalog,
        eventSeam: seam,
        pairingSeam: pairing,
      );
      expect(plan.widgets.single.writeBacks, hasLength(2));
      expect(plan.coverage.droppedWidgets, isEmpty);
      expect(plan.coverage.omittedFields, isEmpty);
    });

    test('a single callback can be explicitly paired (overrides auto)', () {
      final source = emitA2uiCatalogDart(
        _toggleCatalog(),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean),
        pairingSeam: <(String, String), String>{
          ('Toggle', 'onChanged'): 'value',
        },
      );
      expect(source, contains("value: {'path': _restageA2uiPath_value}"));
      expect(source, contains('onChanged: (_restageA2uiNext) =>'));
    });

    test('an un-annotated callback in a multi-control widget → #pair', () {
      final plan = classifyA2uiCatalogDart(
        rangeCatalog(callbackRequired: false),
        eventSeam: rangeSeam(),
        // onHigh is NOT annotated.
        pairingSeam: <(String, String), String>{('Range', 'onLow'): 'low'},
      );
      expect(
        reasonFor(plan, 'Range', 'onHigh'),
        A2uiDartCoverageReason.ambiguousWritePairing,
      );
      // The annotated callback still wires (multi-write-back is per-callback).
      expect(plan.widgets.single.writeBacks, hasLength(1));
    });

    test('an explicit pairing naming a missing value prop → fail-closed', () {
      final plan = classifyA2uiCatalogDart(
        rangeCatalog(),
        eventSeam: rangeSeam(),
        pairingSeam: <(String, String), String>{
          ('Range', 'onLow'): 'nonexistent',
          ('Range', 'onHigh'): 'high',
        },
      );
      expect(
        reasonFor(plan, 'Range', 'onLow'),
        A2uiDartCoverageReason.invalidExplicitWritePairing,
      );
    });

    test('an explicit pairing with a type mismatch → fail-closed', () {
      final catalog = catalogWith([
        entry(
          name: 'W',
          flutterType: 'package:fixture/fixture.dart#W',
          properties: [
            prop('label', PropertyType.string, required: true),
            prop('value', PropertyType.integer, required: true),
            prop('onChanged', PropertyType.event, required: true),
          ],
        ),
      ]);
      final plan = classifyA2uiCatalogDart(
        catalog,
        eventSeam: <(String, String), A2uiCallbackSignature>{
          ('W', 'onChanged'): const A2uiCallbackWriteBack(
            A2uiScalarType.integer,
            nullable: false,
            isList: false,
          ),
        },
        // 'label' is a String value prop; the callback is ValueChanged<int>.
        pairingSeam: <(String, String), String>{('W', 'onChanged'): 'label'},
      );
      expect(
        reasonFor(plan, 'W', 'onChanged'),
        A2uiDartCoverageReason.invalidExplicitWritePairing,
      );
    });

    test('two callbacks targeting the SAME value prop → fail-closed', () {
      final plan = classifyA2uiCatalogDart(
        rangeCatalog(callbackRequired: false),
        eventSeam: rangeSeam(),
        pairingSeam: <(String, String), String>{
          ('Range', 'onLow'): 'low',
          ('Range', 'onHigh'): 'low',
        },
      );
      expect(
        reasonFor(plan, 'Range', 'onLow'),
        A2uiDartCoverageReason.invalidExplicitWritePairing,
      );
      expect(
        reasonFor(plan, 'Range', 'onHigh'),
        A2uiDartCoverageReason.invalidExplicitWritePairing,
      );
      expect(plan.widgets.single.writeBacks, isEmpty);
    });

    test('a pairing entry on a NON-write-back (dispatch) callback fails closed',
        () {
      // A `writeBackValue` pairing on a dispatch callback (no value to write)
      // is incoherent → fail-closed-LOUD, never a silent no-op (the dispatch
      // must NOT still lower).
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Button',
            flutterType: 'package:fixture/fixture.dart#Button',
            properties: [
              prop('label', PropertyType.string),
              prop('onPressed', PropertyType.event),
            ],
          ),
        ]),
        eventSeam: <(String, String), A2uiCallbackSignature>{
          ('Button', 'onPressed'): const A2uiCallbackDispatch(),
        },
        // Incoherent: a dispatch callback has no value to write back.
        pairingSeam: <(String, String), String>{
          ('Button', 'onPressed'): 'label',
        },
      );
      expect(
        reasonFor(plan, 'Button', 'onPressed'),
        A2uiDartCoverageReason.invalidExplicitWritePairing,
      );
      expect(plan.widgets.single.dispatches, isEmpty);
    });
  });

  group('write-back lowering — scaffolding namespace hygiene', () {
    test('a leaf property in the reserved _restageA2ui namespace scopes out',
        () {
      // The generated identifier would shadow a reserved scaffolding/prelude
      // local (e.g. `_restageA2uiPath_*`, `_restageA2uiArg_*`), so it fails
      // closed rather than mis-resolve. Reserving the whole namespace closes
      // the class by construction.
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Widget',
            flutterType: 'package:fixture/fixture.dart#Widget',
            properties: [prop('_restageA2uiArg_x', PropertyType.string)],
          ),
        ]),
      );
      expect(plan.widgets.single.fields, isEmpty);
      expect(
        plan.coverage.omittedFields.single.fieldName,
        '_restageA2uiArg_x',
      );
    });

    test('a #lit write-back value prop in the reserved namespace is unbindable',
        () {
      // A value prop whose identifier is in the reserved namespace is not a
      // bindable leaf, so its callback fails closed (#lit, not write-back).
      final plan = classifyA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'Widget',
            flutterType: 'package:fixture/fixture.dart#Widget',
            properties: [
              prop('_restageA2uiArg_value', PropertyType.boolean),
              prop('onChanged', PropertyType.event),
            ],
          ),
        ]),
        eventSeam: _writeBackSeam(A2uiScalarType.boolean, widget: 'Widget'),
      );
      expect(plan.widgets.single.writeBacks, isEmpty);
      final reasons = plan.coverage.omittedFields.map((o) => o.reason).toSet();
      expect(reasons, contains(A2uiDartCoverageReason.writeBackValueNotBound));
    });
  });

  group('write-back lowering — emitted source is well-formed', () {
    test('a complex interactive widget emits syntactically valid Dart', () {
      // A write-back pair alongside a leaf field and a child slot — exercises
      // the path prelude, the `{path}` read-rewrite, the callback argument,
      // and the child wiring together. The emitted source is genui-dependent
      // (a full compile/render is the milestone render-proof), so this probe
      // confirms it is at least syntactically valid Dart (balanced, escaped).
      final source = emitA2uiCatalogDart(
        catalogWith([
          entry(
            name: 'SettingsRow',
            flutterType: 'package:fixture/fixture.dart#SettingsRow',
            properties: [
              prop('title', PropertyType.string, required: true),
              prop('value', PropertyType.boolean, required: true),
              prop('trailing', PropertyType.widget),
              prop('onChanged', PropertyType.event, required: true),
            ],
          ),
        ]),
        eventSeam: _writeBackSeam(
          A2uiScalarType.boolean,
          widget: 'SettingsRow',
        ),
      );
      // parseString only scans + parses (no resolution), so its diagnostics
      // are purely syntactic — an empty list means the source is well-formed.
      final parsed = parseString(content: source, throwIfDiagnostics: false);
      expect(
        parsed.errors,
        isEmpty,
        reason: 'emitted source has syntax errors:\n'
            '${parsed.errors.join('\n')}',
      );
      // The write-back wiring is present in the complex widget.
      expect(source, contains("value: {'path': _restageA2uiPath_value}"));
      expect(source, contains('onChanged: (_restageA2uiNext) =>'));
    });
  });
}
