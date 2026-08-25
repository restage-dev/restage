import 'package:meta/meta.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One extracted occurrence label and its compiler-issued presentation handle.
@immutable
final class AnalyticsIdDeclaration {
  /// Creates an extracted occurrence declaration.
  const AnalyticsIdDeclaration({
    required this.analyticsId,
    required this.presentationHandle,
  });

  /// The bounded author-facing identifier.
  final String analyticsId;

  /// Label-independent handle retained for final witness resolution.
  final fmt.RfwCatalogOccurrenceHandle presentationHandle;
}

/// Parsed RFW after reserved occurrence labels have been removed.
@immutable
final class AnalyticsIdLoweringResult {
  /// Creates a lowering result.
  AnalyticsIdLoweringResult({
    required this.library,
    required this.text,
    required Iterable<AnalyticsIdDeclaration> declarations,
    required Iterable<Issue> issues,
  })  : declarations = List.unmodifiable(declarations),
        issues = List.unmodifiable(issues);

  /// The sanitized parsed library used by all downstream compiler work.
  final fmt.RemoteWidgetLibrary library;

  /// Source text corresponding to [library], with labels removed.
  final String text;

  /// Noncanonical extracted declarations.
  final List<AnalyticsIdDeclaration> declarations;

  /// Validation or source-rewrite diagnostics.
  final List<Issue> issues;

  /// Whether extraction and validation completed without diagnostics.
  bool get isValid => issues.isEmpty;
}

/// Extracts the reserved occurrence label from each eligible constructor in
/// [library] and returns a label-free RFW form.
///
/// A call is eligible only when the frozen catalog occurrence set recognizes
/// that exact parsed constructor object. This gives built-in and generated
/// customer calls one provenance-driven path while excluding ordinary local
/// shadows and unreachable declarations.
///
/// Every label must resolve through the exact parsed constructor call to one
/// compiler-issued occurrence handle. The initial pass supplies
/// [occurrenceSet], which must own [library]. A later pass supplies
/// [occurrenceRebinding], which must already bind [library] without rerunning
/// catalog eligibility.
///
/// [text] and [library] must describe the same parse, with source locations
/// enabled through [sourceIdentifier]. Call this directly after parsing, before
/// any catalog validation, capability derivation, encoding, or output write.
AnalyticsIdLoweringResult lowerAnalyticsIds({
  required String text,
  required fmt.RemoteWidgetLibrary library,
  required Object sourceIdentifier,
  required String location,
  fmt.ResolvedRfwCatalogOccurrenceSet? occurrenceSet,
  fmt.ResolvedRfwCatalogOccurrenceRebinding? occurrenceRebinding,
}) {
  if (occurrenceSet != null && occurrenceRebinding != null) {
    throw ArgumentError(
      'Analytics label lowering accepts one catalog occurrence binding.',
    );
  }
  if (occurrenceSet != null &&
      !identical(occurrenceSet.parsedLibrary, library)) {
    throw ArgumentError(
      'The catalog occurrence set must own the exact parsed RFW library.',
    );
  }
  if (occurrenceRebinding != null &&
      !identical(occurrenceRebinding.finalLibrary, library)) {
    throw ArgumentError(
      'The catalog occurrence rebinding must own the exact parsed RFW library.',
    );
  }
  final state = _AnalyticsIdLoweringState(
    text: text,
    sourceIdentifier: sourceIdentifier,
    location: location,
    occurrenceSet: occurrenceSet,
    occurrenceRebinding: occurrenceRebinding,
  );
  for (final widget in library.widgets) {
    if (widget.initialState != null) {
      state.walk(
        widget.initialState,
        <String>[
          _pathPart('widget', widget.name),
          'initial-state',
        ],
      );
    }
    state.walk(
      widget.root,
      <String>[
        _pathPart('widget', widget.name),
        'root',
      ],
    );
  }
  final typedCopy = state.copyLibrary(library);
  final frozenSet = occurrenceSet ?? occurrenceRebinding?.occurrenceSet;
  if (frozenSet != null) {
    try {
      frozenSet.rebindFinalLibrary(typedCopy.library);
    } on FormatException catch (error) {
      state.issues.add(
        Issue(
          code: IssueCode.invalidAnalyticsId,
          message: 'Sanitized RFW does not match its frozen catalog '
              'occurrences: $error',
          location: location,
        ),
      );
    }
  }
  String sanitizedText;
  try {
    sanitizedText = _applyEdits(text, state.edits);
  } on FormatException {
    state.issues.add(
      Issue(
        code: IssueCode.invalidAnalyticsId,
        message: 'analyticsId could not be removed from the RFW source.',
        location: location,
      ),
    );
    sanitizedText = text;
  }
  return AnalyticsIdLoweringResult(
    library: typedCopy.library,
    text: sanitizedText,
    declarations: typedCopy.declarations,
    issues: state.issues,
  );
}

