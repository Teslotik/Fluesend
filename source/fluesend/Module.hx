package fluesend;

import fluesend.Command.StructureCommand;
import fluesend.Command.ReturnCommand;
import fluesend.Scope;
import fluesend.Promise;
import fluesend.Socket;

class Module implements Serializable {
    // Current data for invoke
    var connection:Connection = null;
    var command:Command = null;
    // var socket:Socket = null;

    var promises = new Map<Int, Promise>();

    public function new(connection:Connection) {
        this.connection = connection;
        connection.register(this);
    }

    public function onConnect(socket:Socket) {
        return true;
    }

    public function onDisconnect(socket:Socket) {

    }

    public function onValidate(socket:Socket, command:Command) {
        return true;
    }

    public function onSend(socket:Socket, command:Command) {
        return command;
    }

    public function onReceive(socket:Socket, command:Command) {
        return command;
    }

    public function onReturn(promise:Int, command:ReturnCommand):Dynamic {
        var p = promises.get(promise);
        if (p == null) {
            trace("Promise not found");
            return null;
        }
        if (p.callback == null || !p.callback(command.value)) {
            promises.remove(promise);
        }
        return command.value;
    }

    public function onUnpack(structure:Dynamic) {
        
    }

    final public function pack(scope:Scope, structure:Dynamic) {
        var command = new StructureCommand();
        command.scope = scope;
        command.structure = structure;
        connection.write(command);
    }
}