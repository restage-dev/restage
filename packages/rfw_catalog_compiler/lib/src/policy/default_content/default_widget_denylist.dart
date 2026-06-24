// packages/rfw_catalog_compiler/lib/src/policy/default_content/default_widget_denylist.dart

/// Fully-qualified Flutter widget identifiers excluded from the
/// catalog at the widget level (independent of their property types).
/// Curated across navigation surfaces, modal overlays, imperative
/// context builders, drag-and-drop targets, and custom-painting
/// primitives whose semantics cannot be represented declaratively.
const Set<String> kBuiltInWidgetDenylist = {
  // Routing / navigation.
  'package:flutter/src/widgets/navigator.dart#Navigator',
  'package:flutter/src/widgets/router.dart#Router',
  'package:flutter/src/widgets/page_view.dart#PageView',
  'package:flutter/src/widgets/heroes.dart#Hero',

  // Material navigation surfaces.
  'package:flutter/src/material/drawer.dart#Drawer',
  'package:flutter/src/material/navigation_rail.dart#NavigationRail',
  'package:flutter/src/material/navigation_drawer.dart#NavigationDrawer',

  // Dialogs / sheets / snackbars.
  'package:flutter/src/material/dialog.dart#AlertDialog',
  'package:flutter/src/material/dialog.dart#Dialog',
  'package:flutter/src/material/dialog.dart#SimpleDialog',
  'package:flutter/src/material/bottom_sheet.dart#BottomSheet',
  'package:flutter/src/material/snack_bar.dart#SnackBar',

  // Material dropdowns / popup menus / search.
  'package:flutter/src/material/dropdown.dart#DropdownButton',
  'package:flutter/src/material/dropdown_menu.dart#DropdownMenu',
  'package:flutter/src/material/popup_menu.dart#PopupMenuButton',
  'package:flutter/src/material/search_anchor.dart#SearchAnchor',
  'package:flutter/src/material/search_anchor.dart#SearchBar',

  // Forms.
  'package:flutter/src/widgets/form.dart#Form',
  'package:flutter/src/widgets/form.dart#FormField',
  'package:flutter/src/material/text_form_field.dart#TextFormField',

  // Imperative-context builders.
  'package:flutter/src/widgets/layout_builder.dart#LayoutBuilder',
  'package:flutter/src/widgets/basic.dart#Builder',
  'package:flutter/src/widgets/theme.dart#Theme',
  'package:flutter/src/widgets/media_query.dart#MediaQuery',
  'package:flutter/src/widgets/orientation_builder.dart#OrientationBuilder',
  'package:flutter/src/widgets/value_listenable_builder.dart#ValueListenableBuilder',
  'package:flutter/src/widgets/animated_builder.dart#AnimatedBuilder',
  'package:flutter/src/widgets/binding.dart#RootWidget',

  // Cupertino navigation surfaces.
  'package:flutter/src/cupertino/page_scaffold.dart#CupertinoTabScaffold',
  'package:flutter/src/cupertino/route.dart#CupertinoPageRoute',
  'package:flutter/src/cupertino/dialog.dart#CupertinoAlertDialog',
  'package:flutter/src/cupertino/dialog.dart#CupertinoActionSheet',
  'package:flutter/src/cupertino/context_menu.dart#CupertinoContextMenu',

  // Drag-and-drop.
  'package:flutter/src/widgets/drag_target.dart#DragTarget',
  'package:flutter/src/widgets/drag_target.dart#Draggable',
  'package:flutter/src/widgets/drag_target.dart#LongPressDraggable',

  // Custom painting / repaint boundaries.
  'package:flutter/src/widgets/basic.dart#CustomPaint',
  'package:flutter/src/widgets/basic.dart#RepaintBoundary',
};
