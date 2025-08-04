package fluesend;

typedef Response = {
    version:String,
    code:Int,
    status:String,
    headers:Map<String, String>,
    body:Dynamic
}