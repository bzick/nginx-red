package = "lua-_resty-core"
version = "0.1.17-4"
source = {
   url = "git://github.com/openresty/lua-_resty-core",
   tag = "v0.1.17",
}
description = {
   summary = "lua-_resty-core -  New FFI-based Lua API for ngx_http_lua_module and/or ngx_stream_lua_module.",
   detailed = [[

This pure Lua library reimplements part of the ngx_lua module's Nginx API for Lua with LuaJIT FFI and installs the new FFI-based Lua API into the ngx.* and ndk.* namespaces used by the ngx_lua module.

In addition, this Lua library implements any significant new Lua APIs of the ngx_lua module as proper Lua modules, like ngx.semaphore and ngx.balancer.

The FFI-based Lua API can work with LuaJIT's JIT compiler. ngx_lua's default API is based on the standard Lua C API, which will never be JIT compiled and the user Lua code is always interpreted (slowly).

Support for the new ngx_stream_lua_module has also begun.

This library is shipped with the OpenResty bundle by default. So you do not really need to worry about the dependencies and requirements.

   ]],
   homepage = "https://openresty.org/",
   license = "BSD"
}
dependencies = {
   "lua-resty-lrucache",
}

build = {
   type = "builtin",

  modules = {
["ngx.balancer"] = "lib/ngx/balancer.lua",
["ngx.base64"] = "lib/ngx/base64.lua",
["ngx.errlog"] = "lib/ngx/errlog.lua",
["ngx.ocsp"] = "lib/ngx/ocsp.lua",
["ngx.pipe"] = "lib/ngx/pipe.lua",
["ngx.process"] = "lib/ngx/process.lua",
["ngx.re"] = "lib/ngx/re.lua",
["ngx.resp"] = "lib/ngx/resp.lua",
["ngx.semaphore"] = "lib/ngx/semaphore.lua",
["ngx.ssl"] = "lib/ngx/ssl.lua",
["ngx.ssl.session"] = "lib/ngx/ssl/session.lua",
["resty.core"] = "lib/_resty/core.lua",
["resty.core.base"] = "lib/_resty/core/base.lua",
["resty.core.base64"] = "lib/_resty/core/base64.lua",
["resty.core.ctx"] = "lib/_resty/core/ctx.lua",
["resty.core.exit"] = "lib/_resty/core/exit.lua",
["resty.core.hash"] = "lib/_resty/core/hash.lua",
["resty.core.misc"] = "lib/_resty/core/misc.lua",
["resty.core.ndk"] = "lib/_resty/core/ndk.lua",
["resty.core.phase"] = "lib/_resty/core/phase.lua",
["resty.core.regex"] = "lib/_resty/core/regex.lua",
["resty.core.request"] = "lib/_resty/core/request.lua",
["resty.core.response"] = "lib/_resty/core/response.lua",
["resty.core.shdict"] = "lib/_resty/core/shdict.lua",
["resty.core.time"] = "lib/_resty/core/time.lua",
["resty.core.uri"] = "lib/_resty/core/uri.lua",
["resty.core.utils"] = "lib/_resty/core/utils.lua",
["resty.core.var"] = "lib/_resty/core/var.lua",
["resty.core.worker"] = "lib/_resty/core/worker.lua",
  },
}

