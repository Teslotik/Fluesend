package fluesend;

typedef Response = {
    version:String,
    code:String,
    status:String,
    headers:Map<String, String>,
    body:Dynamic
}