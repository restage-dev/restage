import 'dart:io';

import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// A focused fixture exercising the genui-facing constructs whose runtime
/// behaviour a `dynamic`-typed emit could mask:
///  * `Tooltip` — a `BoundString` value field + a SINGLE child slot
///    (`itemContext.buildChild(childId)`, the typed child-slot call);
///  * `Flex` — a required `enumValue` (`Axis`) with no declared default
///    (the fail-closed enum lookup, resolving to the first member) + a LIST
///    child slot.
///
/// All entries are REAL Flutter widgets, so the emitted catalog compiles and
/// renders against the real genui SDK in `restage_a2ui` — the instantiation
/// proof. This test owns regeneration + drift; `restage_a2ui` owns compile +
/// render. (genui is isolated to `restage_a2ui`; this package has no genui
/// dependency.)
Catalog _fixtureCatalog() => catalogWith([
      entry(
        name: 'Tooltip',
        flutterType: 'package:flutter/material.dart#Tooltip',
        childrenSlot: ChildrenSlot.single,
        properties: [
          prop('message', PropertyType.string),
          prop('child', PropertyType.widget),
        ],
      ),
      entry(
        name: 'Flex',
        flutterType: 'package:flutter/widgets.dart#Flex',
        childrenSlot: ChildrenSlot.list,
        properties: [
          const PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'direction',
            type: PropertyType.enumValue,
            description: '',
            required: true,
            enumType: 'Axis',
          ),
          prop('children', PropertyType.widgetList),
        ],
      ),
      // `Visibility` — a `BoundBool` value field + a (required) single child:
      // the BoundBool wrapper render proof.
      entry(
        name: 'Visibility',
        flutterType: 'package:flutter/widgets.dart#Visibility',
        childrenSlot: ChildrenSlot.single,
        properties: [
          prop('visible', PropertyType.boolean),
          const PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'child',
            type: PropertyType.widget,
            description: '',
            required: true,
          ),
        ],
      ),
      // `Wrap` — a `BoundNumber` value field (`spacing`) + a list child slot:
      // the BoundNumber wrapper render proof.
      entry(
        name: 'Wrap',
        flutterType: 'package:flutter/widgets.dart#Wrap',
        childrenSlot: ChildrenSlot.list,
        properties: [
          prop('spacing', PropertyType.real),
          prop('children', PropertyType.widgetList),
        ],
      ),
    ]);

/// The committed generated catalog lives in restage_a2ui (which has the genui
/// dep), one directory up from this package.
const _generatedPath =
    '../restage_a2ui/test/generated/sample_a2ui_catalog.g.dart';

void main() {
  test('generated A2UI catalog fixture is current (drift guard)', () {
    final actual = emitA2uiCatalogDart(_fixtureCatalog());

    final file = File(_generatedPath);
    if (Platform.environment['REGEN_A2UI_DART_GOLDEN'] == '1') {
      file.parent.createSync(recursive: true);
      // The emitter output is trimRight()-ed; commit it with a trailing
      // newline. The committed file is generated code (the emitter's own
      // DartFormatter style), excluded from the format gate like the other
      // generated trees — its on-disk format drifts across dart-format
      // versions, so the gate never reformats it and this byte-compare stays
      // the single source of truth.
      file.writeAsStringSync('$actual\n');
    }

    expect(
      file.existsSync(),
      isTrue,
      reason: 'run with REGEN_A2UI_DART_GOLDEN=1 to generate $_generatedPath',
    );
    expect(
      actual,
      file.readAsStringSync().trimRight(),
      reason: 'the committed restage_a2ui generated catalog has drifted from '
          'the emitter; regenerate with REGEN_A2UI_DART_GOLDEN=1',
    );
  });
}
