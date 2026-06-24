import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _library = 'restage.core';
const _at = '2026-05-11T12:00:00Z';
const _by = 'rfw_catalog_compiler@0.1.0';

void main() {
  group('WireIdAllocator', () {
    test('allocates monotonically with independent per-kind counters', () {
      final allocator = WireIdAllocator(
        library: _library,
        at: _at,
        by: _by,
        existingEvents: [
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0002'),
            name: 'Container',
            source: 'src#Container',
            at: _at,
            by: _by,
          ),
          AllocWireIdEvent(
            type: WireIdKind.property,
            id: WireId('p0003'),
            owner: WireId('w0002'),
            name: 'color',
            source: 'src#Container.color',
            at: _at,
            by: _by,
          ),
        ],
      );

      final widget = allocator.allocate(
        const WireIdAllocationCandidate.widget(
          name: 'Column',
          source: 'src#Column',
        ),
      );
      final property = allocator.allocate(
        WireIdAllocationCandidate.property(
          owner: WireId('w0002'),
          name: 'width',
          source: 'src#Container.width',
        ),
      );
      final structured = allocator.allocate(
        const WireIdAllocationCandidate.structured(
          name: 'LinearGradient',
          source: 'src#LinearGradient',
        ),
      );
      final variant = allocator.allocate(
        WireIdAllocationCandidate.variant(
          owner: structured.id,
          sourceKind: VariantSourceKind.constructor,
          source: 'src#LinearGradient.',
        ),
      );
      final parameter = allocator.allocate(
        WireIdAllocationCandidate.parameter(
          owner: variant.id,
          name: 'radius',
          source: 'src#LinearGradient.radius',
        ),
      );
      final token = allocator.allocate(
        const WireIdAllocationCandidate.designToken(
          name: 'primary',
          tokenType: 'color',
          literalFallback: WireIdEventField<Object?>.value(0xFF000000),
        ),
      );

      expect(widget.id, WireId('w0003'));
      expect(property.id, WireId('p0004'));
      expect(structured.id, WireId('s0001'));
      expect(variant.id, WireId('v0001'));
      expect(parameter.id, WireId('a0001'));
      expect(token.id, WireId('t0001'));
      expect(allocator.currentState.widgets, contains(widget.id));
      expect(allocator.currentState.properties, contains(property.id));
      expect(allocator.currentState.parameters, contains(parameter.id));
    });

    test('preserves candidate declaration order for initial allocation', () {
      final allocator = WireIdAllocator(library: _library, at: _at, by: _by);

      final events = allocator.allocateAll(
        const [
          WireIdAllocationCandidate.widget(name: 'A', source: 'src#A'),
          WireIdAllocationCandidate.widget(name: 'B', source: 'src#B'),
          WireIdAllocationCandidate.structured(name: 'S', source: 'src#S'),
          WireIdAllocationCandidate.union(name: 'U', source: 'src#U'),
        ],
      );

      expect(
        events.map((event) => event.id.value),
        ['w0001', 'w0002', 's0001', 'u0001'],
      );
    });

    test('failed allocation append does not advance allocator state', () {
      final allocator = WireIdAllocator(
        library: _library,
        at: _at,
        by: _by,
        existingEvents: [
          AllocWireIdEvent(
            type: WireIdKind.widget,
            id: WireId('w0001'),
            name: 'Container',
            source: 'src#Container',
            at: _at,
            by: _by,
          ),
        ],
      );
      final eventCount = allocator.events.length;
      final stateBefore = encodeWireIdCurrentStateJson(allocator.currentState);

      expect(
        () => allocator.allocate(
          WireIdAllocationCandidate.property(
            owner: WireId('w9999'),
            name: 'color',
            source: 'src#Missing.color',
          ),
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('prior local alloc'),
          ),
        ),
      );

      expect(allocator.events, hasLength(eventCount));
      expect(
        allocator.currentState.properties,
        isNot(contains(WireId('p0001'))),
      );
      expect(encodeWireIdCurrentStateJson(allocator.currentState), stateBefore);

      final property = allocator.allocate(
        WireIdAllocationCandidate.property(
          owner: WireId('w0001'),
          name: 'color',
          source: 'src#Container.color',
        ),
      );

      expect(property.id, WireId('p0001'));
      expect(allocator.currentState.properties, contains(WireId('p0001')));
    });

    test('rejects allocateCatalog namespace mismatches', () {
      final allocator = WireIdAllocator(library: _library, at: _at, by: _by);

      expect(
        () => allocator.allocateCatalog(
          _catalog(),
          WidgetLibrary.material,
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('must match target library'),
          ),
        ),
      );
    });

    test('rejects existing catalog wire IDs with the wrong kind', () {
      void expectRejects(Catalog catalog, String message) {
        final allocator = WireIdAllocator(library: _library, at: _at, by: _by);
        expect(
          () => allocator.allocateCatalog(catalog, WidgetLibrary.core),
          throwsA(
            isA<WireIdReplayException>().having(
              (error) => error.message,
              'message',
              contains(message),
            ),
          ),
        );
      }

      expectRejects(
        _catalog(widgets: [_widget(wireId: WireId('p0001'))]),
        'expected w*',
      );
      expectRejects(
        _catalog(
          widgets: [
            _widget(
              properties: [_property(wireId: WireId('w0001'))],
            ),
          ],
        ),
        'expected p*',
      );
      expectRejects(
        _catalog(
          structuredTypes: [
            _structured(wireId: WireId('p0001'), name: 'Circle'),
          ],
        ),
        'expected s*',
      );
      expectRejects(
        _catalog(
          structuredTypes: [
            _structured(
              wireId: WireId.unallocatedStructured,
              name: 'Circle',
              fields: [_structuredField(wireId: WireId('s0001'))],
            ),
          ],
        ),
        'expected p*',
      );
      expectRejects(
        _catalog(
          structuredTypes: [
            _structured(
              wireId: WireId.unallocatedStructured,
              name: 'Circle',
              variants: [_variant(wireId: WireId('s0001'))],
            ),
          ],
        ),
        'expected v*',
      );
      expectRejects(
        _catalog(
          structuredTypes: [
            _structured(
              wireId: WireId.unallocatedStructured,
              name: 'Circle',
              variants: [
                _variant(
                  wireId: WireId.unallocatedVariant,
                  parameters: [_parameter(wireId: WireId('p0001'))],
                ),
              ],
            ),
          ],
        ),
        'expected a*',
      );
      expectRejects(
        _catalog(unions: [_union(wireId: WireId('s0001'), members: const [])]),
        'expected u*',
      );
      expectRejects(
        _catalog(designTokens: [_token(wireId: WireId('u0001'))]),
        'expected t*',
      );
    });

    test('allocates factory parameters while walking catalog variants', () {
      final allocator = WireIdAllocator(library: _library, at: _at, by: _by);

      final events = allocator.allocateCatalog(
        _catalog(
          structuredTypes: [
            _structured(
              wireId: WireId.unallocatedStructured,
              name: 'BorderRadius',
              variants: [
                _variant(
                  wireId: WireId.unallocatedVariant,
                  namedConstructor: 'circular',
                  parameters: [
                    _parameter(
                      wireId: WireId.unallocatedParameter,
                      name: null,
                      position: 0,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        WidgetLibrary.core,
      );

      final variantAlloc = events
          .whereType<AllocWireIdEvent>()
          .singleWhere((event) => event.type == WireIdKind.variant);
      final parameterAlloc = events
          .whereType<AllocWireIdEvent>()
          .singleWhere((event) => event.type == WireIdKind.parameter);

      expect(parameterAlloc.id, WireId('a0001'));
      expect(parameterAlloc.owner, variantAlloc.id);
      expect(parameterAlloc.name, '0');
      expect(allocator.currentState.parameters, contains(WireId('a0001')));
      expect(
        allocator.currentState.properties,
        isNot(contains(WireId('a0001'))),
      );
    });

    test('rejects preallocated parameters owned by another variant', () {
      final allocator = WireIdAllocator(
        library: _library,
        at: _at,
        by: _by,
        existingEvents: [
          _structuredAlloc(WireId('s0001'), 'BorderRadius'),
          _variantAlloc(WireId('v0001'), WireId('s0001')),
          _variantAlloc(WireId('v0002'), WireId('s0001')),
          _parameterAlloc(WireId('a0001'), WireId('v0002')),
        ],
      );

      expect(
        () => allocator.allocateCatalog(
          _catalog(
            structuredTypes: [
              _structured(
                wireId: WireId('s0001'),
                name: 'BorderRadius',
                variants: [
                  _variant(
                    wireId: WireId('v0001'),
                    namedConstructor: 'circular',
                    parameters: [_parameter(wireId: WireId('a0001'))],
                  ),
                ],
              ),
            ],
          ),
          WidgetLibrary.core,
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            allOf(contains('a0001'), contains('v0002'), contains('v0001')),
          ),
        ),
      );
    });

    test('rejects preallocated owned IDs attached to another owner', () {
      void expectRejects({
        required List<WireIdEvent> existingEvents,
        required Catalog catalog,
        required String id,
        required String existingOwner,
        required String requestedOwner,
      }) {
        final allocator = WireIdAllocator(
          library: _library,
          at: _at,
          by: _by,
          existingEvents: existingEvents,
        );

        expect(
          () => allocator.allocateCatalog(catalog, WidgetLibrary.core),
          throwsA(
            isA<WireIdReplayException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains(id),
                contains(existingOwner),
                contains(requestedOwner),
              ),
            ),
          ),
        );
      }

      expectRejects(
        existingEvents: [
          _widgetAlloc(WireId('w0001'), 'Box'),
          _widgetAlloc(WireId('w0002'), 'OtherBox'),
          _propertyAlloc(WireId('p0001'), WireId('w0002')),
        ],
        catalog: _catalog(
          widgets: [
            _widget(
              wireId: WireId('w0001'),
              properties: [_property(wireId: WireId('p0001'))],
            ),
          ],
        ),
        id: 'p0001',
        existingOwner: 'w0002',
        requestedOwner: 'w0001',
      );

      expectRejects(
        existingEvents: [
          _structuredAlloc(WireId('s0001'), 'Circle'),
          _structuredAlloc(WireId('s0002'), 'Square'),
          _propertyAlloc(WireId('p0001'), WireId('s0002')),
        ],
        catalog: _catalog(
          structuredTypes: [
            _structured(
              wireId: WireId('s0001'),
              name: 'Circle',
              fields: [_structuredField(wireId: WireId('p0001'))],
            ),
          ],
        ),
        id: 'p0001',
        existingOwner: 's0002',
        requestedOwner: 's0001',
      );

      expectRejects(
        existingEvents: [
          _structuredAlloc(WireId('s0001'), 'Circle'),
          _structuredAlloc(WireId('s0002'), 'Square'),
          _variantAlloc(WireId('v0001'), WireId('s0002')),
        ],
        catalog: _catalog(
          structuredTypes: [
            _structured(
              wireId: WireId('s0001'),
              name: 'Circle',
              variants: [_variant(wireId: WireId('v0001'))],
            ),
          ],
        ),
        id: 'v0001',
        existingOwner: 's0002',
        requestedOwner: 's0001',
      );
    });

    test('emits union memberships in declaration order', () {
      final allocator = WireIdAllocator(
        library: _library,
        at: _at,
        by: _by,
        existingEvents: [
          _structuredAlloc(WireId('s0001'), 'Circle'),
          _structuredAlloc(WireId('s0002'), 'Square'),
          _unionAlloc(WireId('u0001'), 'Shape'),
        ],
      );

      final events = allocator.allocateCatalog(
        _catalog(
          structuredTypes: [
            _structured(wireId: WireId('s0001'), name: 'Circle'),
            _structured(wireId: WireId('s0002'), name: 'Square'),
          ],
          unions: [
            _union(
              wireId: WireId('u0001'),
              members: [
                WireIdRef(library: _library, wireId: WireId('s0002')),
                WireIdRef(library: _library, wireId: WireId('s0001')),
              ],
              memberSourceTypes: const ['src#Square', 'src#Circle'],
            ),
          ],
        ),
        WidgetLibrary.core,
      );

      expect(events, everyElement(isA<AddMemberWireIdEvent>()));
      expect(
        events.cast<AddMemberWireIdEvent>().map(
              (event) => event.member.wireId.value,
            ),
        ['s0002', 's0001'],
      );
      expect(
        allocator.currentState.unions[WireId('u0001')]!.members.map(
          (member) => member.wireId.value,
        ),
        ['s0002', 's0001'],
      );
    });

    test('does not duplicate existing union memberships', () {
      final allocator = WireIdAllocator(
        library: _library,
        at: _at,
        by: _by,
        existingEvents: [
          _structuredAlloc(WireId('s0001'), 'Circle'),
          _structuredAlloc(WireId('s0002'), 'Square'),
          _unionAlloc(WireId('u0001'), 'Shape'),
          AddMemberWireIdEvent(
            target: WireIdRef(library: _library, wireId: WireId('u0001')),
            member: WireIdRef(library: _library, wireId: WireId('s0001')),
            at: _at,
            by: _by,
          ),
        ],
      );

      final events = allocator.allocateCatalog(
        _catalog(
          structuredTypes: [
            _structured(wireId: WireId('s0001'), name: 'Circle'),
            _structured(wireId: WireId('s0002'), name: 'Square'),
          ],
          unions: [
            _union(
              wireId: WireId('u0001'),
              members: [
                WireIdRef(library: _library, wireId: WireId('s0001')),
                WireIdRef(library: _library, wireId: WireId('s0002')),
              ],
              memberSourceTypes: const ['src#Circle', 'src#Square'],
            ),
          ],
        ),
        WidgetLibrary.core,
      );

      expect(events, hasLength(1));
      final event = events.single as AddMemberWireIdEvent;
      expect(event.member.wireId, WireId('s0002'));
    });

    test('resolves sentinel union member refs to allocated structured ids', () {
      // Structured types and the union all arrive unallocated; the
      // union's member refs are structured sentinels. Allocation must
      // mint real structured ids and emit addMember events carrying
      // those real ids rather than the sentinels.
      final allocator = WireIdAllocator(library: _library, at: _at, by: _by);

      final catalog = _catalog(
        structuredTypes: [
          _structured(
            wireId: WireId.unallocatedStructured,
            name: 'Circle',
          ),
          _structured(
            wireId: WireId.unallocatedStructured,
            name: 'Square',
          ),
        ],
        unions: [
          _union(
            wireId: WireId.unallocatedUnion,
            members: const [
              WireIdRef(
                library: _library,
                wireId: WireId.unallocatedStructured,
              ),
              WireIdRef(
                library: _library,
                wireId: WireId.unallocatedStructured,
              ),
            ],
            memberSourceTypes: const ['src#Circle', 'src#Square'],
          ),
        ],
      );

      final events = allocator.allocateCatalog(catalog, WidgetLibrary.core);

      final unionAlloc = events
          .whereType<AllocWireIdEvent>()
          .singleWhere((event) => event.type == WireIdKind.union);
      expect(unionAlloc.id.kind, WireIdKind.union);
      expect(unionAlloc.id.isUnallocated, isFalse);

      final addMembers = events.whereType<AddMemberWireIdEvent>().toList();
      expect(addMembers, hasLength(2));
      for (final event in addMembers) {
        expect(event.member.wireId.kind, WireIdKind.structured);
        expect(
          event.member.wireId.isUnallocated,
          isFalse,
          reason: 'addMember must carry a real structured id, not s0000',
        );
        expect(event.member.library, _library);
      }

      final structuredAllocs = events
          .whereType<AllocWireIdEvent>()
          .where((event) => event.type == WireIdKind.structured)
          .toList();
      final circleId =
          structuredAllocs.singleWhere((event) => event.name == 'Circle').id;
      final squareId =
          structuredAllocs.singleWhere((event) => event.name == 'Square').id;
      expect(
        addMembers.map((event) => event.member.wireId).toList(),
        [circleId, squareId],
      );

      // Re-running allocation over the post-allocation catalog must be
      // replay-idempotent: zero new addMember (or any) events.
      final allocatedCatalog = _catalog(
        structuredTypes: [
          _structured(wireId: circleId, name: 'Circle'),
          _structured(wireId: squareId, name: 'Square'),
        ],
        unions: [
          _union(
            wireId: unionAlloc.id,
            members: [
              WireIdRef(library: _library, wireId: circleId),
              WireIdRef(library: _library, wireId: squareId),
            ],
            memberSourceTypes: const ['src#Circle', 'src#Square'],
          ),
        ],
      );
      final rerun = WireIdAllocator(
        library: _library,
        at: _at,
        by: _by,
        existingEvents: events,
      );
      expect(
        rerun.allocateCatalog(allocatedCatalog, WidgetLibrary.core),
        isEmpty,
      );
    });

    test('rejects union members with no matching structured entry', () {
      final allocator = WireIdAllocator(library: _library, at: _at, by: _by);

      expect(
        () => allocator.allocateCatalog(
          _catalog(
            unions: [
              _union(
                wireId: WireId.unallocatedUnion,
                members: const [
                  WireIdRef(
                    library: _library,
                    wireId: WireId.unallocatedStructured,
                  ),
                ],
                memberSourceTypes: const ['src#Missing'],
              ),
            ],
          ),
          WidgetLibrary.core,
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            contains('has no allocated structured entry'),
          ),
        ),
      );
    });

    test('rejects union with mismatched members and memberSourceTypes lengths',
        () {
      final allocator = WireIdAllocator(library: _library, at: _at, by: _by);

      // Two member WireIdRefs but only one source FQN — length mismatch must
      // throw a clear WireIdReplayException rather than a RangeError.
      const badUnion = UnionEntry(
        wireId: WireId.unallocatedUnion,
        name: 'BadUnion',
        library: WidgetLibrary.core,
        description: 'A malformed union.',
        sourceType: 'src#BadUnion',
        memberSourceTypes: ['src#Circle'], // length 1
        discriminator: DiscriminatorSpec(
          field: '_s',
          values: [
            WireIdRef(library: _library, wireId: WireId.unallocatedStructured),
            WireIdRef(library: _library, wireId: WireId.unallocatedStructured),
          ],
        ),
        members: [
          WireIdRef(library: _library, wireId: WireId.unallocatedStructured),
          WireIdRef(library: _library, wireId: WireId.unallocatedStructured),
        ], // length 2
      );

      expect(
        () => allocator.allocateCatalog(
          _catalog(unions: [badUnion]),
          WidgetLibrary.core,
        ),
        throwsA(
          isA<WireIdReplayException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('BadUnion'),
              contains('members.length'),
              contains('memberSourceTypes.length'),
            ),
          ),
        ),
      );
    });
  });
}

