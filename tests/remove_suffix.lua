package.path = "src/red/?.lua;src/vendor/share/lua/5.1/?.lua;" .. package.path
package.loaded.stat = function() end -- stat is Linux-only and is not used by these tests.

local result, method
ngx = {
    shared = {},
    var = {},
    log = function() end,
    re = {
        gsub = function(uri, from, to)
            return uri:gsub(from, to)
        end
    },
    req = { get_method = function() return method end },
    redirect = function(url, code)
        result = { url = url, code = code }
    end
}

local config = require("config")
require("red")
local red = _G.red
assert(#config.new().remove_suffixes == 0)

local single = config.new()
assert(not single:parse_xml([[<urlrewrite>
    <config param="remove-suffix">index.html</config>
</urlrewrite>]]))
assert(#single.remove_suffixes == 1 and single.remove_suffixes[1] == "index.html")

local multiple = config.new()
assert(not multiple:parse_xml([[<urlrewrite>
    <config param="remove-suffix">index.html</config>
    <config param="remove-suffix">index.htm</config>
</urlrewrite>]]))
assert(#multiple.remove_suffixes == 2 and multiple.remove_suffixes[2] == "index.htm")

local legacy_rule = {
    from = "^/legacy/$", to = "/business/", to_type = config.REDIRECT_TEMP,
    opts = "", auto_lang_prefix = false, query_append = false
}
local cases = {
    { uri = "/index.html", expected = "/" },
    { uri = "/idea/index.html", expected = "/idea/" },
    { uri = "/de-de/idea/index.html", expected = "/de-de/idea/" },
    { uri = "/xx-xx/idea/index.html", expected = "/xx-xx/idea/" },
    { uri = "/idea/index.htm", expected = "/idea/" },
    { uri = "/idea/index.html?tag=a&tag=b&x=a%26b+z&empty=", expected = "/idea/?tag=a&tag=b&x=a%26b+z&empty=" },
    { uri = "/idea/index.html?", expected = "/idea/?" },
    { uri = "/idea/index.html?next=/search?q=1#intro", expected = "/idea/?next=/search?q=1#intro" },
    { uri = "/idea/index.html?next=//host/%2F%5c", expected = "/idea/?next=//host/%2F%5c" },
    { uri = "/a%20b/index.html", expected = "/a%20b/" },
    { uri = "/idea/index.html", method = "HEAD", expected = "/idea/" },
    { uri = "/legacy/index.html", rules = { legacy_rule }, expected = "/legacy/" },
    { uri = "/idea/index.html", runtime = "unavailable", expected = "/idea/" },
    { uri = "/idea/index.html", runtime = "error", expected = "/idea/" },
    { uri = "/index.html", current_uri = "/", expected = "/" },
    { uri = "/idea/index.html", method = "POST", expected = "/idea/" },
    { uri = "/idea/index.html", method = "PUT", expected = "/idea/" },
    { uri = "/idea/index.html", method = "PATCH", expected = "/idea/" },
    { uri = "/idea/index.html", method = "DELETE", expected = "/idea/" },
    { uri = "/idea/index.html", method = "OPTIONS", expected = "/idea/" },
    { uri = "/idea/index.html", suffixes = {} },
    { uri = "/idea/index.htm", suffixes = { "index.html" } },
    { uri = "/idea/no-index.html" },
    { uri = "/idea/other.html" },
    { uri = "/idea/INDEX.HTML" },
    { uri = "/idea/indexXhtml" },
    { uri = "/idea/index.html/" },
    { uri = "/idea/index.html/child" },
    { uri = "/idea/index.html#intro" },
    { uri = "/idea/", current_uri = "/idea/index.html" },
    { uri = "/", current_uri = "/index.html" },
    { uri = "/idea/?next=/index.html" },
    { uri = "//example.invalid/index.html" },
    { uri = "/idea//index.html" },
    { uri = "/\\example.invalid/index.html" },
    { uri = "/idea\\path/index.html" },
    { uri = "/idea%2Fpath/index.html" },
    { uri = "/idea%2fpath/index.html" },
    { uri = "/idea%5Cpath/index.html" },
    { uri = "/idea%5cpath/index.html" },
    { uri = "/idea\r\npath/index.html" },
    { uri = "https://example.invalid/index.html" },
    { uri = "index.html" },
    { uri = "/legacy/index.html", suffixes = {}, rules = { legacy_rule }, expected = "/business/", code = 302 },
    { uri = "/legacy/index.html", method = "POST", rules = { legacy_rule }, expected = "/legacy/" },
    { uri = "/legacy/index.html", method = "POST", suffixes = {}, rules = { legacy_rule }, expected = "/business/", code = 302 }
}

for _, case in ipairs(cases) do
    red.config = config.new()
    red.config.trim_suffix = "index.html"
    for _, suffix in ipairs(case.suffixes or { "index.html", "index.htm" }) do
        red.config:set_param("remove-suffix", suffix)
    end
    red.rules = case.rules or {}
    red.locale = red.config.locale
    local runtime_calls = 0
    red.get_runtime = function()
        runtime_calls = runtime_calls + 1
        assert(case.runtime ~= "error", "Canonicalization must run before loading rules")
        if case.runtime == "unavailable" then return nil end
        return red.rules, red.locale
    end
    method = case.method or "GET"
    ngx.var.request_uri = case.uri
    ngx.var.uri = case.current_uri or case.uri:match("^[^?]*")
    ngx.var.args = "modified=1" -- The original query must come from request_uri.
    result = nil
    red.route()
    assert((result and result.url) == case.expected,
        case.uri .. ": expected " .. tostring(case.expected) .. ", got " .. tostring(result and result.url))
    if result then
        assert(result.code == (case.code or 301))
        if result.code == 301 then assert(runtime_calls == 0) end
    end
end

print("remove-suffix: " .. #cases .. " route cases passed")
