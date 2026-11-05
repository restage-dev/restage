/// The Dart spelling of a positional callback type id such as
/// `(package:flutter/src/gestures/tap.dart#TapDownDetails)->void`.
///
/// Classes are spelled by name, so they must be visible where the code is
/// emitted. Throws a [FormatException] for any other shape.
String dartTypeOfCallbackTypeId(String id) {
  final parser = _Parser(id);
  final type = parser.type();
  if (!parser.done) throw FormatException('Unexpected text', id, parser.at);
  return type;
}

// `name:` before a type, as opposed to a library's `dart:` or `package:`.
final _named = RegExp(r'[A-Za-z_]\w*:(\(|void|dart:|package:)');

final class _Parser {
  _Parser(this.text);

  final String text;
  int at = 0;

  bool get done => at == text.length;

  String type() {
    if (_take('(')) {
      final parameters = <String>[];
      if (!_take(')')) {
        do {
          if (text.startsWith('required ', at) ||
              text.startsWith('optional ', at) ||
              _named.matchAsPrefix(text, at) != null) {
            throw FormatException('Named or optional parameter', text, at);
          }
          parameters.add(type());
        } while (_take(','));
        _expect(')');
      }
      _expect('->');
      final result = type();
      return '$result Function(${parameters.join(', ')})${_nullable()}';
    }
    if (text.startsWith('void', at)) {
      at += 4;
      return 'void';
    }
    final hash = text.indexOf('#', at);
    if (hash < 0) throw FormatException('Expected a nominal type', text, at);
    at = hash + 1;
    final name = RegExp(r'[A-Za-z_$][\w$]*').matchAsPrefix(text, at);
    if (name == null) throw FormatException('Expected a type name', text, at);
    at = name.end;
    var spelled = name[0]!;
    if (_take('<')) {
      final arguments = <String>[];
      do {
        arguments.add(type());
      } while (_take(','));
      _expect('>');
      spelled = '$spelled<${arguments.join(', ')}>';
    }
    return '$spelled${_nullable()}';
  }

  String _nullable() => _take('?') ? '?' : '';

  bool _take(String token) {
    if (!text.startsWith(token, at)) return false;
    at += token.length;
    return true;
  }

  void _expect(String token) {
    if (!_take(token)) throw FormatException('Expected $token', text, at);
  }
}
