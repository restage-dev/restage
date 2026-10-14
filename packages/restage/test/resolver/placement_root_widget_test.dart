import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/placement_mount_resolver.dart';
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;

void main() {
  test('a paywall rooted at main that uses a component mounts main', () {
    final blob = encodeLibraryBlob(parseLibraryFile('''
import restage.core;
widget card = Text(text: "Plan");
widget main = Column(children: [card()]);
'''));
    expect(placementBlobRootWidget(blob), 'main');
  });

  test('a screen rooted at main mounts main', () {
    final blob = encodeLibraryBlob(parseLibraryFile('''
import restage.core;
widget main = Text(text: "Welcome");
widget component_1 = Text(text: "Parked");
'''));
    expect(placementBlobRootWidget(blob), 'main');
  });

  test('a generated screen with an inlined widget mounts its screen root', () {
    final blob = encodeLibraryBlob(parseLibraryFile('''
import restage.core;
widget StatBadge = Text(text: "7");
widget OnboardingScreen = Column(children: [StatBadge()]);
'''));
    expect(placementBlobRootWidget(blob), 'OnboardingScreen');
  });

  test('a library without a root is refused', () {
    final blob = encodeLibraryBlob(parseLibraryFile('''
import restage.core;
widget a = Text(text: "A");
widget b = Text(text: "B");
'''));
    expect(() => placementBlobRootWidget(blob), throwsFormatException);
  });
}
