local type = type
local select = select
local tostring = tostring
local table = table
local getmetatable = getmetatable
local string = string
local pairs = pairs
local pcall = pcall
--- Набор вспомогательных утилит
local utils = {}


--- Export arguments as string
--- @return string
function utils.dump(...)
    local output, n, data = {}, select("#", ...), {...};
    for i = 1, n do
        if type(data[i]) == 'table' then
            table.insert(output, utils.dump_table(data[i], 0, { [tostring(data[i])] = true}))
        else
            table.insert(output, tostring(data[i]))
        end
    end
    return table.concat(output, "\n")
end

--- Serialize the table
--- @param tbl table
--- @param indent number отступ в количествах пробелов
--- @return string
function utils.dump_table(tbl, indent, tables)
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
        else
            formatting = formatting .. "[" .. tostring(k) .. "]" .. " = "
        end
        if type(v) == "table" then
            if tables[v] then
                table.insert(output, formatting .. "*** recursion ***\n")
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

-- split a string
function utils.split(str, delimiter)
    local result = { }
    local from  = 1
    local delim_from, delim_to = string.find( str, delimiter, from  )
    while delim_from do
        table.insert( result, string.sub( str, from , delim_from-1 ) )
        from  = delim_to + 1
        delim_from, delim_to = string.find( str, delimiter, from  )
    end
    table.insert( result, string.sub( str, from  ) )
    return result
end

return utils
