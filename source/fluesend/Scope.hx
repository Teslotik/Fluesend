package fluesend;

enum Scope {
    All;
    Self;
    Others;
    
    Server;
    Clients;
    
    Target(netid:Int);
}