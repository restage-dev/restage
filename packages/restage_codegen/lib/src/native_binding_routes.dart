/// One installed native consumer. The payload can select a declared binding,
/// while both its Dart type and contract identity stay fixed in generated code.
typedef NativeBindingRoute = ({String dartType, String contractType});

/// Fixed native value consumers, keyed by resolved defining-library identity.
/// Custom classes with the same name cannot acquire a native consumer.
NativeBindingRoute? nativeBindingRoute(String sourceType) =>
    switch (sourceType) {
      'package:flutter/src/foundation/key.dart#Key' => (
          dartType: 'Key',
          contractType: 'flutter.Key',
        ),
      'package:flutter/src/widgets/scroll_controller.dart#ScrollController' => (
          dartType: 'ScrollController',
          contractType: 'flutter.ScrollController',
        ),
      'package:flutter/src/material/tab_controller.dart#TabController' => (
          dartType: 'TabController',
          contractType: 'flutter.TabController',
        ),
      _ => null,
    };
