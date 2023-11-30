package = "lua-resty-core"
version = "0.1.21-1"
source = {
    url = "git://github.com/openresty/lua-resty-core",
    tag = "v0.1.21",
}
description = {
    summary = "New FFI-based Lua API for ngx_http_lua_module and/or ngx_stream_lua_module.",
    homepage = "https://openresty.org/",
    license = "BSD"
}
dependencies = {}
build = {
    type = "builtin",
    modules = {
        ["ngx.re"] = "lib/ngx/re.lua",
        ["ngx.req"] = "lib/ngx/req.lua",
        ["ngx.ssl"] = "lib/ngx/ssl.lua",
        ["ngx.ocsp"] = "lib/ngx/ocsp.lua",
        ["ngx.pipe"] = "lib/ngx/pipe.lua",
        ["ngx.resp"] = "lib/ngx/resp.lua",
        ["ngx.base64"] = "lib/ngx/base64.lua",
        ["ngx.errlog"] = "lib/ngx/errlog.lua",
        ["ngx.process"] = "lib/ngx/process.lua",
        ["ngx.balancer"] = "lib/ngx/balancer.lua",
        ["ngx.semaphore"] = "lib/ngx/semaphore.lua",
        ["ngx.ssl.session"] = "lib/ngx/ssl/session.lua",
        ["resty.core"] = "lib/resty/core.lua",
        ["resty.core.ctx"] = "lib/resty/core/ctx.lua",
        ["resty.core.ndk"] = "lib/resty/core/ndk.lua",
        ["resty.core.uri"] = "lib/resty/core/uri.lua",
        ["resty.core.var"] = "lib/resty/core/var.lua",
        ["resty.core.base"] = "lib/resty/core/base.lua",
        ["resty.core.exit"] = "lib/resty/core/exit.lua",
        ["resty.core.hash"] = "lib/resty/core/hash.lua",
        ["resty.core.misc"] = "lib/resty/core/misc.lua",
        ["resty.core.time"] = "lib/resty/core/time.lua",
        ["resty.core.phase"] = "lib/resty/core/phase.lua",
        ["resty.core.regex"] = "lib/resty/core/regex.lua",
        ["resty.core.utils"] = "lib/resty/core/utils.lua",
        ["resty.core.base64"] = "lib/resty/core/base64.lua",
        ["resty.core.shdict"] = "lib/resty/core/shdict.lua",
        ["resty.core.socket"] = "lib/resty/core/socket.lua",
        ["resty.core.worker"] = "lib/resty/core/worker.lua",
        ["resty.core.request"] = "lib/resty/core/request.lua",
        ["resty.core.response"] = "lib/resty/core/response.lua",
    }
}