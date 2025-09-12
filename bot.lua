 -- Setup Bot Instance --
local bot = {}
bot.running = true

-- Unload Existing Bot Instance --
if _G.BOT_INSTANCE and _G.BOT_INSTANCE.cleanup then
    _G.BOT_INSTANCE.cleanup()
end

local BotConfig = loadfile("BotConfig.lua")() or _G.BotCfg -- Bot Configuration File
local BOT_TOKEN = BotConfig.token
local COMMANDS = BotConfig.commands
local CHANNEL_ID = BotConfig.channel
local PREFIX = BotConfig.prefix or "!"
local http = game:GetService("HttpService")
local DEBUG = true -- Debug Mode to show ALL detail in Console

local dm_user = bot.dm_user

local function DebugConsole(content,type)
    if DEBUG then 
        if type == "warn" then 
            warn(content) 
        else 
            print(content) 
        end
    end
end
local function prettyPrintJson(jsonString)
    local result = ""
    local indentLevel = 0
    local inString = false  
    for i = 1, #jsonString do
        local char = jsonString:sub(i,i)
        if char == '"' and jsonString:sub(i-1,i-1) ~= "\\" then
            inString = not inString
        end
        if not inString then
            if char == "{" or char == "[" then
                result = result .. char .. "\n" .. string.rep("  ", indentLevel + 1)
                indentLevel = indentLevel + 1
            elseif char == "}" or char == "]" then
                indentLevel = indentLevel - 1
                result = result .. "\n" .. string.rep("  ", indentLevel) .. char
            elseif char == "," then
                result = result .. char .. "\n" .. string.rep("  ", indentLevel)
            elseif char == ":" then
                result = result .. char .. " "
            else
                result = result .. char
            end
        else
            result = result .. char
        end
    end
    return result
end
local json = "Data.json"
if not isfile(json) then writefile(json,"{}") end

local function SaveFile(filename, data, options)
    options = options or {}
    local fileData = {}
    if isfile(filename) then
        local success, loaded = pcall(function()
            return http:JSONDecode(readfile(filename))
        end)
        if success and loaded then
            fileData = loaded
        end
    end
    if options.mode == "append" and options.path then
        local current = fileData
        local path = {}
        for part in options.path:gmatch("[^%.]+") do
            table.insert(path, part)
        end
        for i, part in ipairs(path) do
            if i == #path then
                current[part] = current[part] or {}
                if type(current[part]) == "table" then
                    table.insert(current[part], data)
                else
                    current[part] = data
                end
            else
                current[part] = current[part] or {}
                current = current[part]
            end
        end
    elseif options.mode == "set" and options.path then
        local current = fileData
        local path = {}
        for part in options.path:gmatch("[^%.]+") do
            table.insert(path, part)
        end
        for i, part in ipairs(path) do
            if i == #path then
                current[part] = data
            else
                current[part] = current[part] or {}
                current = current[part]
            end
        end
    else
        fileData = data
    end
    local jsonStr = prettyPrintJson(http:JSONEncode(fileData))
    writefile(filename, jsonStr)
    return true
end

local function LoadFile(filename)
    if not isfile(filename) then return {} end
    local success, data = pcall(function()
        return http:JSONDecode(readfile(filename))
    end)
    return success and data or {}
end

local BASE_URL = "https://discord.com/api/v10" -- Discord Endpoint
local headers = {
    ["Authorization"] = "Bot " .. BOT_TOKEN,
    ["Content-Type"] = "application/json",
    ["User-Agent"] = "My Discord Bot"
}
local lastProcessedMessageId = nil

function parseDiscordTimestamp(isoTimestamp)
    local year, month, day, hour, min, sec = isoTimestamp:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    })
end

function makeRequest(method, endpoint, data)
    local url = BASE_URL .. endpoint
    local jsonData = data and http:JSONEncode(data) or nil
    local success, response = pcall(function()
        if syn then
            return syn.request({
                Url = url,
                Method = method,
                Headers = headers,
                Body = jsonData
            })
        else
            return request({
                Url = url,
                Method = method,
                Headers = headers,
                Body = jsonData
            })
        end
    end)
    if success then
        if response.Success then
            if response.Body and response.Body ~= "" then
                local parsed, result = pcall(function() 
                    return http:JSONDecode(response.Body) 
                end)
                if parsed then
                    return result
                else
                    DebugConsole("Failed to parse JSON response:" .. response.Body,"warn")
                    return nil
                end
            else
                return true
            end
        else
            warn("HTTP request failed. Status:", response.StatusCode, response.StatusMessage)
            if response.Body then
                warn("Response body:", response.Body)
            end
            return nil
        end
    else
        return nil
    end
