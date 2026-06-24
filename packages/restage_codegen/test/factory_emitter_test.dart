import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('emitFactoryFunction', () {
    test('emits a closure for a real-catalog scalar-only widget', () {
      // `Divider` from restage.material — childrenSlot.none, no fires,
      // no decomposes, three scalar properties.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Divider',
        library: WidgetLibrary.material,
        category: WidgetCategory.decoration,
        description: 'A thin horizontal line.',
        flutterType: 'package:flutter/material.dart#Divider',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'height',
            type: PropertyType.length,
            description: 'Total vertical space.',
            defaultSource: LiteralDefault(16.0),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'thickness',
            type: PropertyType.length,
            description: 'Stroke thickness.',
            defaultSource: LiteralDefault(1.0),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'color',
            type: PropertyType.color,
            description: 'Stroke color.',
            defaultBrandToken: 'onBackground',
          ),
        ],
      );

      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains(
          'Widget _buildDivider(BuildContext context, DataSource source)',
        ),
      );
      expect(source, contains('return Divider('));
      expect(
        source,
        contains("source.v<double>(<Object>['height']) ?? 16.0"),
      );
      expect(
        source,
        contains("source.v<double>(<Object>['thickness']) ?? 1.0"),
      );
      // Brand-token defaults pass through as null today (Flutter's
      // own theme resolution provides the runtime value).
      expect(
        source,
        contains("ArgumentDecoders.color(source, <Object>['color'])"),
      );
      expect(source, isNot(contains('?? null')));
    });

    test('covers every emittable scalar PropertyType', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'AllScalars',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: 'Synthetic test fixture covering each scalar type.',
        flutterType: 'package:test_pkg/widget.dart#AllScalars',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'flag',
            type: PropertyType.boolean,
            description: 'A boolean.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'count',
            type: PropertyType.integer,
            description: 'An integer.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'ratio',
            type: PropertyType.real,
            description: 'A double.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'size',
            type: PropertyType.length,
            description: 'A length (double).',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'label',
            type: PropertyType.string,
            description: 'A string.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'tint',
            type: PropertyType.color,
            description: 'A color.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'pad',
            type: PropertyType.edgeInsets,
            description: 'An EdgeInsets.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'placement',
            type: PropertyType.alignment,
            description: 'An alignment.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'concretePlacement',
            type: PropertyType.alignmentXY,
            description: 'A concrete Alignment.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'weight',
            type: PropertyType.fontWeight,
            description: 'A FontWeight.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'span',
            type: PropertyType.duration,
            description: 'A Duration.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'curve',
            type: PropertyType.curve,
            description: 'A Curve.',
          ),
        ],
      );

      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains("source.v<bool>(<Object>['flag'])"));
      expect(source, contains("source.v<int>(<Object>['count'])"));
      expect(source, contains("source.v<double>(<Object>['ratio'])"));
      expect(source, contains("source.v<double>(<Object>['size'])"));
      expect(source, contains("source.v<String>(<Object>['label'])"));
      expect(
        source,
        contains("ArgumentDecoders.color(source, <Object>['tint'])"),
      );
      expect(
        source,
        contains("ArgumentDecoders.edgeInsets(source, <Object>['pad'])"),
      );
      expect(
        source,
        contains(
          "ArgumentDecoders.alignment(source, <Object>['placement'])",
        ),
      );
      expect(
        source,
        contains(
          "RestageDecoders.alignmentXY(source, <Object>['concretePlacement'])",
        ),
      );
      expect(
        source,
        contains(
          'ArgumentDecoders.enumValue<FontWeight>('
          "FontWeight.values, source, <Object>['weight'])",
        ),
      );
      expect(
        source,
        contains("RestageDecoders.duration(source, <Object>['span'])"),
      );
      expect(
        source,
        contains("RestageDecoders.curve(source, <Object>['curve'])"),
      );
    });

    test('a string-list slot decodes through the fail-safe stringList decoder',
        () {
      // A `stringList` slot lowers to the tolerant `RestageDecoders.stringList`
      // — a present-but-degenerate list (a non-string element on a corrupt /
      // tamper wire) DROPS the bad element rather than throwing and crashing
      // the render (the `booleanList` / `selectionOptionList` present-malformed
      // convention). Absent → null so the required-slot contract still applies.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'TextLike',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:test_pkg/widget.dart#TextLike',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'fontFamilyFallback',
            type: PropertyType.stringList,
            description: 'Fallback families.',
          ),
        ],
      );

      final source = emitFactoryFunction(entry);

      expect(source, isNotNull);
      expect(
        source,
        contains(
          "RestageDecoders.stringList(source, <Object>['fontFamilyFallback'])",
        ),
      );
      // The throwing element-decode is gone — a malformed element must NOT
      // crash the render.
      expect(source, isNot(contains('must be a string')));
    });

    test('a shapeBorder circle default emits a CircleBorder fallback', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'ChoiceChipLike',
        library: WidgetLibrary.material,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:test_pkg/widget.dart#ChoiceChipLike',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'avatarBorder',
            type: PropertyType.shapeBorder,
            description: 'Avatar border.',
            // The curated default carries the shape's wire-type
            // discriminator; the emitter renders the const ShapeBorder.
            defaultSource: LiteralDefault('circle'),
          ),
        ],
      );

      final source = emitFactoryFunction(entry);

      expect(source, isNotNull);
      expect(
        source,
        contains(
          'avatarBorder: RestageDecoders.shapeBorder(source, '
          "<Object>['avatarBorder']) ?? const CircleBorder()",
        ),
      );
    });

    test(
        'a shapeBorder property without a default is not special-cased '
        'by name', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'ChoiceChipLike',
        library: WidgetLibrary.material,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:test_pkg/widget.dart#ChoiceChipLike',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'avatarBorder',
            type: PropertyType.shapeBorder,
            description: 'Avatar border.',
          ),
        ],
      );

      final source = emitFactoryFunction(entry);

      expect(source, isNotNull);
      // No curated default → no fabricated CircleBorder fallback; the name
      // alone no longer triggers a special-case.
      expect(source, isNot(contains('const CircleBorder()')));
    });

    test('emits source.optionalChild for an optional child slot', () {
      // `Center` from restage.core — childrenSlot.single, optional
      // child + two scalar properties.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Center',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:flutter/widgets.dart#Center',
        childrenSlot: ChildrenSlot.single,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'child',
            type: PropertyType.widget,
            description: 'Optional child to center.',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'widthFactor',
            type: PropertyType.real,
            description: '',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'heightFactor',
            type: PropertyType.real,
            description: '',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains('return Center('));
      expect(
        source,
        contains("child: source.optionalChild(<Object>['child'])"),
      );
      expect(
        source,
        contains("widthFactor: source.v<double>(<Object>['widthFactor'])"),
      );
    });

    test('emits source.child for a required child slot', () {
      // `Padding` from restage.core — childrenSlot.single, required
      // child + a required EdgeInsets default.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Padding',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:flutter/widgets.dart#Padding',
        childrenSlot: ChildrenSlot.single,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'padding',
            type: PropertyType.edgeInsets,
            description: '',
            required: true,
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'child',
            type: PropertyType.widget,
            description: '',
            required: true,
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains('return Padding('));
      expect(source, contains("child: source.child(<Object>['child'])"));
    });

    test('emits source.childList for a list child slot', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'ListWrapper',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#ListWrapper',
        childrenSlot: ChildrenSlot.list,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'children',
            type: PropertyType.widgetList,
            description: '',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains('return ListWrapper('));
      expect(
        source,
        contains("children: source.childList(<Object>['children'])"),
      );
    });

    test(
        'emits entries with non-canonical widget properties '
        '(Scaffold-shaped: childrenSlot.none + body/appBar widgets)', () {
      // body emits as a plain `optionalChild` slot; appBar carries
      // `widgetType: 'PreferredSizeWidget'` so the codegen appends a
      // downcast to satisfy Flutter's narrower ctor param.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'ScaffoldLike',
        library: WidgetLibrary.material,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#ScaffoldLike',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'body',
            type: PropertyType.widget,
            description: '',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'appBar',
            type: PropertyType.widget,
            description: '',
            widgetType: 'PreferredSizeWidget',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains("body: source.optionalChild(<Object>['body'])"));
      expect(
        source,
        contains(
          "appBar: source.optionalChild(<Object>['appBar']) "
          'as PreferredSizeWidget?',
        ),
      );
    });

    test(
        'emits entries with extra widget properties beyond the canonical '
        "child (CupertinoPageScaffold-shaped: 'child' + 'navigationBar')", () {
      // The canonical 'child' slot still emits last (per
      // sort_child_properties_last); 'navigationBar' joins the
      // named-args block as a regular `optionalChild` slot.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'PageScaffoldLike',
        library: WidgetLibrary.cupertino,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#PageScaffoldLike',
        childrenSlot: ChildrenSlot.single,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'child',
            type: PropertyType.widget,
            description: '',
            required: true,
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'navigationBar',
            type: PropertyType.widget,
            description: '',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains(
          "navigationBar: source.optionalChild(<Object>['navigationBar'])",
        ),
      );
      // child is the last named arg.
      expect(source, contains("child: source.child(<Object>['child']),\n"));
    });

    test(
        'skips ChildrenSlot.single entries lacking a canonical child '
        'property (single slot whose widget property is not named `child`)',
        () {
      // Catalog convention: the canonical child slot is always named
      // `child`. A `ChildrenSlot.single` entry whose widget property
      // is named differently (e.g. `home`) doesn't match Flutter's
      // ctor param shape and isn't safe for the mechanical emitter.
      // (Forward guard — the live MaterialApp entry uses
      // `ChildrenSlot.none`; no current built-in entry trips this
      // particular path.)
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'NonCanonicalSingle',
        library: WidgetLibrary.material,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#NonCanonicalSingle',
        childrenSlot: ChildrenSlot.single,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'home',
            type: PropertyType.widget,
            description: '',
          ),
        ],
      );
      expect(emitFactoryFunction(entry), isNull);
    });

    test('emits source.voidHandler for an onPressed event', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'PressableLike',
        library: WidgetLibrary.core,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:test_pkg/w.dart#PressableLike',
        childrenSlot: ChildrenSlot.none,
        fires: [WidgetEventName.onPressed],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onPressed',
            type: PropertyType.event,
            description: '',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains("onPressed: source.voidHandler(<Object>['onPressed'])"),
      );
    });

    test('emits source.voidHandler for an onTap event', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'TappableLike',
        library: WidgetLibrary.core,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:test_pkg/w.dart#TappableLike',
        childrenSlot: ChildrenSlot.none,
        fires: [WidgetEventName.onTap],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onTap',
            type: PropertyType.event,
            description: '',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains("onTap: source.voidHandler(<Object>['onTap'])"),
      );
    });

    test('emits source.voidHandler for an onEnd event', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'ImplicitAnimationLike',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:test_pkg/w.dart#ImplicitAnimationLike',
        childrenSlot: ChildrenSlot.none,
        fires: [WidgetEventName.onEnd],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onEnd',
            type: PropertyType.event,
            description: '',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains("onEnd: source.voidHandler(<Object>['onEnd'])"),
      );
    });

    test(
      'skips entries whose event property names mismatch the fires list',
      () {
        // `fires` declares onPressed but the property is named onTap —
        // bespoke surface handles the mismatch.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'EventMismatch',
          library: WidgetLibrary.core,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#EventMismatch',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onPressed],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onTap',
              type: PropertyType.event,
              description: '',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test(
      'skips non-void events that omit callbackSignature',
      () {
        // Without `callbackSignature`, the emitter has no typed
        // shape to thread through `source.handler<T>(...)` and falls
        // outside the void-handler shortcut's domain.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ChangeableLike',
          library: WidgetLibrary.core,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#ChangeableLike',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onChanged',
              type: PropertyType.event,
              description: '',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test(
      'emits typed handler for ValueChanged<bool> onChanged events',
      () {
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ChangeableLike',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#ChangeableLike',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'value',
              type: PropertyType.boolean,
              description: '',
              required: true,
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onChanged',
              type: PropertyType.event,
              description: '',
              callbackSignature: 'ValueChanged<bool>',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(
          source,
          contains('source.handler<ValueChanged<bool>>'),
        );
        expect(source, contains('(bool value)'));
        expect(source, contains("trigger(<String, Object?>{'value': value})"));
      },
    );

    test(
      'emits typed handler for ValueChanged<String> onSubmitted events',
      () {
        // Companion to the `onChanged + ValueChanged<bool>` case above:
        // proves the typed-handler path is not specific to `onChanged`
        // or to the `bool` payload type — any non-void event name with
        // a recognized `ValueChanged<T>` signature routes the same way.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'TextFieldLike',
          library: WidgetLibrary.cupertino,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#TextFieldLike',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onSubmitted],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onSubmitted',
              type: PropertyType.event,
              description: '',
              callbackSignature: 'ValueChanged<String>',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(
          source,
          contains('source.handler<ValueChanged<String>>'),
        );
        expect(source, contains("<Object>['onSubmitted']"));
        expect(source, contains('(String value)'));
        expect(source, contains("trigger(<String, Object?>{'value': value})"));
      },
    );

    test(
      'required typed-handler emits a no-op closure fallback when the '
      'Flutter ctor param is non-nullable',
      () {
        // Mirrors the CupertinoDatePicker shape: required event with a
        // typed `ValueChanged<DateTime>` callback. `source.handler<T>(...)`
        // returns `T?`, so the emit threads a no-op `(DateTime _) {}`
        // fallback so the assignment to the non-nullable
        // `onDateTimeChanged` Flutter param compiles. Binding an event
        // handler is an editor-time choice; the catalog stays renderable
        // without one.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'RequiredTypedHandler',
          library: WidgetLibrary.cupertino,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#RequiredTypedHandler',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onDateTimeChanged',
              type: PropertyType.event,
              description: '',
              required: true,
              callbackSignature: 'ValueChanged<DateTime>',
              firesAs: 'onChanged',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        // The handler call is present + the no-op closure fallback is
        // appended via `??`.
        expect(
          source,
          contains('source.handler<ValueChanged<DateTime>>'),
        );
        expect(source, contains('?? (DateTime _) {}'));
        // The required-scalar throw fallback must not be emitted for a
        // typed handler — the user-facing diagnostic is "no handler
        // bound = no event fires", not "paywall load failed".
        expect(
          source,
          isNot(
            contains(
              "'RequiredTypedHandler.onDateTimeChanged is required.'",
            ),
          ),
        );
      },
    );

    test(
      'required typed-handler with nullable type parameter emits a '
      'nullable-typed no-op fallback',
      () {
        // Covers the regex-side acceptance of `\\w+\\??` in
        // `_kValueChangedSignature` — `ValueChanged<bool?>` (tristate
        // checkbox shape) when `required: true` must emit
        // `?? (bool? _) {}`, not `?? (bool _) {}`.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'TristateHandler',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#TristateHandler',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onChanged',
              type: PropertyType.event,
              description: '',
              required: true,
              callbackSignature: 'ValueChanged<bool?>',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(source, contains('source.handler<ValueChanged<bool?>>'));
        expect(source, contains('?? (bool? _) {}'));
      },
    );

    test(
      'emits a list-valued typed handler for ValueChanged<List<String>> '
      'settled-selection events',
      () {
        // The first list-valued event shape: a multi-select widget that
        // fires the whole settled selection as one `List<String>` over the
        // rfw DynamicList wire (`trigger({'value': <list>})`). The handler
        // type is `ValueChanged<List<String>>`; the typed parameter is the
        // `List<String>`. The scalar paths above are unaffected.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'MultiSelectLike',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#MultiSelectLike',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onChanged',
              type: PropertyType.event,
              description: '',
              callbackSignature: 'ValueChanged<List<String>>',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(
          source,
          contains('source.handler<ValueChanged<List<String>>>'),
        );
        expect(source, contains('(List<String> value)'));
        expect(source, contains("trigger(<String, Object?>{'value': value})"));
      },
    );

    test(
      'required list-valued typed-handler emits a List<String> no-op '
      'closure fallback',
      () {
        // The required-event analogue of the scalar no-op fallback: a
        // required `ValueChanged<List<String>>` whose Flutter ctor param is
        // non-nullable threads a `(List<String> _) {}` fallback so the
        // assignment compiles, never the required-scalar throw.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'RequiredMultiSelect',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#RequiredMultiSelect',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onChanged',
              type: PropertyType.event,
              description: '',
              required: true,
              callbackSignature: 'ValueChanged<List<String>>',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(
          source,
          contains('source.handler<ValueChanged<List<String>>>'),
        );
        expect(source, contains('?? (List<String> _) {}'));
        expect(
          source,
          isNot(contains("'RequiredMultiSelect.onChanged is required.'")),
        );
      },
    );

    test(
      'skips non-void events whose callbackSignature is unrecognized',
      () {
        // `'BarBaz'` doesn't match the supported `ValueChanged<T>`
        // shape — the eligibility gate rejects so the registry typo
        // surfaces at codegen rather than at the consumer build.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'BogusHandler',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#BogusHandler',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onChanged',
              type: PropertyType.event,
              description: '',
              callbackSignature: 'BarBaz',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test(
      'emits a `disabled` pre-amble and gates onPressed for the '
      '`gateOnPressed` synthetic strategy',
      () {
        // Mirrors CupertinoButton's catalog shape: childrenSlot.single +
        // canonical child + onPressed event + scalars + disabled
        // synthetic.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'GatedButton',
          library: WidgetLibrary.cupertino,
          category: WidgetCategory.action,
          description: '',
          flutterType: 'package:test_pkg/w.dart#GatedButton',
          childrenSlot: ChildrenSlot.single,
          fires: [WidgetEventName.onPressed],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'child',
              type: PropertyType.widget,
              description: '',
              required: true,
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onPressed',
              type: PropertyType.event,
              description: '',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'disabled',
              type: PropertyType.boolean,
              description: '',
              defaultSource: LiteralDefault(false),
              synthetic: 'gateOnPressed',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(
          source,
          contains(
            "final disabled = source.v<bool>(<Object>['disabled']) ?? false;",
          ),
        );
        expect(
          source,
          contains(
            'onPressed: disabled ? null : '
            "source.voidHandler(<Object>['onPressed'])",
          ),
        );
        // The synthetic disabled never appears as a ctor arg.
        expect(source, isNot(contains('disabled: ')));
      },
    );

    test(
      'skips entries declaring a `fires` entry without a matching '
      'event property (and vice versa)',
      () {
        // The symmetric counterpart of the "EventMismatch" test:
        // here the cardinality differs (fires has one entry, the
        // property list has none of type event). Bijection check
        // rejects via the size-mismatch clause.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'FireWithoutProp',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#FireWithoutProp',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onPressed],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'someScalar',
              type: PropertyType.string,
              description: '',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test(
      'bijection matches via `firesAs` when the property name differs '
      'from the fire taxonomy name',
      () {
        // Mirrors the CupertinoDatePicker shape: the Flutter ctor names
        // its event param `onDateTimeChanged`, but the catalog event
        // taxonomy is `onChanged`. `firesAs: 'onChanged'` declares the
        // property satisfies the onChanged fire while keeping the
        // Flutter ctor name as the property name (and ctor arg name).
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'TaxonomyRenamed',
          library: WidgetLibrary.cupertino,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#TaxonomyRenamed',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onDateTimeChanged',
              type: PropertyType.event,
              description: '',
              required: true,
              callbackSignature: 'ValueChanged<DateTime>',
              firesAs: 'onChanged',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        // Ctor arg name and source key both use the property `name`
        // (the Flutter ctor param) — `firesAs` is bijection-side only.
        expect(
          source,
          contains(
            'onDateTimeChanged: source.handler<ValueChanged<DateTime>>(',
          ),
        );
        expect(source, contains("<Object>['onDateTimeChanged']"));
        // The taxonomy name must not leak into the emitted ctor or
        // source-key path.
        expect(source, isNot(contains('onChanged:')));
        expect(source, isNot(contains("'onChanged'")));
      },
    );

    test(
      'event properties without `firesAs` continue to match against '
      '`name` (regression guard for existing curations)',
      () {
        // Existing curations (CupertinoSwitch, CupertinoTextField, …)
        // have property name == fire taxonomy name. The bijection
        // check falls back to `name` when `firesAs` is unset.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'PlainChanged',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#PlainChanged',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onChanged',
              type: PropertyType.event,
              description: '',
              required: true,
              callbackSignature: 'ValueChanged<bool>',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(
          source,
          contains('onChanged: source.handler<ValueChanged<bool>>('),
        );
      },
    );

    test(
      'mismatched `firesAs` value still fails the bijection',
      () {
        // `firesAs: 'onPressed'` doesn't match `fires: [onChanged]` —
        // the bijection check rejects. Regression guard ensuring the
        // `firesAs` field doesn't accidentally loosen the check.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'WrongFiresAs',
          library: WidgetLibrary.cupertino,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#WrongFiresAs',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onChanged],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onDateTimeChanged',
              type: PropertyType.event,
              description: '',
              required: true,
              callbackSignature: 'ValueChanged<DateTime>',
              firesAs: 'onPressed',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test('skips entries with duplicate event-property names', () {
      // Two onPressed event properties — the bijection check rejects
      // because the property list has more entries than the unique
      // name set.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'DupEventProps',
        library: WidgetLibrary.material,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:test_pkg/w.dart#DupEventProps',
        childrenSlot: ChildrenSlot.none,
        fires: [WidgetEventName.onPressed],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onPressed',
            type: PropertyType.event,
            description: '',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onPressed',
            type: PropertyType.event,
            description: '',
          ),
        ],
      );
      expect(emitFactoryFunction(entry), isNull);
    });

    test('skips entries with duplicate `fires` entries', () {
      // Same WidgetEventName listed twice — the bijection check
      // rejects because `entry.fires` has more entries than the
      // unique name set.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'DupFires',
        library: WidgetLibrary.material,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:test_pkg/w.dart#DupFires',
        childrenSlot: ChildrenSlot.none,
        fires: [WidgetEventName.onPressed, WidgetEventName.onPressed],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onPressed',
            type: PropertyType.event,
            description: '',
          ),
        ],
      );
      expect(emitFactoryFunction(entry), isNull);
    });

    test(
      'skips entries with multiple `gateOnPressed` synthetics',
      () {
        // Two bool properties both flagged synthetic 'gateOnPressed' —
        // `_gatingPropertyOf` would silently pick the first; the
        // emitter rejects to keep eligibility and emit in lockstep.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'DoubleGate',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#DoubleGate',
          childrenSlot: ChildrenSlot.none,
          fires: [WidgetEventName.onPressed],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'onPressed',
              type: PropertyType.event,
              description: '',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'disabled',
              type: PropertyType.boolean,
              description: '',
              defaultSource: LiteralDefault(false),
              synthetic: 'gateOnPressed',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'inactive',
              type: PropertyType.boolean,
              description: '',
              defaultSource: LiteralDefault(false),
              synthetic: 'gateOnPressed',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test(
      'skips `gateOnPressed` synthetic when the entry has no onPressed '
      'event property',
      () {
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'NoEventToGate',
          library: WidgetLibrary.material,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#NoEventToGate',
          childrenSlot: ChildrenSlot.none,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'disabled',
              type: PropertyType.boolean,
              description: '',
              defaultSource: LiteralDefault(false),
              synthetic: 'gateOnPressed',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test('emits Icon with positional IconData wrap (iconData synthetic)', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'IconLike',
        library: WidgetLibrary.material,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/widgets.dart#Icon',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'iconCodepoint',
            type: PropertyType.integer,
            description: '',
            required: true,
            synthetic: 'iconData',
            positional: true,
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'size',
            type: PropertyType.length,
            description: '',
            defaultSource: LiteralDefault(24.0),
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains('return Icon('));
      // Required iconData synthetic routes through the throw-on-missing
      // fallback (same contract as required scalar properties) so a
      // malformed blob fails loudly instead of rendering a
      // zero-codepoint icon. Non-required codepoints retain `?? 0`;
      // see the sibling test below.
      expect(
        source,
        contains(
          "IconData(source.v<int>(<Object>['iconCodepoint']) ?? "
          "(throw ArgumentError('IconLike.iconCodepoint is required.')), "
          "fontFamily: 'MaterialIcons')",
        ),
      );
      // No `iconCodepoint:` named arg in the emitted source.
      expect(source, isNot(contains('iconCodepoint: ')));
    });

    test(
      'iconData synthetic with required: false retains the ?? 0 fallback',
      () {
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'IconLike',
          library: WidgetLibrary.material,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#Icon',
          childrenSlot: ChildrenSlot.none,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'iconCodepoint',
              type: PropertyType.integer,
              description: '',
              synthetic: 'iconData',
              positional: true,
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(
          source,
          contains(
            "IconData(source.v<int>(<Object>['iconCodepoint']) ?? 0, "
            "fontFamily: 'MaterialIcons')",
          ),
        );
        expect(source, isNot(contains('throw ArgumentError')));
      },
    );

    test(
      'emits Image.network with positional URL string',
      () {
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ImageLike',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#Image.network',
          childrenSlot: ChildrenSlot.none,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'url',
              type: PropertyType.string,
              description: '',
              required: true,
              positional: true,
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'width',
              type: PropertyType.length,
              description: '',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(source, contains('return Image.network('));
        // url emits positionally, no `url:` prefix; required-no-default
        // string throws on missing instead of falling back silently.
        expect(
          source,
          contains(
            "source.v<String>(<Object>['url']) ?? "
            '(throw ArgumentError(',
          ),
        );
        expect(source, isNot(contains('url: ')));
      },
    );

    test(
      'positional ctor args emit ahead of named ones in source order',
      () {
        // Regression guard: Dart syntax requires positional args before
        // named args. The emitter walks `properties` in declaration
        // order; a future refactor that reorders the loop without
        // preserving positional-first would silently produce code that
        // fails to compile in the consumer build.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'PositionalThenNamed',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#PositionalThenNamed',
          childrenSlot: ChildrenSlot.none,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'src',
              type: PropertyType.string,
              description: '',
              required: true,
              positional: true,
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'extent',
              type: PropertyType.length,
              description: '',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        final positionalIndex =
            source!.indexOf("source.v<String>(<Object>['src']) ??");
        final namedIndex =
            source.indexOf("extent: source.v<double>(<Object>['extent'])");
        expect(positionalIndex, greaterThanOrEqualTo(0));
        expect(namedIndex, greaterThan(positionalIndex));
      },
    );

    test(
      'skips iconData synthetic when the property is not also marked '
      'positional (the wrap only makes sense in the positional slot)',
      () {
        // `Icon.iconCodepoint` is supported when paired with
        // `positional: true` (covered by the positive
        // "Icon with positional IconData wrap" test). Without
        // `positional: true`, the wrap would try to slot into a
        // non-existent `iconCodepoint:` named parameter — reject.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'NonPositionalIconData',
          library: WidgetLibrary.material,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#Icon',
          childrenSlot: ChildrenSlot.none,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'iconCodepoint',
              type: PropertyType.integer,
              description: '',
              required: true,
              synthetic: 'iconData',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test(
      'skips entries with cross-recipe flatProperties collisions',
      () {
        // Two recipes referencing the same flat property would render
        // the property's value twice (once per structured target) —
        // a malformed-catalog signal.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'CollidingRecipes',
          library: WidgetLibrary.material,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:test_pkg/w.dart#CollidingRecipes',
          childrenSlot: ChildrenSlot.none,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'fontSize',
              type: PropertyType.length,
              description: '',
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: WireIdRef(
                library: 'restage.core',
                wireId: WireId.unallocatedStructured,
              ),
              flatProperties: <WireId, WireId>{},
            ),
            DecompositionRecipe(
              structuredRef: WireIdRef(
                library: 'restage.core',
                wireId: WireId.unallocatedStructured,
              ),
              flatProperties: <WireId, WireId>{},
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test('skips enumValue properties that omit enumType', () {
      // Without enumType, the emitter has no Flutter enum to thread
      // through `ArgumentDecoders.enumValue<T>(T.values, ...)`. The
      // catalog validator rejects this earlier; the emitter rejects
      // again as defense-in-depth.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'WithEnum',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#WithEnum',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'fit',
            type: PropertyType.enumValue,
            description: '',
          ),
        ],
      );
      expect(emitFactoryFunction(entry), isNull);
    });

    test(
      'emits ArgumentDecoders.enumValue<T> for enumType-bearing properties',
      () {
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'WithEnum',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: '',
          flutterType: 'package:test_pkg/w.dart#WithEnum',
          childrenSlot: ChildrenSlot.none,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'fit',
              type: PropertyType.enumValue,
              description: '',
              enumType: 'BoxFit',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(source, contains('fit: ArgumentDecoders.enumValue<BoxFit>'));
        expect(source, contains("BoxFit.values, source, <Object>['fit']"));
      },
    );

    test(
        'renders string defaultValue on alignment as '
        'AlignmentDirectional.<value>', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'WithAlignedAlignment',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#WithAlignedAlignment',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'alignment',
            type: PropertyType.alignment,
            description: '',
            defaultSource: LiteralDefault('topStart'),
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains('?? AlignmentDirectional.topStart'));
    });

    test(
        'renders string defaultValue on alignmentXY as '
        'Alignment.<value>', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'WithConcreteAlignment',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#WithConcreteAlignment',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'alignment',
            type: PropertyType.alignmentXY,
            description: '',
            defaultSource: LiteralDefault('center'),
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains(
          'alignment: RestageDecoders.alignmentXY(source, '
          "<Object>['alignment']) ?? Alignment.center",
        ),
      );
    });

    test('renders string defaultValue on curve as Curves.<value>', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'WithCurve',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#WithCurve',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'curve',
            type: PropertyType.curve,
            description: '',
            defaultSource: LiteralDefault('linear'),
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains(
          'curve: RestageDecoders.curve(source, '
          "<Object>['curve']) ?? Curves.linear",
        ),
      );
    });

    test('renders string defaultValue on enumValue as <EnumType>.<value>', () {
      // `defaultValue: 'start'` carries the enum value name; the
      // emitter combines it with `enumType` to produce a typed
      // fallback so the emitted code satisfies the non-nullable
      // Flutter ctor parameter.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'WithDefaultedEnum',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#WithDefaultedEnum',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'mainAxisAlignment',
            type: PropertyType.enumValue,
            description: '',
            enumType: 'MainAxisAlignment',
            defaultSource: LiteralDefault('start'),
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains('?? MainAxisAlignment.start'));
    });

    test('emits non-canonical widget properties as optionalChild slots', () {
      // AppBar.title is a Widget? slot that lives alongside the
      // widget's other named scalar args; it isn't the canonical
      // 'child' single-slot. Emitter routes it through
      // `source.optionalChild` directly.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'WithNamedSlot',
        library: WidgetLibrary.material,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#WithNamedSlot',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'title',
            type: PropertyType.widget,
            description: '',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains("title: source.optionalChild(<Object>['title'])"),
      );
    });

    test(
      'emits borderRadius synthetic as BorderRadius.circular wrap '
      'with optional-decode coalescing to zero',
      () {
        // `ClipRRect.borderRadius` is non-nullable on the Flutter ctor
        // with default `BorderRadius.zero`. The catalog surfaces the
        // uniform-corner radius as a single real; the synthetic wraps
        // it. The optional decode coalesces to 0.0 so a missing slot
        // collapses to `BorderRadius.zero`.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ClipRRectLike',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#ClipRRect',
          childrenSlot: ChildrenSlot.single,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadius',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCircular',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'child',
              type: PropertyType.widget,
              description: '',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(source, contains('return ClipRRect('));
        expect(
          source,
          stringContainsInOrder([
            'borderRadius: BorderRadius.circular(',
            "source.v<double>(<Object>['borderRadius']) ?? 0.0)",
          ]),
        );
      },
    );

    test(
      'borderRadius synthetic skips the optional coalesce when the property '
      'carries a literal default',
      () {
        // A literal `defaultValue` flows through `_decodeExpression` as
        // `<decoded> ?? <default>` and resolves to a non-null `double`,
        // so the wrap doesn't need its own `?? 0.0` fallback (which
        // would emit a `dead_null_aware_expression` analyzer warning).
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ClipRRectLike',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#ClipRRect',
          childrenSlot: ChildrenSlot.single,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadius',
              type: PropertyType.real,
              description: '',
              defaultSource: LiteralDefault(4.0),
              synthetic: 'borderRadiusCircular',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'child',
              type: PropertyType.widget,
              description: '',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(
          source,
          stringContainsInOrder([
            'borderRadius: BorderRadius.circular(',
            "source.v<double>(<Object>['borderRadius']) ?? 4.0)",
          ]),
        );
        // Defensive: no double-`??` chain.
        expect(source, isNot(contains('?? 4.0) ?? 0.0')));
      },
    );

    test('skips borderRadius synthetic when the property is not real', () {
      // The synthetic only makes sense for a scalar uniform-corner
      // radius. A non-real property carrying the synthetic is a
      // catalog authoring error; the eligibility gate rejects so a
      // misuse surfaces loudly rather than producing a mistyped wrap.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'NonRealBorderRadius',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/widgets.dart#NonRealBorderRadius',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'borderRadius',
            type: PropertyType.integer,
            description: '',
            synthetic: 'borderRadiusCircular',
          ),
        ],
      );
      expect(emitFactoryFunction(entry), isNull);
    });

    test(
      'emits the per-corner BorderRadius.only / circular conditional when '
      'a borderRadius synthetic is paired with corner synthetics (direct sink)',
      () {
        // `ClipRRect.borderRadius` is non-nullable on the Flutter ctor.
        // When the catalog surfaces the four per-corner radii alongside the
        // uniform radius, the emitter must choose `BorderRadius.only(...)`
        // when ANY corner is present on the wire and fall back to the
        // uniform `BorderRadius.circular(...)` otherwise — never both. Each
        // omitted corner coalesces to `0.0` (Flutter's `Radius.zero`).
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ClipRRectLike',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#ClipRRect',
          childrenSlot: ChildrenSlot.single,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadius',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCircular',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusTopLeft',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusTopRight',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusBottomLeft',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusBottomRight',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'child',
              type: PropertyType.widget,
              description: '',
            ),
          ],
        );
        final source = emitFactoryFunction(entry);
        expect(source, isNotNull);
        expect(source, contains('return ClipRRect('));
        // The never-both branch: a presence guard over all four corners
        // selects `.only`, falling through to the uniform `.circular`.
        expect(
          source,
          stringContainsInOrder([
            'borderRadius: (',
            "source.v<double>(<Object>['borderRadiusTopLeft'])",
            "source.v<double>(<Object>['borderRadiusTopRight'])",
            "source.v<double>(<Object>['borderRadiusBottomLeft'])",
            "source.v<double>(<Object>['borderRadiusBottomRight'])",
            ') != null',
            'BorderRadius.only(',
            "topLeft: Radius.circular(source.v<double>(<Object>['borderRadiusTopLeft']) ?? 0.0)",
            "topRight: Radius.circular(source.v<double>(<Object>['borderRadiusTopRight']) ?? 0.0)",
            "bottomLeft: Radius.circular(source.v<double>(<Object>['borderRadiusBottomLeft']) ?? 0.0)",
            "bottomRight: Radius.circular(source.v<double>(<Object>['borderRadiusBottomRight']) ?? 0.0)",
            "BorderRadius.circular(source.v<double>(<Object>['borderRadius']) ?? 0.0)",
          ]),
        );
      },
    );

    test(
      'a partial corner set (3 of 4) fails loud instead of silently '
      'defaulting the missing corner to Radius.zero',
      () {
        // The all-four-or-none curation convention is enforced: a 3-corner
        // slip (here missing `borderRadiusBottomRight`) must throw at
        // emission, NOT silently emit a `BorderRadius.only` that defaults the
        // unmapped corner to `Radius.zero` (every `.only` arg is optional, so
        // a partial set would otherwise compile + mis-render).
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'PartialCornerClip',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#ClipRRect',
          childrenSlot: ChildrenSlot.single,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadius',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCircular',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusTopLeft',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusTopRight',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusBottomLeft',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'child',
              type: PropertyType.widget,
              description: '',
            ),
          ],
        );
        expect(
          () => emitFactoryFunction(entry),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('borderRadius corner synthetics'),
                contains('all four'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'the corner synthetics are not independently emitted as ctor args',
      () {
        // The four corner reals are consumed by the borderRadius emission;
        // they must never surface as `borderRadiusTopLeft: ...` direct
        // named args (which would not match any Flutter ctor parameter).
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'ClipRRectLike',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#ClipRRect',
          childrenSlot: ChildrenSlot.single,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadius',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCircular',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusTopLeft',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusTopRight',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusBottomLeft',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusBottomRight',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'child',
              type: PropertyType.widget,
              description: '',
            ),
          ],
        );
        final source = emitFactoryFunction(entry)!;
        expect(source, isNot(contains('borderRadiusTopLeft:')));
        expect(source, isNot(contains('borderRadiusTopRight:')));
        expect(source, isNot(contains('borderRadiusBottomLeft:')));
        expect(source, isNot(contains('borderRadiusBottomRight:')));
      },
    );

    test(
      'a corner synthetic on its own (no uniform borderRadius) is rejected',
      () {
        // The corner synthetics only make sense paired with the uniform
        // borderRadius synthetic that owns the reconstruction. An orphan
        // corner has no emission path; the eligibility gate rejects.
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'OrphanCorner',
          library: WidgetLibrary.core,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:flutter/widgets.dart#ClipRRect',
          childrenSlot: ChildrenSlot.none,
          fires: [],
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'borderRadiusTopLeft',
              type: PropertyType.real,
              description: '',
              synthetic: 'borderRadiusCorner',
            ),
          ],
        );
        expect(emitFactoryFunction(entry), isNull);
      },
    );

    test('a non-real corner synthetic is rejected', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'NonRealCorner',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/widgets.dart#ClipRRect',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'borderRadius',
            type: PropertyType.real,
            description: '',
            synthetic: 'borderRadiusCircular',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'borderRadiusTopLeft',
            type: PropertyType.integer,
            description: '',
            synthetic: 'borderRadiusCorner',
          ),
        ],
      );
      expect(emitFactoryFunction(entry), isNull);
    });

    test('emits widgetType-bearing widget property with downcast', () {
      // Scaffold.appBar is `PreferredSizeWidget?`, narrower than
      // `Widget?`; the codegen appends a downcast so the slot
      // type-checks against the Flutter ctor parameter.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'WithCastSlot',
        library: WidgetLibrary.material,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#WithCastSlot',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'appBar',
            type: PropertyType.widget,
            description: '',
            widgetType: 'PreferredSizeWidget',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains(
          "appBar: source.optionalChild(<Object>['appBar']) "
          'as PreferredSizeWidget?',
        ),
      );
    });

    test('parses a named-constructor flutterType', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Image',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/widgets.dart#Image.network',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'url',
            type: PropertyType.string,
            description: '',
            required: true,
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      // Named-ctor segment folds into the function name to avoid clashes
      // with sibling Image entries on other ctors.
      expect(
        source,
        contains(
          'Widget _buildImage(BuildContext context, DataSource source)',
        ),
      );
      expect(source, contains('return Image.network('));
      expect(source, contains("source.v<String>(<Object>['url'])"));
    });

    test('emits EdgeInsets.fromLTRB literal for 4-element list defaults', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Padded',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#Padded',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'padding',
            type: PropertyType.edgeInsets,
            description: '',
            defaultSource: LiteralDefault([12.0, 24.0, 12.0, 24.0]),
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains('?? const EdgeInsets.fromLTRB(12.0, 24.0, 12.0, 24.0)'),
      );
    });

    test('rejects a malformed EdgeInsets default at codegen time', () {
      // 2-element list instead of the required 4-element [L,T,R,B].
      // Silent passthrough would drop the declared default with no
      // diagnostic; the emitter throws so the typo surfaces at build.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'BadPadded',
        library: WidgetLibrary.core,
        category: WidgetCategory.layout,
        description: '',
        flutterType: 'package:test_pkg/w.dart#BadPadded',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'padding',
            type: PropertyType.edgeInsets,
            description: '',
            defaultSource: LiteralDefault([12.0, 24.0]),
          ),
        ],
      );
      expect(
        () => emitFactoryFunction(entry),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('4-element list of numbers'),
          ),
        ),
      );
    });

    test(
        'required: false scalar without a defaultValue does NOT inject a '
        'zero fallback (the optional Flutter param accepts null)', () {
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'OptionalScalar',
        library: WidgetLibrary.core,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:test_pkg/w.dart#OptionalScalar',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'label',
            type: PropertyType.string,
            description: '',
          ),
        ],
      );
      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(source, contains("source.v<String>(<Object>['label'])"));
      expect(source, isNot(contains('?? ')));
    });

    // Required scalars without a literal `defaultValue` emit a throw
    // so a malformed blob fails loudly (surfaces as `PaywallLoadFailed`
    // upstream) rather than rendering a silently-zeroed widget the
    // user can't tell is broken. The same rule applies to every
    // emittable scalar property type — including color, where the
    // throw replaces the previous "no fallback, let the consuming
    // package break the build" stance with a runtime guard that's
    // active even when curation drifts.
    const requiredScalarTypes = <PropertyType>[
      PropertyType.boolean,
      PropertyType.integer,
      PropertyType.real,
      PropertyType.length,
      PropertyType.string,
      PropertyType.color,
      PropertyType.edgeInsets,
      PropertyType.alignment,
      PropertyType.alignmentXY,
      PropertyType.fontWeight,
      PropertyType.duration,
      PropertyType.curve,
      // enumValue is in the nullable-decoder truth table too; the loop
      // must lock the contract for it. `_isEmittableProperty` rejects
      // enumValue without an `enumType`, so the fixture supplies one.
      PropertyType.enumValue,
    ];

    for (final type in requiredScalarTypes) {
      test(
        'required: true ${type.name} without defaultValue throws on missing',
        () {
          final widget = WidgetEntry(
            wireId: WireId.unallocatedWidget,
            name: 'RequiredScalar',
            library: WidgetLibrary.core,
            category: WidgetCategory.decoration,
            description: '',
            flutterType: 'package:test_pkg/w.dart#RequiredScalar',
            childrenSlot: ChildrenSlot.none,
            fires: const [],
            properties: [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'value',
                type: type,
                description: '',
                required: true,
                enumType: type == PropertyType.enumValue ? 'BoxFit' : null,
              ),
            ],
          );
          final source = emitFactoryFunction(widget);
          expect(source, isNotNull);
          expect(
            source,
            contains(
              "?? (throw ArgumentError('RequiredScalar.value is required.'))",
            ),
          );
        },
      );
    }
  });

  group('theme-binding defaults', () {
    test(
        'emits a runtime-resolver call as the ?? fallback for a '
        'ThemeBindingDefault color property', () {
      // A `color`-typed property whose default resolves against the
      // active Flutter theme at render time. The emitter routes the
      // `??` fallback through the runtime resolver, cast to the
      // property's nullable Flutter type.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'ThemedIcon',
        library: WidgetLibrary.material,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/material.dart#ThemedIcon',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'color',
            type: PropertyType.color,
            description: '',
            defaultSource: ThemeBindingDefault(
              ThemeBindingPath.path('iconTheme.color'),
            ),
          ),
        ],
      );

      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains(
          "ArgumentDecoders.color(source, <Object>['color']) ?? "
          "resolveThemeBinding(context, path: 'iconTheme.color') as Color?",
        ),
      );
    });

    test(
        'a FlutterCtorDefault property with no legacy defaultValue emits '
        'no ?? fallback', () {
      // `FlutterCtorDefault` explicitly delegates to Flutter's own ctor
      // default — codegen omits the `??` fallback entirely so the
      // Flutter ctor parameter default applies.
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'CtorDefaultIcon',
        library: WidgetLibrary.material,
        category: WidgetCategory.decoration,
        description: '',
        flutterType: 'package:flutter/material.dart#CtorDefaultIcon',
        childrenSlot: ChildrenSlot.none,
        fires: [],
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'color',
            type: PropertyType.color,
            description: '',
            defaultSource: FlutterCtorDefault(),
          ),
        ],
      );

      final source = emitFactoryFunction(entry);
      expect(source, isNotNull);
      expect(
        source,
        contains("ArgumentDecoders.color(source, <Object>['color'])"),
      );
      expect(source, isNot(contains('?? ')));
    });

    group('native decomposition', () {
      test('emits TextStyle from native field mappings', () {
        final fontSizeProp = WireId('p0001');
        final colorProp = WireId('p0002');
        final fontSizeField = WireId('p0003');
        final colorField = WireId('p0004');
        final textStyleRef = _ref('restage.material', 's0001');
        final textStyleCtorRef = _ref('restage.material', 'v0001');

        final entry = WidgetEntry(
          wireId: WireId('w0001'),
          name: 'TextLike',
          library: WidgetLibrary.material,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:test_pkg/w.dart#TextLike',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: fontSizeProp,
              name: 'fontSize',
              type: PropertyType.length,
              description: '',
              defaultSource: const LiteralDefault(14.0),
              valueShape: const ScalarShape(propertyType: PropertyType.length),
            ),
            PropertyEntry(
              wireId: colorProp,
              name: 'color',
              type: PropertyType.color,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.color),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: textStyleRef,
              flatProperties: {
                fontSizeField: fontSizeProp,
                colorField: colorProp,
              },
              targetArg: 'style',
              construction: FactoryInvocation(
                variantRef: textStyleCtorRef,
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: fontSizeField,
                  propertyRef: fontSizeProp,
                  transform: const IdentityTransform(),
                ),
                DecompositionFieldMapping(
                  fieldRef: colorField,
                  propertyRef: colorProp,
                  transform: const IdentityTransform(),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              _textStyleStructured(
                textStyleRef: textStyleRef,
                textStyleCtorRef: textStyleCtorRef,
                fontSizeField: fontSizeField,
                colorField: colorField,
              ),
            ],
          ),
        );

        final source = emitFactoryFunction(entry, nativeIndex: index);
        expect(source, isNotNull);
        expect(
          source,
          matches(
            RegExp(
              r'style:\s*TextStyle\(\s*'
              r"fontSize:\s*source\.v<double>\(<Object>\['fontSize'\]\)"
              r' \?\? 14\.0,\s*'
              r"color:\s*ArgumentDecoders\.color\(source, <Object>\['color'\]\)"
              r'\s*\)',
            ),
          ),
        );
        expect(source, isNot(contains('    fontSize: source')));
        expect(source, isNot(contains('    color: ArgumentDecoders')));
      });

      test('constructVariant error policy emits a required-throw fallback', () {
        final radiusProp = WireId('p0001');
        final radiusField = WireId('p0002');
        final boxRef = _ref('restage.core', 's0001');
        final boxCtorRef = _ref('restage.core', 'v0001');
        final borderRadiusRef = _ref('restage.core', 's0002');
        final circularCtorRef = _ref('restage.core', 'v0002');
        final circularRadiusParam = WireId('a0001');

        final entry = WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Decorated',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: '',
          flutterType: 'package:flutter/widgets.dart#Decorated',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: radiusProp,
              name: 'borderRadius',
              type: PropertyType.real,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.real),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: boxRef,
              flatProperties: {radiusField: radiusProp},
              targetArg: 'decoration',
              construction: FactoryInvocation(
                variantRef: boxCtorRef,
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: radiusField,
                  propertyRef: radiusProp,
                  transform: ConstructVariantTransform(
                    resultStructuredRef: borderRadiusRef,
                    invocation: FactoryInvocation(
                      variantRef: circularCtorRef,
                      receiver: const ResultStructuredTypeReceiver(),
                      memberName: 'circular',
                    ),
                    argumentBindings: [
                      PropertyValueArgumentBinding(
                        parameterRef: circularRadiusParam,
                        nullPolicy: TransformNullPolicy.error,
                        missingPolicy: TransformMissingPolicy.error,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              _boxDecorationSingleRadius(
                boxRef: boxRef,
                boxCtorRef: boxCtorRef,
                borderRadiusRef: borderRadiusRef,
                radiusField: radiusField,
              ),
              _borderRadiusStructured(
                borderRadiusRef: borderRadiusRef,
                circularCtorRef: circularCtorRef,
                circularRadiusParam: circularRadiusParam,
              ),
            ],
          ),
        );

        final source = emitFactoryFunction(entry, nativeIndex: index);
        expect(source, isNotNull);
        // The error policy emits a loud throw rather than a silent `!`.
        expect(source, contains('throw ArgumentError'));
        expect(source, contains('Decorated.borderRadius is required.'));
      });

      test('constructVariant literal source emits the literal value', () {
        final radiusProp = WireId('p0001');
        final radiusField = WireId('p0002');
        final boxRef = _ref('restage.core', 's0001');
        final boxCtorRef = _ref('restage.core', 'v0001');
        final borderRadiusRef = _ref('restage.core', 's0002');
        final circularCtorRef = _ref('restage.core', 'v0002');
        final circularRadiusParam = WireId('a0001');

        final entry = WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Decorated',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: '',
          flutterType: 'package:flutter/widgets.dart#Decorated',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: radiusProp,
              name: 'borderRadius',
              type: PropertyType.real,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.real),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: boxRef,
              flatProperties: {radiusField: radiusProp},
              targetArg: 'decoration',
              construction: FactoryInvocation(
                variantRef: boxCtorRef,
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: radiusField,
                  propertyRef: radiusProp,
                  transform: ConstructVariantTransform(
                    resultStructuredRef: borderRadiusRef,
                    invocation: FactoryInvocation(
                      variantRef: circularCtorRef,
                      receiver: const ResultStructuredTypeReceiver(),
                      memberName: 'circular',
                    ),
                    argumentBindings: [
                      LiteralArgumentBinding(
                        literal: 8.0,
                        parameterRef: circularRadiusParam,
                        nullPolicy: TransformNullPolicy.nullResult,
                        missingPolicy: TransformMissingPolicy.nullResult,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              _boxDecorationSingleRadius(
                boxRef: boxRef,
                boxCtorRef: boxCtorRef,
                borderRadiusRef: borderRadiusRef,
                radiusField: radiusField,
              ),
              _borderRadiusStructured(
                borderRadiusRef: borderRadiusRef,
                circularCtorRef: circularCtorRef,
                circularRadiusParam: circularRadiusParam,
              ),
            ],
          ),
        );

        final source = emitFactoryFunction(entry, nativeIndex: index);
        expect(source, isNotNull);
        // The literal binding renders the literal value verbatim, with no
        // decoder call or null guard.
        expect(source, contains('BorderRadius.circular(8.0)'));
        // A literal binding takes no decoder call / null guard for the slot.
        expect(
          source,
          isNot(contains("source.v<double>(<Object>['borderRadius']")),
        );
      });

      test(
          'constructVariant nestedTransform that is not a constructVariant '
          'fails with a diagnostic naming the actual transform kind', () {
        // A NestedTransformArgumentBinding whose nested transform is an
        // IdentityTransform (not the constructVariant the emitter requires)
        // passes the support check (identity is supported) but cannot be
        // emitted as a nested construction. The diagnostic must name the real
        // failure — the wrong transform subtype — not "missing metadata".
        final radiusProp = WireId('p0001');
        final radiusField = WireId('p0002');
        final boxRef = _ref('restage.core', 's0001');
        final boxCtorRef = _ref('restage.core', 'v0001');
        final borderRadiusRef = _ref('restage.core', 's0002');
        final circularCtorRef = _ref('restage.core', 'v0002');
        final circularRadiusParam = WireId('a0001');

        final entry = WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Decorated',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: '',
          flutterType: 'package:flutter/widgets.dart#Decorated',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: radiusProp,
              name: 'borderRadius',
              type: PropertyType.real,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.real),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: boxRef,
              flatProperties: {radiusField: radiusProp},
              targetArg: 'decoration',
              construction: FactoryInvocation(
                variantRef: boxCtorRef,
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: radiusField,
                  propertyRef: radiusProp,
                  transform: ConstructVariantTransform(
                    resultStructuredRef: borderRadiusRef,
                    invocation: FactoryInvocation(
                      variantRef: circularCtorRef,
                      receiver: const ResultStructuredTypeReceiver(),
                      memberName: 'circular',
                    ),
                    argumentBindings: [
                      NestedTransformArgumentBinding(
                        nestedTransform: const IdentityTransform(),
                        parameterRef: circularRadiusParam,
                        nullPolicy: TransformNullPolicy.nullResult,
                        missingPolicy: TransformMissingPolicy.nullResult,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              _boxDecorationSingleRadius(
                boxRef: boxRef,
                boxCtorRef: boxCtorRef,
                borderRadiusRef: borderRadiusRef,
                radiusField: radiusField,
              ),
              _borderRadiusStructured(
                borderRadiusRef: borderRadiusRef,
                circularCtorRef: circularCtorRef,
                circularRadiusParam: circularRadiusParam,
              ),
            ],
          ),
        );

        expect(
          () => emitFactoryFunction(entry, nativeIndex: index),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('must be a constructVariant transform'),
                contains('identity'),
              ),
            ),
          ),
        );
      });

      test('emits native enum properties from valueShape enumRef', () {
        final shapeProp = WireId('p0001');
        final shapeField = WireId('p0002');
        final boxRef = _ref('restage.core', 's0001');
        final boxCtorRef = _ref('restage.core', 'v0001');

        final entry = WidgetEntry(
          wireId: WireId('w0001'),
          name: 'Decorated',
          library: WidgetLibrary.core,
          category: WidgetCategory.layout,
          description: '',
          flutterType: 'package:flutter/widgets.dart#Decorated',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: shapeProp,
              name: 'shape',
              type: PropertyType.enumValue,
              description: '',
              defaultSource: const LiteralDefault('rectangle'),
              valueShape: const EnumShape(
                propertyType: PropertyType.enumValue,
                enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/painting.dart',
                  symbolName: 'BoxShape',
                ),
              ),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: boxRef,
              flatProperties: {shapeField: shapeProp},
              targetArg: 'decoration',
              construction: FactoryInvocation(
                variantRef: boxCtorRef,
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: shapeField,
                  propertyRef: shapeProp,
                  transform: const IdentityTransform(),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              StructuredEntry(
                wireId: boxRef.wireId,
                name: 'BoxDecoration',
                library: WidgetLibrary.fromNamespace(boxRef.library),
                description: '',
                sourceType: 'package:flutter/painting.dart#BoxDecoration',
                fields: [
                  StructuredField(
                    wireId: shapeField,
                    name: 'shape',
                    type: PropertyType.enumValue,
                    description: '',
                    valueShape: const EnumShape(
                      propertyType: PropertyType.enumValue,
                      enumRef: DartTypeRef(
                        libraryUri: 'package:flutter/painting.dart',
                        symbolName: 'BoxShape',
                      ),
                    ),
                  ),
                ],
                variants: [
                  ConstructorVariant(
                    wireId: boxCtorRef.wireId,
                    argMappings: {
                      'shape': ArgMapping(targetFields: [shapeField]),
                    },
                    parameters: [
                      _namedParam(
                        wireId: WireId('a0001'),
                        name: 'shape',
                        propertyType: PropertyType.enumValue,
                        valueShape: const EnumShape(
                          propertyType: PropertyType.enumValue,
                          enumRef: DartTypeRef(
                            libraryUri: 'package:flutter/painting.dart',
                            symbolName: 'BoxShape',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );

        final source = emitFactoryFunction(entry, nativeIndex: index);

        expect(source, isNotNull);
        expect(
          source,
          contains(
            [
              'shape: ArgumentDecoders.enumValue<BoxShape>(',
              "BoxShape.values, source, <Object>['shape']) ?? ",
              'BoxShape.rectangle',
            ].join(),
          ),
        );
      });

      test('fails loudly for unsupported native scalar coercions', () {
        final fontSizeProp = WireId('p0001');
        final fontSizeField = WireId('p0002');
        final textStyleRef = _ref('restage.material', 's0001');
        final textStyleCtorRef = _ref('restage.material', 'v0001');

        final entry = WidgetEntry(
          wireId: WireId('w0001'),
          name: 'TextLike',
          library: WidgetLibrary.material,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:test_pkg/w.dart#TextLike',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: fontSizeProp,
              name: 'fontSize',
              type: PropertyType.real,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.real),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: textStyleRef,
              flatProperties: {fontSizeField: fontSizeProp},
              targetArg: 'style',
              construction: FactoryInvocation(
                variantRef: textStyleCtorRef,
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: fontSizeField,
                  propertyRef: fontSizeProp,
                  transform: const CoerceScalarTransform(
                    scalarCoercion: 'realToLength',
                  ),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              StructuredEntry(
                wireId: textStyleRef.wireId,
                name: 'TextStyle',
                library: WidgetLibrary.fromNamespace(textStyleRef.library),
                description: '',
                sourceType: 'package:flutter/painting.dart#TextStyle',
                fields: [
                  StructuredField(
                    wireId: fontSizeField,
                    name: 'fontSize',
                    type: PropertyType.length,
                    description: '',
                    valueShape:
                        const ScalarShape(propertyType: PropertyType.length),
                  ),
                ],
                variants: [
                  ConstructorVariant(
                    wireId: textStyleCtorRef.wireId,
                    argMappings: {
                      'fontSize': ArgMapping(targetFields: [fontSizeField]),
                    },
                    parameters: [
                      _namedParam(
                        wireId: WireId('a0001'),
                        name: 'fontSize',
                        propertyType: PropertyType.length,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );

        expect(
          () => emitFactoryFunction(entry, nativeIndex: index),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('coerceScalar'),
                contains('TextLike.fontSize'),
                contains('factory emission'),
              ),
            ),
          ),
        );
      });

      test('fails when a native field mapping is not in the variant args', () {
        final fontSizeProp = WireId('p0001');
        final colorProp = WireId('p0002');
        final fontSizeField = WireId('p0003');
        final colorField = WireId('p0004');
        final textStyleRef = _ref('restage.material', 's0001');
        final textStyleCtorRef = _ref('restage.material', 'v0001');

        final entry = WidgetEntry(
          wireId: WireId('w0001'),
          name: 'TextLike',
          library: WidgetLibrary.material,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:test_pkg/w.dart#TextLike',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: fontSizeProp,
              name: 'fontSize',
              type: PropertyType.length,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.length),
            ),
            PropertyEntry(
              wireId: colorProp,
              name: 'color',
              type: PropertyType.color,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.color),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: textStyleRef,
              flatProperties: {
                fontSizeField: fontSizeProp,
                colorField: colorProp,
              },
              targetArg: 'style',
              construction: FactoryInvocation(
                variantRef: textStyleCtorRef,
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: fontSizeField,
                  propertyRef: fontSizeProp,
                  transform: const IdentityTransform(),
                ),
                DecompositionFieldMapping(
                  fieldRef: colorField,
                  propertyRef: colorProp,
                  transform: const IdentityTransform(),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              _textStyleStructured(
                textStyleRef: textStyleRef,
                textStyleCtorRef: textStyleCtorRef,
                fontSizeField: fontSizeField,
                colorField: colorField,
                includeColorArgMapping: false,
              ),
            ],
          ),
        );

        expect(
          () => emitFactoryFunction(entry, nativeIndex: index),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains(colorField.value),
                contains(textStyleCtorRef.wireId.value),
                contains('argMapping'),
              ),
            ),
          ),
        );
      });

      test('fails when a mapped native field has no factory parameter', () {
        final fontSizeProp = WireId('p0001');
        final colorProp = WireId('p0002');
        final fontSizeField = WireId('p0003');
        final colorField = WireId('p0004');
        final textStyleRef = _ref('restage.material', 's0001');
        final textStyleCtorRef = _ref('restage.material', 'v0001');

        final entry = WidgetEntry(
          wireId: WireId('w0001'),
          name: 'TextLike',
          library: WidgetLibrary.material,
          category: WidgetCategory.decoration,
          description: '',
          flutterType: 'package:test_pkg/w.dart#TextLike',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: [
            PropertyEntry(
              wireId: fontSizeProp,
              name: 'fontSize',
              type: PropertyType.length,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.length),
            ),
            PropertyEntry(
              wireId: colorProp,
              name: 'color',
              type: PropertyType.color,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.color),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: textStyleRef,
              flatProperties: {
                fontSizeField: fontSizeProp,
                colorField: colorProp,
              },
              targetArg: 'style',
              construction: FactoryInvocation(
                variantRef: textStyleCtorRef,
                receiver: const ResultStructuredTypeReceiver(),
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: fontSizeField,
                  propertyRef: fontSizeProp,
                  transform: const IdentityTransform(),
                ),
                DecompositionFieldMapping(
                  fieldRef: colorField,
                  propertyRef: colorProp,
                  transform: const IdentityTransform(),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              _textStyleStructured(
                textStyleRef: textStyleRef,
                textStyleCtorRef: textStyleCtorRef,
                fontSizeField: fontSizeField,
                colorField: colorField,
                includeColorParameter: false,
              ),
            ],
          ),
        );

        expect(
          () => emitFactoryFunction(entry, nativeIndex: index),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains(colorField.value),
                contains(textStyleCtorRef.wireId.value),
                contains('parameter'),
              ),
            ),
          ),
        );
      });

      test('emits widget-scoped styleFrom from native receiver metadata', () {
        final childProp = WireId('p0001');
        final eventProp = WireId('p0002');
        final backgroundColorProp = WireId('p0003');
        final paddingProp = WireId('p0004');
        final backgroundColorField = WireId('p0005');
        final paddingField = WireId('p0006');
        final buttonStyleRef = _ref('restage.material', 's0002');
        final styleFromRef = _ref('restage.material', 'v0002');

        final entry = WidgetEntry(
          wireId: WireId('w0002'),
          name: 'GeneratedButton',
          library: WidgetLibrary.material,
          category: WidgetCategory.action,
          description: '',
          flutterType: 'package:test_pkg/w.dart#GeneratedButton',
          childrenSlot: ChildrenSlot.single,
          fires: const [WidgetEventName.onPressed],
          properties: [
            PropertyEntry(
              wireId: childProp,
              name: 'child',
              type: PropertyType.widget,
              description: '',
              required: true,
            ),
            PropertyEntry(
              wireId: eventProp,
              name: 'onPressed',
              type: PropertyType.event,
              description: '',
            ),
            PropertyEntry(
              wireId: backgroundColorProp,
              name: 'backgroundColor',
              type: PropertyType.color,
              description: '',
              valueShape: const ScalarShape(propertyType: PropertyType.color),
            ),
            PropertyEntry(
              wireId: paddingProp,
              name: 'padding',
              type: PropertyType.edgeInsets,
              description: '',
              valueShape:
                  const ScalarShape(propertyType: PropertyType.edgeInsets),
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: buttonStyleRef,
              flatProperties: {
                backgroundColorField: backgroundColorProp,
                paddingField: paddingProp,
              },
              targetArg: 'style',
              construction: FactoryInvocation(
                variantRef: styleFromRef,
                receiver: const OwningWidgetTypeReceiver(),
                memberName: 'styleFrom',
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: backgroundColorField,
                  propertyRef: backgroundColorProp,
                  transform: const IdentityTransform(),
                ),
                DecompositionFieldMapping(
                  fieldRef: paddingField,
                  propertyRef: paddingProp,
                  transform: const IdentityTransform(),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              _buttonStyleStructured(
                buttonStyleRef: buttonStyleRef,
                styleFromRef: styleFromRef,
                backgroundColorField: backgroundColorField,
                paddingField: paddingField,
              ),
            ],
          ),
        );

        final source = emitFactoryFunction(entry, nativeIndex: index);
        expect(source, isNotNull);
        expect(
          source,
          matches(
            RegExp(
              r'style:\s*GeneratedButton\.styleFrom\(\s*'
              r'backgroundColor:\s*ArgumentDecoders\.color\(source, '
              r"<Object>\['backgroundColor'\]\),\s*"
              r'padding:\s*ArgumentDecoders\.edgeInsets\(source, '
              r"<Object>\['padding'\]\)\s*\)",
            ),
          ),
        );
      });

      test('emits button shape through native identity metadata', () {
        final childProp = WireId('p0001');
        final eventProp = WireId('p0002');
        final shapeProp = WireId('p0003');
        final shapeField = WireId('p0004');
        final backgroundColorField = WireId('p0005');
        final paddingField = WireId('p0006');
        final buttonStyleRef = _ref('restage.material', 's0002');
        final styleFromRef = _ref('restage.material', 'v0002');
        final outlinedBorderRef = _ref('restage.material', 'u0001');
        final roundedBorderRef = _ref('restage.material', 's0003');
        final shapeShape = UnionShape(
          propertyType: PropertyType.shapeBorder,
          unionRef: outlinedBorderRef,
          wireCodec: CatalogWireCodec.rfwShapeBorder,
        );

        final entry = WidgetEntry(
          wireId: WireId('w0002'),
          name: 'GeneratedButton',
          library: WidgetLibrary.material,
          category: WidgetCategory.action,
          description: '',
          flutterType: 'package:test_pkg/w.dart#GeneratedButton',
          childrenSlot: ChildrenSlot.single,
          fires: const [WidgetEventName.onPressed],
          properties: [
            PropertyEntry(
              wireId: childProp,
              name: 'child',
              type: PropertyType.widget,
              description: '',
              required: true,
            ),
            PropertyEntry(
              wireId: eventProp,
              name: 'onPressed',
              type: PropertyType.event,
              description: '',
            ),
            PropertyEntry(
              wireId: shapeProp,
              name: 'shape',
              type: PropertyType.shapeBorder,
              description: '',
              valueShape: shapeShape,
            ),
          ],
          decomposes: [
            DecompositionRecipe(
              structuredRef: buttonStyleRef,
              flatProperties: {shapeField: shapeProp},
              targetArg: 'style',
              construction: FactoryInvocation(
                variantRef: styleFromRef,
                receiver: const OwningWidgetTypeReceiver(),
                memberName: 'styleFrom',
              ),
              fieldMappings: [
                DecompositionFieldMapping(
                  fieldRef: shapeField,
                  propertyRef: shapeProp,
                  transform: const IdentityTransform(),
                ),
              ],
            ),
          ],
        );
        final index = NativeCatalogIndex(
          _catalogWith(
            widgets: [entry],
            structuredTypes: [
              _buttonStyleStructured(
                buttonStyleRef: buttonStyleRef,
                styleFromRef: styleFromRef,
                backgroundColorField: backgroundColorField,
                paddingField: paddingField,
                shapeField: shapeField,
                shapeValueShape: shapeShape,
              ),
              StructuredEntry(
                wireId: roundedBorderRef.wireId,
                name: 'RoundedRectangleBorder',
                library: WidgetLibrary.material,
                description: '',
                sourceType:
                    'package:flutter/painting.dart#RoundedRectangleBorder',
                fields: const [],
                variants: const [],
              ),
            ],
            unions: [
              UnionEntry(
                wireId: outlinedBorderRef.wireId,
                name: 'OutlinedBorder',
                library: WidgetLibrary.material,
                description: '',
                sourceType: 'package:flutter/painting.dart#OutlinedBorder',
                memberSourceTypes: const [
                  'package:flutter/painting.dart#RoundedRectangleBorder',
                ],
                discriminator: DiscriminatorSpec(
                  field: '_s',
                  values: [roundedBorderRef],
                ),
                members: [roundedBorderRef],
              ),
            ],
          ),
        );

        final source = emitFactoryFunction(entry, nativeIndex: index);
        expect(source, isNotNull);
        expect(source, contains('style: GeneratedButton.styleFrom('));
        expect(
          source,
          stringContainsInOrder([
            'shape: (RestageDecoders.shapeBorder(',
            "source, <Object>['shape']",
            'as OutlinedBorder?)',
          ]),
        );
      });

      test(
        'emits BoxDecoration native mappings including nested radius and '
        'union codecs',
        () {
          final radiusProp = WireId('p0001');
          final shapeProp = WireId('p0002');
          final boxShadowProp = WireId('p0003');
          final gradientProp = WireId('p0004');
          final borderProp = WireId('p0005');
          final childProp = WireId('p0006');
          final radiusField = WireId('p0007');
          final shapeField = WireId('p0008');
          final boxShadowField = WireId('p0009');
          final gradientField = WireId('p0010');
          final borderField = WireId('p0011');
          final boxRef = _ref('restage.core', 's0003');
          final borderRadiusRef = _ref('restage.core', 's0004');
          final linearGradientRef = _ref('restage.core', 's0005');
          final borderRef = _ref('restage.core', 's0006');
          final boxShadowRef = _ref('restage.core', 's0007');
          final gradientUnionRef = _ref('restage.core', 'u0001');
          final borderUnionRef = _ref('restage.core', 'u0002');
          final boxCtorRef = _ref('restage.core', 'v0003');
          final circularCtorRef = _ref('restage.core', 'v0004');
          final circularRadiusParam = WireId('a0006');

          final entry = WidgetEntry(
            wireId: WireId('w0003'),
            name: 'ContainerLike',
            library: WidgetLibrary.core,
            category: WidgetCategory.layout,
            description: '',
            flutterType: 'package:flutter/widgets.dart#Container',
            childrenSlot: ChildrenSlot.single,
            fires: const [],
            properties: [
              PropertyEntry(
                wireId: radiusProp,
                name: 'borderRadius',
                type: PropertyType.real,
                description: '',
                valueShape: const ScalarShape(propertyType: PropertyType.real),
              ),
              PropertyEntry(
                wireId: shapeProp,
                name: 'shape',
                type: PropertyType.enumValue,
                description: '',
                enumType: 'BoxShape',
                defaultSource: const LiteralDefault('rectangle'),
                valueShape: const EnumShape(
                  propertyType: PropertyType.enumValue,
                  enumRef: DartTypeRef(
                    libraryUri: 'package:flutter/painting.dart',
                    symbolName: 'BoxShape',
                  ),
                ),
              ),
              PropertyEntry(
                wireId: boxShadowProp,
                name: 'boxShadow',
                type: PropertyType.boxShadowList,
                description: '',
                valueShape: ListShape(
                  propertyType: PropertyType.boxShadowList,
                  itemShape: StructuredShape(
                    propertyType: PropertyType.structured,
                    structuredRef: boxShadowRef,
                  ),
                  wireCodec: CatalogWireCodec.rfwBoxShadowList,
                ),
              ),
              PropertyEntry(
                wireId: gradientProp,
                name: 'gradient',
                type: PropertyType.gradient,
                description: '',
                valueShape: UnionShape(
                  propertyType: PropertyType.gradient,
                  unionRef: gradientUnionRef,
                  wireCodec: CatalogWireCodec.rfwGradient,
                ),
              ),
              PropertyEntry(
                wireId: borderProp,
                name: 'border',
                type: PropertyType.border,
                description: '',
                valueShape: UnionShape(
                  propertyType: PropertyType.border,
                  unionRef: borderUnionRef,
                  wireCodec: CatalogWireCodec.rfwBorder,
                ),
              ),
              PropertyEntry(
                wireId: childProp,
                name: 'child',
                type: PropertyType.widget,
                description: '',
              ),
            ],
            decomposes: [
              DecompositionRecipe(
                structuredRef: boxRef,
                flatProperties: {
                  radiusField: radiusProp,
                  shapeField: shapeProp,
                  boxShadowField: boxShadowProp,
                  gradientField: gradientProp,
                  borderField: borderProp,
                },
                targetArg: 'decoration',
                construction: FactoryInvocation(
                  variantRef: boxCtorRef,
                  receiver: const ResultStructuredTypeReceiver(),
                ),
                fieldMappings: [
                  DecompositionFieldMapping(
                    fieldRef: radiusField,
                    propertyRef: radiusProp,
                    transform: ConstructVariantTransform(
                      resultStructuredRef: borderRadiusRef,
                      invocation: FactoryInvocation(
                        variantRef: circularCtorRef,
                        receiver: const ResultStructuredTypeReceiver(),
                        memberName: 'circular',
                      ),
                      argumentBindings: [
                        PropertyValueArgumentBinding(
                          parameterRef: circularRadiusParam,
                          nullPolicy: TransformNullPolicy.nullResult,
                          missingPolicy: TransformMissingPolicy.nullResult,
                        ),
                      ],
                    ),
                  ),
                  DecompositionFieldMapping(
                    fieldRef: shapeField,
                    propertyRef: shapeProp,
                    transform: const IdentityTransform(),
                  ),
                  DecompositionFieldMapping(
                    fieldRef: boxShadowField,
                    propertyRef: boxShadowProp,
                    transform: const ProjectListTransform(
                      itemTransform: IdentityTransform(),
                    ),
                  ),
                  DecompositionFieldMapping(
                    fieldRef: gradientField,
                    propertyRef: gradientProp,
                    transform: const IdentityTransform(),
                  ),
                  DecompositionFieldMapping(
                    fieldRef: borderField,
                    propertyRef: borderProp,
                    transform: const IdentityTransform(),
                  ),
                ],
              ),
            ],
          );
          final index = NativeCatalogIndex(
            _catalogWith(
              widgets: [entry],
              structuredTypes: [
                _boxDecorationStructured(
                  boxRef: boxRef,
                  boxCtorRef: boxCtorRef,
                  borderRadiusRef: borderRadiusRef,
                  boxShadowRef: boxShadowRef,
                  radiusField: radiusField,
                  shapeField: shapeField,
                  boxShadowField: boxShadowField,
                  gradientField: gradientField,
                  borderField: borderField,
                  gradientUnionRef: gradientUnionRef,
                  borderUnionRef: borderUnionRef,
                ),
                _borderRadiusStructured(
                  borderRadiusRef: borderRadiusRef,
                  circularCtorRef: circularCtorRef,
                  circularRadiusParam: circularRadiusParam,
                ),
                _emptyStructured(
                  ref: linearGradientRef,
                  name: 'LinearGradient',
                  sourceType: 'package:flutter/painting.dart#LinearGradient',
                ),
                _emptyStructured(
                  ref: borderRef,
                  name: 'Border',
                  sourceType: 'package:flutter/painting.dart#Border',
                ),
                _emptyStructured(
                  ref: boxShadowRef,
                  name: 'BoxShadow',
                  sourceType: 'package:flutter/painting.dart#BoxShadow',
                ),
              ],
              unions: [
                _union(
                  ref: gradientUnionRef,
                  name: 'Gradient',
                  sourceType: 'package:flutter/painting.dart#Gradient',
                  memberRef: linearGradientRef,
                  memberSourceType:
                      'package:flutter/painting.dart#LinearGradient',
                ),
                _union(
                  ref: borderUnionRef,
                  name: 'BoxBorder',
                  sourceType: 'package:flutter/painting.dart#BoxBorder',
                  memberRef: borderRef,
                  memberSourceType: 'package:flutter/painting.dart#Border',
                ),
              ],
            ),
          );

          final source = emitFactoryFunction(entry, nativeIndex: index);
          expect(source, isNotNull);
          expect(source, contains('decoration: BoxDecoration('));
          expect(
            source,
            stringContainsInOrder([
              'borderRadius: ',
              "source.v<double>(<Object>['borderRadius']) == null",
              '? null',
              ': BorderRadius.circular(',
            ]),
          );
          expect(source, isNot(contains('?? 0.0)')));
          expect(
            source,
            contains(
              [
                'shape: ArgumentDecoders.enumValue<BoxShape>(',
                "BoxShape.values, source, <Object>['shape']) ?? ",
                'BoxShape.rectangle',
              ].join(),
            ),
          );
          expect(
            source,
            contains(
              [
                'boxShadow: ArgumentDecoders.list<BoxShadow>(',
                "source, <Object>['boxShadow'], ArgumentDecoders.boxShadow)",
              ].join(),
            ),
          );
          expect(
            source,
            contains(
              [
                'gradient: ArgumentDecoders.gradient(',
                "source, <Object>['gradient'])",
              ].join(),
            ),
          );
          expect(
            source,
            contains(
              "border: ArgumentDecoders.border(source, <Object>['border'])",
            ),
          );
        },
      );

      test(
        'emits mapped constructor-only parameters and typed default fallbacks',
        () {
          final inheritProp = WireId('p0001');
          final fontPackageProp = WireId('p0002');
          final inheritField = WireId('p0003');
          final colorField = WireId('p0004');
          final textStyleRef = _ref('restage.core', 's0001');
          final textStyleCtorRef = _ref('restage.core', 'v0001');
          final inheritParam = WireId('a0001');
          final packageParam = WireId('a0002');

          final entry = WidgetEntry(
            wireId: WireId('w0001'),
            name: 'Text',
            library: WidgetLibrary.core,
            category: WidgetCategory.decoration,
            description: '',
            flutterType: 'package:flutter/widgets.dart#Text',
            childrenSlot: ChildrenSlot.none,
            fires: const [],
            properties: [
              PropertyEntry(
                wireId: inheritProp,
                name: 'inherit',
                type: PropertyType.boolean,
                description: '',
                valueShape:
                    const ScalarShape(propertyType: PropertyType.boolean),
              ),
              PropertyEntry(
                wireId: fontPackageProp,
                name: 'fontPackage',
                type: PropertyType.string,
                description: '',
                valueShape:
                    const ScalarShape(propertyType: PropertyType.string),
              ),
            ],
            decomposes: [
              DecompositionRecipe(
                structuredRef: textStyleRef,
                flatProperties: {inheritField: inheritProp},
                targetArg: 'style',
                construction: FactoryInvocation(
                  variantRef: textStyleCtorRef,
                  receiver: const ResultStructuredTypeReceiver(),
                ),
                fieldMappings: [
                  DecompositionFieldMapping(
                    fieldRef: inheritField,
                    propertyRef: inheritProp,
                    transform: const IdentityTransform(),
                  ),
                ],
                parameterMappings: [
                  DecompositionParameterMapping(
                    parameterRef: packageParam,
                    propertyRef: fontPackageProp,
                    transform: const IdentityTransform(),
                  ),
                ],
              ),
            ],
          );
          final index = NativeCatalogIndex(
            _catalogWith(
              widgets: [entry],
              structuredTypes: [
                _textStyleStructured(
                  textStyleRef: textStyleRef,
                  textStyleCtorRef: textStyleCtorRef,
                  inheritField: inheritField,
                  colorField: colorField,
                  inheritParam: inheritParam,
                  packageParam: packageParam,
                  includeColorArgMapping: false,
                  includeColorParameter: false,
                ),
              ],
            ),
          );

          final source = emitFactoryFunction(entry, nativeIndex: index);

          expect(source, isNotNull);
          expect(source, contains('style: TextStyle('));
          expect(
            source,
            contains("inherit: source.v<bool>(<Object>['inherit']) ?? true"),
          );
          expect(
            source,
            contains("package: source.v<String>(<Object>['fontPackage'])"),
          );
          expect(source, isNot(contains('color:')));
        },
      );
    });
  });
}

