import 'package:analyzer/dart/element/element.dart';

/// Whether [element] is, or extends, the Flutter framework type [name].
bool isFlutterFrameworkType(InterfaceElement element, String name) =>
    _isWidgetsType(element, name, 'framework.dart');

// Whether [element] is, or extends, the Flutter widgets type [name], declared
// in [file] of the widgets library when given.
bool _isWidgetsType(
  InterfaceElement element,
  String name, [
  String file = '',
]) => [element.thisType, ...element.allSupertypes].any(
  (type) =>
      type.element.name == name &&
      type.element.library.identifier.startsWith(
        'package:flutter/src/widgets/$file',
      ),
);
