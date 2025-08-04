package fluesend;

import fluesend.Utils;
import fluesend.Command.StructureCommand;
import fluesend.Command.RpcCommand;
import fluesend.Command.ReturnCommand;
import haxe.io.Bytes;
import fluesend.Scope;
#if js
import js.html.WebSocket;
#else
import sys.net.Socket as SysSocket;
#end

@:access(fluesend.Socket)
class Connection {
    public var serializer = new Serializer();

    var socket = new Socket();
    #if js
    var clients = new Map<WebSocket, Socket>();
    #else
    var clients = new Map<SysSocket, Socket>();
    #end

    var callbacks = new Array<Module>();
    var output = new List<Command>();
    var temp = Bytes.alloc(4096);

    var toRetry:Void->Void = null;

    public var traceInfo = false;
    public var traceVerbose = false;

    #if js

    #else
    public var ip(get, never):String;
    function get_ip() {
        return socket.ip;
    }

    public var port(get, never):Null<Int>;
    function get_port() {
        return socket.port;
    }
    #end

    public var isServer(get, never):Null<Bool>;
    function get_isServer() {
        return socket.isServer;
    }

    public var isRunning(get, never):Bool;
    function get_isRunning() {
        return socket.isServer != null;
    }

    public var netid(get, set):Null<Int>;
    function get_netid() {
        return socket.netid;
    }
    function set_netid(v:Int) {
        return socket.netid = v;
    }

    public function new() {
        serializer.registerType(RpcCommand);
        serializer.registerType(StructureCommand);
        serializer.registerType(ReturnCommand);
        serializer.registerEnum(Scope);
        serializer.useMarkedFields = true;
        setupSocket(socket);
    }

    public function getSocket(netid:Int) {
        if (socket.netid == netid)
            return socket;
        for (_ => client in clients) {
            if (client.netid == netid)
                return client;
        }
        return null;
    }

    public function register(module:Module) {
        callbacks.push(module);
    }

    public function unregister(module:Module) {
        return callbacks.remove(module);
    }

    function setupSocket(socket:Socket) {
        socket.netid = Utils.id();

        socket.onOpen = info -> {
            if (traceInfo) {
                if (isServer == null) {
                    trace('(Idle) Socket open: ' + info);
                } else if (isServer) {
                    trace('(Server) Socket open: ' + info);
                } else {
                    trace('(Client) Socket open: ' + info);
                }
            }
        }

        socket.onInfo = info -> {
            if (traceInfo) {
                if (isServer == null) {
                    trace('(Idle) Socket info: ' + info);
                } else if (isServer) {
                    trace('(Server) Socket info: ' + info);
                } else {
                    trace('(Client) Socket info: ' + info);
                }
            }
        }

        socket.onClose = () -> {
            if (traceInfo) {
                if (isServer == null) {
                    trace('(Idle) Socket closed');
                } else if (isServer) {
                    trace('(Server) Socket closed');
                } else {
                    trace('(Client) Socket closed');
                }
            }
            // Remove client
            @:privateAccess
            var keys = [for (r => s in clients) if (s == socket) r];
            for (key in keys) {
                clients.remove(key);
            }
        }

        socket.onError = error -> {
            if (traceInfo) {
                if (isServer == null) {
                    trace('(Idle) Socket error: ' + error);
                } else if (isServer) {
                    trace('(Server) Socket error: ' + error);
                } else {
                    trace('(Client) Socket error: ' + error);
                }
            }
        }
    }

    public function bind(ip:String, port:Int, connections:Int) {
        if (isRunning)
            throw "Connection is already in use";

        toRetry = () -> bind(ip, port, connections);

        var status = socket.bind(ip, port, connections);
        if (!tryConnect(socket)) {
            socket.close();
            status = false;
        }
        return status;
    }

    public function connect(ip:String, port:Int) {
        if (isRunning)
            throw "Connection is already in use";

        toRetry = () -> connect(ip, port);

        var status = socket.connect(ip, port);
        if (!tryConnect(socket)) {
            socket.close();
            status = false;
        }
        return status;
    }

    public function retry() {
        if (!isRunning && toRetry != null) {
            if (traceVerbose)
                trace("Retrying");
            toRetry();
        }
        return isRunning;
    }

    public function close() {
        socket?.close();
        for (_ => client in clients)
            client.close();
    }

    public function write(command:Command) {
        if (!isRunning) {
            if (traceVerbose)
                trace("Failed to write: Socket is closed!");
            return;
        }
        command.owner = netid;
        output.add(command);
    }

    public function writeTo(netid:Int, command:Command) {
        if (!isRunning) {
            if (traceVerbose)
                trace("Failed to write: Socket is closed!");
            return;
        }
        if (!isServer)
            throw "Only server can write to specific netid";
        command.owner = this.netid;
        command.scope = Target(netid);
        output.add(command);
    }