final class _AnalyticsIdLoweringState {
  _AnalyticsIdLoweringState({
    required this.text,
    required this.sourceIdentifier,
    required this.location,
    required this.occurrenceSet,
    required this.occurrenceRebinding,
  });

  final String text;
  final Object sourceIdentifier;
  final String location;
  final fmt.ResolvedRfwCatalogOccurrenceSet? occurrenceSet;
  final fmt.ResolvedRfwCatalogOccurrenceRebinding? occurrenceRebinding;
  final List<Issue> issues = <Issue>[];
  final List<_TextEdit> edits = <_TextEdit>[];
  final Set<fmt.ConstructorCall> _constructorsToStrip =
      Set<fmt.ConstructorCall>.identity();
  final Map<fmt.RfwCatalogOccurrenceHandle, _AnalyticsIdDeclarationDraft>
      _declarationByPresentationHandle =
      <fmt.RfwCatalogOccurrenceHandle, _AnalyticsIdDeclarationDraft>{};

  void walk(Object? node, List<String> path) {
    if (node is fmt.ConstructorCall) {
      _extractFromConstructor(node, path);
      for (final entry in node.arguments.entries) {
        walk(
          entry.value,
          <String>[...path, _pathPart('argument', entry.key)],
        );
      }
      return;
    }
    if (node is List) {
      for (var index = 0; index < node.length; index += 1) {
        walk(node[index], <String>[...path, 'item:$index']);
      }
      return;
    }
    if (node is Map) {
      for (final entry in node.entries) {
        walk(
          entry.value,
          <String>[...path, _pathPart('entry', '${entry.key}')],
        );
      }
      return;
    }
    if (node is fmt.Switch) {
      walk(node.input, <String>[...path, 'switch-input']);
      for (final entry in node.outputs.entries) {
        walk(
          entry.value,
          <String>[...path, _pathPart('switch', '${entry.key}')],
        );
      }
      return;
    }
    if (node is fmt.Loop) {
      walk(node.input, <String>[...path, 'loop-input']);
      walk(node.output, <String>[...path, 'loop-output']);
      return;
    }
    if (node is fmt.WidgetBuilderDeclaration) {
      walk(node.widget, <String>[...path, 'builder']);
      return;
    }
    if (node is fmt.EventHandler) {
      walk(node.eventArguments, <String>[...path, 'event']);
      return;
    }
    if (node is fmt.SetStateHandler) {
      walk(node.value, <String>[...path, 'set-state']);
      return;
    }
    if (node is fmt.BoundArgsReference) {
      walk(node.arguments, <String>[...path, 'bound-arguments']);
      return;
    }
    if (node is fmt.BoundLoopReference) {
      walk(node.value, <String>[...path, 'bound-loop']);
    }
  }