WireIdRef _ref(String library, String wireId) =>
    WireIdRef(library: library, wireId: WireId(wireId));

Catalog _catalogWith({
  required List<WidgetEntry> widgets,
  required List<StructuredEntry> structuredTypes,
  List<UnionEntry> unions = const [],
}) {
  final libraries = <WidgetLibrary, LibraryInfo>{};
  for (final widget in widgets) {
    libraries[widget.library] = const LibraryInfo(version: '1.0.0');
  }
  for (final structured in structuredTypes) {
    libraries.putIfAbsent(
      structured.library,
      () => const LibraryInfo(version: '1.0.0'),
    );
  }
  for (final union in unions) {
    libraries.putIfAbsent(
      union.library,
      () => const LibraryInfo(version: '1.0.0'),
    );
  }
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: libraries,
    widgets: widgets,
    structuredTypes: structuredTypes,
    unions: unions,
  );
}

StructuredEntry _textStyleStructured({
  required WireIdRef textStyleRef,
  required WireIdRef textStyleCtorRef,
  required WireId colorField,
  WireId? fontSizeField,
  WireId? inheritField,
  WireId? inheritParam,
  WireId? packageParam,
  bool includeColorArgMapping = true,
  bool includeColorParameter = true,
}) =>
    StructuredEntry(
      wireId: textStyleRef.wireId,
      name: 'TextStyle',
      library: WidgetLibrary.fromNamespace(textStyleRef.library),
      description: '',
      sourceType: 'package:flutter/painting.dart#TextStyle',
      fields: [
        if (fontSizeField != null)
          StructuredField(
            wireId: fontSizeField,
            name: 'fontSize',
            type: PropertyType.length,
            description: '',
            valueShape: const ScalarShape(propertyType: PropertyType.length),
          ),
        if (inheritField != null)
          StructuredField(
            wireId: inheritField,
            name: 'inherit',
            type: PropertyType.boolean,
            description: '',
            valueShape: const ScalarShape(propertyType: PropertyType.boolean),
          ),
        StructuredField(
          wireId: colorField,
          name: 'color',
          type: PropertyType.color,
          description: '',
          valueShape: const ScalarShape(propertyType: PropertyType.color),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: textStyleCtorRef.wireId,
          argMappings: {
            if (fontSizeField != null)
              'fontSize': ArgMapping(targetFields: [fontSizeField]),
            if (inheritField != null)
              'inherit': ArgMapping(targetFields: [inheritField]),
            if (includeColorArgMapping)
              'color': ArgMapping(targetFields: [colorField]),
          },
          parameters: [
            if (fontSizeField != null)
              _namedParam(
                wireId: WireId('a0001'),
                name: 'fontSize',
                propertyType: PropertyType.length,
              ),
            if (inheritParam != null)
              FactoryParameter(
                wireId: inheritParam,
                name: 'inherit',
                kind: FactoryParameterKind.named,
                required: false,
                nullable: false,
                defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
                defaultValue: const LiteralParameterDefault(true),
                valueShape:
                    const ScalarShape(propertyType: PropertyType.boolean),
              ),
            if (packageParam != null)
              FactoryParameter(
                wireId: packageParam,
                name: 'package',
                kind: FactoryParameterKind.named,
                required: false,
                nullable: true,
                defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
                valueShape:
                    const ScalarShape(propertyType: PropertyType.string),
              ),
            if (includeColorParameter)
              _namedParam(
                wireId: WireId('a0002'),
                name: 'color',
                propertyType: PropertyType.color,
              ),
          ],
        ),
      ],
    );