end

function sendMessage(channelId, content)
    print("Attempting to send message:", content)
    local result = makeRequest("POST", "/channels/" .. channelId .. "/messages", {
        content = content
    })
    if result then
        return result
    else
        print("Failed to send message")
        return nil
    end
end

function SendMessageEMBED(channelId, embedData)
    local embed = {
        title = embedData.title or "",
        description = embedData.description or "",
        color = embedData.color or 14893841,
        fields = embedData.fields or {},
        footer = embedData.footer,
        image = embedData.image and { url = embedData.image } or nil,
        thumbnail = embedData.thumbnail and { url = embedData.thumbnail } or nil,
        author = embedData.author,
        timestamp = embedData.timestamp and os.date("!%Y-%m-%dT%H:%M:%SZ", embedData.timestamp) or nil
    }
    for k, v in pairs(embed) do
        if v == nil then
            embed[k] = nil
        end
    end
    local result = makeRequest("POST", "/channels/" .. channelId .. "/messages", {
        embeds = {embed}
    })
    if result then
        return result
    else
        print("Failed to send embed message")
        return nil
    end
end
function dm_user(title,content, user_id)
    local channel_result = makeRequest("POST", "/users/@me/channels", {
        recipient_id = user_id
    })
    if channel_result and channel_result.id then
        SendMessageEMBED(channel_result.id, {
            title = title,
            description = content,
            color = 14893841,
        })
        if SendMessageEMBED then
            DebugConsole("DM sent successfully to user ID: " .. user_id)
            return true
        else
            DebugConsole("Failed to send embed message to DM channel")
            local fallback = makeRequest("POST", "/channels/" .. channel_result.id .. "/messages", {
                content = content
            })
            return fallback
        end
    else
        DebugConsole("Failed to create DM channel with user ID: " .. user_id)
        return nil
    end
end
function getMessages(channelId, limit)
    limit = limit or 10
    return makeRequest("GET", "/channels/" .. channelId .. "/messages?limit=" .. tostring(limit))
end

function processMessages(messages)
    if not messages or type(messages) ~= "table" or #messages == 0 then
        print("No messages to process")
        return
    end
    local newestMessageId = messages[1].id
    for _, message in ipairs(messages) do
        if message.id > newestMessageId then
            newestMessageId = message.id
        end
    end
    if not lastProcessedMessageId then
        lastProcessedMessageId = newestMessageId
        return
    end
    for _, message in ipairs(messages) do
        if message.id > lastProcessedMessageId then
            print("New message from " .. message.author.username .. ": " .. message.content)
            if not message.author.bot and string.sub(message.content or "", 1, 1) == "!" then
                handleCommand(message)
            end
        end
    end
    lastProcessedMessageId = newestMessageId
end

function handleCommand(message)
    if message.author.bot then return end
    local content = message.content
    if not content:sub(1, #PREFIX) == PREFIX then return end
    local args = {}
    for word in content:gmatch("%S+") do
        table.insert(args, word)
    end
    if #args == 0 then return end
    local commandName = args[1]:sub(#PREFIX + 1):lower()
    table.remove(args, 1)
    local command = COMMANDS[commandName]
    if command and command.execute then
        local success, result = pcall(function()
            return command.execute(message, table.unpack(args))
        end)
        if not success then
            print("Command error:", result)
            sendMessage(message.channel_id, "❌ An error occurred: " .. tostring(result))
            return
        end
        if result then
            if type(result) == "table" and result.embed then
                SendMessageEMBED(message.channel_id, result.embed)
            else
                sendMessage(message.channel_id, tostring(result))
            end
        end
    else
        print("Unknown command:", commandName)
        sendMessage(message.channel_id, "❌ Unknown command. Type `!help` for a list of commands.")
    end
end
if _G.BOT_INSTANCE and _G.BOT_INSTANCE.cleanup then
    _G.BOT_INSTANCE.cleanup()
end
_G.BOT_INSTANCE = bot
function bot.cleanup()
    if bot.running then
        print("Shutting down bot...")
        pcall(function()
            sendMessage(CHANNEL_ID, "Bot is going offline. Bye!")
        end)
        bot.running = false
    end
end
task.spawn(function()
    pcall(function()
        sendMessage(CHANNEL_ID, "Bot is now online! Type !help for commands.")
    end)
    while bot.running do
        local success, messages = pcall(function()
            return getMessages(CHANNEL_ID, 10)
        end)
        if success and messages then
            processMessages(messages)
        else
            warn("Failed to get messages")
        end
        for i = 1, 3 do
            if not bot.running then break end
            task.wait(1)
        end
    end
    bot.cleanup()
end)
return bot
