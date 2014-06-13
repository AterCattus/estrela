local OOP = require('estrela.oop.single')

local Router = require('estrela.ngx.router')
local Request = require('estrela.ngx.request')
local Response = require('estrela.ngx.response')

local _app = {
    _callErrorCb = function(self, errno)
        local route = self.router:getByName(errno)
        if route then
            return self:_callRoute(route.cb, errno)
        else
            return ngx.exit(errno)
        end
    end,

    _callDefers = function(self)
        for _,defer in ipairs(self.defers) do
            local ok, res = pcall(defer.cb, unpack(defer.args))
            if not ok then
                self.defers = {}
                self.error = res
                return self:_callErrorCb(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end
        end
        self.defers = {}
    end,

    _callRoute = function(self, cb, errno)
        self.defers = {}

        local ok, res = xpcall(
            function()
                return cb(self, self.req, self.resp)
            end,
            function(err)
                return err .. '\n' .. debug.traceback()
            end
        )

        self:_callDefers()

        if ok then
            return res
        elseif errno == ngx.HTTP_INTERNAL_SERVER_ERROR then
            -- ошибка в обработчике ошибки. прерываем работу
            return ngx.exit(errno)
        else
            self.error = res
            return self:_callErrorCb(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end
    end,
}

return OOP.name 'ngx.app'.class {
    new = function(self, routes)
        self.router = Router(routes)
        self.route = nil
        self.req  = nil
        self.resp = nil
        self.error = ''
        self.defers = {}
    end,

    serve = function(self)
        self.req  = Request()
        self.resp = Response()
        self.error = ''

        local found = false
        for route in self.router:route(self.req.path) do
            found = true
            self.route = route
            if not self:_callRoute(route.cb) then
                break
            end
        end

        if not found then
            return self:_callErrorCb(ngx.HTTP_NOT_FOUND)
        end
    end,

    defer = function(self, func, ...)
        if type(func) ~= 'function' then
            return nil, 'missing func'
        end
        table.insert(self.defers, {cb = func, args = {...}})
        return true
    end,

    __index__ = function(self, key)
        return _app[key]
    end,
}
