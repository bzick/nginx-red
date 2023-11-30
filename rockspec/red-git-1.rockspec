package = "red"
version = "git-1"
source = {
    url = "https://github.com/bzick/nginx-red/archive/refs/tags/1.17.zip"
}
description = {
    summary = "Exec redirect rules",
}
dependencies = {
    "lua-messagepack == 0.5.2-1",
    "lua-resty-cookie"
}
build = {
    type = "builtin",
    modules = {}
}