  void _extractFromConstructor(
    fmt.ConstructorCall call,
    List<String> parentPath,
  ) {
    final hasAnalyticsId = call.arguments.containsKey(kAnalyticsIdPropertyName);
    final path = <String>[...parentPath, _pathPart('call', call.name)];
    final occurrence = occurrenceSet?.occurrenceForCall(call) ??
        occurrenceRebinding?.bindingForCall(call)?.occurrence;
    if (occurrence == null) {
      if (hasAnalyticsId) _missingPresentationHandle(path);
      return;
    }
    if (!hasAnalyticsId) return;
    final source = call.source;
    if (source == null || source.start.source != sourceIdentifier) {
      issues.add(
        Issue(
          code: IssueCode.invalidAnalyticsId,
          message: 'analyticsId requires source locations for safe removal.',
          location: _locationFor(path),
        ),
      );
      return;
    }
    final removal = _analyticsIdRemoval(text, source);
    if (removal == null) {
      issues.add(
        Issue(
          code: IssueCode.invalidAnalyticsId,
          message: 'analyticsId could not be located in the parsed constructor '
              'source.',
          location: _locationFor(path),
        ),
      );
      return;
    }
    edits.addAll(removal.edits);
    _constructorsToStrip.add(call);

    final value = call.arguments[kAnalyticsIdPropertyName];
    if (value is! String || !isValidAnalyticsId(value)) {
      issues.add(
        Issue(
          code: IssueCode.invalidAnalyticsId,
          message: 'analyticsId must be a static lowercase identifier of 1 to '
              '$kAnalyticsIdMaximumLength ASCII characters.',
          location: _locationFor(path),
        ),
      );
      return;
    }
    final declaration = _AnalyticsIdDeclarationDraft(
      analyticsId: value,
      presentationHandle: occurrence.handle,
    );
    final existing = _declarationByPresentationHandle[occurrence.handle];
    if (existing != null && existing.analyticsId != declaration.analyticsId) {
      issues.add(
        Issue(
          code: IssueCode.invalidAnalyticsId,
          message: 'Conflicting analyticsId declarations share one compiler '
              'occurrence handle.',
          location: _locationFor(path),
        ),
      );
      return;
    }
    if (existing == null) {
      _declarationByPresentationHandle[occurrence.handle] = declaration;
    }
  }

  void _missingPresentationHandle(List<String> path) {
    issues.add(
      Issue(
        code: IssueCode.invalidAnalyticsId,
        message: 'analyticsId requires an authoritative catalog occurrence '
            'for the same parsed constructor call.',
        location: _locationFor(path),
      ),
    );
  }

  _AnalyticsIdTypedCopy copyLibrary(fmt.RemoteWidgetLibrary original) {
    late final Object? Function(Object? value) copyValue;

    T withSource<T extends fmt.BlobNode>(T copy, fmt.BlobNode source) {
      copy.propagateSource(source);
      return copy;
    }

    Object copyRequired(Object? value) =>
        copyValue(value) ??
        (throw StateError('RFW typed copy produced an unexpected null'));

    fmt.DynamicMap copyDynamicMap(fmt.DynamicMap value) => <String, Object?>{
          for (final entry in value.entries) entry.key: copyValue(entry.value),
        };

    Map<Object?, Object> copySwitchOutputs(Map<Object?, Object> value) =>
        <Object?, Object>{
          for (final entry in value.entries)
            entry.key: copyRequired(entry.value),
        };

    fmt.ConstructorCall copyConstructor(fmt.ConstructorCall value) {
      final stripAnalyticsId = _constructorsToStrip.contains(value);
      final copy = withSource(
        fmt.ConstructorCall(
          value.name,
          <String, Object?>{
            for (final entry in value.arguments.entries)
              if (!stripAnalyticsId || entry.key != kAnalyticsIdPropertyName)
                entry.key: copyValue(entry.value),
          },
        ),
        value,
      );
      return copy;
    }

    copyValue = (value) {
      switch (value) {
        case final fmt.ConstructorCall call:
          return copyConstructor(call);
        case final fmt.EventHandler handler:
          return withSource(
            fmt.EventHandler(
              handler.eventName,
              copyDynamicMap(handler.eventArguments),
            ),
            handler,
          );
        case final fmt.SetStateHandler handler:
          return withSource(
            fmt.SetStateHandler(
              handler.stateReference,
              copyRequired(handler.value),
            ),
            handler,
          );
        case final fmt.WidgetBuilderDeclaration builder:
          return withSource(
            fmt.WidgetBuilderDeclaration(
              builder.argumentName,
              copyRequired(builder.widget) as fmt.BlobNode,
            ),
            builder,
          );
        case final fmt.Loop loop:
          return withSource(
            fmt.Loop(copyRequired(loop.input), copyRequired(loop.output)),
            loop,
          );
        case final fmt.Switch switchNode:
          return withSource(
            fmt.Switch(
              copyRequired(switchNode.input),
              copySwitchOutputs(switchNode.outputs),
            ),
            switchNode,
          );
        case final fmt.BoundArgsReference reference:
          return withSource(
            fmt.BoundArgsReference(
              copyRequired(reference.arguments),
              reference.parts,
            ),
            reference,
          );
        case final fmt.BoundLoopReference reference:
          return withSource(
            fmt.BoundLoopReference(
              copyRequired(reference.value),
              reference.parts,
            ),
            reference,
          );
        case final fmt.DynamicMap map:
          return copyDynamicMap(map);
        case final List<Object?> list:
          return <Object?>[for (final item in list) copyValue(item)];
        default:
          return value;
      }
    };

    final library = fmt.RemoteWidgetLibrary(
      original.imports,
      [
        for (final widget in original.widgets)
          withSource(
            fmt.WidgetDeclaration(
              widget.name,
              widget.initialState == null
                  ? null
                  : copyDynamicMap(widget.initialState!),
              copyRequired(widget.root) as fmt.BlobNode,
            ),
            widget,
          ),
      ],
    );
    return _AnalyticsIdTypedCopy(
      library: library,
      declarations: [
        for (final draft in _declarationByPresentationHandle.values)
          AnalyticsIdDeclaration(
            analyticsId: draft.analyticsId,
            presentationHandle: draft.presentationHandle,
          ),
      ],
    );
  }

