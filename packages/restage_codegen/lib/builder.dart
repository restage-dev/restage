import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:restage_codegen/src/factory_function_builder.dart';
import 'package:restage_codegen/src/library_visitor.dart';
import 'package:restage_codegen/src/onboarding/flow_builder.dart';
import 'package:restage_codegen/src/onboarding/screen_builder.dart';
import 'package:restage_codegen/src/paywall_flow_builder.dart';
import 'package:restage_codegen/src/restage_source_roster_builder.dart';
import 'package:restage_codegen/src/surface_publication/dynamic_output_owner.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:restage_codegen/src/visitors/paywall_source_visitor.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_builder.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

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

/// build_runner factory entry point for message screen codegen. Same machinery
/// as the onboarding screen builder, scoped to the `lib/message/screens/`
/// source root by the surface parameter.
Builder messageScreenBuilder(BuilderOptions options) =>
    OnboardingScreenBuilder(options, surface: Surface.message);

/// build_runner factory entry point for message flow codegen. Same machinery as
/// the onboarding flow builder, scoped to `lib/message/flows/` by the surface.
Builder messageFlowBuilder(BuilderOptions options) =>
    OnboardingFlowBuilder(options, surface: Surface.message);

/// build_runner factory entry point for survey screen codegen. Same machinery
/// as the onboarding screen builder, scoped to `lib/survey/screens/` by the
/// surface parameter.
Builder surveyScreenBuilder(BuilderOptions options) =>
    OnboardingScreenBuilder(options, surface: Surface.survey);

/// build_runner factory entry point for survey flow codegen. Same machinery as
/// the onboarding flow builder, scoped to `lib/survey/flows/` by the surface.
Builder surveyFlowBuilder(BuilderOptions options) =>
    OnboardingFlowBuilder(options, surface: Surface.survey);

/// build_runner factory entry point for paywall navigation flow codegen.
Builder paywallFlowBuilder(BuilderOptions options) =>
    PaywallFlowBuilder(options);

/// build_runner factory entry point for the package-wide Restage source and
/// output ownership roster.  The builder is intentionally separate from all
/// artifact emitters: it discovers legacy source declarations through the
/// tracked package graph and writes the deterministic package index/roster
/// before later compiler lanes consume the ownership contract.
Builder restageSourceRosterBuilder(BuilderOptions options) =>
    RestageSourceRosterBuilder(options);

/// build_runner factory entry point for canonical package compilation.
Builder restagePackageSurfaceCompilerBuilder(BuilderOptions options) =>
    PackageSurfaceCompilerBuilder(options);

/// build_runner factory entry point for the fixed surface-publication bundle.
Builder restageSurfacePublicationBundleBuilder(BuilderOptions options) =>
    RestageSurfacePublicationBundleBuilder(options);

/// build_runner factory entry point for dynamic surface-publication outputs.
PostProcessBuilder restageSurfacePublicationOutputOwner(
  BuilderOptions options,
) =>
    RestageSurfacePublicationOutputOwner(options);

/// build_runner factory entry point for the package-wide customer-catalog
/// emitter. Walks every `lib/**.dart` for `@RestageWidget`-annotated
/// classes and emits a single `lib/user_catalog.g.dart` aggregating them.
Builder userCatalogBuilder(BuilderOptions options) =>
    UserCatalogBuilder(options);

/// build_runner factory entry point for the package-wide customer-catalog
/// JSON emitter. Walks every `lib/**.dart` for `@RestageWidget`-annotated
/// classes and emits `lib/src/widget_catalog/catalog.json` from the same
/// allocation as `lib/user_catalog.g.dart`, so a paywall referencing a
/// registered custom widget resolves it against the catalog.
Builder userCatalogJsonBuilder(BuilderOptions options) =>
    UserCatalogJsonBuilder(options);

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

/// build_runner factory entry point for the package-wide A2UI catalog emitter.
/// Walks every `lib/**.dart` for `@RestageWidget`-annotated classes, assembles
/// the analyzer-fed A2UI seams off the resolved elements, and emits a single
/// `lib/generated/restage_a2ui_catalog.g.dart` declaring
/// `buildRestageCatalogItems()` (the genui `Catalog` source) plus the colocated
/// `restage_a2ui_catalog.a2ui.json` capability stamp. Opt-in (not applied to
/// dependents) — the emitted code imports the genui runtime, so a consumer
/// enables it only when they want an A2UI catalog.
Builder userA2uiCatalogBuilder(BuilderOptions options) =>
    UserA2uiCatalogBuilder(options);

/// Opt-in Widgetbook v4 stories derived from `@RestageWidget` metadata.
Builder widgetbookStoryBuilder(BuilderOptions options) =>
    createWidgetbookStoryBuilder(options);
