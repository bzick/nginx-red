package.path = "src/red/?.lua;src/vendor/share/lua/5.1/?.lua;" .. package.path
package.loaded.stat = function() end -- stat is Linux-only and is not used by these tests.

local result
ngx = {
    shared = {},
    var = {},
    header = {},
    log = function() end,
    re = {
        gsub = function(uri, from, to)
            return uri:gsub(from, to)
        end
    },
    redirect = function(url, code)
        result = { url = url, code = code }
    end,
    req = {
        set_uri = function(url)
            result = { url = url, code = "forwarding" }
        end,
        set_uri_args = function() end
    }
}

local config = require("config")
require("red")
local red = _G.red

local function check(suffixes, destination, expected, to_type, query)
    red.config = config.new()
    if type(suffixes) == "string" then
        suffixes = { suffixes }
    end
    for _, suffix in ipairs(suffixes) do
        red.config:set_param("trim-target-suffix", suffix)
    end
    ngx.var.args = query
    result = nil
    local rule = {
        from = "^/trim/$",
        to = destination,
        opts = "",
        to_type = to_type or config.REDIRECT_TEMP,
        auto_lang_prefix = false,
        query_append = query ~= nil,
        to_has_query = destination:find("?", 1, true) ~= nil
    }
    assert(red.try_rule("/trim/", nil, rule, nil))
    assert(result and result.url == expected,
        string.format("suffixes %q, target %q: expected %q, got %q",
            table.concat(suffixes, ", "), destination, expected, result and result.url or "nil"))
    assert(result.code == (to_type == config.FORWARDING and "forwarding" or 302))
end

local parsed = config.new()
assert(not parsed:parse_xml([[<urlrewrite>
    <config param="trim-target-suffix">/index.html</config>
    <config param="trim-target-suffix">/index.htm</config>
</urlrewrite>]]))
assert(#parsed.trim_target_suffixes == 2)
assert(parsed.trim_target_suffixes[1] == "/index.html")
assert(parsed.trim_target_suffixes[2] == "/index.htm")

local single = config.new()
assert(not single:parse_xml([[<urlrewrite>
    <config param="trim-target-suffix">/index.html</config>
</urlrewrite>]]))
assert(#single.trim_target_suffixes == 1)
assert(single.trim_target_suffixes[1] == "/index.html")

check("/index.html", "/docs/index.html?view=full", "/docs?view=full&source=campaign", nil, "source=campaign")
check("index.html", "/docs/index.html?view=full", "/docs/?view=full&source=campaign", nil, "source=campaign")
check({ "/index.html", "/index.htm" }, "/docs/index.htm", "/docs")
check({ "index.html", "/index.html" }, "/docs/index.html", "/docs")
check({ "/index.html", "index.html" }, "/docs/index.html", "/docs")
check({ "/index.html", "/index.htm" }, "/docs/index.php", "/docs/index.php")
check("/index.html", "/index.html", "/")
check("index.html", "/index.html", "/")
check("index.html", "index.html", "./")
check("/index.html", "https://example.invalid/docs/index.html#intro", "https://example.invalid/docs#intro")
check("index.html", "https://example.invalid/docs/index.html#intro", "https://example.invalid/docs/#intro")
check("/index.html", "https://example.invalid/index.html", "https://example.invalid/")
check("/index.html", "https://index.html", "https://index.html")
check("index.html", "https://example.index.html", "https://example.index.html")
check("/index.html", "/docs/?next=/index.html", "/docs/?next=/index.html")
check("/index.html", "/forwarded/index.html", "/forwarded", config.FORWARDING)
check("index.html", "/forwarded/index.html", "/forwarded/", config.FORWARDING)
check("", "/docs/index.html", "/docs/index.html")

print("trim-target-suffix: ok")
