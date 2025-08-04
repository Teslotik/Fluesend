package fluesend.module;

class PingModule extends Module {
    @:rpc
    public function ping() {
        if (connection.isServer) {
            trace("Ping server! " + connection.netid);
        } else {
            trace("Ping client! " + connection.netid);
        }
    }
}