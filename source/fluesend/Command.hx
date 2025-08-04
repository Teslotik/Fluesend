package fluesend;

import fluesend.Scope;

abstract class Command {
    @s public var owner:Int = -1;           // socket identifier
    @s public var scope:Scope = All;
    @s public var promise:Null<Int> = null; // promise to return value
    @s public var isBlocking:Bool = false;
}

class RpcCommand extends Command {
    @s public var method:String = null;
    @s public var args:Array<Dynamic> = [];

    public function new() {}
}

class StructureCommand extends Command {
    @s public var structure:Dynamic = null;

    public function new() {}
}

class ReturnCommand extends Command {
    @s public var value:Dynamic = null;

    public function new() {}
}