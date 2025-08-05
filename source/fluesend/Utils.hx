package fluesend;

import haxe.rtti.CType.MetaData;
import haxe.io.Bytes;
import haxe.crypto.Sha1;
import haxe.crypto.Base64;
import haxe.io.BytesOutput;
import haxe.io.BytesInput;
import haxe.Int64;
import fluesend.Opcode;
import haxe.rtti.Meta;

class Utils {
    // https://stackoverflow.com/questions/7666509/hash-function-for-string
    public static function hashString(string:String) {
        var hash = 0;
        for (i in 0...string.length) {
            hash += string.charCodeAt(i);
            hash += (hash << 10);
            hash ^= (hash >> 6);
        }
        hash += (hash << 3);
        hash ^= (hash >> 11);
        hash += (hash << 15);
        return hash;
    }

    public static function id() {
        // 2 ^ 30
        return Math.floor(Math.random() * 1073741824);
    }

    public static function collectMeta(cls:Class<Dynamic>) {
        var meta = new Map<String, Dynamic>();
        while (cls != null) {
            var struct = Meta.getFields(cls);
            for (field in Reflect.fields(struct))
                meta.set(field, Reflect.field(struct, field));
            cls = Type.getSuperClass(cls);
        }
        return meta;
    }

    public static function validateHttpVersion(version:String) {
        switch version {
            case "HTTP/0.9":
            case "HTTP/1.0":
            case "HTTP/1.1":
            case "HTTP/2":
            case "HTTP/3":
            default:
                return false;
        }
        return true;
    }

    public static function parseHttpRequest(data:Bytes) {
        var pos = 0;
        var string = "";

        function nextChar(char:String) {
			pos = string.indexOf(char, pos);
			if (pos == -1)
				return pos = string.length;
			return pos++;
		}

        function nextValue() {
            while (string.charAt(pos) == " ")
                pos++;
            return pos;
        }

        var request:Request = {
            method: "GET",
            path: "/",
            version: "HTTP/1.1",
            headers: new Map<String, String>(),
            body: null
        };
        
        var input = new BytesInput(data);
        
        // Read request line
        pos = 0;
        string = input.readLine();
        request.method = string.substring(pos, nextChar(" "));
        request.path = string.substring(pos, nextChar(" "));
        request.version = string.substring(pos, nextChar(" "));

        // Validations
        if (!validateHttpVersion(request.version))
            return null;
        /// @todo path validation

        // Read headers
        while (true) {
            pos = 0;
            string = input.readLine();
            if (string.length == 0)
                break;
            request.headers.set(
                string.substring(pos, nextChar(":")).toLowerCase(),
                string.substring(nextValue(), string.length)
            );
        }

        // Read payload
        request.body = input.readAll();

        return request;
    }

    public static function parseHttpResponse(data:Bytes) {
        var pos = 0;
        var string = "";

        function nextChar(char:String) {
			pos = string.indexOf(char, pos);
			if (pos == -1)
				return pos = string.length;
			return pos++;
		}

        function nextValue() {
            while (string.charAt(pos) == " ")
                pos++;
            return pos;
        }

        var response:Response = {
            version: "HTTP/1.1",
            code: "200",
            status: "OK",
            headers: new Map<String, String>(),
            body: null
        };
        
        var input = new BytesInput(data);
        
        // Read response line
        pos = 0;
        string = input.readLine();
        response.version = string.substring(pos, nextChar(" "));
        response.code = string.substring(pos, nextChar(" "));
        response.status = string.substring(pos, string.length);

        // Validations
        if (!validateHttpVersion(response.version))
            return null;

        // Read headers
        while (true) {
            pos = 0;
            string = input.readLine();
            if (string.length == 0)
                break;
            response.headers.set(
                string.substring(pos, nextChar(":")).toLowerCase(),
                string.substring(nextValue(), string.length)
            );
        }

        // Read payload
        response.body = input.readAll();

        return response;
    }

    public static function composeHttpRequest(request:Request) {
        var output = new BytesOutput();
        
        // Write request line
        output.writeString(request.method);
        output.writeString(" ");
        output.writeString(request.path);
        output.writeString(" ");
        output.writeString(request.version);
        output.writeString("\r\n");

        // Write headers
        for (key => value in request.headers) {
            output.writeString(key);
            output.writeString(": ");
            output.writeString(value);
            output.writeString("\r\n");
        }

        output.writeString("\r\n");

        // Write payload
        if (request.body is Bytes) {
            output.write(request.body);
        } else if (request.body is String) {
            output.writeString(request.body);
        } else if (request.body != null) {
            trace("Unknown format", request.body);
        }

        return output.getBytes();
    }

