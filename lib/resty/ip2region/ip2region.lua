--[[
-- @description : It is a IP location library for openresty
-- @author : shixinke <ishixinke@qq.com> 
-- @website : www.shixinke.com
-- @date : 2018-02-02
-- 使用时请下载最新的ip库：https://github.com/lionsoul2014/ip2region/blob/master/data/ip2region.db
--]]
local _M = {
    _version = '0.01'
}

local shdict = ngx.shared
local math = math
local tonumber = tonumber
local index_block_length = 12
local total_header_length = 8192
local io_open = io.open
local str_byte = string.byte
local substr = string.sub
local str_match = string.match
local str_gsub = string.gsub
local ngx_var = ngx.var
local math_ceil = math.ceil
local bit = require 'bit'
local ngx_null = ngx.null


local mt = {
    __index = _M
}

--[[
-- @description : left shift int number　
-- @param number num : number
-- @param number displacement : displacement
--]]
local function int_lshift(num, displacement)
    if not num or type(num) ~= 'number' then
        return nil, 'not a number'
    end
    return (num * 2 ^ displacement) % 2 ^ 32
end

local function int_rshift(num, displacement)
    if not num or type(num) ~= 'number' then
        return nil, 'not a number'
    end
    return (math_ceil(num / (2 ^ displacement))) % 2 ^ 32
end


local function merge2long(num1, num2, num3, num4)
    local long_num = 0
    if type(num1) ~= 'number' or type(num2) ~= 'number' or type(num2) ~= 'number' or type(num2) ~= 'number' then
        return long_num, 'parameters expected number, get '..type(num1)..'....'
    end
    long_num = long_num + int_lshift(num1, 24)
    long_num = long_num + int_lshift(num2, 16)
    long_num = long_num + int_lshift(num3, 8)
    long_num = long_num + num4
    if long_num >= 0 then
        return long_num
    else
        return long_num + math.pow(2, 32)
    end
end

--[[
-- @description : translate ip address to long
-- @param string ip : ip address
-- @return long or nil
--
--]]
local function ip2long(ip)
    if not ip or type(ip) ~= 'string' then
        return ip, 'not a string IP address'
    end
    local ip1, ip2, ip3, ip4 = str_match(ip, "(%d+).(%d+).(%d+).(%d+)")
    return merge2long(tonumber(ip1), tonumber(ip2), tonumber(ip3), tonumber(ip4))
end


local function substr2long(str, offset)
    return merge2long(str_byte(substr(str, offset + 3, offset + 3), 1), str_byte(substr(str, offset+2, offset+2), 1), str_byte(substr(str, offset+1, offset+1), 1), str_byte(substr(str, offset, offset), 1))
end

