local M = {}

local _find = string.find

local T = require('estrela.util.table')

function M.find(str, sub, start, stop)
    stop = stop or #str
    start = start or 1

    local p = _find(str, sub, start, true)
    return (p and p <= stop) and p or nil
end

function M.rfind(str, sub, start, stop)
    stop = stop or #str
    start = start or 1

    local last_pos
    while true do
        local f, t = _find(str, sub, start, true)
        if not f or f > stop then
            break
        end

        last_pos = f
        start = t + 1
    end

    return last_pos
end

function M.split(str, sep, maxsplit, sep_regex)
    if type(sep) ~= 'string' or #sep < 1 then
        return T.list(str:gmatch('.'))
    end

    plain = not sep_regex

    if not _find(str, sep, 1, plain) then
        return {str}
    end

    if not maxsplit or maxsplit < 1 then
        maxsplit = #str
    end

    local res = {}

    local prev_pos = 1
    while #res < maxsplit - 1 do
        local pos, pos_t = _find(str, sep, prev_pos, plain)
        if not pos then
            res[#res + 1] = str:sub(prev_pos)
            prev_pos = #str + 1
            break
        end

        res[#res + 1] = str:sub(prev_pos, pos - 1)
        prev_pos = pos_t + 1
    end

    if prev_pos <= #str then
        res[#res + 1] = str:sub(prev_pos)
    end

    return res
end

function M.trim(str, chars)
    chars = chars or '%s'
    return M.ltrim(M.rtrim(str, chars), chars)
end

function M.rtrim(str, chars)
    chars = chars or '%s'
    return str:gsub('['..chars..']+$', '')
end

function M.ltrim(str, chars)
    chars = chars or '%s'
    return str:gsub('^['..chars..']+', '')
end

function M.htmlencode(str, withQuotes)
    str = str
        :gsub([[&]], [[&amp;]])
        :gsub([[<]], [[&lt;]])
        :gsub([[>]], [[&gt;]])

    if withQuotes then
        str = str
            :gsub([["]], [[&quot;]])
            :gsub([[']], [[&#039;]])
    end

    return str
end

function M.starts(str, prefix)
    return prefix:len() == 0 or _find(str, prefix, 1, true) == 1
end

function M.ends(str, suffix)
    local sl = suffix:len()
    return sl == 0 or _find(str, suffix, -sl, true) == (str:len() - sl + 1)
end

--[[Разбор значений HTTP заголовков на компоненты
]]
function M.parse_header_value(str)
    local byte = string.byte
    local trim = M.trim

    local ST_KEY = 1
    local ST_VAL = 2
    local ST_VAL_WAIT_QUOTE = 3
    local ST_VAL_SLASHED = 4

    local SEMI  = byte(';')
    local EQUAL = byte('=')
    local QUOTE = byte('"')
    local SLASH = byte([[\]])

    local map = {}

    local function to_map(k, v)
        k = trim(k)

        if not v then
            k, v = '', k
        else
            v = trim(v)
        end

        if byte(v) == QUOTE then
            v = loadstring('return '..v)
            if v then
                local ok, res = pcall(v)
                v = ok and res or nil
            end
            v = v or ''
        end

        if map[k] then
            if type(map[k]) ~= 'table' then
                map[k] = {map[k]}
            end
            table.insert(map[k], v)
        else
            map[k] = trim(v)
        end
    end

    local state = ST_KEY
    local sl = #str
    local pos = 1
    local last_pos = 1
    local key = nil

    while pos <= sl do
        local ch = byte(str, pos)

        if state == ST_KEY then
            if ch == SEMI then
                if pos > last_pos then
                    to_map(str:sub(last_pos, pos - 1), nil)
                end
                last_pos = pos + 1
            elseif ch == EQUAL then
                key = str:sub(last_pos, pos - 1)
                last_pos = pos + 1
                state = ST_VAL
            end
        elseif state == ST_VAL then
            if ch == SEMI then
                to_map(key, str:sub(last_pos, pos - 1))
                key = nil
                last_pos = pos + 1
                state = ST_KEY
            elseif ch == QUOTE then
                last_pos = pos
                state = ST_VAL_WAIT_QUOTE
            end
        elseif state == ST_VAL_WAIT_QUOTE then
            if ch == QUOTE then
                to_map(key, str:sub(last_pos, pos))
                key = nil
                last_pos = pos + 1
                state = ST_KEY
            elseif ch == SLASH then
                state = ST_VAL_SLASHED
            end
        elseif state == ST_VAL_SLASHED then
            state = ST_VAL_WAIT_QUOTE
        end

        pos = pos + 1
    end

    local val = last_pos <= sl and str:sub(last_pos, sl) or nil
    if not key then
        key, val = val, nil
    end

    if key then
        to_map(key, val)
    end

    return map
end

function M.cmpi(str, str2)
    return str:lower() == str2:lower()
end

function M.apply_patch()
    setmetatable(string, {
        __index = M,
    })
    string.find = M.find
end

return M