local rules = rules
local match = ngx.re.match
local log   = ngx.log
local redirect = ngx.redirect

local uri = ngx.var.uri -- request uri
local args = ngx.var.args -- request query parameters


for _, rule in ipairs(rules) do
    -- o — compile-once mode (similar to Perl's /o modifier), to enable the worker-process-level compiled-regex cache
    local matched, err = match(uri, rule.from, "o")
    if matched then
        local to_url = string.gsub(rule.to, '$(%d)', matched)
        if rule.qsappend then
            to_url = to_url .. args
        end
        if rule.permanent then
            -- redirect(to_url, 301)
        else
            -- redirect(to_url, 302)
        end
    elseif err then
        log(ngx.WARN, "Broken regexp " .. rule .. ": " .. tostring(err))
    end
end
