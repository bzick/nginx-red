local type = type
local select = select
local table = table
local getmetatable = getmetatable
local string, tostring = string, tostring
local pairs = pairs
local pcall = pcall

--- Набор вспомогательных утилит
local utils = {}
local mtime = require("stat")

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
                table.insert(output, formatting .. utils.dump_table(v, indent + 1, tables) .. "\n")
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

--- Разбивает строку по разделителю.
--- @param str string
--- @param delimiter string
--- @return table
function utils.split(str, delimiter, plain)
    local result = { }
    local from  = 1
    local delim_from, delim_to = string.find( str, delimiter, from, plain  )
    while delim_from do
        table.insert( result, string.sub( str, from , delim_from-1 ) )
        from  = delim_to + 1
        delim_from, delim_to = string.find( str, delimiter, from, plain  )
    end
    table.insert( result, string.sub( str, from  ) )
    return result
end

--- Creates new table with keys from a list.
--- @param keys table list of keys
--- @param value any value for each key
--- @return table
function utils.combine(keys, value)
    local t = {}
    for _, v in pairs(keys) do
        t[v] = value
    end
    return t
end

--- Возвращает mtime указанного файла
--- @param filename string путь до файла
--- @return number|nil если файла нет то будет возвращено nil
function utils.get_file_mtime(filename)
    return mtime(filename)
end

--- Возвращает директорию от пути
--- @param path string
--- @return string
function utils.basedir(path)
    return path:match("(.*/)")
end

return utils
