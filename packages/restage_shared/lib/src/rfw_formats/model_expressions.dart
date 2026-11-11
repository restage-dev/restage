// Copyright 2026 Restage Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This file is hand-formatted.

part of 'model.dart';

/// The format version that introduced [Program], [Effects], [Guard] and
/// [NativeReference].
///
/// A runtime that predates a node cannot decode it, so a blob containing one
/// fails to decode rather than rendering incorrectly.
const int expressionNodesFormatVersion = 1;

/// Reserved initial-state key: maps state fields to the arguments that
/// initialise them once, when the widget's state is created.
const String restageInitStateKey = '_restageInit';

/// A typed expression whose value is computed where the argument resolves.
///
/// [program] is inert data describing the expression: its typed operation
/// nodes, root, parameters and locals. Only an evaluator the host installs
/// interprets it. [captures] maps each captured name to an argument node,
/// such as a [DataReference] or [StateReference], whose value the program
/// reads.
class Program extends BlobNode {
  /// Wraps the given [program] data and [captures] in a [Program] object.
  ///
  /// Neither map may be mutated after the object is created.
  const Program(this.program, this.captures);

  /// The format version that introduced this node.
  static const int formatVersion = expressionNodesFormatVersion;

  /// The expression's inert description.
  final DynamicMap program;

  /// The argument node supplying each captured value, by capture name.
  final DynamicMap captures;

  @override
  String toString() => 'program $program captures $captures';
}

/// An ordered sequence of steps run when an event fires.
///
/// Each step is a [SetStateHandler], an [EventHandler] or a [Guard]. Steps run
/// in order, and each one sees state as the previous step left it.
class Effects extends AnyEventHandler {
  /// Wraps the given [steps] in an [Effects] object.
  ///
  /// The [steps] must not be mutated after the object is created.
  const Effects(this.steps);

  /// The format version that introduced this node.
  static const int formatVersion = expressionNodesFormatVersion;

  /// The steps, in the order they run.
  final DynamicList steps;

  @override
  String toString() => 'effects $steps';
}

/// Steps that run only when [condition] evaluates to true.
class Guard extends AnyEventHandler {
  /// Wraps the given [condition] and [steps] in a [Guard] object.
  ///
  /// The [steps] must not be mutated after the object is created.
  const Guard(this.condition, this.steps);

  /// The format version that introduced this node.
  static const int formatVersion = expressionNodesFormatVersion;

  /// A [Program] that evaluates to a boolean.
  final Object condition;

  /// The steps that run when [condition] is true, in order.
  final DynamicList steps;

  @override
  String toString() => 'when $condition $steps';
}

/// A reference to an object the host supplies for the mounted widget.
///
/// The object itself never travels in the blob. [key] names it, and [type] and
/// [nullable] state what the blob expects to receive. It is read by
/// `nativeValue`, as a program capture, or in an effect step; elsewhere it is
/// not resolved.
class NativeReference extends BlobNode {
  /// Wraps the given [key], [type] and [nullable] in a [NativeReference] object.
  const NativeReference(this.key, this.type, {required this.nullable});

  /// The format version that introduced this node.
  static const int formatVersion = expressionNodesFormatVersion;

  /// The key under which the host supplies the object.
  final String key;

  /// The name of the object's type, such as `flutter.Color`.
  final String type;

  /// Whether the host may supply null.
  final bool nullable;

  @override
  String toString() => 'native { key: "$key", type: "$type", nullable: $nullable }';
}
