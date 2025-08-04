package;

import flixel.FlxSprite;
import fluesend.Module;
import fluesend.Connection;

class SharedCursor extends Module {
    public var sprite:FlxSprite = null;
    
    public function new(connection:Connection, sprite:FlxSprite) {
        super(connection);
        this.sprite = sprite;
    }

    @:rpc
    public function setPosition(x:Int, y:Int) {
        sprite.setPosition(x, y);
    }
}