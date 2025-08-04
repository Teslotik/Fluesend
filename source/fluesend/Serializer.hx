package fluesend;

import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.ds.ObjectMap;
import haxe.io.BytesInput;
import haxe.io.Bytes;
import haxe.rtti.Meta;
import Type.ValueType;
import haxe.io.BytesBuffer;

using Lambda;
using StringTools;

// @todo crypto

// https://haxe.org/manual/std-serialization-format.html
class Serializer {
    public var maxDepth:Null<Int> = null;
    public var maxDataSize:Null<Int> = null;
    public var useMarkedFields = false;

    var types = new Map<String, Class<Dynamic>>();
    var enums = new Map<String, Enum<Dynamic>>();

    public function new() {
        
    }

    /// @note We use types registration instead of global types
    // to prevent unauthorized access
    public function registerType(cls:Class<Dynamic>) {
        types.set(Type.getClassName(cls), cls);
    }

    public function unregisterType(name:String) {
        return types.remove(name);
    }

    public function registerEnum(cls:Enum<Dynamic>) {
        enums.set(Type.getEnumName(cls), cls);
    }

    public function unregisterEnum(name:String) {
        return enums.remove(name);
    }

    public function serialize(obj:Dynamic) {
        var input = new BytesBuffer();
        function walk(field:Dynamic, depth = 0) {
            if (maxDepth != null && depth >= maxDepth)
                throw "Max depth";
            if (field == null) {
                input.addByte("n".code);
            } else if (Type.typeof(field).match(ValueType.TInt)) {
                if (field == 0) {
                    input.addByte("z".code);
                } else {
                    input.addByte("i".code);
                    input.addInt32(field);
                }
            } else if (Type.typeof(field).match(ValueType.TFloat)) {
                if (Math.isNaN(field)) {
                    input.addByte("k".code);
                } else if (!Math.isFinite(field) && field < 0) {
                    input.addByte("m".code);
                } else if (!Math.isFinite(field) && field > 0) {
                    input.addByte("p".code);
                } else {
                    input.addByte("d".code);
                    input.addDouble(field);
                }
            } else if (Type.typeof(field).match(ValueType.TBool)) {
                input.addByte(field ? "t".code : "f".code);
            } else if (field is String) {
                var string:String = StringTools.urlEncode(field);
                input.addByte("y".code);
                input.addInt32(string.length);
                input.addByte(":".code);
                input.addString(string);
            } else if (field is List) {
                input.addByte("l".code);
                for (item in (field:List<Dynamic>))
                    walk(item, depth + 1);
                input.addByte("h".code);
            } else if (field is Array) {
                input.addByte("a".code);
                /// @todo multiple null
                for (item in (field:Array<Dynamic>))
                    walk(item, depth + 1);
                input.addByte("h".code);
            } else if (field is StringMap) {
                input.addByte("b".code);
                for (key => value in (field:StringMap<Dynamic>)) {
                    walk(key, depth + 1);
                    walk(value, depth + 1);
                }
                input.addByte("h".code);
            } else if (field is IntMap) {
                input.addByte("q".code);
                for (key => value in (field:IntMap<Dynamic>)) {
                    walk(key, depth + 1);
                    walk(value, depth + 1);
                }
                input.addByte("h".code);
            } else if (field is ObjectMap) {
                input.addByte("M".code);
                for (key => value in (field:ObjectMap<Dynamic, Dynamic>)) {
                    walk(key, depth + 1);
                    walk(value, depth + 1);
                }
                input.addByte("h".code);
            } else if (Type.typeof(field).match(ValueType.TObject)) {
                input.addByte("o".code);
                for (f in Reflect.fields(field)) {
                    walk(f, depth + 1);
                    walk(Reflect.field(field, f), depth + 1);
                }
                input.addByte("g".code);
            } else if (Type.typeof(field).match(ValueType.TClass(_))) {
                var cls = Type.getClass(field);
                var name = Type.getClassName(cls);
                if (!types.exists(name))
                    throw "Unregistered type: " + name;
                input.addByte("c".code);
                walk(name, depth + 1);
                var meta = Utils.collectMeta(cls);
                for (f in Reflect.fields(field)) {
                    if (useMarkedFields && (!meta.exists(f) || !Reflect.hasField(meta.get(f), "s")))
                        continue;
                    walk(f);
                    walk(Reflect.field(field, f), depth + 1);
                }
                input.addByte("g".code);
            } else if (Type.typeof(field).match(ValueType.TEnum(_))) {
                var name = Type.getEnumName(switch Type.typeof(field) {
                    case ValueType.TEnum(e): e;
                    default: return;
                });
                if (!enums.exists(name))
                    throw "Unregistered enum: " + name;
                input.addByte("w".code);
                walk(name, depth + 1);
                walk(Type.enumConstructor(field), depth + 1);
                input.addByte(":".code);
                input.addInt32(Type.enumParameters(field).length);
                for (f in Type.enumParameters(field))
                    walk(f, depth + 1);
            }
        }
        walk(obj);
        return input.getBytes();
    }

