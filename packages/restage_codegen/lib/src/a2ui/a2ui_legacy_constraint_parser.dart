import 'dart:convert';

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Parses the closed legacy validation grammar into typed constraints.
RestageConstraints parseA2uiLegacyConstraint(String expression) =>
    _A2uiLegacyConstraintParser(expression).parse();

/// A deterministic lexical failure in a legacy validation expression.
final class A2uiLegacyConstraintParseException implements Exception {
  /// Creates a lexical failure with human-readable [detail].
  const A2uiLegacyConstraintParseException(this.detail);

  /// Human-readable syntax failure detail.
  final String detail;

  @override
  String toString() => detail;
}

final class _A2uiLegacyConstraintParser {
  _A2uiLegacyConstraintParser(this.source);

  final String source;
  var _index = 0;

  RestageConstraints parse() {
    _skipWhitespace();
    final name = _takeIdentifier();
    if (name.isEmpty) _fail('expected a supported function name');
    _skipWhitespace();
    _expect('(', 'expected ( after $name');

    return switch (name) {
      'range' => _parseRange(),
      'oneOf' => _parseOneOf(),
      'matches' => _parseMatches(),
      _ => _unsupported(name),
    };
  }

  RestageConstraints _parseRange() {
    final minimum = _parseJsonScalar();
    if (minimum is! num) _fail('range minimum must be a finite JSON number');
    _expectSeparator();
    final maximum = _parseJsonScalar();
    if (maximum is! num) _fail('range maximum must be a finite JSON number');
    _finishCall();
    return RestageConstraints(minimum: minimum, maximum: maximum);
  }

  RestageConstraints _parseOneOf() {
    _skipWhitespace();
    if (_peek(')')) _fail('oneOf requires at least one JSON scalar');
    final values = <Object?>[];
    while (true) {
      values.add(_parseJsonScalar());
      _skipWhitespace();
      if (!_peek(',')) break;
      _index++;
      _skipWhitespace();
      if (_peek(')')) _fail('oneOf does not allow a trailing comma');
    }
    _finishCall();
    return RestageConstraints(allowedValues: values);
  }

  RestageConstraints _parseMatches() {
    final pattern = _parseJsonScalar();
    if (pattern is! String) _fail('matches requires one JSON string');
    _finishCall();
    return RestageConstraints(pattern: pattern);
  }

  Object? _parseJsonScalar() {
    _skipWhitespace();
    if (_index >= source.length) _fail('expected a JSON scalar');
    if (_peek('"')) return _parseJsonString();
    if (_startsWith('true')) {
      _index += 4;
      return true;
    }
    if (_startsWith('false')) {
      _index += 5;
      return false;
    }
    if (_startsWith('null')) {
      _index += 4;
      return null;
    }
    final character = source[_index];
    if (character == '-' || _isDigit(character)) return _parseJsonNumber();
    _fail('expected a JSON scalar');
  }

  String _parseJsonString() {
    final start = _index;
    _index++; // opening quote
    var escaped = false;
    while (_index < source.length) {
      final code = source.codeUnitAt(_index);
      final character = source[_index];
      if (!escaped && character == '"') {
        _index++;
        final token = source.substring(start, _index);
        try {
          return jsonDecode(token) as String;
        } on Object {
          _fail('invalid JSON string');
        }
      }
      if (!escaped && code < 0x20) _fail('invalid JSON string');
      if (!escaped && character == r'\') {
        escaped = true;
      } else {
        escaped = false;
      }
      _index++;
    }
    _fail('unterminated JSON string');
  }

  num _parseJsonNumber() {
    final start = _index;
    if (_peek('-')) _index++;
    if (_index >= source.length) _fail('invalid JSON number');

    if (_peek('0')) {
      _index++;
    } else {
      final first = source[_index];
      if (first.codeUnitAt(0) < 0x31 || first.codeUnitAt(0) > 0x39) {
        _fail('invalid JSON number');
      }
      _takeDigits();
    }
    if (_peek('.')) {
      _index++;
      if (_index >= source.length || !_isDigit(source[_index])) {
        _fail('invalid JSON number fraction');
      }
      _takeDigits();
    }
    if (_peek('e') || _peek('E')) {
      _index++;
      if (_peek('+') || _peek('-')) _index++;
      if (_index >= source.length || !_isDigit(source[_index])) {
        _fail('invalid JSON number exponent');
      }
      _takeDigits();
    }

    final token = source.substring(start, _index);
    final value = jsonDecode(token);
    if (value is! num || !value.isFinite) {
      _fail('JSON numbers must be finite');
    }
    return value;
  }

  void _expectSeparator() {
    _skipWhitespace();
    _expect(',', 'expected , between arguments');
  }

  void _finishCall() {
    _skipWhitespace();
    _expect(')', 'expected ) after the final argument');
    _skipWhitespace();
    if (_index != source.length) _fail('unexpected trailing input');
  }

  String _takeIdentifier() {
    final start = _index;
    while (_index < source.length) {
      final code = source.codeUnitAt(_index);
      final isLetter =
          code >= 0x41 && code <= 0x5a || code >= 0x61 && code <= 0x7a;
      if (!isLetter) break;
      _index++;
    }
    return source.substring(start, _index);
  }

  void _takeDigits() {
    while (_index < source.length && _isDigit(source[_index])) {
      _index++;
    }
  }

  void _skipWhitespace() {
    while (_index < source.length) {
      final code = source.codeUnitAt(_index);
      if (code != 0x20 && code != 0x09 && code != 0x0a && code != 0x0d) {
        break;
      }
      _index++;
    }
  }

  void _expect(String character, String detail) {
    if (!_peek(character)) _fail(detail);
    _index++;
  }

  bool _startsWith(String token) => source.startsWith(token, _index);

  bool _peek(String character) =>
      _index < source.length && source[_index] == character;

  static bool _isDigit(String character) {
    final code = character.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  Never _unsupported(String name) =>
      _fail('unsupported validation function "$name"');

  Never _fail(String detail) => throw A2uiLegacyConstraintParseException(
        '$detail at character ${_index + 1}',
      );
}