    function read() {
        if (!isRunning) {
            if (traceVerbose)
                trace("Failed to read: Socket is closed!");
            return;
        }

        if (isServer) {
            // Pass data through in case connection is a server
            #if js
            for (_ => socket in clients) {
                var data = null;
                while (true) {
                    data = socket.read();
                    if (data == null)
                        break;
                    var command = try {
                        serializer.deserialize(data);
                    } catch (e:Dynamic) {
                        trace("Failed to deserialize");
                        continue;
                    }
                    // Map owner to local id
                    command.owner = socket.netid;
                    output.add(tryReceive(socket, command));
                }
            }
            #else
            var read = [for (r in clients.keys()) r];
            if (read.length > 0) {
                try {
                    read = SysSocket.select(read, null, null, 0).read;
                } catch (e:Dynamic) {
                    trace("Failed to select: " + e, [for (r => s in clients) s.isServer]);
                    return;
                }
                for (raw in read) {
                    var socket = clients.get(raw);
                    var data = null;
                    while (true) {
                        data = socket.read();
                        if (data == null)
                            break;
                        var command = try {
                            serializer.deserialize(data);
                        } catch (e:Dynamic) {
                            trace("Failed to deserialize");
                            continue;
                        }
                        command.owner = socket.netid;
                        output.add(tryReceive(socket, command));
                    }
                }
            }
            #end
        } else {
            // Invoke immediately in case connection is a client
            var data = null;
            while (true) {
                data = socket.read();
                if (data == null) {
                    break;
                } else {
                    var command = try {
                        serializer.deserialize(data);
                    } catch (e:Dynamic) {
                        trace("Failed to deserialize");
                        continue;
                    }
                    if (tryValidate(socket, command))
                        execute(tryReceive(socket, command));
                }
            }
        }
    }

    function accept() {
        while (true) {
            var s = socket.accept();
            if (s == null)
                break;
            setupSocket(s);
            if (!tryConnect(s)) {
                s.close();
                continue;
            }
            @:privateAccess
            clients.get(s.raw)?.close();
            @:privateAccess
            clients.set(s.raw, s);
        }
    }

    public function poll() {
        if (!isRunning) {
            if (traceVerbose)
                trace("Failed to poll: Socket is closed!");
            return;
        }

        #if js

        #else
        if (socket.isServer) {
            accept();
        }
        #end
        
        read();
    }

    public function flush() {
        if (!isRunning) {
            if (traceVerbose)
                trace("Failed to flush: Socket is closed!");
            return;
        }
        if (output.isEmpty()) {
            return;
        }

        if (isServer) {
            while (!output.isEmpty()) {
                var item = output.pop();
                // Invoke clients
                for (client in clients) {
                    var command:Command = null;
                    if (item.scope == All) {
                        command = item;
                    } else if (item.scope == Self) {
                        if (item.owner == client.netid)
                            command = item;
                    } else if (item.scope == Others) {
                        if (item.owner != client.netid)
                            command = item;
                    } else if (item.scope == Clients) {
                        command = item;
                    } else if (item.scope.match(Scope.Target(_))) {
                        var target = switch item.scope {
                            case Target(netid): netid;
                            default: null;
                        }
                        if (target != null && target == client.netid) {
                            command = item;
                        }
                    }
                    if (command != null && tryValidate(client, command)) {
                        try {
                            client.push(serializer.serialize(trySend(client, command)));
                        } catch (e:Dynamic) {
                            trace("Failed to send", e);
                        }
                    }
                }
                
                if (item.isBlocking) {
                    for (client in clients) {
                        try {
                            client.send();
                        } catch (e:Dynamic) {
                            trace("Failed to send", e);
                        }
                    }
                }

                // Invoke self (server)
                // We call server at the end, because in case it's closing
                // server needs to send all data before
                var command:Command = null;
                if (item.scope == All) {
                    command = item;
                } else if (item.scope == Self) {
                    if (item.owner == socket.netid)
                        command = item;
                } else if (item.scope == Others) {
                    if (item.owner != socket.netid)
                        command = item;
                } else if (item.scope == Server) {
                    command = item;
                } else if (item.scope.match(Scope.Target(_))) {
                    var target = switch item.scope {
                        case Target(netid): netid;
                        default: null;
                    }
                    if (target != null && target == socket.netid) {
                        command = item;
                    }
                }
                if (command != null && tryValidate(socket, command)) {
                    try {
                        execute(trySend(socket, command));
                    } catch (e:Dynamic) {
                        trace("Failed to send", e);
                    }
                }
            }

            for (client in clients) {
                try {
                    client.send();
                } catch (e:Dynamic) {
                    trace("Failed to send", e);
                }
            }

        } else {
            try {
                for (item in output) {
                    socket.push(serializer.serialize(trySend(socket, item)));
                }
                socket.send();
            } catch (e:Dynamic) {
                trace("Failed to send", e);
            }
        }
        output.clear();
    }

    // -------------------------- Delegates --------------------------

    function tryConnect(socket:Socket) {
        for (module in callbacks) {
            if (!module.onConnect(socket))
                return false;
        }
        return true;
    }

    function onDisconnect() {
        for (module in callbacks) {
            module.onDisconnect(socket);
        }
    }

    function tryValidate(socket:Socket, command:Command) {
        for (module in callbacks) {
            if (!module.onValidate(socket, command))
                return false;
        }
        return true;
    }

    function trySend(socket:Socket, command:Command) {
        for (module in callbacks) {
            command = module.onSend(socket, command);
        }
        return command;
    }

    function tryReceive(socket:Socket, command:Command) {
        for (module in callbacks) {
            command = module.onReceive(socket, command);
        }
        return command;
    }

    function execute(command:Command) {
        for (module in callbacks) {
            @:privateAccess
            module.command = command;
            if (command is Command.RpcCommand) {
                var command:RpcCommand = cast command;
                module.invoke(command.method, command.args, command.owner, command.promise);
            } else if (command is Command.StructureCommand) {
                var command:StructureCommand = cast command;
                module.onUnpack(command.structure);
            } else if (command is Command.ReturnCommand) {
                var command:ReturnCommand = cast command;
                module.onReturn(command.promise, command);
            }
        }
        return true;
    }
}