StructuredEntry _buttonStyleStructured({
  required WireIdRef buttonStyleRef,
  required WireIdRef styleFromRef,
  required WireId backgroundColorField,
  required WireId paddingField,
  WireId? shapeField,
  CatalogValueShape? shapeValueShape,
}) =>
    StructuredEntry(
      wireId: buttonStyleRef.wireId,
      name: 'ButtonStyle',
      library: WidgetLibrary.fromNamespace(buttonStyleRef.library),
      description: '',
      sourceType: 'package:flutter/material.dart#ButtonStyle',
      fields: [
        StructuredField(
          wireId: backgroundColorField,
          name: 'backgroundColor',
          type: PropertyType.color,
          description: '',
          valueShape: const ScalarShape(propertyType: PropertyType.color),
        ),
        StructuredField(
          wireId: paddingField,
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: '',
          valueShape: const ScalarShape(propertyType: PropertyType.edgeInsets),
        ),
        if (shapeField != null)
          StructuredField(
            wireId: shapeField,
            name: 'shape',
            type: PropertyType.shapeBorder,
            description: '',
            valueShape: shapeValueShape ??
                const ScalarShape(propertyType: PropertyType.shapeBorder),
          ),
      ],
      variants: [
        StaticMethodVariant(
          wireId: styleFromRef.wireId,
          staticAccessor: 'styleFrom',
          argMappings: {
            'backgroundColor': ArgMapping(targetFields: [backgroundColorField]),
            'padding': ArgMapping(targetFields: [paddingField]),
            if (shapeField != null)
              'shape': ArgMapping(targetFields: [shapeField]),
          },
          parameters: [
            _namedParam(
              wireId: WireId('a0003'),
              name: 'backgroundColor',
              propertyType: PropertyType.color,
            ),
            _namedParam(
              wireId: WireId('a0004'),
              name: 'padding',
              propertyType: PropertyType.edgeInsets,
            ),
            if (shapeField != null)
              _namedParam(
                wireId: WireId('a0005'),
                name: 'shape',
                propertyType: PropertyType.shapeBorder,
                valueShape: shapeValueShape ??
                    const ScalarShape(propertyType: PropertyType.shapeBorder),
              ),
          ],
        ),
      ],
    );

