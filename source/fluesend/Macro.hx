package fluesend;

import haxe.macro.Expr;
import haxe.macro.Compiler;
import haxe.macro.Expr.ExprDef;
import haxe.macro.Expr.FieldType;
import haxe.macro.Context;
import haxe.macro.Expr.Field;

using Lambda;
using haxe.macro.ExprTools;

class Macro {
    macro public static function serializable():Array<Field> {
        var fields:Array<Field> = Context.getBuildFields();
        var result = new Array<Field>();
        var isRoot = Context.getLocalClass().get().superClass == null;

        Compiler.registerCustomMetadata({
            metadata: ":rpc",
            doc: "Remote protocol call",
            params: [
                "scope:Scope = All",
                "isBlocking:Bool = false"
            ]
        });

        Compiler.registerCustomMetadata({
            metadata: "s",
            doc: "Serializable field"
        });

        var conditions = new Array<Expr>();
        
        for (field in fields) {
            var meta = field.meta.find(m -> m.name == ":rpc");
            
            if (meta == null) {
                result.push(field);
                continue;
            }
            var fun = switch field.kind {
                case FFun(f): f;
                default: {
                    result.push(field);
                    continue;
                }
            }

            // Read metadata params
            var params = meta.params.iterator();
            var scope = params.hasNext() ? params.next() : macro fluesend.Scope.All;
            var isBlocking = params.hasNext() ? params.next() : macro false;

            var hasReturn = false;
            var bodyWithReturn = fun.expr.map(e -> switch e.expr {
                case EReturn(e):
                    hasReturn = true;
                    macro {
                        // Replace returns with ReturnCommand
                        if (connection != null && promise != null) {
                            var command = new fluesend.Command.ReturnCommand();
                            command.scope = Target(owner);          // from invoke() args
                            command.value = $e{e};                  // expression from return statement
                            command.promise = promise;              // from invoke() args. id of promise in the caller module
                            command.isBlocking = $e{isBlocking};    // from metadata params
                            connection.write(command);
                        }
                    }
                default: e;
            });

            // Inline rpc function into invoke function
            // args becomes variables and body becomes expression
            conditions.push(macro {
                if (method == $v{field.name}) {
                    $e{{
                        // Unpack args to variables
                        expr: EVars([for (i => a in fun.args) {
                            name: a.name,
                            type: a.type,
                            expr: macro args[$v{i}]
                        }]),
                        pos: Context.currentPos()
                    }}

                    $e{bodyWithReturn}

                    // trace("invoke", method);
                }
            });

            // Convert args names to array of identifiers to pass them as invoke args
            var args = [for (a in fun.args) macro $i{a.name}];

            fun.ret = macro: fluesend.Promise;

            // Convert function body to rpc call command
            fun.expr = macro {
                if (connection == null)
                    return null;
                var command = new fluesend.Command.RpcCommand();
                command.scope = $e{scope};              // from metadata params
                command.method = $v{field.name};        // name of function itself
                command.args = $a{args};                // array of function args
                command.isBlocking = $e{isBlocking};    // from metadata params
                connection.write(command);
                return $e{!hasReturn ? macro null : macro {
                    command.promise = fluesend.Utils.id();
                    var promise = {};
                    promises.set(command.promise, promise);
                    promise;
                }};
            }

            result.push(field);
        }

        result.push({
            name: "invoke",
            access: isRoot ? [APublic] : [APublic, AOverride],
            kind: FFun({
                args: [{
                    name: "method",
                    type: macro: String
                }, {
                    name: "args",
                    type: macro: Array<Dynamic>
                }, {
                    name: "owner",
                    type: macro: Int
                }, {
                    name: "promise",        // to return value
                    type: macro: Null<Int>
                }],
                ret: macro: Dynamic,
                expr: macro {
                    $b{conditions}
                    return null;
                }
            }),
            pos: Context.currentPos()
        });

        return result;
    }
}