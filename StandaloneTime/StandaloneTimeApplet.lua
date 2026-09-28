local oo = require("loop.simple")
local Applet = require("jive.Applet")
local Framework = require("jive.ui.Framework")
local Timer = require("jive.ui.Timer")
local SocketUdp = require("jive.net.SocketUdp")
local Process = require("jive.net.Process")
local Resolver = require("applets.StandaloneTime.Resolver")
local string = require("string")
local tostring = tostring
local math = require("math")
local os = require("os")
local table = require("table")

local log = require("jive.utils.log").logger("StandaloneTime")
local jnt = jnt

module(..., Framework.constants)
oo.class(_M, Applet)

local NTP_PORT = 123
local TIMEOUT_MS = 5000
local START_DELAY_MS = 10000
local RETRY_DELAYS = { 60000, 300000, 900000, 3600000 }
local RESYNC_MS = 86400000
local SERVERS = { "time.google.com", "pool.ntp.org", "time.cloudflare.com" }
local started = false

-- Keep each literal below signed 32-bit range on the Radio's Lua runtime.
local NTP_EPOCH_HIGH = 2000000000
local NTP_EPOCH_LOW = 208988800

local function uint32(data, offset)
    local b1, b2 = string.byte(data, offset), string.byte(data, offset + 1)
    local b3, b4 = string.byte(data, offset + 2), string.byte(data, offset + 3)
    if not b4 then return nil end
    return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end