    public function deserialize(data:Bytes):Dynamic {
        if (maxDataSize != null && data.length > maxDataSize)
            throw "Max data size";
        var data = new BytesInput(data);
        function walk():Dynamic {
            var type = data.readByte();
            if (type == "n".code) {
                return null;
            } else if (type == "z".code) {
                return 0;
            } else if (type == "i".code) {
                return data.readInt32();
            } else if (type == "k".code) {
                return Math.NaN;
            } else if (type == "m".code) {
                return Math.NEGATIVE_INFINITY;
            } else if (type == "p".code) {
                return Math.POSITIVE_INFINITY;
            } else if (type == "d".code) {
                return data.readDouble();
            } else if (type == "t".code) {
                return true;
            } else if (type == "f".code) {
                return false;
            } else if (type == "y".code) {
                var len = data.readInt32();
                data.readByte();
                return data.readString(len).urlDecode();
            } else if (type == "l".code) {
                var list = new List();
                while (true) {
                    var item:Dynamic = walk();
                    if (item == this)
                        break;
                    list.add(item);
                }
                return list;
            } else if (type == "a".code) {
                var array = new Array();
                while (true) {
                    var item:Dynamic = walk();
                    if (item == this)
                        break;
                    array.push(item);
                }
                return array;
            } else if (type == "b".code) {
                var map = new StringMap();
                while (true) {
                    var key:Dynamic = walk();
                    if (key == this)
                        break;
                    map.set(key, walk());
                }
                return map;
            } else if (type == "q".code) {
                var map = new IntMap();
                while (true) {
                    var key:Dynamic = walk();
                    if (key == this)
                        break;
                    map.set(key, walk());
                }
                return map;
            } else if (type == "M".code) {
                var map = new ObjectMap();
                while (true) {
                    var key:Dynamic = walk();
                    if (key == this)
                        break;
                    map.set(key, walk());
                }
                return map;
            } else if (type == "o".code) {
                // Anon struct
                var struct:Dynamic = {};
                while (true) {
                    var key:Dynamic = walk();
                    if (key == this)
                        break;
                    Reflect.setField(struct, key, walk());
                }
                return struct;
            } else if (type == "c".code) {
                var name = walk();
                var cls = types.get(name);
                if (cls == null)
                    throw "Unregistered type: " + name;
                var instance = Type.createEmptyInstance(cls);
                var meta = Utils.collectMeta(cls);
                /// @note Serialized object may not contains some fields
                while (true) {
                    var key:Dynamic = walk();
                    if (key == this)
                        break;
                    if (useMarkedFields && (!meta.exists(key) || !Reflect.hasField(meta.get(key), "s")))
                        "Field must be marked as @s";
                    var value:Dynamic = walk();
                    Reflect.setField(instance, key, value);
                }
                return instance;
            } else if (type == "w".code) {
                var cls = enums.get(walk());
                if (cls == null)
                    throw "Unregistered enum";
                var constructor = walk();
                data.readByte();
                var params = [for (i in 0...data.readInt32()) walk()];
                return Type.createEnum(cls, constructor, params);
            } else if (type == "g".code) {
                return this;    // a little hack - we need to return some unique token as a terminator
            } else if (type == "h".code) {
                return this;
            }
            throw "Unknown format: " + type;
        }
        return walk();
    }
}