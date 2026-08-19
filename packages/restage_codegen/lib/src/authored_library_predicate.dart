import 'package:build/build.dart';

/// Whether [asset] is an authored Dart library candidate for Restage source
/// discovery.
///
/// The resolver remains responsible for rejecting Dart `part` files. This
/// predicate deliberately does not attach product meaning to directory names:
/// an authored canonical source may live anywhere beneath `lib/`, including a
/// directory literally named `generated`.
bool isAuthoredDartLibraryAsset(AssetId asset) =>
    asset.path.startsWith('lib/') &&
    asset.path.endsWith('.dart') &&
    !asset.path.endsWith('.g.dart') &&
    !asset.path.endsWith('.stories.dart');
