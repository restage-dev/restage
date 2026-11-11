// Copyright 2026 Restage Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This file is hand-formatted.

part of 'text.dart';

// Grammar of the expression nodes, in the extended (library) syntax:
//
//   program { <program data>, captures: { <name>: <argument>, ... } }
//   effects [ <step>, ... ]          where a step is `set`, `event` or `when`
//   when <program> [ <step>, ... ]
//   native { key: "<key>", type: "<type>", nullable: <bool> }
//
// The keywords are contextual: followed by `(` they still name a widget.

extension on _Parser {
  Object _readExpressionNodeOrConstructorCall({
    List<String> widgetBuilderScope = const <String>[],
  }) {
    final SourceLocation? start = _getSourceLocation();
    final _Token keywordToken = _source.current;
    final String identifier = (keywordToken as _IdentifierToken).value;
    const keywords = <String>{'program', 'effects', 'when', 'native'};
    if (!keywords.contains(identifier)) {
      return _readConstructorCall(widgetBuilderScope: widgetBuilderScope);
    }
    _advance();
    if (_foundSymbol(_SymbolToken.openParen)) {
      _advance();
      final DynamicMap arguments = _readMapBody(
        extended: true,
        widgetBuilderScope: widgetBuilderScope,
      );
      _expectSymbol(_SymbolToken.closeParen);
      return _withSourceRange(ConstructorCall(identifier, arguments), start);
    }
    switch (identifier) {
      case 'program':
        return _withSourceRange(_readProgramBody(keywordToken, widgetBuilderScope), start);
      case 'effects':
        return _withSourceRange(Effects(_readSteps(widgetBuilderScope)), start);
      case 'when':
        final _Token conditionToken = _source.current;
        final Object condition = _readValue(extended: true, widgetBuilderScope: widgetBuilderScope);
        if (condition is! Program) {
          throw ParserException._fromToken('Expected a program as the condition of "when"', conditionToken);
        }
        return _withSourceRange(Guard(condition, _readSteps(widgetBuilderScope)), start);
      default:
        return _withSourceRange(_readNativeBody(keywordToken), start);
    }
  }

  Program _readProgramBody(_Token keywordToken, List<String> widgetBuilderScope) {
    final DynamicMap body = _readMap(extended: true, widgetBuilderScope: widgetBuilderScope);
    final Object? captures = body.remove('captures');
    if (captures != null && captures is! DynamicMap) {
      throw ParserException._fromToken('The captures of a program must be a map', keywordToken);
    }
    if (_containsNode(body)) {
      throw ParserException._fromToken('Program data must not contain references or widgets; put them in captures', keywordToken);
    }
    return Program(body, (captures as DynamicMap?) ?? DynamicMap());
  }

  DynamicList _readSteps(List<String> widgetBuilderScope) {
    final _Token listToken = _source.current;
    final DynamicList steps = _readList(extended: true, widgetBuilderScope: widgetBuilderScope);
    for (final step in steps) {
      if (step is! EventHandler && step is! SetStateHandler && step is! Guard) {
        throw ParserException._fromToken('Expected only "set", "event" and "when" steps', listToken);
      }
    }
    return steps;
  }

  NativeReference _readNativeBody(_Token keywordToken) {
    final DynamicMap body = _readMap(extended: false);
    final Object? key = body['key'];
    final Object? type = body['type'];
    final Object? nullable = body['nullable'];
    if (body.length != 3 || key is! String || type is! String || nullable is! bool) {
      throw ParserException._fromToken('A native reference needs exactly a string key, a string type and a boolean nullable', keywordToken);
    }
    return NativeReference(key, type, nullable: nullable);
  }

  bool _containsNode(Object? value) {
    if (value is BlobNode) {
      return true;
    }
    if (value is DynamicMap) {
      return value.values.any(_containsNode);
    }
    if (value is DynamicList) {
      return value.any(_containsNode);
    }
    return false;
  }
}
