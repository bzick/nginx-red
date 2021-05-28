package = "redirector"
version = "git-1"
source = {
    url = "https://github.com/bzick/redirector/-/archive/master/pylon-master.zip"
}
description = {
    summary = "Exec redirect rules",
}
dependencies = {
    "lua-resty-core >= 0.1.17",
    "xml2lua >= 1.4"
}
build = {
    type = "builtin",
    modules = {}
}