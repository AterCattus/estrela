local OOP = require('estrela.oop.single')
local S = require('estrela.util.string')
local T = require('estrela.util.table')

local name_regexp = ':([_a-zA-Z0-9]+)'

local function _preprocessRoutes(routes)
    local routes_urls, routes_codes = {}, {}

    local function _prefixSimplify(prefix)
        local pref = ngx.re.gsub(prefix, name_regexp, ' ', 'jo')
        return pref
    end

    local function _prefix2regexp(prefix)
        local re = ngx.re.gsub(prefix, name_regexp, '(?<$1>[^/]+)', 'jo')
        -- если в регулярке указывается ограничитель по концу строки, то добавляю опциональный /? перед концом
        -- после этого регулярка '/foo$' будет подходить и для '/foo', и для '/foo/'
        re = ngx.re.gsub(re, [[\$$]], [[/?$$]], 'jo')
        return '^'..re
    end

    local function _addPrefix(prefix, cb, name)
        local prefixType = type(prefix)
        if prefixType == 'string' then
            table.insert(routes_urls, {
                cb          = cb,
                prefixShort = _prefixSimplify(prefix),
                prefix      = prefix,
                name        = name or nil,
                re          = _prefix2regexp(prefix)
            })
        elseif prefixType == 'number' then
            table.insert(routes_codes, {
                cb          = cb,
                prefix      = prefix,
                name        = name or nil,
            })
        end
    end

    for prefix, cb in pairs(routes) do
        if type(prefix) == 'table' then
            for name, pref in pairs(prefix) do
                _addPrefix(pref, cb, name)
            end
        else
            _addPrefix(prefix, cb)
        end
    end

    table.sort(routes_urls, function(a, b)
        return a.prefixShort > b.prefixShort
    end)

    return routes_urls, routes_codes
end

return OOP.name 'ngx.router'.class {
    new = function(self, routes)
        self.routes = routes
        self.routes_urls = nil
        self.routes_codes = nil
        self.path_prefix = ''
    end,

    getFullUrl = function(self, url)
        return self.path_prefix .. url
    end,

    mount = function(self, prefix, routes)
        for _prefix, cb in pairs(routes) do
            local _prefix_type = type(_prefix)
            if _prefix_type == 'string' then
                self.routes[prefix .. _prefix] = cb
            elseif _prefix_type == 'number' then
                self.routes[_prefix] = cb
            elseif _prefix_type == 'table' then
                local _new_prefix = {}
                for name, _sub_prefix in pairs(_prefix) do
                    _new_prefix[name] = prefix .. _sub_prefix
                end
                self.routes[_new_prefix] = cb
            end
        end
    end,

    route = function(self, pathFull)
        local app = ngx.ctx.estrela

        if not self.routes_urls then
            self.routes_urls, self.routes_codes = _preprocessRoutes(self.routes)
        end

        local path = pathFull
        if self.path_prefix then
            path = path:sub(self.path_prefix:len() + 1)
        end

        local method = app.req.method

        local function check_method(route)
            for k,cb in pairs(route) do
                if type(k) == 'table' then
                    if T.contains(k, method) then
                        return cb
                    end
                elseif method == k:upper() then
                    return cb
                end
            end
            return nil
        end

        return coroutine.wrap(function()
            for _,p in pairs(self.routes_urls) do
                local captures = ngx.re.match(path, p.re, 'jo')
                if captures then
                    local cb = p.cb

                    if type(cb) == 'string' then
                        cb = require(cb)
                    end

                    if type(cb) == 'table' then
                        cb = check_method(cb)
                    end

                    if cb then
                        coroutine.yield {
                            prefix = p.prefix,
                            cb     = cb,
                            params = captures,
                            name   = p.name,
                            path   = path,
                            pathFull = pathFull
                        }
                    end
                end
            end
        end)
    end,

    getByName = function(self, name)
        local name_type = type(name)
        if name_type == 'string' then
            for _,p in pairs(self.routes_urls) do
                if p.name == name then
                    return p
                end
            end
        elseif name_type == 'number' then
            for _,p in pairs(self.routes_codes) do
                if (p.prefix == name) or (p.name == name) then
                    return p
                end
            end
        end
    end,

    urlFor = function(self, name, params)
        params = params or {}

        local route = self:getByName(name)
        if not route then
            return nil
        end

        local url = ngx.re.gsub(route.prefix, name_regexp, function(m) return params[m[1]] or '' end, 'jo')
        return self:getFullUrl(S.rtrim(url, '$'))
    end,
}