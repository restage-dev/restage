import 'package:analyzer/dart/ast/ast.dart';

/// Whether calling a function with [body] runs it. A generator body runs only
/// when its result is iterated, which a void callback slot never does.
bool runsWhenCalled(FunctionBody body) => !body.isGenerator;

/// [handler] as a closure whose body runs when it is called, or null.
///
/// Every recogniser that re-expresses a handler body as design actions reads
/// this first. A split that copies the closure's source keeps it as written.
FunctionExpression? runnableClosure(Expression handler) =>
    handler is FunctionExpression && runsWhenCalled(handler.body)
    ? handler
    : null;

/// The generator keyword of [body], such as `sync*`, or null.
String? generatorKeyword(FunctionBody body) => body.isGenerator
    ? '${body.keyword?.lexeme ?? ''}${body.star?.lexeme ?? ''}'
    : null;
