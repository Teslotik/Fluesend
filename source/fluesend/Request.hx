package fluesend;

typedef Request = {
    method:String,
    path:String,
    version:String,
    headers:Map<String, String>,
    body:Dynamic
}