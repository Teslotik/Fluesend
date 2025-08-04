package;

import fluesend.module.PingModule;
import fluesend.Connection;

class Ping {
    public function new() {
        // Create connection (socket wrapper for multiple connections)
        var server = new Connection();
        server.traceInfo = true;    // connection will log everything
        // Register callbacks module
        var serverModule = new PingModule(server);

        var client = new Connection();
        client.traceInfo = true;
        var clientModule = new PingModule(client);

        // Connect
        server.bind("127.0.0.1", 7000, 10);
        client.connect("127.0.0.1", 7000);

        // ---------- usually you do this in loop

        // Accept connection
        server.poll();

        // Add command into queue
        clientModule.ping();

        // Send data from queue to the server
        client.flush();

        // Receive data and pass it into the output queue
        server.poll();
        // Validate data, execute on server and send for execution to clients
        server.flush();

        // Receive and execute
        client.poll();
    }

    static function main() {
        new Ping();
    }
}