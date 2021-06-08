local ngx = ngx

local rdr = {}

function rdr.start_reader(self, rules_path)
    ngx.log(ngx.WARN, "start_reader with", rules_path)
end

function rdr.route(self)
    ngx.log(ngx.WARN, "route")
end

function rdr.dump_table(tbl, indent, tables)
    if not indent then
        indent = 0
    elseif indent > 16 then
        return "*** too deep ***"
    end
    local output = {};
    local mt = getmetatable(tbl)
    local tab = string.rep("  ", indent + 1)
    local iter, ctx, key
    if mt and mt.__pairs then
        iter, ctx, key = mt.__pairs(tbl)
    else
        iter, ctx, key = pairs(tbl)
    end
    for k, v in iter, ctx, key do
        local formatting = tab
        if type(k) == 'string' then
            formatting = formatting .. k .. " = "
        elseif type(k) ~= 'number' then
            formatting = formatting .. "[" .. tostring(k) .. "]" .. " = "
        end
        if type(v) == "table" then
            if tables[v] then
                table.insert(output, formatting .. "*** recursion ***\n")
                --output = output .. formatting .. "*** recursion ***\n"
            elseif type(k) == "string" and k:sub(1, 1) == "_" then
                table.insert(output, formatting .. "(table) " .. "*** private field with table ***\n")
            else
                tables[v] = true
                table.insert(output, formatting .. dump_table(v, indent + 1, tables) .. "\n")
                tables[v] = nil
            end
        elseif type(v) == "userdata" then
            local ok, str = pcall(tostring, v)
            if not ok then
                str = "*** could not convert to string (userdata): " .. tostring(str) .. " ***"
            end
            table.insert(output, formatting .. "(" .. type(v) .. ") " .. str .. "\n")
        else
            table.insert(output, formatting .. "(" .. type(v) .. ") " .. tostring(v) .. "\n")
        end
    end

    if #output > 0 then
        return "{\n" .. table.concat(output, "") ..  string.rep("  ", indent) .. "}"
    else
        return "{}"
    end
end

return rdr