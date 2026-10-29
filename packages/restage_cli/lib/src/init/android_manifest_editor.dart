import 'package:xml/xml.dart' show XmlException;
import 'package:xml/xml_events.dart';

/// The app's main Android manifest.
const String androidMainManifestPath =
    'android/app/src/main/AndroidManifest.xml';

const String _internetPermission = 'android.permission.INTERNET';

/// Whether [source] declares the INTERNET permission, and not for removal.
/// A manifest that does not parse declares nothing.
bool androidManifestAllowsInternet(String source) {
  try {
    return parseEvents(source).whereType<XmlStartElementEvent>().any(
      (element) =>
          (element.name == 'uses-permission' ||
              element.name == 'uses-permission-sdk-23') &&
          _attribute(element, 'android:name') == _internetPermission &&
          !const {
            'remove',
            'removeAll',
          }.contains(_attribute(element, 'tools:node')),
    );
  } on XmlException {
    return false;
  }
}

/// [source] with the INTERNET permission added as the manifest's first child,
/// or null when it already has it or its root is not an open `<manifest>`.
String? addAndroidInternetPermission(String source) {
  if (androidManifestAllowsInternet(source)) return null;
  final XmlStartElementEvent root;
  try {
    root = parseEvents(
      source,
      withLocation: true,
    ).whereType<XmlStartElementEvent>().first;
  } on XmlException {
    return null;
  } on StateError {
    return null;
  }
  if (root.name != 'manifest' || root.isSelfClosing) return null;
  final end = root.stop!;
  final newline = source.contains('\r\n') ? '\r\n' : '\n';
  final rest = source.substring(end);
  final indent =
      RegExp(r'^\r?\n([ \t]+)\S').firstMatch(rest)?.group(1) ?? '    ';
  return '${source.substring(0, end)}$newline$indent'
      '<uses-permission android:name="$_internetPermission"/>$rest';
}

String? _attribute(XmlStartElementEvent element, String name) => element
    .attributes
    .where((attribute) => attribute.name == name)
    .firstOrNull
    ?.value;
