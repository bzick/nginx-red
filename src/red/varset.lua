local setmetatable = setmetatable
local type = type
local os = os
local tostring = tostring
local ngx = ngx
local table = table
local cookie = require("resty.cookie")

local loaders = {}

function loaders.cookie(name)
    return cookie:new():get(name)
end

function loaders.arg(name)
    local args = ngx.req.get_uri_args()
    if args[name] then
        if type(args[name]) == "table" then
            return args[name][1]
        else
            return args[name]
        end
    end
end

function loaders.env(name)
    return os.getenv(name)
end

function loaders.nginx(name)
    if ngx.var[name] then
        return tostring(ngx.var[name])
    end
end

function loaders.header(name)
    if ngx.header[name] then
        return tostring(ngx.header[name])
    end
end


--- @class red.variable переменная, которая умеет тащить своё значение из всяких мест.
--- @field default any дефолтное значение переменной
--- @field loaders table[] список загрузчиков, где искать значения
local variable = {}
local variable_meta = { __index = variable }

function variable.new(default)
    return setmetatable({
        default     = default,
        loaders     = {},
    }, variable_meta)
end

--- Добавляет загрузчик значения для переменной.
--- @param from string название загрузчика: cookie, arg, env, nginx
--- @param name string ключ, который имеет значение у загрузчика
function variable:add_loader(from, name)
    if loaders[from] then
        table.insert(self.loaders, {from = from, name = name})
    end
end

--- Производит поиск значений по всем, заранее добавленным, лоадерам.
--- @return string если найдёт значение то вернётся что нашел, иначе будет возвращен дефолт, если и его нет - пустая строка
function variable:get_value()
    local value
    for _, loader in ipairs(self.loaders) do
        value = loaders[loader.from](loader.name)
        if value then
            return value
        end
    end
    return self.default or ""
end

--- @class red.varset набор переменных, которые можно применять к любой строке
--- @field vars table<string,red.variable>
local varset = {}
local meta = { __index = varset }

function varset.new()
    return setmetatable({
        vars  = {},
        count = 0,
    }, meta)
end

--- Создаёт новую переменную в наборе.
--- @param name string имя переменной в наборе
--- @param default any дефолтное значение переменной
--- @return red.variable сама переменная, можно настраивать загрузчики значений.
function varset:add_variable(name, default)
    local var = variable.new(default)
    self.vars[name] = var
    self.count = self.count + 1
    return var
end

--- Производит подстановку значений в строке из, используя созданные переменные.
--- @param tpl string строка с подстановками вида {some_variable}
--- @return string
function varset:replace(str)
    return (str:gsub('(%b{})', function(w)
        w = w:sub(2, -2)
        if self.vars[w] then
            return self.vars[w]:get_value()
        else
            return "{" .. w .. "}"
        end
    end))
end

--- Проверяет что в строке есть подстановка переменной вида {some_variable}.
--- @param str string
--- @return boolean
function varset.has_placeholders(str)
    local pos_start = str:find("{", 1, true)
    if pos_start then
        local pos_end = str:find("}", pos_start, true)
        if pos_end then
            return true
        end
    end
    return false
end

return varset