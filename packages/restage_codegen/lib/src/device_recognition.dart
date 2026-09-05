import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// A recognised read of the published `data.device.*` namespace.
class DeviceRead {
  /// Creates a read of the contract [path].
  const DeviceRead(this.path);

  /// The contract path, or null when the member is outside the contract.
  final String? path;
}

const Map<String, String> _kSizeMembers = {
  'width': 'screenWidth',
  'height': 'screenHeight',
  'shortestSide': 'shortestSide',
  'longestSide': 'longestSide',
};

const Map<String, String> _kPaddingMembers = {
  'top': 'safeAreaTop',
  'bottom': 'safeAreaBottom',
  'left': 'safeAreaLeft',
  'right': 'safeAreaRight',
};

const Set<String> _kLocaleSubtags = {'languageCode', 'countryCode'};

/// The `data.device.*` read [expr] performs, or `null` when [expr] is not
/// rooted at a device source at all. The single canonical device-read
/// recogniser the classifier, the translator lowerer, and the slot validator
/// all route through, so the three never drift.
///
/// Recognised shapes:
/// - `MediaQuery.sizeOf(c).width|height|shortestSide|longestSide` and
///   `MediaQuery.of(c).size.<same>`
/// - `MediaQuery.orientationOf(c)` and `MediaQuery.of(c).orientation`
/// - `MediaQuery.devicePixelRatioOf(c)` and `MediaQuery.of(c).devicePixelRatio`
/// - `MediaQuery.paddingOf(c).top|bottom|left|right` and
///   `MediaQuery.of(c).padding.<same>`
/// - `Localizations.localeOf(c).languageCode|countryCode`
/// - `defaultTargetPlatform` and `Theme.of(c).platform`
///
/// The chain may pass through a bound `final` local captured in [bindings].
DeviceRead? deviceRead(
  Expression expr, {
  Map<Element, Expression> bindings = const {},
}) {
  final chain = _deviceChain(expr, bindings);
  if (chain == null) return null;
  final root = chain.root;
  final segments = chain.segments;

  if (root is SimpleIdentifier) {
    if (!isFlutterTopLevelValue(root, 'defaultTargetPlatform')) return null;
    return segments.isEmpty
        ? const DeviceRead('platform')
        : const DeviceRead(null);
  }
  if (root is! MethodInvocation) return null;
  // Every recognised source takes the BuildContext as its single argument.
  final args = root.argumentList.arguments;
  if (args.length != 1 || args.first is! SimpleIdentifier) return null;
  final method = root.methodName.name;

  if (isFlutterStaticMember(root, 'MediaQuery')) {
    return DeviceRead(_mediaQueryPath(method, segments));
  }
  if (isFlutterStaticMember(root, 'Localizations')) {
    if (method != 'localeOf') return const DeviceRead(null);
    if (segments.length == 1 && _kLocaleSubtags.contains(segments.first)) {
      return DeviceRead(segments.first);
    }
    return const DeviceRead(null);
  }
  if (isFlutterStaticOf(root, 'Theme')) {
    // Only the platform read belongs to this namespace; every other Theme
    // chain stays with the theme recogniser.
    if (segments.length == 1 && segments.first == 'platform') {
      return const DeviceRead('platform');
    }
  }
  return null;
}

/// The contract path [expr] reads, or `null` when it is not an in-contract
/// device read.
String? deviceReadPath(
  Expression expr, {
  Map<Element, Expression> bindings = const {},
}) =>
    deviceRead(expr, bindings: bindings)?.path;

/// Whether [expr] is an in-contract device read — the boolean form of
/// [deviceReadPath].
bool isDeviceReadChain(
  Expression expr, {
  Map<Element, Expression> bindings = const {},
}) =>
    deviceReadPath(expr, bindings: bindings) != null;

/// Whether [invocation] is a static call on a framework class named
/// [className], for any member name. [isFlutterStaticOf] is the `of`-only
/// sibling.
bool isFlutterStaticMember(MethodInvocation invocation, String className) {
  final element = invocation.methodName.element;
  if (element != null) {
    if (!libraryIsFlutter(element)) return false;
    return element.enclosingElement?.name == className;
  }
  final target = invocation.target;
  if (target is SimpleIdentifier) return target.name == className;
  if (target is PrefixedIdentifier) return target.identifier.name == className;
  return false;
}

/// Whether [identifier] references the framework top-level value [name].
/// A resolved reference must come from a framework library.
bool isFlutterTopLevelValue(SimpleIdentifier identifier, String name) {
  if (identifier.name != name) return false;
  final element = identifier.element;
  if (element == null) return true;
  return libraryIsFlutter(element);
}

String? _mediaQueryPath(String method, List<String> segments) {
  switch (method) {
    case 'sizeOf':
      return segments.length == 1 ? _kSizeMembers[segments.first] : null;
    case 'paddingOf':
      return segments.length == 1 ? _kPaddingMembers[segments.first] : null;
    case 'devicePixelRatioOf':
      return segments.isEmpty ? 'pixelRatio' : null;
    case 'orientationOf':
      return segments.isEmpty ? 'orientation' : null;
    case 'of':
      if (segments.length == 1 && segments.first == 'devicePixelRatio') {
        return 'pixelRatio';
      }
      if (segments.length == 1 && segments.first == 'orientation') {
        return 'orientation';
      }
      if (segments.length != 2) return null;
      return switch (segments.first) {
        'size' => _kSizeMembers[segments[1]],
        'padding' => _kPaddingMembers[segments[1]],
        _ => null,
      };
    default:
      return null;
  }
}