StructuredEntry _boxDecorationStructured({
  required WireIdRef boxRef,
  required WireIdRef boxCtorRef,
  required WireIdRef borderRadiusRef,
  required WireIdRef boxShadowRef,
  required WireId radiusField,
  required WireId shapeField,
  required WireId boxShadowField,
  required WireId gradientField,
  required WireId borderField,
  required WireIdRef gradientUnionRef,
  required WireIdRef borderUnionRef,
}) =>
    StructuredEntry(
      wireId: boxRef.wireId,
      name: 'BoxDecoration',
      library: WidgetLibrary.fromNamespace(boxRef.library),
      description: '',
      sourceType: 'package:flutter/painting.dart#BoxDecoration',
      fields: [
        StructuredField(
          wireId: radiusField,
          name: 'borderRadius',
          type: PropertyType.structured,
          description: '',
          structuredRef: borderRadiusRef,
          valueShape: StructuredShape(
            propertyType: PropertyType.structured,
            structuredRef: borderRadiusRef,
          ),
        ),
        StructuredField(
          wireId: shapeField,
          name: 'shape',
          type: PropertyType.enumValue,
          description: '',
          valueShape: const EnumShape(
            propertyType: PropertyType.enumValue,
            enumRef: DartTypeRef(
              libraryUri: 'package:flutter/painting.dart',
              symbolName: 'BoxShape',
            ),
          ),
        ),
        StructuredField(
          wireId: boxShadowField,
          name: 'boxShadow',
          type: PropertyType.boxShadowList,
          description: '',
          valueShape: ListShape(
            propertyType: PropertyType.boxShadowList,
            itemShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: boxShadowRef,
            ),
            wireCodec: CatalogWireCodec.rfwBoxShadowList,
          ),
        ),
        StructuredField(
          wireId: gradientField,
          name: 'gradient',
          type: PropertyType.gradient,
          description: '',
          unionRef: gradientUnionRef,
          valueShape: UnionShape(
            propertyType: PropertyType.gradient,
            unionRef: gradientUnionRef,
            wireCodec: CatalogWireCodec.rfwGradient,
          ),
        ),
        StructuredField(
          wireId: borderField,
          name: 'border',
          type: PropertyType.border,
          description: '',
          unionRef: borderUnionRef,
          valueShape: UnionShape(
            propertyType: PropertyType.border,
            unionRef: borderUnionRef,
            wireCodec: CatalogWireCodec.rfwBorder,
          ),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: boxCtorRef.wireId,
          argMappings: {
            'borderRadius': ArgMapping(targetFields: [radiusField]),
            'shape': ArgMapping(targetFields: [shapeField]),
            'boxShadow': ArgMapping(targetFields: [boxShadowField]),
            'gradient': ArgMapping(targetFields: [gradientField]),
            'border': ArgMapping(targetFields: [borderField]),
          },
          parameters: [
            _namedParam(
              wireId: WireId('a0005'),
              name: 'borderRadius',
              propertyType: PropertyType.structured,
              valueShape: StructuredShape(
                propertyType: PropertyType.structured,
                structuredRef: borderRadiusRef,
              ),
            ),
            _namedParam(
              wireId: WireId('a0007'),
              name: 'shape',
              propertyType: PropertyType.enumValue,
              valueShape: const EnumShape(
                propertyType: PropertyType.enumValue,
                enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/painting.dart',
                  symbolName: 'BoxShape',
                ),
              ),
            ),
            _namedParam(
              wireId: WireId('a0008'),
              name: 'boxShadow',
              propertyType: PropertyType.boxShadowList,
              valueShape: ListShape(
                propertyType: PropertyType.boxShadowList,
                itemShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: boxShadowRef,
                ),
                wireCodec: CatalogWireCodec.rfwBoxShadowList,
              ),
            ),
            _namedParam(
              wireId: WireId('a0009'),
              name: 'gradient',
              propertyType: PropertyType.gradient,
              valueShape: UnionShape(
                propertyType: PropertyType.gradient,
                unionRef: gradientUnionRef,
                wireCodec: CatalogWireCodec.rfwGradient,
              ),
            ),
            _namedParam(
              wireId: WireId('a0010'),
              name: 'border',
              propertyType: PropertyType.border,
              valueShape: UnionShape(
                propertyType: PropertyType.border,
                unionRef: borderUnionRef,
                wireCodec: CatalogWireCodec.rfwBorder,
              ),
            ),
          ],
        ),
      ],
    );

