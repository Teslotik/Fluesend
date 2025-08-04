package fluesend;

import haxe.io.Error;
import haxe.io.Eof;
import haxe.io.BytesBuffer;
import haxe.io.Bytes;
import haxe.io.BytesData;
import fluesend.Request;
import fluesend.Response;
#if js
import js.html.WebSocket;
import js.lib.ArrayBuffer;
import js.html.Blob;
#else
import sys.net.Host;
import sys.net.Socket as SysSocket;
import sys.net.UdpSocket as SysUdpSocket;
#end

using Lambda;

class Socket {
    public var magic(default, null):Int = Bytes.ofString("flue").getInt32(0);
    public var netid:Null<Int> = null;
    public var maxMessageSize:Null<Int> = null;

    #if js
    var raw:WebSocket = null;
    #else
    var raw:SysSocket = null;
    #end

    #if js
    /// @todo actually we can get this info from handshake request (?)
    #else
    public var ip:String = null;
    public var port:Null<Int> = null;
    public var remoteIp:String = null;
    public var remotePort:Null<Int> = null;
    #end

    public var onOpen:String->Void = null;
    public var onInfo:String->Void = null;
    public var onClose:Void->Void = null;
    public var onError:String->Void = null;

    var isTcp = true;
    var isBinary = true;  /// @todo user must set this flag // currently unused
    public var isServer(default, null):Null<Bool> = null;
    public var isWebSocket(default, null):Null<Bool> = null;
    public var keepAlive = true;

    // Messages queue
    var input = new Array<Bytes>();
    var inputBuffer = Bytes.alloc(6144);
    //
    var output = new Array<Bytes>();
    var outputBuffer = Bytes.alloc(6144);

    // Offset in output buffer
    var pos = 0;

    public function new() {
        
    }

    public function bind(ip:String, port:Int, connections = 10) {
        close();

        if (onInfo != null)
            onInfo('Binding to: ${ip}:${port}');

        #if js
        error("bind() is not implemented for this target");
        return false;

        #else
        var socket = if (isTcp) {
            new SysSocket();
        } else {
            new SysUdpSocket();
        }
        try {
            socket.bind(new Host(ip), port);
            socket.listen(connections);
            socket.setBlocking(false);
            raw = socket;
            isServer = true;
            isWebSocket = false;
            this.ip = ip;
            this.port = port;
            if (onOpen != null)
                onOpen("Started");
        } catch (e:Dynamic) {
            error("Failed to bind");
            close();
            return false;
        }
        #end

        return true;
    }

    public function connect(ip:String, port:Int) {
        close();

        if (onInfo != null)
            onInfo('Connecting to: ${ip}:${port}');

        #if js
        try {
            raw = new WebSocket('ws://${ip}:${port}');
            raw.binaryType = ARRAYBUFFER;
            isWebSocket = true;
        } catch (e:Dynamic) {
            error("Failed to connect: " + e);
            close();
            return false;
        }
        raw.onopen = e -> {
            if (onOpen != null)
                onOpen("Connected");
        }
        raw.onclose = event -> close();
        raw.onerror = error -> this.error("Unknown: " + error.type);
        raw.onmessage = event -> {
            if (event.data is String) {
                error("String is not supported");
                // unpack(Bytes.ofString(cast event.data));
            } else if (event.data is ArrayBuffer) {
                if (maxMessageSize != null && cast(event.data, BytesData).byteLength > maxMessageSize) {
                    error("Max message size");
                    return;
                }
                unpack(Bytes.ofData(cast event.data));
            } else if (event.data is Blob) {
                error("Blob is not supported");
            } else {
                error("Unknown messsage type");
            }
        }
        isServer = false;

        #else
        var socket = if (isTcp) {
            new SysSocket();
        } else {
            new SysUdpSocket();
        }
        try {
            socket.connect(new Host(ip), port);
            socket.setBlocking(false);
            raw = socket;
            isServer = false;
            isWebSocket = false;
            var host = socket.host();
            this.ip = host.host.toString();
            this.port = host.port;
            if (onOpen != null)
                onOpen("Connected");
        } catch (e:Dynamic) {
            error("Failed to connect: " + e);
            close();
            return false;
        }
        remoteIp = ip;
        remotePort = port;
        #end

        return true;
    }

    public function accept() {
        #if js
        error("accept() is not implemented for this target");
        return null;
        
        #else
        try {
            var r = raw.accept();
            r.setBlocking(false);
            var socket = new Socket();
            socket.raw = r;
            socket.isServer = false;

            var peer = r.peer();
            socket.ip = peer.host.toString();
            socket.port = peer.port;
            socket.remoteIp = ip;
            socket.remotePort = port;

            if (onOpen != null)
                onOpen("Received a new connection");

            return socket;
        } catch (e:Dynamic) {
            // if (onInfo != null)
            //     onInfo("No clients to accept");
        }
        #end

        return null;
    }

    public function close() {
        clear();
        if (raw == null)
            return;
        raw?.close();
        raw = null;
        isWebSocket = null;
        isServer = null;
        #if js

        #else
        ip = null;
        port = null;
        remoteIp = null;
        remotePort = null;
        #end
        input.resize(0);
        output.resize(0);
        if (onClose != null)
            onClose();
    }