Catalog _catalog({
  List<WidgetEntry> widgets = const [],
  List<StructuredEntry> structuredTypes = const [],
  List<UnionEntry> unions = const [],
  List<DesignTokenEntry> designTokens = const [],
}) {
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: _at,
    libraries: {
      WidgetLibrary.core: LibraryInfo(version: '0.1.0'),
    },
    widgets: widgets,
    structuredTypes: structuredTypes,
    unions: unions,
    designTokens: designTokens,
  );
}

WidgetEntry _widget({
  WireId wireId = WireId.unallocatedWidget,
  List<PropertyEntry> properties = const [],
}) {
  return WidgetEntry(
    wireId: wireId,
    name: 'Box',
    library: WidgetLibrary.core,
    category: WidgetCategory.layout,
    description: 'A box.',
    flutterType: 'src#Box',
    childrenSlot: ChildrenSlot.none,
    fires: const [],
    properties: properties,
  );
}

PropertyEntry _property({required WireId wireId}) {
  return PropertyEntry(
    wireId: wireId,
    name: 'color',
    type: PropertyType.color,
    description: 'A color.',
  );
}

StructuredEntry _structured({
  required WireId wireId,
  required String name,
  List<StructuredField> fields = const [],
  List<FactoryVariant> variants = const [],
}) {
  return StructuredEntry(
    wireId: wireId,
    name: name,
    library: WidgetLibrary.core,
    description: 'A structured type.',
    sourceType: 'src#$name',
    fields: fields,
    variants: variants,
  );
}

