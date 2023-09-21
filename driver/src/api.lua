local os = require "os"
local string = require "string"
local table = require "table"

local log = require "log"
local json = require "st.json"
local base64 = require "st.base64"
local utils = require "st.utils"
local mdns = require "st.mdns"

local Request = require "luncheon.request"
local Response = require "luncheon.response"
local socket = require "cosock.socket"
local net_url = require 'net.url'

local function parse_txt_record(tb, txt)
    for k, v in string.gmatch(txt, "([^=]+)=(.*)") do tb[k] = v end
end

local SERVICE_TYPE = "_ewelink._tcp"
local DOMAIN = "local"

--- func resolves host address
---@param deviceid string
---@return table or nil
local function resolve(deviceid)
    local hosts, err = mdns.resolve("eWeLink_" .. deviceid, SERVICE_TYPE, DOMAIN)
    if err or not hosts or #hosts == 0 then return nil, err or "Host not found" end
    return hosts[1]
end
local function discover()
    local mdns_responses, err = mdns.discover(SERVICE_TYPE, DOMAIN)
    if err ~= nil then
        log.error(err)
        return
    end

    if not (mdns_responses and mdns_responses.found and #mdns_responses.found > 0) then
        log.warn("No mdns responses for service this attempt, continuing...")
        return nil
    end
    for _, response in ipairs(mdns_responses.found) do
        if response.txt and response.txt.text then
            local records = {}
            for _, bytearr in ipairs(response.txt.text) do
                parse_txt_record(records, string.char(table.unpack(bytearr)))
            end
            response.txt = records
        end
    end
    return mdns_responses.found
end
local function get_request(method, url)
    if type(url) == 'string' then url = net_url.parse(url) end
    local sock, err = socket.tcp()
    if err then
        log.trace(err)
        return nil, err
    end
    _, err = sock:settimeout(60)
    if err then
        log.trace(err)
        return nil, err
    end
    _, err = sock:connect(url.host, url.port)
    if err then
        log.trace(err)
        return nil, err
    end
    return Request.new(method, url, sock)
end
local function generate_response(request, data)
    local success, err = request:send(json.encode(data))
    if err then
        log.trace(err)
        return nil, err
    end
    local resp, err = Response.tcp_source(request.socket)
    if err then
        log.trace(err)
        return nil, err
    end
    local body = resp:get_body()
    request.socket:close()
    return body, nil
end

-- crypto
require("lockbox").ALLOW_INSECURE = true
local MD5 = require "lockbox.digest.md5"
local AES128Cipher = require "lockbox.cipher.aes128"
local CBCMode = require "lockbox.cipher.mode.cbc"
local Stream = require "lockbox.util.stream"
local ZeroPadding = require "lockbox.padding.zero"

local function decrypt(devicekey, iv, data)
    local key = MD5().init().update(Stream.fromString(devicekey)).finish().asBytes()
    local decrypted = CBCMode.Decipher().setKey(key).setBlockCipher(AES128Cipher).setPadding(ZeroPadding).init().update(
                          Stream.fromString(iv)).update(Stream.fromString(data)).finish().asBytes()
    local npad = #decrypted - decrypted[#decrypted]
    return string.char(table.unpack(decrypted, 1, npad))
end

local function encrypt(devicekey, data)
    local iv = "5356665504675235"
    local key = MD5().init().update(Stream.fromString(devicekey)).finish().asBytes()
    local npad = AES128Cipher.blockSize - (#data % AES128Cipher.blockSize)
    local encrypted = CBCMode.Cipher().setKey(key).setBlockCipher(AES128Cipher).setPadding(ZeroPadding).init().update(
                          Stream.fromString(iv)).update(Stream.fromString(data .. string.rep(string.char(npad), npad)))
                          .finish().asBytes()
    return iv, string.char(table.unpack(encrypted))
end

local function build_message(deviceid, devicekey, params)
    local msg = {
        sequence = tostring(os.time()),
        deviceid = deviceid,
        selfApikey = "123"
    }
    if devicekey then
        local iv, data = encrypt(devicekey, json.encode(params))
        msg.iv = base64.encode(iv)
        msg.data = base64.encode(data)
        msg.encrypt = true
    end
    return msg
end

-- api

local api = {}
function api.send(deviceid, devicekey, command, params)
    local host_info, err = resolve(deviceid)
    if host_info == nil then return nil, err end
    local msg = build_message(deviceid, devicekey, params)
    -- log.trace(json.encode(msg))
    local url = "http://" .. host_info.address .. ":" .. host_info.port .. "/zeroconf/" .. command
    url = net_url.parse(url)
    local request = get_request("POST", url):set_content_type("application/json"):add_header("Connection", "close")
    local resp, err = generate_response(request, msg)
    -- log.trace(resp, err)
    return resp, err
end

function api.discover(last_seqs, last_seen, counter, logmdns)
    local records = discover()
    for idx, record in ipairs(records) do
        if logmdns then log.trace("broadcast:", utils.stringify_table(record)) end
        local deviceid = record.txt.id
        last_seen[deviceid] = counter
        if record.txt.seq == last_seqs[deviceid] then
            records[idx] = nil
        else
            last_seqs[deviceid] = record.txt.seq
        end
    end

    return records
end
function api.read_record(record, devicekey, logmdns)
    local deviceid = record.txt.id
    local data = base64.decode(record.txt.data1)
    if record.txt.encrypt then
        if devicekey == nil then return end
        data = decrypt(devicekey, base64.decode(record.txt.iv), data)
        if logmdns then log.trace("decrypted broadcast:", utils.stringify_table(data)) end
    end
    local success, result = pcall(json.decode, data)
    if not success then
        log.error("json.decode: ", result)
        return
    end
    return result
end
function api.download_info(url)
    if url then
        local request, err = get_request("GET", url)
        if err then return end
        local body = generate_response(request)
        if not body then return nil, err end
        local success, json_result = pcall(json.decode, body)
        if not success then return nil end
        return json_result
    end
end
return api
