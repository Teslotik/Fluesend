package fluesend;

enum abstract Opcode(Int) from Int to Int {
    var Utf8 = 1;
    var Binary = 2;
}
