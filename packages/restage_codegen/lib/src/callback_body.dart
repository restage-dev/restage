import 'package:analyzer/dart/ast/ast.dart';

/// Whether calling a function with [body] runs it. A generator body runs only
/// when its result is iterated, which a void callback slot never does.
bool runsWhenCalled(FunctionBody body) => !body.isGenerator;
