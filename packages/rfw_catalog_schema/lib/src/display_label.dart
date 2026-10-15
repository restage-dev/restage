final RegExp _words = RegExp(r'[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|\d+');

const Set<String> _acronyms = {'id', 'url', 'rgb', 'rtl', 'ime'};

/// A sentence-case label for a camelCase [identifier]: `textAlign` becomes
/// `Text align`. Acronyms stay upper case (`analyticsId` becomes
/// `Analytics ID`) and a leading `is` drops (`isScrollable` becomes
/// `Scrollable`).
String identifierLabel(String identifier) {
  var words = [for (final match in _words.allMatches(identifier)) match[0]!];
  if (words.length > 1 && words.first == 'is') words = words.sublist(1);
  if (words.isEmpty) return identifier;
  return [
    for (var i = 0; i < words.length; i++) _labelWord(words[i], first: i == 0),
  ].join(' ');
}

/// A label for a catalog widget [name], without a `Restage` prefix:
/// `RestageShaderMask` becomes `Shader mask`.
String widgetLabel(String name) {
  final unprefixed = RegExp('^Restage(?=[A-Z])').hasMatch(name)
      ? name.substring('Restage'.length)
      : name;
  return identifierLabel(unprefixed);
}

String _labelWord(String word, {required bool first}) {
  final lower = word.toLowerCase();
  final isAcronym = _acronyms.contains(lower) ||
      (word.length > 1 && word == word.toUpperCase() && word != lower);
  if (isAcronym) return word.toUpperCase();
  return first ? lower[0].toUpperCase() + lower.substring(1) : lower;
}
