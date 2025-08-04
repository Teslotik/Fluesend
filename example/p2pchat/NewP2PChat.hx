package;

import fluesend.Utils;
import fluesend.Scope;
import fluesend.Command;
import fluesend.Socket;
import fluesend.Connection;
import fluesend.Command.RpcCommand;
import fluesend.Module;

using Lambda;

typedef Peer = {
    name:String,
    ip:String,
    port:Null<Int>,
    id:Null<Int>
}

/**
 * @note ChatModule is a dirty sketch of possible p2p implementation
 * it is not ready yet!
 */
class ChatModule extends Module {
    public var self:Peer = null;
    public var peers = new Map<Int, Peer>();
    public var joined = new Array<{netid:Int, id:Int}>();

    public var isJoined = false;

    public function new(connection:Connection, name:String) {
        super(connection);

        connection.traceInfo = false;
        // connection.traceInfo = true;
        self = {
            name: name,
            ip: null,
            port: null,
            id: null
        }
    }

    override function onValidate(socket:Socket, command:Command):Bool {
        if (connection.isServer) {
            if (command is RpcCommand) {
                var command:RpcCommand = cast command;
                
                if (command.method == "register") {
                    var isInChat = joined.exists(info -> info.netid == command.owner);
                    if (isInChat) {
                        trace('ERROR: Peer ${command.owner} is already in chat', command.args);
                        return false;
                    }
                }

                if (command.method == "login") {
                    var id = command.args[0];
                    var isRegistered = peers.exists(id);
                    if (!isRegistered) {
                        trace('ERROR: Peer ${command.owner} is not registered, register before login', command.args);
                        return false;
                    }
                }

                /// @note This checks fires multiple times - it is a correct behaviour
                // because multiple clients are connected, so it checks for each one
                if (command.method == "sendMessage") {
                    var id = command.args[0];
                    if (!joined.exists(info -> info.id == id)) {
                        trace('ERROR: Sender ${id} is not in chat!');
                        return false;
                    }

                    if (!joined.exists(info -> info.netid == socket.netid)) {
                        trace('ERROR: Receiver ${socket.netid} is not in chat!');
                        return false;
                    }
                }
            }
        }
        return true;
    }

    override function onConnect(socket:Socket):Bool {
        self.ip = connection.ip;
        self.port = connection.port;
        if (isJoined) {
            login(self.id, self.ip, self.port);
        }
        return true;
    }

    @:rpc(Scope.Server, true)
    public function register(ip:String, port:Int, name:String, password:String) {
        trace('${name} registered in chat');
        var id = Utils.hashString(password);
        peers.set(id, {
            name: name,
            ip: ip,
            port: port,
            id: id
        });
        return id;
    }

    @:rpc(Scope.Server)
    public function login(id:Int, ip:String, port:Int) {
        trace('${peers.get(id).name} logined into chat ${command.owner}');
        joined.push({
            netid: command.owner,
            id: id
        });
        var peer = peers.get(id);
        peer.ip = ip;
        peer.port = port;
        return id;
    }

    @:rpc(Scope.Others)
    public function sendMessage(id:Int, message:String) {
        trace('::::: ${self.name} received a message: ${message} :::::');
    }

    /// @todo validation
    @:rpc(Scope.All, true)
    function doMigrate(next:Peer, peers:Map<Int, Peer>) {
        if (connection.isServer) {
            delay(3, () -> {
                trace('----- Legacy server ${self.name} started to reconnect -----');
                connection.close();
                connection.connect(next.ip, next.port);
            });
        } else if (next.id == self.id) {
            trace('----- New server ${self.name} started to bind -----');
            connection.close();
            // Migrating data
            this.peers = peers;
            connection.bind(next.ip, next.port, 10);
        } else {
            trace('----- Client ${self.name} started to reconnect -----');
            connection.close();
            // Reconnecting clients
            connection.connect(next.ip, next.port);
        }
    }

    public function migrate() {
        for (id => candidate in peers) {
            if (id == self.id)
                continue;
            trace('===== Server ${candidate.name} started migration =====');
            doMigrate(candidate, peers);
            joined.resize(0);
            return;
        }
        trace("Failed to migrate, no peers");
    }


    // A very bad solution
    function delay(time:Int, f:Void->Void) {
        skip = time;
        delayed = f;
    }

    var delayed:Void->Void = null;
    var skip = 0;
    public function pollRetry() {
        if (skip == 1 && delayed != null) {
            delayed();
            delayed = null;
        }
        skip--;
    }
}

class NewP2PChat {
    var ivan:Connection = null;
    var ivanChat:ChatModule = null;
    //
    var boris:Connection = null;
    var borisChat:ChatModule = null;
    //
    var dimitri:Connection = null;
    var dimitriChat:ChatModule = null;

    var time = -10;   // emulate different computers

    function chat() {
        ivan.retry();
        boris.retry();
        dimitri.retry();

        // Accept and read data
        ivan.poll();
        boris.poll();
        dimitri.poll();

        if (time == -5) {
            ivanChat.register(ivanChat.self.ip, ivanChat.self.port, ivanChat.self.name, "qwerty").callback = v -> {
                ivanChat.self.id = v;
                ivanChat.isJoined = true;
                return false;
            };
            // borisChat.register(borisChat.self.ip, borisChat.self.port, borisChat.self.name, "123").callback = v -> {
            //     borisChat.self.id = v;
            //     borisChat.isJoined = true;
            //     return false;
            // };
            dimitriChat.register(dimitriChat.self.ip, dimitriChat.self.port, dimitriChat.self.name, "07.11.1917").callback = v -> {
                dimitriChat.self.id = v;
                dimitriChat.isJoined = true;
                return false;
            };
        }

        if (time == -1) {
            ivanChat.login(ivanChat.self.id, ivanChat.self.ip, ivanChat.self.port);
            borisChat.login(borisChat.self.id, borisChat.self.ip, borisChat.self.port);
            dimitriChat.login(dimitriChat.self.id, dimitriChat.self.ip, dimitriChat.self.port);
        }

        // Write to buffer and send data
        if (time == 0) {
            ivanChat.sendMessage(ivanChat.self.id, "Hello");
            ivan.flush();
            // trace(ivanChat.self.id);
        } else if (time == 1) {
            borisChat.sendMessage(borisChat.self.id, "You are welcome!");
            boris.flush();
            // trace(borisChat.self.id);
        } else if (time == 2) {
            dimitriChat.sendMessage(dimitriChat.self.id, "How is your day?");
            dimitri.flush();
            // trace(dimitriChat.self.id);
        } else if (time == 4) {
            time = 0;
        }

        ivan.flush();
        boris.flush();
        dimitri.flush();

        ivanChat.pollRetry();
        borisChat.pollRetry();
        dimitriChat.pollRetry();

        Sys.sleep(0.4);
        time++;
    }

    public function new() {
        // Create connections and chat modules
        ivan = new Connection();
        ivanChat = new ChatModule(ivan, "Ivan");
        //
        boris = new Connection();
        borisChat = new ChatModule(boris, "Boris");
        //
        dimitri = new Connection();
        dimitriChat = new ChatModule(dimitri, "Dimitri");

        // dimitri.traceInfo = true;

        ivan.bind("127.0.0.1", 7000, 10);
        boris.connect("127.0.0.1", 7000);
        dimitri.connect("127.0.0.1", 7000);

        // Accept connections
        ivan.flush();

        for (i in 0...40) {
            chat();
            if (i == 15) {
                ivanChat.migrate();
            }
        }
    }

    static function main() {
        new NewP2PChat();
    }
}