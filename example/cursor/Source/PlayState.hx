package;

import fluesend.Connection;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.util.FlxColor;

class PlayState extends FlxState {
    // Connection
    var connection = new Connection();
    var cursor:SharedCursor = null;

    // Renderer
    var sprite = new FlxSprite();

    var ip = "127.0.0.1";   // localhost
    var port = 7005;

    override public function create() {
        super.create();

        connection.traceInfo = true;

        // Create renderer
        sprite.makeGraphic(20, 20, FlxColor.RED);
        this.add(sprite);
        sprite.setPosition(FlxG.mouse.x, FlxG.mouse.y);

        // Create callbacks module
        cursor = new SharedCursor(connection, sprite);

        // bind wil be false in case application is already started
        if (connection.bind(ip, port, 10)) {
            trace("Started as a server");
        } else if (connection.connect(ip, port)) {
            trace("Started as a client");
        } else {
            trace("Failed to start");
            return;
        }

        FlxG.autoPause = false;
    }

    override public function update(elapsed:Float) {
        super.update(elapsed);

        // Retry connection if it is disconnected
        connection.retry();

        // Accept and receive data
        connection.poll();

        // Update position on server and client
        if (FlxG.mouse.deltaX != 0 || FlxG.mouse.deltaY != 0) {
            cursor.setPosition(FlxG.mouse.x, FlxG.mouse.y);
        }

        // Send data
        connection.flush();
    }
}