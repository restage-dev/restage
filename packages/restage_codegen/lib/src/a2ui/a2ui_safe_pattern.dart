/// Returns null when [pattern] belongs to the shared ASCII regex subset.
///
/// The subset is intentionally lexical: it admits only syntax whose search
/// semantics agree between Dart's RegExp and JSON Schema's ECMA-262 pattern
/// dialect. A non-null result explains the first rejected construct.
String? a2uiSafePatternRejection(String pattern) =>
    _A2uiSafePatternScanner(pattern).scan();

/// Conservative finite regex-quantifier ceiling shared by the admitted
/// Dart/ECMAScript subset.
///
/// Direct characterization proved every quantifier form at 65,535 under the
/// pinned Dart Unicode RegExp and V8's ECMAScript Unicode engine. Both engines
/// also accept larger bounds, so this is an intentional portable policy limit,
/// not a claim about either engine's implementation ceiling.
const int a2uiSafePatternMaxQuantifier = 65535;

final class _A2uiSafePatternScanner {
  _A2uiSafePatternScanner(this.pattern);

  static const _outsideEscapable = r'\.^$*+?()[]{}|';
  static const _classEscapable = r'\][^-';

  final String pattern;
  var _index = 0;

  String? scan() {
    if (_peek('^')) _index++;

    while (_index < pattern.length) {
      if (_peek(r'$')) {
        if (_index == pattern.length - 1) {
          _index++;
          return null;
        }
        return r'an unescaped $ anchor is only allowed at the end';
      }

      final atomError = _scanAtom();
      if (atomError != null) return atomError;

      final quantifierError = _scanQuantifier();
      if (quantifierError != null) return quantifierError;
    }
    return null;
  }

  String? _scanAtom() {
    final code = pattern.codeUnitAt(_index);
    final character = pattern[_index];
    if (!_isPrintableAscii(code)) {
      return 'only printable ASCII literals are allowed';
    }
    if (character == '[') return _scanClass();
    if (character == r'\') {
      final escaped = _scanEscape(inClass: false);
      return escaped.error;
    }

    final error = switch (character) {
      '.' => 'dot/wildcard is not allowed; escape it for a literal dot',
      '^' => 'an unescaped ^ anchor is only allowed at the start',
      '(' || ')' => 'grouping and lookaround syntax are not allowed',
      '|' => 'alternation is not allowed',
      '*' || '+' || '?' => 'a quantifier must follow one literal or class',
      '{' || '}' => 'a braced quantifier must follow one literal or class',
      ']' => 'a closing bracket must belong to a bracket class',
      _ => null,
    };
    if (error != null) return error;
    _index++;
    return null;
  }

  String? _scanClass() {
    _index++; // [
    if (_peek('^')) _index++;
    var members = 0;

    while (_index < pattern.length) {
      if (_peek(']')) {
        if (members == 0) return 'a bracket class must not be empty';
        _index++;
        return null;
      }

      final start = _scanClassAtom();
      if (start.error != null) return start.error;
      members++;

      if (_peek('-')) {
        _index++;
        if (_index >= pattern.length || _peek(']')) {
          return 'a class range must have an ASCII endpoint on both sides';
        }
        final end = _scanClassAtom();
        if (end.error != null) return end.error;
        if (start.code! > end.code!) {
          return 'a class range must be ordered from lower to higher ASCII';
        }
      }
    }
    return 'a bracket class must have a closing ]';
  }

  _ClassAtom _scanClassAtom() {
    final code = pattern.codeUnitAt(_index);
    final character = pattern[_index];
    if (!_isPrintableAscii(code)) {
      return const _ClassAtom.error(
        'bracket classes may contain only printable ASCII literals',
      );
    }
    if (character == r'\') return _scanEscape(inClass: true);
    if (character == '-') {
      return const _ClassAtom.error(
        'a literal class hyphen must be escaped',
      );
    }
    if (character == '[') {
      return const _ClassAtom.error(
        'a literal class opening bracket must be escaped',
      );
    }
    _index++;
    return _ClassAtom.code(code);
  }

  _ClassAtom _scanEscape({required bool inClass}) {
    _index++; // backslash
    if (_index >= pattern.length) {
      return const _ClassAtom.error('a trailing backslash is not allowed');
    }
    final escapedCode = pattern.codeUnitAt(_index);
    final escaped = pattern[_index];
    final escapable = inClass ? _classEscapable : _outsideEscapable;
    if (!_isPrintableAscii(escapedCode) || !escapable.contains(escaped)) {
      return _ClassAtom.error(
        inClass
            ? r'class escapes may quote only \, [, ], ^, or -'
            : 'escapes may quote only metacharacters outside a class',
      );
    }
    _index++;
    return _ClassAtom.code(escapedCode);
  }

  String? _scanQuantifier() {
    if (_index >= pattern.length) return null;
    if (_peek('?') || _peek('*') || _peek('+')) {
      _index++;
      return null;
    }
    if (!_peek('{')) return null;

    _index++;
    final minimumDigits = _takeDigits();
    if (minimumDigits.isEmpty) {
      return 'a braced quantifier requires a decimal minimum';
    }
    String? maximumDigits;
    if (_peek('}')) {
      maximumDigits = minimumDigits;
    } else {
      if (!_peek(',')) {
        return 'a braced quantifier must be {m}, {m,}, or {m,n}';
      }
      _index++;
      final digits = _takeDigits();
      maximumDigits = digits.isEmpty ? null : digits;
    }
    if (!_peek('}')) {
      return 'a braced quantifier must have a closing }';
    }
    _index++;

    final minimum = _parsePortableQuantifierBound(minimumDigits);
    final maximum = maximumDigits == null
        ? null
        : _parsePortableQuantifierBound(maximumDigits);
    if (minimum == null || maximumDigits != null && maximum == null) {
      return 'every finite quantifier bound must be no greater than '
          '$a2uiSafePatternMaxQuantifier';
    }
    if (maximum != null && minimum > maximum) {
      return 'a braced quantifier minimum must not exceed its maximum';
    }
    return null;
  }

  int? _parsePortableQuantifierBound(String digits) {
    var value = 0;
    for (final code in digits.codeUnits) {
      final digit = code - 0x30;
      if (value > (a2uiSafePatternMaxQuantifier - digit) ~/ 10) return null;
      value = value * 10 + digit;
    }
    return value;
  }

  String _takeDigits() {
    final start = _index;
    while (_index < pattern.length) {
      final code = pattern.codeUnitAt(_index);
      if (code < 0x30 || code > 0x39) break;
      _index++;
    }
    return pattern.substring(start, _index);
  }

  bool _peek(String character) =>
      _index < pattern.length && pattern[_index] == character;

  static bool _isPrintableAscii(int code) => code >= 0x20 && code <= 0x7e;
}

final class _ClassAtom {
  const _ClassAtom.code(this.code) : error = null;

  const _ClassAtom.error(this.error) : code = null;

  final int? code;
  final String? error;
}
