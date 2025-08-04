package;

import fluesend.Connection;
import fluesend.Scope;
import fluesend.Module;

class ChatModule extends Module {
    var name:String = "Anon";

    public function new(connection:Connection, name:String) {
        super(connection);
        this.name = name;
    }

    @:rpc(Scope.Others)
    function doSendMessage(message:String) {
        trace('${name} received a new message: ${message}');
    }

    public function sendMessage(message:String) {
        doSendMessage('[${name}] ${message}');
    }
}

class Chat {
    var ivan:Connection = new Connection();
    var ivanChat:ChatModule = null;
    
    var boris:Connection = new Connection();
    var borisChat:ChatModule = null;

    var dimitry:Connection = new Connection();
    var dimitryChat:ChatModule = null;
    
    var messages = [
        "Hello",
        "Ok",
        "Whats up?",
        "What are you doing?",
        "Can you help?",
        "Weather is cold",
        "Do you have a cat?",
        "Did you see a new GUI library called Juil?"
    ];

    public function new() {
        ivanChat = new ChatModule(ivan, "Ivan");
        borisChat = new ChatModule(boris, "Boris");
        dimitryChat = new ChatModule(dimitry, "Dimitry");

        ivan.bind("127.0.0.1", 7000, 10);
        boris.connect("127.0.0.1", 7000);
        dimitry.connect("127.0.0.1", 7000);

        for (_ in 0...30) {
            // Accept connections and read data
            ivan.poll();
            boris.poll();
            dimitry.poll();

            // Take a random message
            var message = messages[Math.floor(Math.random() * messages.length)];
            if (Math.random() < 0.5) {
                // Add message to the output queue
                ivanChat.sendMessage(message);
            } else {
                borisChat.sendMessage(message);
            }

            // Send data from queue
            ivan.flush();
            boris.flush();
            dimitry.flush();

            Sys.sleep(0.5);
        }
    }

    static function main() {
        new Chat();
    }
}