StructuredEntry _boxDecorationSingleRadius({
  required WireIdRef boxRef,
  required WireIdRef boxCtorRef,
  required WireIdRef borderRadiusRef,
  required WireId radiusField,
}) =>
    StructuredEntry(
      wireId: boxRef.wireId,
      name: 'BoxDecoration',
      library: WidgetLibrary.fromNamespace(boxRef.library),
      description: '',
      sourceType: 'package:flutter/painting.dart#BoxDecoration',
      fields: [
        StructuredField(
          wireId: radiusField,
          name: 'borderRadius',
          type: PropertyType.structured,
          description: '',
          structuredRef: borderRadiusRef,
          valueShape: StructuredShape(
            propertyType: PropertyType.structured,
            structuredRef: borderRadiusRef,
          ),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: boxCtorRef.wireId,
          argMappings: {
            'borderRadius': ArgMapping(targetFields: [radiusField]),
          },
          parameters: [
            FactoryParameter(
              wireId: WireId('a0010'),
              name: 'borderRadius',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: StructuredShape(
                propertyType: PropertyType.structured,
                structuredRef: borderRadiusRef,
              ),
            ),
          ],
        ),
      ],
    );

StructuredEntry _borderRadiusStructured({
  required WireIdRef borderRadiusRef,
  required WireIdRef circularCtorRef,
  required WireId circularRadiusParam,
}) =>
    StructuredEntry(
      wireId: borderRadiusRef.wireId,
      name: 'BorderRadius',
      library: WidgetLibrary.fromNamespace(borderRadiusRef.library),
      description: '',
      sourceType: 'package:flutter/painting.dart#BorderRadius',
      fields: [
        StructuredField(
          wireId: WireId('p0012'),
          name: 'radius',
          type: PropertyType.real,
          description: '',
          valueShape: const ScalarShape(propertyType: PropertyType.real),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: circularCtorRef.wireId,
          namedConstructor: 'circular',
          argMappings: {
            '': ArgMapping(targetFields: [WireId('p0012')]),
          },
          parameters: [
            FactoryParameter(
              wireId: circularRadiusParam,
              position: 0,
              kind: FactoryParameterKind.positional,
              required: true,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
              valueShape: const ScalarShape(propertyType: PropertyType.real),
            ),
          ],
        ),
      ],
    );

