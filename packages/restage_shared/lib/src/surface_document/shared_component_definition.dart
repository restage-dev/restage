import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:restage_shared/src/rfw_canonical_order.dart';
import 'package:restage_shared/src/rfw_formats.dart' hide WidgetLibrary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show Catalog, WidgetLibrary;

/// The entry declaration name of a shared component payload.
const String kSharedComponentEntryName = 'main';

/// The declarations [declaration] reaches in [libraryBlob], itself
/// excluded.
Set<String> componentReachedDeclarations(
  Uint8List libraryBlob,
  String declaration,
) =>
    _reached(decodeLibraryBlob(libraryBlob), declaration);

Set<String> _reached(RemoteWidgetLibrary library, String declaration) {
  final byName = {for (final widget in library.widgets) widget.name: widget};
  final reached = <String>{};
  void visit(String name) {
    final widget = byName[name];
    if (widget == null) return;
    for (final root in [widget.initialState, widget.root]) {
      _calls(root, (call) {
        if (byName.containsKey(call) &&
            call != declaration &&
            reached.add(call)) {
          visit(call);
        }
      });
    }
  }

  visit(declaration);
  return reached;
}

/// [declaration] of [libraryBlob] and what it reaches, as the library blob of
/// a shared component: the entry is [kSharedComponentEntryName] and the rest
/// keep their names, sorted. With a [catalog], only the imports that supply
/// widgets it uses are kept.
Uint8List componentLibraryBlob(
  Uint8List libraryBlob,
  String declaration, {
  Catalog? catalog,
}) {
  final library = decodeLibraryBlob(libraryBlob);
  final byName = {for (final widget in library.widgets) widget.name: widget};
  final entry = byName[declaration];
  if (entry == null) throw StateError('No declaration named $declaration.');
  final reached = _reached(library, declaration);
  if (reached.contains(kSharedComponentEntryName)) {
    throw StateError('A component cannot contain a declaration named main.');
  }
  final widgets = [
    WidgetDeclaration(
        kSharedComponentEntryName, entry.initialState, entry.root),
    for (final name in reached.toList()..sort()) byName[name]!,
  ];
  return encodeLibraryBlob(RemoteWidgetLibrary(
    catalog == null
        ? library.imports
        : _neededImports(
            library.imports, byName.keys.toSet(), widgets, catalog),
    widgets,
  ));
}

/// The fingerprint of the component rooted at [entry] in [libraryBlob] with
/// slot defaults [slots] (by declaration name), and the declarations it
/// reaches in the order a canonical walk first meets them.
///
/// Names and map key order don't change it; any other edit does.
({String fingerprint, List<String> parts}) componentFingerprint(
  Uint8List libraryBlob,
  String entry,
  Map<String, Map<String, Object?>> slots,
) {
  final library = canonicalizeLibrary(decodeLibraryBlob(libraryBlob));
  final byName = {for (final widget in library.widgets) widget.name: widget};
  if (!byName.containsKey(entry)) {
    throw StateError('No declaration named $entry.');
  }
  final order = <String>[entry];
  void visit(String name) {
    final widget = byName[name]!;
    for (final root in [widget.initialState, widget.root]) {
      _calls(root, (call) {
        if (byName.containsKey(call) && !order.contains(call)) {
          order.add(call);
          visit(call);
        }
      });
    }
  }

  visit(entry);
  final names = {
    entry: kSharedComponentEntryName,
    for (final (index, name) in order.skip(1).indexed)
      name: 'part_${index + 1}',
  };
  final blob = encodeLibraryBlob(RemoteWidgetLibrary(const [], [
    for (final name in order)
      WidgetDeclaration(
        names[name]!,
        byName[name]!.initialState == null
            ? null
            : _renamed(byName[name]!.initialState, names)! as DynamicMap,
        _renamed(byName[name]!.root, names)! as BlobNode,
      ),
  ]));
  final slotText = jsonEncode(_sortedJson({
    for (final name in order)
      if (slots[name] case final defaults? when defaults.isNotEmpty)
        names[name]!: defaults,
  }));
  final digest = sha256.convert([...blob, 0, ...utf8.encode(slotText)]);
  return (
    fingerprint: digest.toString().substring(0, 16),
    parts: order.skip(1).toList(),
  );
}

List<Import> _neededImports(
  List<Import> imports,
  Set<String> localNames,
  List<WidgetDeclaration> widgets,
  Catalog catalog,
) {
  final used = <String>{};
  for (final widget in widgets) {
    for (final root in [widget.initialState, widget.root]) {
      _calls(root, (call) {
        if (!localNames.contains(call)) used.add(call);
      });
    }
  }
  final needed = <Import>{};
  for (final name in used) {
    var found = false;
    for (final import in imports) {
      final namespace = import.name.parts.join('.');
      if (catalog.findByName(name, WidgetLibrary.fromNamespace(namespace)) !=
          null) {
        needed.add(import);
        found = true;
      }
    }
    if (!found) return imports;
  }
  return [
    for (final import in imports)
      if (needed.contains(import)) import,
  ];
}

// Calls [visit] with each constructor name under [value], depth first.
void _calls(Object? value, void Function(String name) visit) {
  switch (value) {
    case ConstructorCall():
      visit(value.name);
      _calls(value.arguments, visit);
    case final Map<String, Object?> map:
      map.values.forEach((value) => _calls(value, visit));
    case final List<Object?> list:
      list.forEach((value) => _calls(value, visit));
    case EventHandler():
      _calls(value.eventArguments, visit);
    case SetStateHandler():
      _calls(value.value, visit);
    case Loop():
      _calls(value.input, visit);
      _calls(value.output, visit);
    case Switch():
      _calls(value.input, visit);
      for (final entry in value.outputs.entries) {
        _calls(entry.key, visit);
        _calls(entry.value, visit);
      }
    case WidgetBuilderDeclaration():
      _calls(value.widget, visit);
    default:
  }
}

Object? _renamed(Object? value, Map<String, String> names) => switch (value) {
      ConstructorCall() => ConstructorCall(
          names[value.name] ?? value.name,
          _renamed(value.arguments, names)! as DynamicMap,
        ),
      final Map<String, Object?> map => <String, Object?>{
          for (final entry in map.entries)
            entry.key: _renamed(entry.value, names),
        },
      final List<Object?> list => [
          for (final item in list) _renamed(item, names),
        ],
      EventHandler() => EventHandler(value.eventName,
          _renamed(value.eventArguments, names)! as DynamicMap),
      SetStateHandler() =>
        SetStateHandler(value.stateReference, _renamed(value.value, names)!),
      Loop() =>
        Loop(_renamed(value.input, names)!, _renamed(value.output, names)!),
      Switch() => Switch(_renamed(value.input, names)!, {
          for (final entry in value.outputs.entries)
            _renamed(entry.key, names): _renamed(entry.value, names)!,
        }),
      WidgetBuilderDeclaration() => WidgetBuilderDeclaration(
          value.argumentName,
          _renamed(value.widget, names)! as BlobNode,
        ),
      _ => value,
    };

Object? _sortedJson(Object? value) => switch (value) {
      final Map<Object?, Object?> map => {
          for (final key in map.keys.cast<String>().toList()..sort())
            key: _sortedJson(map[key]),
        },
      final List<Object?> list => [for (final item in list) _sortedJson(item)],
      _ => value,
    };
