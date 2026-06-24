import 'package:build/build.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:restage_codegen/src/factory_function_builder.dart';
import 'package:restage_codegen/src/library_visitor.dart';
import 'package:restage_codegen/src/onboarding/flow_builder.dart';
import 'package:restage_codegen/src/onboarding/screen_builder.dart';
import 'package:restage_codegen/src/paywall_flow_builder.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:restage_codegen/src/visitors/paywall_source_visitor.dart';

/// build_runner factory entry point for the per-paywall codegen builder.
///
/// Returns a [RestageCodegenBuilder] with the default visitor list.
/// Additional visitors append here.
Builder restageCodegenBuilder(BuilderOptions options) => RestageCodegenBuilder(
      options,
      visitors: const <LibraryVisitor>[
        PaywallSourceVisitor(),
      ],
    );

/// build_runner factory entry point for onboarding screen codegen.
Builder onboardingScreenBuilder(BuilderOptions options) =>
    OnboardingScreenBuilder(options);

/// build_runner factory entry point for onboarding flow codegen.
Builder onboardingFlowBuilder(BuilderOptions options) =>
    OnboardingFlowBuilder(options);

/// build_runner factory entry point for paywall navigation flow codegen.
Builder paywallFlowBuilder(BuilderOptions options) =>
    PaywallFlowBuilder(options);

/// build_runner factory entry point for the package-wide customer-catalog
/// emitter. Walks every `lib/**.dart` for `@RestageWidget`-annotated
/// classes and emits a single `lib/user_catalog.g.dart` aggregating them.
Builder userCatalogBuilder(BuilderOptions options) =>
    UserCatalogBuilder(options);

/// build_runner factory entry point for the per-package factory function
/// emitter. Reads each curated library's `lib/src/widget_catalog/catalog.json`
/// and writes `lib/src/registration.g.dart` declaring a const
/// `Map<String, LocalWidgetBuilder>` consumed by the SDK runtime.
Builder factoryFunctionBuilder(BuilderOptions options) =>
    FactoryFunctionBuilder(options);

/// build_runner factory entry point for the package-wide customer-factory
/// emitter. Walks every `lib/**.dart` for `@RestageWidget`-annotated
/// classes, generates per-widget `LocalWidgetBuilder` closures, and emits
/// a single `lib/user_factories.g.dart` exposing a
/// `registerRestageCustomerWidgets()` helper the customer calls once at
/// startup.
Builder userFactoryBuilder(BuilderOptions options) =>
    UserFactoryBuilder(options);