  String _locationFor(List<String> path) => '$location/${path.join('/')}';
}

final class _AnalyticsIdDeclarationDraft {
  const _AnalyticsIdDeclarationDraft({
    required this.analyticsId,
    required this.presentationHandle,
  });

  final String analyticsId;
  final fmt.RfwCatalogOccurrenceHandle presentationHandle;
}

final class _AnalyticsIdTypedCopy {
  _AnalyticsIdTypedCopy({
    required this.library,
    required Iterable<AnalyticsIdDeclaration> declarations,
  }) : declarations = List<AnalyticsIdDeclaration>.unmodifiable(declarations);

  final fmt.RemoteWidgetLibrary library;
  final List<AnalyticsIdDeclaration> declarations;
}

String _pathPart(String kind, String value) =>
    '$kind:${Uri.encodeComponent(value)}';

final class _TextEdit {
  const _TextEdit(this.start, this.end);

  final int start;
  final int end;
}

String _applyEdits(String text, List<_TextEdit> edits) {
  final ordered = [...edits]..sort((left, right) => right.start - left.start);
  var previousStart = text.length + 1;
  var sanitized = text;
  for (final edit in ordered) {
    if (edit.start < 0 ||
        edit.end > text.length ||
        edit.start >= edit.end ||
        edit.end > previousStart) {
      throw const FormatException('Overlapping analyticsId source edits.');
    }
    sanitized = sanitized.replaceRange(edit.start, edit.end, '');
    previousStart = edit.start;
  }
  return sanitized;
}

final class _AnalyticsIdSourceRemoval {
  const _AnalyticsIdSourceRemoval(this.edits);

  final List<_TextEdit> edits;
}

final class _CallOpenParenScan {
  const _CallOpenParenScan(this.open, this.reservedCommentEdits);

  final int open;
  final List<_TextEdit> reservedCommentEdits;
}

_AnalyticsIdSourceRemoval? _analyticsIdRemoval(
  String text,
  fmt.SourceRange source,
) {
  final start = source.start.offset;
  final end = source.end.offset;
  final scan = _findCallOpenParen(text, start, end);
  if (scan == null) return null;
  final open = scan.open;
  final close = _findMatchingParen(text, open, end);
  if (close == null) return null;

  final segments = _argumentSegments(text, open + 1, close);
  final labelIndex = segments.indexWhere(
    (segment) => _isAnalyticsIdArgument(text, segment),
  );
  if (labelIndex < 0) return null;
  final nonEmpty = segments
      .where((segment) => !_isTriviaOnly(text, segment.start, segment.end))
      .toList(growable: false);
  if (nonEmpty.length == 1) {
    return _AnalyticsIdSourceRemoval([
      ...scan.reservedCommentEdits,
      _TextEdit(open + 1, close),
    ]);
  }

  final label = segments[labelIndex];
  if (label.comma != null) {
    return _AnalyticsIdSourceRemoval([
      ...scan.reservedCommentEdits,
      _TextEdit(label.start, _skipWhitespace(text, label.comma! + 1)),
    ]);
  }
  final previous = segments[labelIndex - 1];
  if (previous.comma == null) return null;
  return _AnalyticsIdSourceRemoval([
    ...scan.reservedCommentEdits,
    _TextEdit(previous.comma!, label.end),
  ]);
}