    public function read() {
        if (input.length == 0 && raw == null) {
            error("Socket is closed");
            return null;
        }

        #if js
        if (raw.readyState != WebSocket.OPEN)
            return null;
        // Data will appear automatically in socket's callback
        return input.shift();
        
        #else
        try {
            if (input.length == 0) {
                var buffer = new BytesBuffer();

                var len = 0;
                var l = 0;
                do {
                    if (maxMessageSize != null && len > maxMessageSize)
                        throw "Max message size";
                    l = raw.input.readBytes(inputBuffer, 0, inputBuffer.length);
                    if (l > 0)
                        buffer.addBytes(inputBuffer, 0, l);
                    len += l;
                } while (l == inputBuffer.length);
                
                var bytes = buffer.getBytes();

                if (isWebSocket == null) {
                    if (isFluesendRquest(bytes)) {
                        if (onInfo != null)
                            onInfo("Socket from system");
                        unpack(bytes);
                        isWebSocket = false;
                    } else {
                        var request = Utils.parseHttpRequest(bytes);
                        if (request == null)
                            throw "Unsupported data format";
                        if (isHandshake(request)) {
                            if (onInfo != null)
                                onInfo("Socket from web");
                            // Handshake is required just for WebSocket
                            var key = request.headers.get("sec-websocket-key");
                            var response:Response = {
                                version: request.version,
                                code: 101,
                                status: "Switching Protocols",
                                headers: [
                                    "Upgrade" => "websocket",
                                    "Connection" => "Upgrade",
                                    "Sec-WebSocket-Accept" => Utils.computeHttpAcceptKey(key)
                                ],
                                body: null
                            };
                            sendRaw(Utils.composeHttpResponse(response));
                            isWebSocket = true;
                        } else {
                            throw "Unsupported handshake format";
                        }
                    }
                } else if (isWebSocket) {
                    var bytes = Utils.decodeFrame(bytes);
                    if (isFluesendRquest(bytes)) {
                        unpack(bytes);
                    } else {
                        throw "Unsupported frame data format";
                    }
                } else {
                    if (isFluesendRquest(bytes)) {
                        unpack(bytes);
                    } else {
                        throw "Unsupported socket data format";
                    }
                }
            }
        } catch (e:Dynamic) {
            if (e is Eof) {
                if (keepAlive) {
                    if (onInfo != null)
                        onInfo("No data");
                } else {
                    close();
                }
            } else if (e is Error) {
                switch e {
                    case Blocked:
                    case OutsideBounds:
                        error("Wrong format" + e);
                    default:
                        error("Unknown: " + e);
                }
            } else {
                error("Unknown: " + e);
            }
            return null;
        }
        return input.shift();
        #end
    }

    public function send() {
        if (raw == null) {
            error("Socket is closed");
            return;
        }

        if (output.length == 0)
            return;

        #if js
        if (raw.readyState != WebSocket.OPEN)
            return;
        #end

        var buffer = pack(output);

        try {
            #if js
            raw.send(buffer.sub(0, pos).getData());
            
            #else
            if (isWebSocket) {
                raw.output.write(Utils.encodeFrame(buffer.sub(0, pos), Binary));
            } else {
                raw.output.writeBytes(buffer, 0, pos);
            }
            raw.output.flush();
            #end
        } catch (e:Dynamic) {
            error("Send error: " + e);
        }
        
        output.resize(0);
    }

    public function sendRaw(data:Dynamic) {
        if (raw == null) {
            error("Socket is closed");
            return;
        }

        #if js
        if (raw.readyState != WebSocket.OPEN)
            return;
        #end

        try {
            #if js
            raw.send(data);
            
            #else
            raw.output.write(data);
            raw.output.flush();
            #end
        } catch (e:Dynamic) {
            error("Send error: " + e);
        }
    }

    public function push(data:Bytes) {
        output.push(data);
    }

    public function clear() {
        input.resize(0);
        output.resize(0);
    }

    function error(message:String) {
        if (onError != null)
            onError(message);
        close();
    }

    function pack(data:Array<Bytes>) {
        pos = 0;
        // Add header
        outputBuffer.setInt32(pos, magic);
        pos += 4;
        // Compose body: msgLen + message
        for (message in data) {
            outputBuffer.setInt32(pos, message.length);
            pos += 4;
            outputBuffer.blit(pos, message, 0, message.length);
            pos += message.length;
        }
        return outputBuffer;
    }

    function unpack(data:Bytes) {
        var pos = 4;    // magic size
        while (pos < data.length) {
            var l = data.getInt32(pos);
            pos += 4;
            if (l == magic)
                continue;
            if (pos >= data.length)
                break;
            input.push(data.sub(pos, l));
            pos += l;
        }
    }

    public static function isWebSocketFrame(data:Bytes):Bool {
        if (data.length < 2)
            return false;
        
        var a = data.get(0);
        var b = data.get(1);
        
        var fin = (a >> 7) & 1;
        var opcode = a & 0x0F;
        var mask = (b >> 7) & 1;
        
        if (opcode >= 0 && opcode <= 15 && mask == 1)
            return true;
        
        return false;
    }

    function isFluesendRquest(request:Bytes) {
        return request.getInt32(0) == magic;
    }

    function isHandshake(request:Request) {
        // Check request line
        if (request.method != "GET")
            return false;
        // Check headers
        if (request.headers.get("upgrade") != "websocket")
            return false;
        if (!request.headers.exists("connection"))
            return false;
        if (!request.headers.exists("sec-websocket-key"))
            return false;
        if (request.headers.get("sec-websocket-version") != "13")
            return false;
        return true;
    }
}