/// Walks [expr]'s property chain down to its root, splicing through bound
/// locals, and returns the root plus the property names in source order.
({Expression root, List<String> segments})? _deviceChain(
  Expression expr,
  Map<Element, Expression> bindings,
) {
  final reversed = <String>[];
  var current = expr;
  while (true) {
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    if (current is PropertyAccess) {
      final target = current.target;
      if (target == null) return null;
      reversed.add(current.propertyName.name);
      current = target;
      continue;
    }
    if (current is PrefixedIdentifier) {
      final bound = bindings[current.prefix.element];
      if (bound == null) {
        // Not a bound local — `foundation.defaultTargetPlatform` and friends
        // resolve on the identifier.
        return (root: current.identifier, segments: reversed.reversed.toList());
      }
      reversed.add(current.identifier.name);
      current = bound;
      continue;
    }
    if (current is SimpleIdentifier) {
      final bound = bindings[current.element];
      if (bound == null) break;
      current = bound;
      continue;
    }
    break;
  }
  return (root: current, segments: reversed.reversed.toList());
}

/// The `dart:io` `Platform` flags, mapped to the published platform token.
const Map<String, String> _kPlatformFlags = {
  'isIOS': 'iOS',
  'isAndroid': 'android',
  'isMacOS': 'macOS',
  'isWindows': 'windows',
  'isLinux': 'linux',
  'isFuchsia': 'fuchsia',
};

/// The platform token [expr] tests for as a bare boolean flag — `kIsWeb`, or
/// one of the `dart:io` `Platform.isX` getters. `Platform` must resolve against
/// `dart:io`, so an app class of that name is not read as a platform test.
String? devicePlatformFlag(Expression expr) {
  final current = _unwrapParens(expr);
  if (current is SimpleIdentifier) {
    return isFlutterTopLevelValue(current, 'kIsWeb') ? 'web' : null;
  }
  if (current is! PrefixedIdentifier) return null;
  if (current.prefix.name != 'Platform') return null;
  final element = current.identifier.element;
  final library = element?.library?.identifier;
  if (library != null && library != 'dart:io') return null;
  return _kPlatformFlags[current.identifier.name];
}

/// Recognises `<device read> ==|!= <token>` in either operand order. The token
/// is a framework enum member for `platform`, a string literal for the locale
/// subtags. [resolve] splices a bound local into an operand.
({String path, String key, bool equals})? deviceTokenComparison(
  BinaryExpression expr, {
  Map<Element, Expression> bindings = const {},
  Expression Function(Expression) resolve = _identity,
  bool Function(Element?) isFrameworkLibrary = isFrameworkValueTypeLibrary,
}) {
  final operator = expr.operator.lexeme;
  if (operator != '==' && operator != '!=') return null;
  final left = _unwrapParens(resolve(expr.leftOperand));
  final right = _unwrapParens(resolve(expr.rightOperand));
  for (final (read, other) in <(Expression, Expression)>[
    (left, right),
    (right, left),
  ]) {
    final path = deviceReadPath(read, bindings: bindings);
    if (path == null) continue;
    final key = _deviceTokenKey(path, other, isFrameworkLibrary);
    if (key == null) return null;
    return (path: path, key: key, equals: operator == '==');
  }
  return null;
}

/// The switch key [other] contributes for the device [path].
String? _deviceTokenKey(
  String path,
  Expression other,
  bool Function(Element?) isFrameworkLibrary,
) {
  if (path == 'platform') {
    return _frameworkEnumMember(other, 'TargetPlatform', isFrameworkLibrary);
  }
  if (path == 'orientation') {
    return _frameworkEnumMember(other, 'Orientation', isFrameworkLibrary);
  }
  if (path == 'languageCode' || path == 'countryCode') {
    final literal = _unwrapParens(other);
    if (literal is SimpleStringLiteral) return literal.value;
  }
  return null;
}

/// The `<className>.<member>` framework enum member [expr] names.
String? _frameworkEnumMember(
  Expression expr,
  String className,
  bool Function(Element?) isFrameworkLibrary,
) {
  final current = _unwrapParens(expr);
  if (current is PrefixedIdentifier) {
    if (current.prefix.name != className) return null;
    if (!isFrameworkLibrary(current.identifier.element)) return null;
    return current.identifier.name;
  }
  if (current is PropertyAccess) {
    final target = current.target;
    if (target is PrefixedIdentifier && target.identifier.name == className) {
      return current.propertyName.name;
    }
  }
  return null;
}

Expression _identity(Expression expr) => expr;

Expression _unwrapParens(Expression expr) {
  var current = expr;
  while (current is ParenthesizedExpression) {
    current = current.expression;
  }
  return current;
}