_CallOpenParenScan? _findCallOpenParen(String text, int start, int end) {
  final reservedCommentEdits = <_TextEdit>[];
  for (var index = start; index < end;) {
    final code = text.codeUnitAt(index);
    if (code == 0x22 || code == 0x27) {
      index = _skipString(text, index, end);
      continue;
    }
    if (code == 0x2f && index + 1 < end) {
      final next = text.codeUnitAt(index + 1);
      if (next == 0x2f || next == 0x2a) {
        final commentEnd = _skipComment(text, index, end);
        if (_containsIdentifier(
          text,
          index,
          commentEnd,
          kAnalyticsIdPropertyName,
        )) {
          reservedCommentEdits.add(_TextEdit(index, commentEnd));
        }
        index = commentEnd;
        continue;
      }
    }
    if (code == 0x28) {
      return _CallOpenParenScan(index, reservedCommentEdits);
    }
    index += 1;
  }
  return null;
}

bool _containsIdentifier(
  String text,
  int start,
  int end,
  String identifier,
) {
  var index = text.indexOf(identifier, start);
  while (index >= 0 && index < end) {
    final before = index == start ? null : text.codeUnitAt(index - 1);
    final afterIndex = index + identifier.length;
    final after = afterIndex >= end ? null : text.codeUnitAt(afterIndex);
    if ((before == null || !_isIdentifierPart(before)) &&
        (after == null || !_isIdentifierPart(after))) {
      return true;
    }
    index = text.indexOf(identifier, index + identifier.length);
  }
  return false;
}

int? _findMatchingParen(String text, int open, int end) {
  var depth = 0;
  for (var index = open; index < end;) {
    final code = text.codeUnitAt(index);
    if (code == 0x22 || code == 0x27) {
      index = _skipString(text, index, end);
      continue;
    }
    if (code == 0x2f && index + 1 < end) {
      final next = text.codeUnitAt(index + 1);
      if (next == 0x2f || next == 0x2a) {
        index = _skipComment(text, index, end);
        continue;
      }
    }
    if (code == 0x28) depth += 1;
    if (code == 0x29) {
      depth -= 1;
      if (depth == 0) return index;
    }
    index += 1;
  }
  return null;
}

List<_ArgumentSegment> _argumentSegments(String text, int start, int end) {
  final segments = <_ArgumentSegment>[];
  var segmentStart = start;
  var depth = 0;
  for (var index = start; index < end;) {
    final code = text.codeUnitAt(index);
    if (code == 0x22 || code == 0x27) {
      index = _skipString(text, index, end);
      continue;
    }
    if (code == 0x2f && index + 1 < end) {
      final next = text.codeUnitAt(index + 1);
      if (next == 0x2f || next == 0x2a) {
        index = _skipComment(text, index, end);
        continue;
      }
    }
    if (code == 0x28 || code == 0x5b || code == 0x7b) depth += 1;
    if (code == 0x29 || code == 0x5d || code == 0x7d) depth -= 1;
    if (code == 0x2c && depth == 0) {
      segments.add(_ArgumentSegment(segmentStart, index, index));
      segmentStart = index + 1;
    }
    index += 1;
  }
  segments.add(_ArgumentSegment(segmentStart, end, null));
  return segments;
}