StructuredField _structuredField({required WireId wireId}) {
  return StructuredField(
    wireId: wireId,
    name: 'radius',
    type: PropertyType.length,
    description: 'A radius.',
  );
}

FactoryVariant _variant({
  required WireId wireId,
  String? namedConstructor,
  List<FactoryParameter> parameters = const [],
}) {
  return ConstructorVariant(
    wireId: wireId,
    namedConstructor: namedConstructor,
    parameters: parameters,
  );
}

FactoryParameter _parameter({
  required WireId wireId,
  String? name = 'radius',
  int? position,
}) {
  return FactoryParameter(
    wireId: wireId,
    name: name,
    position: position,
    kind: name == null
        ? FactoryParameterKind.positional
        : FactoryParameterKind.named,
    required: true,
    nullable: false,
    defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
    valueShape: const ScalarShape(
      propertyType: PropertyType.real,
      dartTypeRef: DartTypeRef(libraryUri: 'dart:core', symbolName: 'double'),
    ),
  );
}

UnionEntry _union({
  required WireId wireId,
  required List<WireIdRef> members,
  List<String>? memberSourceTypes,
}) {
  final sources = memberSourceTypes ??
      [
        for (var i = 0; i < members.length; i++)
          'package:test/test.dart#ShapeMember$i',
      ];
  return UnionEntry(
    wireId: wireId,
    name: 'Shape',
    library: WidgetLibrary.core,
    description: 'A shape union.',
    sourceType: 'package:test/test.dart#Shape',
    memberSourceTypes: sources,
    discriminator: DiscriminatorSpec(field: '_s', values: members),
    members: members,
  );
}