local function printableRefid(data)
    local out, printable = {}, true
    for i = 13, 16 do
        local b = string.byte(data, i)
        if not b then return "" end
        if b < 32 or b > 126 then printable = false else out[#out + 1] = string.char(b) end
    end
    if printable then return table.concat(out) end
    return ""
end

local function utcString(seconds)
    local t = os.date("!*t", seconds)
    if not t then return nil end
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
end

local function closeSocket(self)
    if self.socket then self.socket:close(); self.socket = nil end
end

local function stopTimer(self)
    if self.timer then self.timer:stop(); self.timer = nil end
end

local function schedule(self, delay, callback)
    if self.nextTimer then self.nextTimer:stop() end
    self.nextTimer = Timer(delay, function()
        self.nextTimer = nil
        callback()
    end, true)
    self.nextTimer:start()
end

local function beginNextServer(self)
    self.serverIndex = self.serverIndex + 1
    if self.serverIndex > #SERVERS then
        self.retryIndex = math.min(self.retryIndex + 1, #RETRY_DELAYS)
        local delay = RETRY_DELAYS[self.retryIndex]
        log:warn("StandaloneTime: all servers failed; retry in " .. tostring(delay) .. " ms")
        -- Restart the ordered list at server 1; index 0 is not a server.
        schedule(self, delay, function() self.serverIndex = 1; self:nextRequest() end)
    else
        schedule(self, 100, function() self:nextRequest() end)
    end
end

local function failAttempt(self, reason)
    log:error("StandaloneTime: server " .. tostring(self.server) .. " failed: " .. reason)
    closeSocket(self)
    stopTimer(self)
    beginNextServer(self)
end

local function runCommand(self, command, marker, callback)
    local output = ""
    local process = Process(jnt, command)
    self.process = process
    local finished = false
    local guard = Timer(10000, function()
        if not finished then
            finished = true
            log:error("StandaloneTime: command timeout: " .. command)
            self.process = nil
            callback(false, output)
        end
    end, true)
    self.commandTimer = guard
    guard:start()
    process:read(function(chunk, err)
        if finished then return end
        if err then output = output .. tostring(err)
        elseif chunk then output = output .. tostring(chunk)
        else
            finished = true
            guard:stop()
            self.commandTimer = nil
            self.process = nil
            local ok = string.find(output, marker, 1, true) ~= nil
            callback(ok, output)
        end
    end)
end

local function writeRtc(self, utc)
    local command = "hwclock -w -u >/dev/null 2>&1; rc=$?; echo STANDALONETIME_HWCLOCK_RC:$rc"
    runCommand(self, command, "STANDALONETIME_HWCLOCK_RC:0", function(ok, output)
        if not ok then
            log:error("StandaloneTime: hwclock -w -u failed: " .. output)
            beginNextServer(self)
            return
        end
        log:warn("StandaloneTime: hwclock -w -u succeeded")
        log:warn("StandaloneTime: Linux clock and RTC synchronized from NTP UTC = " .. utc)
        self.retryIndex = 0
        log:warn("StandaloneTime: next synchronization in 86400000 ms")
        schedule(self, RESYNC_MS, function() self.serverIndex = 1; self:nextRequest() end)
    end)
end

local function writeClock(self, unix)
    local utc = utcString(unix)
    if not utc then return failAttempt(self, "cannot format packet timestamp") end
    log:warn("StandaloneTime: setting Linux UTC from packet: " .. utc)
    local command = "date -u -s \"" .. utc .. "\" >/dev/null 2>&1; rc=$?; echo STANDALONETIME_DATE_RC:$rc"
    runCommand(self, command, "STANDALONETIME_DATE_RC:0", function(ok, output)
        if not ok then
            log:error("StandaloneTime: date -u -s failed: " .. output)
            beginNextServer(self)
            return
        end
        log:warn("StandaloneTime: date -u -s succeeded; writing RTC")
        writeRtc(self, utc)
    end)
end

local function responseSink(self, chunk, err)
    if err then return failAttempt(self, "UDP receive error: " .. tostring(err)) end
    if not chunk or not chunk.data then return end
    local data, length = chunk.data, string.len(chunk.data)
    log:warn("StandaloneTime: SNTP response received from " .. tostring(chunk.ip) .. ":" .. tostring(chunk.port))
    log:warn("StandaloneTime: NTP response length=" .. tostring(length))
    if length < 48 then return failAttempt(self, "short packet") end

    local first = string.byte(data, 1)
    local li = math.floor(first / 64) % 4
    local version = math.floor(first / 8) % 8
    local mode = first % 8
    -- NTP stratum is byte 2 (Lua's 1-based string indexing), not byte 9.
    local stratum = string.byte(data, 2)
    local refid = printableRefid(data)
    local refTs, orgTs = uint32(data, 17), uint32(data, 25)
    local recvTs, txTs = uint32(data, 33), uint32(data, 41)
    log:warn("StandaloneTime: NTP response LI=" .. tostring(li) .. " version=" .. tostring(version) ..
        " mode=" .. tostring(mode) .. " stratum=" .. tostring(stratum) .. " refid=\"" .. refid .. "\"")
    log:warn("StandaloneTime: timestamps ref=" .. tostring(refTs) .. " originate=" .. tostring(orgTs) ..
        " receive=" .. tostring(recvTs) .. " transmit=" .. tostring(txTs))
    if stratum == 0 then log:warn("StandaloneTime: stratum=0 reference/Kiss code=\"" .. refid .. "\"") end

    if mode ~= 4 or version < 3 or version > 4 or stratum < 1 or stratum > 15 then
        return failAttempt(self, "invalid NTP response")
    end
    if not txTs or txTs == 0 then return failAttempt(self, "zero transmit timestamp") end
    -- 2208988800 overflows on this Lua 5.1/ARM runtime; keep the split
    -- subtraction instead of reintroducing the unsafe literal.
    local unix = txTs - NTP_EPOCH_HIGH - NTP_EPOCH_LOW
    log:warn("StandaloneTime: NTP seconds = " .. tostring(txTs))
    log:warn("StandaloneTime: Unix seconds = " .. tostring(unix))
    if unix < 1500000000 or unix > 2000000000 then return failAttempt(self, "implausible transmit timestamp") end
    log:warn("StandaloneTime: valid SNTP response from " .. tostring(self.server))
    log:warn("StandaloneTime: UTC = " .. utcString(unix))
    closeSocket(self)
    stopTimer(self)
    writeClock(self, unix)
end

local function sendRequest(self, ip)
    self.socket = SocketUdp(jnt, function(chunk, err) responseSink(self, chunk, err) end)
    if not self.socket or not self.socket.t_sock then return failAttempt(self, "unable to create UDP socket") end
    local packet = string.char(0x23) .. string.rep(string.char(0), 47)
    if string.len(packet) ~= 48 or string.byte(packet, 1) ~= 0x23 then
        return failAttempt(self, "internal request validation failed")
    end
    self.socket:send(function() return packet end, ip, NTP_PORT)
    log:warn("StandaloneTime: SNTP request sent to " .. tostring(self.server) .. " (" .. tostring(ip) .. "):123")
    self.timer = Timer(TIMEOUT_MS, function() failAttempt(self, "timeout") end, true)
    self.timer:start()
end

local function resolveAndSend(self)
    local server = self.server
    local resolver = Resolver.new({ log = log })
    resolver:resolve(server, function(ip, err)
        if not ip then return failAttempt(self, "DNS failed: " .. tostring(err)) end
        sendRequest(self, ip)
    end)
end

function _M:nextRequest()
    self.server = SERVERS[self.serverIndex]
    log:warn("StandaloneTime: starting request for " .. tostring(self.server))
    resolveAndSend(self)
end

function init(self)
    if started then return end
    started = true
    self.serverIndex = 0
    self.retryIndex = 0
    log:warn("StandaloneTime: applet initialized; waiting for network/DNS readiness")
    self.startTimer = Timer(START_DELAY_MS, function()
        self.startTimer = nil
        self.serverIndex = 1
        self:nextRequest()
    end, true)
    self.startTimer:start()
end

function standaloneTimeStart(self)
    log:warn("StandaloneTime: applet started through service registration")
    return true
end

function free(self)
    if self.startTimer then self.startTimer:stop() end
    if self.nextTimer then self.nextTimer:stop() end
    if self.commandTimer then self.commandTimer:stop() end
    stopTimer(self)
    closeSocket(self)
end