bool _isAnalyticsIdArgument(String text, _ArgumentSegment segment) {
  var index = _skipTrivia(text, segment.start, segment.end);
  final key = _readMapKey(text, index, segment.end);
  if (key == null || key.value != kAnalyticsIdPropertyName) return false;
  index = _skipTrivia(text, key.end, segment.end);
  return index < segment.end && text.codeUnitAt(index) == 0x3a;
}

bool _isTriviaOnly(String text, int start, int end) =>
    _skipTrivia(text, start, end) == end;

int _skipWhitespace(String text, int start) {
  var index = start;
  while (index < text.length && _isWhitespace(text.codeUnitAt(index))) {
    index += 1;
  }
  return index;
}

int _skipTrivia(String text, int start, int end) {
  var index = start;
  while (index < end) {
    if (_isWhitespace(text.codeUnitAt(index))) {
      index += 1;
      continue;
    }
    if (text.codeUnitAt(index) == 0x2f && index + 1 < end) {
      final next = text.codeUnitAt(index + 1);
      if (next == 0x2f || next == 0x2a) {
        index = _skipComment(text, index, end);
        continue;
      }
    }
    break;
  }
  return index;
}

bool _isWhitespace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;

int _skipComment(String text, int start, int end) {
  var index = start;
  final next = text.codeUnitAt(index + 1);
  if (next == 0x2f) {
    index += 2;
    while (index < end && text.codeUnitAt(index) != 0x0a) {
      index += 1;
    }
    return index;
  }
  index += 2;
  while (index + 1 < end) {
    if (text.codeUnitAt(index) == 0x2a && text.codeUnitAt(index + 1) == 0x2f) {
      return index + 2;
    }
    index += 1;
  }
  return end;
}

int _skipString(String text, int start, int end) {
  final quote = text.codeUnitAt(start);
  var index = start + 1;
  while (index < end) {
    final code = text.codeUnitAt(index);
    if (code == 0x5c) {
      index += 2;
      continue;
    }
    index += 1;
    if (code == quote) return index;
  }
  return end;
}

_MapKey? _readMapKey(String text, int start, int end) {
  if (start >= end) return null;
  final code = text.codeUnitAt(start);
  if (code == 0x22 || code == 0x27) {
    return _readQuotedMapKey(text, start, end);
  }
  if (!_isIdentifierStart(code)) return null;
  var index = start + 1;
  while (index < end && _isIdentifierPart(text.codeUnitAt(index))) {
    index += 1;
  }
  return _MapKey(text.substring(start, index), index);
}

_MapKey? _readQuotedMapKey(String text, int start, int end) {
  final quote = text.codeUnitAt(start);
  final buffer = StringBuffer();
  var index = start + 1;
  while (index < end) {
    final code = text.codeUnitAt(index);
    if (code == quote) return _MapKey(buffer.toString(), index + 1);
    if (code != 0x5c) {
      buffer.writeCharCode(code);
      index += 1;
      continue;
    }
    if (index + 1 >= end) return null;
    final escaped = text.codeUnitAt(index + 1);
    switch (escaped) {
      case 0x62:
        buffer.writeCharCode(0x08);
      case 0x66:
        buffer.writeCharCode(0x0c);
      case 0x6e:
        buffer.writeCharCode(0x0a);
      case 0x72:
        buffer.writeCharCode(0x0d);
      case 0x74:
        buffer.writeCharCode(0x09);
      case 0x75:
        if (index + 5 >= end) return null;
        final value = int.tryParse(
          text.substring(index + 2, index + 6),
          radix: 16,
        );
        if (value == null) return null;
        buffer.writeCharCode(value);
        index += 6;
        continue;
      default:
        buffer.writeCharCode(escaped);
    }
    index += 2;
  }
  return null;
}

bool _isIdentifierStart(int code) =>
    code == 0x5f ||
    (code >= 0x41 && code <= 0x5a) ||
    (code >= 0x61 && code <= 0x7a);

bool _isIdentifierPart(int code) =>
    _isIdentifierStart(code) || (code >= 0x30 && code <= 0x39);

final class _ArgumentSegment {
  const _ArgumentSegment(this.start, this.end, this.comma);

  final int start;
  final int end;
  final int? comma;
}

final class _MapKey {
  const _MapKey(this.value, this.end);

  final String value;
  final int end;
}