AllocWireIdEvent _widgetAlloc(WireId id, String name) {
  return AllocWireIdEvent(
    type: WireIdKind.widget,
    id: id,
    name: name,
    source: 'src#$name',
    at: _at,
    by: _by,
  );
}

AllocWireIdEvent _propertyAlloc(WireId id, WireId owner) {
  return AllocWireIdEvent(
    type: WireIdKind.property,
    id: id,
    owner: owner,
    name: 'color',
    source: 'src#Owner.color',
    at: _at,
    by: _by,
  );
}

AllocWireIdEvent _structuredAlloc(WireId id, String name) {
  return AllocWireIdEvent(
    type: WireIdKind.structured,
    id: id,
    name: name,
    source: 'src#$name',
    at: _at,
    by: _by,
  );
}

AllocWireIdEvent _variantAlloc(WireId id, WireId owner) {
  return AllocWireIdEvent(
    type: WireIdKind.variant,
    id: id,
    owner: owner,
    sourceKind: VariantSourceKind.constructor,
    source: 'src#Variant',
    at: _at,
    by: _by,
  );
}

AllocWireIdEvent _parameterAlloc(WireId id, WireId owner) {
  return AllocWireIdEvent(
    type: WireIdKind.parameter,
    id: id,
    owner: owner,
    name: 'radius',
    source: 'src#Variant.radius',
    at: _at,
    by: _by,
  );
}

AllocWireIdEvent _unionAlloc(WireId id, String name) {
  return AllocWireIdEvent(
    type: WireIdKind.union,
    id: id,
    name: name,
    source: 'src#$name',
    at: _at,
    by: _by,
  );
}

DesignTokenEntry _token({required WireId wireId}) {
  return DesignTokenEntry(
    wireId: wireId,
    name: 'primary',
    library: WidgetLibrary.core,
    type: DesignTokenType.color,
    literalFallback: 0xFF000000,
  );
}