    public static function composeHttpResponse(response:Response) {
        var output = new BytesOutput();
        
        // Write response line
        output.writeString(response.version);
        output.writeString(" ");
        output.writeString(response.code);
        output.writeString(" ");
        output.writeString(response.status);
        output.writeString("\r\n");

        // Write headers
        for (key => value in response.headers) {
            output.writeString(key);
            output.writeString(": ");
            output.writeString(value);
            output.writeString("\r\n");
        }

        output.writeString("\r\n");

        // Write payload
        if (response.body is Bytes) {
            output.write(response.body);
        } else if (response.body is String) {
            output.writeString(response.body);
        } else if (response.body != null) {
            trace("Unknown format", response.body);
        }

        return output.getBytes();
    }

    public static function computeHttpAcceptKey(key:String) {
        var magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var hash = Sha1.make(Bytes.ofString(key + magic));
        return Base64.encode(hash);
    }

    /*
    FIN                     (1 bit) Indicates if this is the final frame in message
    RSV1, RSV2, RSV3        (3 bits) Reserved for extensions (usually 0)
    Opcode                  (4 bits) Frame type (text, binary, ping, etc.)
    Mask                    (1 bit) Mask flag (always 1 from client)
    Payload length          (7 bits or more) Length of the payload
    Extended payload length (16 or 64 bits) Used if payload length > 125 bytes
    Masking key             (32 bits (4 bytes)) Masking key for payload data (if Mask=1)
    Payload data            (variable length) Actual message data
    */
    // Convert data to frame
    public static function encodeFrame(payload:Bytes, opcode:Opcode = Utf8):Bytes {
        var output = new BytesOutput();
        
        // FIN (1), RSV1 (1), RSV2 (1), RSV3 (1), opcode (4)
        var fin = 0x80;
        output.writeByte(fin | (opcode & 0x0F));
        
        // Set payload length
        var len = payload.length;
        if (len <= 125) {
            output.writeByte(len);
        } else if (len <= 0xFFFF) {
            output.writeByte(126);
            output.writeByte((len >> 8) & 0xFF);
            output.writeByte(len & 0xFF);
        } else {
            output.writeByte(127);
            // @todo 64-bit length
            output.writeByte(0);
            output.writeByte(0);
            output.writeByte(0);
            output.writeByte(0);
            output.writeByte((len >> 24) & 0xFF);
            output.writeByte((len >> 16) & 0xFF);
            output.writeByte((len >> 8) & 0xFF);
            output.writeByte(len & 0xFF);
        }

        // Payload without mask because server->client (doesn't required)
        output.writeBytes(payload, 0, len);

        return output.getBytes();
    }

    // Convert frame to data
    public static function decodeFrame(frame:Bytes):Bytes {
        var input = new BytesInput(frame);

        if (input.length < 2)
            throw "Frame is too short";

        var b1 = input.readByte();
        var fin = (b1 & 0x80) != 0;
        var opcode = b1 & 0x0F;

        var b2 = input.readByte();
        var masked = (b2 & 0x80) != 0;

        // Read payload length
        var len = b2 & 0x7F;
        if (len == 126) {
            len = (input.readByte() << 8) | input.readByte();
        } else if (len == 127) {
            // Skip first 4 bytes (for simplicity)
            // @todo 64-bit length
            for (i in 0...4)
                input.readByte();
            len = 0;
            for (i in 0...4) {
                len = (len << 8) | input.readByte();
            }
        }

        if (masked) {
            var maskingKey = Bytes.alloc(4);
            input.readBytes(maskingKey, 0, 4);

            var payload = Bytes.alloc(len);
            input.readBytes(payload, 0, len);

            // Unmasking
            for (i in 0...len) {
                var original = payload.get(i);
                var maskByte = maskingKey.get(i % 4);
                payload.set(i, original ^ maskByte);
            }
            return payload;
        } else {
            // Just read the payload if not masked
            var payload = Bytes.alloc(len);
            input.readBytes(payload, 0, len);
            return payload;
        }
    }

    public static function hexToBytes(hex:String):Bytes {
        if (hex.length % 2 != 0)
            throw "Hex string must have even length";

        var len = Std.int(hex.length / 2);
        var b = Bytes.alloc(len);
        for (i in 0...len) {
            b.set(i, Std.parseInt("0x" + hex.substr(i * 2, 2)));
        }
        
        return b;
    }
}
