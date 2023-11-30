package = "lua-resty-lrucache"
version = "0.10-1"
source = {
    url = "git://github.com/openresty/lua-resty-lrucache",
    tag = "v0.10",
}
description = {
    summary = "Lua-land LRU cache based on the LuaJIT FFI.",
    homepage = "https://github.com/openresty/lua-resty-lrucache",
    license = "BSD"
}
dependencies = {}
build = {
    type = "builtin",
    modules = {
        ["resty.lrucache"] = "lib/resty/lrucache.lua",
        ["resty.lrucache.pureffi"] = "lib/resty/lrucache/pureffi.lua",
    }
}