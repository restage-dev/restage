import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/duplicate_implicit.restage.g.dart';

// The file name can derive only one ID. Both declarations intentionally omit
// id so the package roster rejects the library before partial output.
@Screen(surface: Surface.general)
final class FirstImplicitScreen extends StatelessWidget {
  const FirstImplicitScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('First');
}

@Screen(surface: Surface.general)
final class SecondImplicitScreen extends StatelessWidget {
  const SecondImplicitScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Second');
}
