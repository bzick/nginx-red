package = "red"
version = "git-1"
source = {
    url = "https://github.com/bzick/redirector/-/archive/master/pylon-master.zip"
}
description = {
    summary = "Exec redirect rules",
}
dependencies = {
    "xml2lua >= 1.4",
    "lua-messagepack == 0.5.2-1",
    "lua-resty-cookie"
}
build = {
    type = "builtin",
    modules = {}
}