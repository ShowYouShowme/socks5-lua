local skynet    = require "skynet"
local socket    = require "skynet.socket"
local dns = require "skynet.dns"
--[[
    测试命令: curl --socks5 127.0.0.1:8001 http://www.baidu.com/
--]]

-- close socket 后,read 会抛出异常
-- close socket 后,write 不会出错
-- 对端关闭,read返回nil
-- 链接失败,open会返回nil,通过assert来校验即可
-- 一个socket 多次close 是可以的
local function tunnel(from, to, name)
    while true do
        local data = socket.read(from) -- TODO可能会出错,用pcall包装住
        if not data then
            -- 出错了
            -- skynet.error(name, "发生错误")
            socket.close(from)
            socket.close(to)
            return
        else
            socket.write(to, data)
        end
    end
end

local function request(cID)
    local str = socket.read(cID)
    if str then
        skynet.error("[stage 2]")
        skynet.error(string.byte(str, 1, -1))

        -- 解包
        local ver, cmd, rsv, atype = string.unpack("<BBBB", str, 1)
        skynet.error(string.format("ver : %d, cmd : %d, rsv : %d, atype : %d", ver, cmd, rsv, atype))
        if atype == 0x01 then -- ipv4 地址
            local response = string.pack('>BBBBBBBBBB',0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
            socket.write(cID, response)
            local port = string.unpack(">H", str, -2)
            -- skynet.error("port : ", port)
            local ip = string.format("%d.%d.%d.%d:%d",string.byte(str,5),string.byte(str,6),string.byte(str,7),string.byte(str,8),port)
            skynet.error("connect ".. ip)
            local id  = socket.open(ip)
            assert(id)
            local from = cID
            local to = id
            --启动读协程
            skynet.fork(tunnel, from, to, "client --> server")
            skynet.fork(tunnel, to, from, "server --> client")
            skynet.error("开始转发流量")
            -- 开始转发流量
        elseif atype == 0x03 then -- 域名
            local port = string.unpack(">H", str, -2)
            local url = string.sub(str, 6, -3)
            skynet.error("url : ", url, " len : ", #url)
            local ip = dns.resolve(url)
            ip = ip .. ":" .. tostring(port)
            skynet.error("ip : ", ip, " type : ", type(ip))

            skynet.error("connect ".. ip)
            local id  = socket.open(ip)
            assert(id)
            local from = cID
            local to = id
            --启动读协程
            skynet.fork(tunnel, from, to, "client --> server")
            skynet.fork(tunnel, to, from, "server --> client")
            skynet.error("开始转发流量")

            local response = string.pack('>BBBBBBBBBB',0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
            socket.write(cID, response)
            -- 域名解析为IP
            -- skynet.error('[暂时不支持域名处理]')
        elseif atype == 0x04 then
            skynet.error('[暂时不支持IPv6]')
        else -- 返回错误
            skynet.error('[非法类型]')
        end
    
    end
end

-- negotiation
local function negotiation(cID, addr)
    socket.start(cID)
    local str = socket.read(cID)
    if str then
        skynet.error('[stage 1]')
        skynet.error(string.byte(str, 1, -1))
        local resp = string.pack('>BB',0x05, 0x00) -- 二进制数据流解包
        skynet.error(string.byte(resp, 1, -1))
        
        socket.write(cID, resp)
        skynet.fork(request, cID)
    else
        socket.close(cID)
        skynet.error(addr .. " disconnect")
        return
    end
end

local function accept(cID, addr)
    skynet.fork(negotiation, cID, addr) --来一个链接，就开一个新的协程来处理客户端数据
end

--服务入口
skynet.start(function()
    dns.server()
    local addr = "0.0.0.0:8001"
    skynet.error("listen " .. addr)
    local lID = socket.listen(addr)
    assert(lID)
    socket.start(lID, accept)
end)