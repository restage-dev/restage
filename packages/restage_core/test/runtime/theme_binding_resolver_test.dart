import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/src/runtime/theme_binding_resolver.dart';

void main() {
  // colorScheme family
  testWidgets('resolves colorScheme.primary against the active theme',
      (tester) async {
    const seed = Color(0xFF112233);
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light(primary: seed)),
        home: Builder(
          builder: (context) {
            resolved =
                resolveThemeBinding(context, path: 'colorScheme.primary');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved, seed);
  });

  testWidgets('resolves colorScheme.onPrimary against the active theme',
      (tester) async {
    const seed = Color(0xFF334455);
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light(onPrimary: seed)),
        home: Builder(
          builder: (context) {
            resolved =
                resolveThemeBinding(context, path: 'colorScheme.onPrimary');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved, seed);
  });

  testWidgets('resolves colorScheme.surface against the active theme',
      (tester) async {
    const seed = Color(0xFF667788);
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light(surface: seed)),
        home: Builder(
          builder: (context) {
            resolved =
                resolveThemeBinding(context, path: 'colorScheme.surface');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved, seed);
  });

  // iconTheme family
  testWidgets('resolves iconTheme.color against the active theme',
      (tester) async {
    const seed = Color(0xFF99AABB);
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(iconTheme: const IconThemeData(color: seed)),
        home: Builder(
          builder: (context) {
            resolved = resolveThemeBinding(context, path: 'iconTheme.color');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved, seed);
  });

  testWidgets('resolves iconTheme.size against the active theme',
      (tester) async {
    const seed = 42.0;
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(iconTheme: const IconThemeData(size: seed)),
        home: Builder(
          builder: (context) {
            resolved = resolveThemeBinding(context, path: 'iconTheme.size');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved, seed);
  });

  // defaultTextStyle family
  testWidgets('resolves defaultTextStyle.color against the active text style',
      (tester) async {
    const seed = Color(0xFFCCDDEE);
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTextStyle(
          style: const TextStyle(color: seed),
          child: Builder(
            builder: (context) {
              resolved =
                  resolveThemeBinding(context, path: 'defaultTextStyle.color');
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(resolved, seed);
  });

  testWidgets(
      'resolves defaultTextStyle.fontSize against the active text style',
      (tester) async {
    const seed = 16.0;
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTextStyle(
          style: const TextStyle(fontSize: seed),
          child: Builder(
            builder: (context) {
              resolved = resolveThemeBinding(context,
                  path: 'defaultTextStyle.fontSize');
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(resolved, seed);
  });

  testWidgets(
      'resolves defaultTextStyle.fontWeight against the active text style',
      (tester) async {
    const seed = FontWeight.w700;
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTextStyle(
          style: const TextStyle(fontWeight: seed),
          child: Builder(
            builder: (context) {
              resolved = resolveThemeBinding(context,
                  path: 'defaultTextStyle.fontWeight');
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(resolved, seed);
  });

  // Unknown path
  testWidgets('returns null for an unknown path', (tester) async {
    Object? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = resolveThemeBinding(context, path: 'nope.nope');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved, isNull);
  });
}