StructuredEntry _emptyStructured({
  required WireIdRef ref,
  required String name,
  required String sourceType,
}) =>
    StructuredEntry(
      wireId: ref.wireId,
      name: name,
      library: WidgetLibrary.fromNamespace(ref.library),
      description: '',
      sourceType: sourceType,
      fields: const [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v${ref.wireId.value.substring(1)}'),
        ),
      ],
    );

UnionEntry _union({
  required WireIdRef ref,
  required String name,
  required String sourceType,
  required WireIdRef memberRef,
  required String memberSourceType,
}) =>
    UnionEntry(
      wireId: ref.wireId,
      name: name,
      library: WidgetLibrary.fromNamespace(ref.library),
      description: '',
      sourceType: sourceType,
      memberSourceTypes: [memberSourceType],
      discriminator: DiscriminatorSpec(field: 'kind', values: [memberRef]),
      members: [memberRef],
    );

FactoryParameter _namedParam({
  required WireId wireId,
  required String name,
  required PropertyType propertyType,
  CatalogValueShape? valueShape,
}) =>
    FactoryParameter(
      wireId: wireId,
      name: name,
      kind: FactoryParameterKind.named,
      required: false,
      nullable: true,
      defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
      valueShape: valueShape ?? ScalarShape(propertyType: propertyType),
    );