local function format_region(tab)
    if not tab or type(tab) ~= 'table' or not tab['region'] then
        return nil, 'not an avilable region table'
    end
    local info = {city_id = tab.city_id, country = '', region = '',  province = '', city = '', isp = ''}
    local arr = {}
    str_gsub(tab.region,'[^|]+',function ( field )
        arr[#arr + 1] = field
    end)
    info.country = arr[1] or ''
    info.region = arr[2] or ''
    info.province = arr[3] or ''
    info.city = arr[4]
    info.isp = arr[5]
    return info
end

local function is_empty_string(str)
    if not str or str == '' or str == ngx_null then
        return true
    end
    return false
end


function _M.new(opts)
    opts = opts or {}
    local dict = opts.dict and shdict[opts.dict] or shdict.ip_data
    local file = opts.file or 'lib/resty/ip2region/data/ip2region.db'
    local root = opts.root or ngx_var.root or ngx_var.document_root
    if substr(file, 1, 1) ~= '/' then
        file = root..'/'..file
    end
    return setmetatable({
        mode = opts.mode or 'memory',
        file = file,
        dict = dict,
        first = nil,
        last = nil,
        blocks = 0,
        content = nil,
        fd = nil,
        headers = {
            idx = {},
            ptr = {},
            length = 0
        }
    }, mt)
end

function _M.memory_search(self, ip)
    if is_empty_string(ip) then
        return nil, 'the IP is empty'
    end
    local content = self.content
    local err = ''
    if content == nil then
        if self.dict then
            content = self.dict:get('ip_region_data')
        end
        if not content then
            content, err = self:loadfile()
            if content and self.dict then
                self.dict:set('ip_region_data', content)
            end
        end
    end

    if not content then
        return nil, err
    end
    if not self.first then
        self.first = substr2long(content, 1)
    end
    if not self.last then
        self.last = substr2long(content, 5)
    end
    if not self.blocks or self.blocks < 1 then
        self.blocks = (self.last - self.first) / index_block_length + 1
    end
    if type(ip) == 'string' then
        ip = ip2long(ip)
    end
    local heads = 1
    local tails = self.blocks + 1
    local ptr = 1
    while ( heads <= tails ) do
        local mid = int_rshift(heads + tails, 1)
        local tmp = self.first + mid * index_block_length
        local tmp_ip = substr2long(content, tmp + 1)
        if ip < tmp_ip then
            tails = mid - 1
        else
            local end_ip = substr2long(content, tmp + 5)
            if ip > end_ip then
                heads = mid + 1
            else
                ptr = substr2long(content, tmp + 9)
                break
            end
        end
    end

    if ptr == 0 then
        return nil, 'not found'
    end


    local data_len = bit.band(int_rshift(ptr, 24), 0xFF)
    local ptr = bit.band(ptr, 0x00FFFFFF)
    local tmp = {
        city_id = substr2long(content, ptr + 1),
        region = substr(content, ptr + 5, ptr + data_len -1)
    }
    return format_region(tmp)
end



function _M.bin_search(self, ip, multi)
    if is_empty_string(ip) then
        return nil, 'the IP is empty'
    end
    if self.fd == nil then
        local fd, err = io_open(self.file, 'rb')
        if not fd then
            return nil, err
        end
        self.fd = fd
    end
    self.fd:seek("set", 0)
    local super_block = self.fd:read(8)
    if not self.first then
        self.first = substr2long(super_block, 1)
    end
    if not self.last then
        self.last = substr2long(super_block, 5)
    end
    if not self.blocks or self.blocks < 1 then
        self.blocks = (self.last - self.first) / index_block_length + 1
    end

    if type(ip) == 'string' then
        ip = ip2long(ip)
    end

    local heads = 0
    local tails = self.blocks + 1
    local ptr = 1
    local times = 0
    while ( heads <= tails ) do
        times = times + 1
        local mid = int_rshift(heads + tails, 1)
        local tmp = (mid - 1) * index_block_length
        self.fd:seek('set', self.first + tmp)
        local buff = self.fd:read(index_block_length)
        local tmp_ip = substr2long(buff, 1)
        if ip < tmp_ip then
            tails = mid - 1
        else
            local end_ip = substr2long(buff, 5)

            if ip > end_ip then
                heads = mid + 1
            else
                ptr = substr2long(buff, 9)
                break
            end
        end
    end

    if ptr == 0 then
        return nil, 'not found'
    end

    local data_len = bit.band(int_rshift(ptr, 24), 0xFF)
    local ptr = bit.band(ptr, 0x00FFFFFF)
    self.fd:seek('set', ptr)
    local data = self.fd:read(data_len -1)
    local tmp = {
        city_id = substr2long(data, 1),
        region = substr(data, 5)
    }
    if not multi then
        self:close()
    end
    return format_region(tmp)
end

function _M.btree_search(self, ip, multi)
    if is_empty_string(ip) then
        return nil, 'the IP is empty'
    end
    if self.fd == nil then
        local fd, err = io_open(self.file, 'rb')
        if not fd then
            return nil, err
        end
        self.fd = fd
    end
    local headers = self.headers
    if not headers.idx or #headers.idx < 1 then
        self.fd:seek('set', 8)
        local buff = self.fd:read(total_header_length)
        self.headers.idx = {}
        self.headers.ptr = {}
        self.headers.length = 0
        for i = 1, total_header_length, 8 do
            local start_ip = substr2long(buff, i)
            local data_ptr = substr2long(buff, i + 4)
            if data_ptr == 0 then
                break
            end
            self.headers.length = self.headers.length + 1
            self.headers.idx[self.headers.length] = start_ip
            self.headers.ptr[self.headers.length] = data_ptr

        end
    end
    if type(ip) == 'string' then
        ip = ip2long(ip)
    end

    local heads = 0
    local tails = self.headers.length
    local start_ptr = 1
    local end_ptr = 1
    local t = 0
    while ( heads <= tails ) do
        t = t + 1
        local mid = int_rshift(heads + tails, 1)
        if ip == self.headers.idx[mid] then
            if mid > 1 then
                start_ptr = self.headers.ptr[mid - 1]
                end_ptr = self.headers.ptr[mid]
            else
                start_ptr = self.headers.ptr[mid]
                end_ptr = self.headers.ptr[mid + 1]
            end
            break
        end


        if ip < self.headers.idx[mid] then
            if mid == 1 then
                start_ptr = self.headers.ptr[mid]
                end_ptr = self.headers.ptr[mid + 1]
                break
            elseif ip > self.headers.idx[mid-1] then
                start_ptr = self.headers.ptr[mid-1]
                end_ptr = self.headers.ptr[mid]
                break
            end
            tails = mid - 1
        else
            if mid == self.headers.length then
                start_ptr = self.headers.ptr[mid-1]
                end_ptr = self.headers.ptr[mid]
                break
            elseif ip <= self.headers.idx[mid + 1] then
                start_ptr = self.headers.ptr[mid]
                end_ptr = self.headers.ptr[mid + 1]
                break
            end
            heads = mid + 1
        end
    end

    if start_ptr == 0 then
        return nil, 'not found'
    end

    local block_len = end_ptr - start_ptr
    self.fd:seek('set', start_ptr)
    local idx = self.fd:read(block_len + index_block_length)
    local ptr = 1
    heads = 0
    tails = block_len / index_block_length + 1
    local times = 0
    while heads <= tails do
        times = times + 1
        local mid = int_rshift(heads + tails, 1)
        local tmp = (mid - 1) * index_block_length
        local tmp_ip = substr2long(idx, tmp + 1)
        if ip < tmp_ip then
            tails = mid - 1
        else
            local end_ip = substr2long(idx, tmp + 5)

            if ip > end_ip then
                heads = mid
            else
                ptr = substr2long(idx, tmp + 9)
                break
            end
        end
    end

    local data_len = bit.band(int_rshift(ptr, 24), 0xFF)
    local ptr = bit.band(ptr, 0x00FFFFFF)
    self.fd:seek('set', ptr)
    local data = self.fd:read(data_len - 1)

    local tmp = {
        city_id = substr2long(data, 1),
        region = substr(data, 5)
    }
    if not multi then
        self:close()
    end
    return format_region(tmp)
end

function _M.search(self, ip, multi)
    if is_empty_string(ip) then
        return nil, 'the IP is empty'
    end
    if self.mode == 'memory' then
        return self:memory_search(ip)
    elseif self.mode == 'binary' then
        return self:bin_search(ip, multi)
    elseif self.mode == 'btree' then
        return self:btree_search(ip, multi)
    end
end


function _M.loadfile(self)
    if self.content ~= nil then
        return self.content
    end
    local path = self.file
    if not path then
        return nil, 'the file path is nil'
    end
    local fd, err = io_open(path, 'rb')
    if fd == nil then
        return nil, err
    end
    self.content = fd:read('*a')
    fd:close()
    return self.content
end

function _M.close(self)
    if self.fd then
        self.fd:close()
    end
end

return _M
