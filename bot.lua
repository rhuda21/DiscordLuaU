local bot = {}
bot.running = true

if _G.BOT_INSTANCE and _G.BOT_INSTANCE.cleanup then
	_G.BOT_INSTANCE.cleanup()
end

local BotConfig = require(script.BotConfig)
local COMMANDS = require(script.Commands)
local GUILD_ID = BotConfig.guildId
local PREFIX = BotConfig.prefix or "!"
local http = game:GetService("HttpService")
local DEBUG = true

local BASE_URL = "https://discord.com/api/v10" -- you will need to use a proxy if u want to use inside Roblox game
local headers = { ["Content-Type"] = "application/json" }
local lastProcessedIds = {}
local slashHandlers = {}
local reactionHandlers = {}
local currentMessage = nil

local function DebugConsole(content, warn_type)
	if not DEBUG then return end
	if warn_type == "warn" then warn(content) else print(content) end
end

local function makeRequest(method, endpoint, data)
	local url = BASE_URL .. endpoint
	local success, response = pcall(function()
		return http:RequestAsync({
			Url = url,
			Method = method,
			Headers = {
				["Content-Type"] = "application/json",
				["X-User-Id"]    = currentMessage and currentMessage.author.id or "",
				["X-Channel-Id"] = currentMessage and currentMessage.channel_id or "",
				["X-Message-Id"] = currentMessage and currentMessage.id or "",
			},
			Body = data and http:JSONEncode(data) or nil
		})
	end)
	if not success then return nil end
	if not response.Success then
		DebugConsole("HTTP " .. method .. " " .. endpoint .. " failed: " .. response.StatusCode, "warn")
		return nil
	end
	if response.Body and response.Body ~= "" then
		local ok, result = pcall(function() return http:JSONDecode(response.Body) end)
		return ok and result or nil
	end
	return true
end

local function sendMessage(channelId, content)
	return makeRequest("POST", "/channels/" .. channelId .. "/messages", { content = content })
end

local function sendEmbed(channelId, embedData)
	local embed = {
		title       = embedData.title or "",
		description = embedData.description or "",
		color       = embedData.color or 14893841,
		fields      = embedData.fields or {},
		footer      = embedData.footer,
		image       = embedData.image and { url = embedData.image } or nil,
		thumbnail   = embedData.thumbnail and { url = embedData.thumbnail } or nil,
		author      = embedData.author,
		timestamp   = embedData.timestamp and os.date("!%Y-%m-%dT%H:%M:%SZ", embedData.timestamp) or nil,
	}
	return makeRequest("POST", "/channels/" .. channelId .. "/messages", { embeds = { embed } })
end

local function replyToMessage(channelId, messageId, content)
	return makeRequest("POST", "/channels/" .. channelId .. "/messages", {
		content = content,
		message_reference = { message_id = messageId }
	})
end

local function replyWithEmbed(channelId, messageId, embedData)
	local embed = {
		title       = embedData.title or "",
		description = embedData.description or "",
		color       = embedData.color or 14893841,
		fields      = embedData.fields or {},
		footer      = embedData.footer,
		image       = embedData.image and { url = embedData.image } or nil,
		thumbnail   = embedData.thumbnail and { url = embedData.thumbnail } or nil,
	}
	return makeRequest("POST", "/channels/" .. channelId .. "/messages", {
		embeds = { embed },
		message_reference = { message_id = messageId }
	})
end

local function editMessage(channelId, messageId, newContent)
	return makeRequest("PATCH", "/channels/" .. channelId .. "/messages/" .. messageId, { content = newContent })
end

local function deleteMessage(channelId, messageId)
	return makeRequest("DELETE", "/channels/" .. channelId .. "/messages/" .. messageId)
end

local function pinMessage(channelId, messageId)
	return makeRequest("PUT", "/channels/" .. channelId .. "/pins/" .. messageId)
end

local function getMessages(channelId, limit, afterId)
	local query = "?limit=" .. tostring(limit or 10)
	if afterId then query = query .. "&after=" .. afterId end
	return makeRequest("GET", "/channels/" .. channelId .. "/messages" .. query)
end

local function addReaction(channelId, messageId, emoji)
	return makeRequest("PUT", "/channels/" .. channelId .. "/messages/" .. messageId .. "/reactions/" .. http:UrlEncode(emoji) .. "/@me")
end

local function removeReaction(channelId, messageId, emoji)
	return makeRequest("DELETE", "/channels/" .. channelId .. "/messages/" .. messageId .. "/reactions/" .. http:UrlEncode(emoji) .. "/@me")
end

local function clearReactions(channelId, messageId)
	return makeRequest("DELETE", "/channels/" .. channelId .. "/messages/" .. messageId .. "/reactions")
end

local function onReaction(messageId, emoji, callback)
	if not reactionHandlers[messageId] then reactionHandlers[messageId] = {} end
	reactionHandlers[messageId][emoji] = callback
end

local function dmUser(userId, title, content)
	local channel = makeRequest("POST", "/users/@me/channels", { recipient_id = userId })
	if not channel or not channel.id then return nil end
	return sendEmbed(channel.id, { title = title, description = content })
end

local function dmRaw(userId, content)
	local channel = makeRequest("POST", "/users/@me/channels", { recipient_id = userId })
	if not channel or not channel.id then return nil end
	return sendMessage(channel.id, content)
end

local function getGuildChannels(guildId)
	return makeRequest("GET", "/guilds/" .. guildId .. "/channels")
end

local function createChannel(guildId, name, channelType, topic)
	return makeRequest("POST", "/guilds/" .. guildId .. "/channels", {
		name = name, type = channelType or 0, topic = topic
	})
end

local function deleteChannel(channelId)
	return makeRequest("DELETE", "/channels/" .. channelId)
end

local function setChannelTopic(channelId, topic)
	return makeRequest("PATCH", "/channels/" .. channelId, { topic = topic })
end

local function sendToAllChannels(guildId, content, filter)
	local channels = getGuildChannels(guildId)
	if not channels then return end
	for _, channel in ipairs(channels) do
		if channel.type == 0 then
			if not filter or filter(channel) then
				sendMessage(channel.id, content)
				task.wait(0.5)
			end
		end
	end
end

local function getGuildRoles(guildId)
	return makeRequest("GET", "/guilds/" .. guildId .. "/roles")
end

local function addRole(guildId, userId, roleId)
	return makeRequest("PUT", "/guilds/" .. guildId .. "/members/" .. userId .. "/roles/" .. roleId)
end

local function removeRole(guildId, userId, roleId)
	return makeRequest("DELETE", "/guilds/" .. guildId .. "/members/" .. userId .. "/roles/" .. roleId)
end

local function createRole(guildId, name, color, permissions)
	return makeRequest("POST", "/guilds/" .. guildId .. "/roles", {
		name = name, color = color or 0, permissions = permissions or "0"
	})
end

local function deleteRole(guildId, roleId)
	return makeRequest("DELETE", "/guilds/" .. guildId .. "/roles/" .. roleId)
end

local function getMember(guildId, userId)
	return makeRequest("GET", "/guilds/" .. guildId .. "/members/" .. userId)
end

local function getMembers(guildId, limit)
	return makeRequest("GET", "/guilds/" .. guildId .. "/members?limit=" .. tostring(limit or 100))
end

local function kickMember(guildId, userId)
	return makeRequest("DELETE", "/guilds/" .. guildId .. "/members/" .. userId)
end

local function banMember(guildId, userId, reason, deleteMessageDays)
	return makeRequest("PUT", "/guilds/" .. guildId .. "/bans/" .. userId, {
		reason = reason or "", delete_message_days = deleteMessageDays or 0
	})
end

local function unbanMember(guildId, userId)
	return makeRequest("DELETE", "/guilds/" .. guildId .. "/bans/" .. userId)
end

local function setNickname(guildId, userId, nickname)
	return makeRequest("PATCH", "/guilds/" .. guildId .. "/members/" .. userId, { nick = nickname })
end

local function timeoutMember(guildId, userId, durationSeconds)
	return makeRequest("PATCH", "/guilds/" .. guildId .. "/members/" .. userId, {
		communication_disabled_until = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() + durationSeconds)
	})
end

local function registerSlashCommand(guildId, name, description, options)
	return makeRequest("POST", "/applications/@me/guilds/" .. guildId .. "/commands", {
		name = name, description = description, options = options or {}
	})
end

local function getSlashCommands(guildId)
	return makeRequest("GET", "/applications/@me/guilds/" .. guildId .. "/commands")
end

local function deleteSlashCommand(guildId, commandId)
	return makeRequest("DELETE", "/applications/@me/guilds/" .. guildId .. "/commands/" .. commandId)
end

local function onSlashCommand(name, callback)
	slashHandlers[name:lower()] = callback
end

local function respondToInteraction(interactionId, interactionToken, content, ephemeral)
	return makeRequest("POST", "/interactions/" .. interactionId .. "/" .. interactionToken .. "/callback", {
		type = 4,
		data = { content = content, flags = ephemeral and 64 or nil }
	})
end

local function respondWithEmbed(interactionId, interactionToken, embedData, ephemeral)
	return makeRequest("POST", "/interactions/" .. interactionId .. "/" .. interactionToken .. "/callback", {
		type = 4,
		data = {
			embeds = {{ title = embedData.title or "", description = embedData.description or "", color = embedData.color or 14893841, fields = embedData.fields or {} }},
			flags = ephemeral and 64 or nil
		}
	})
end

local function deferInteraction(interactionId, interactionToken)
	return makeRequest("POST", "/interactions/" .. interactionId .. "/" .. interactionToken .. "/callback", { type = 5 })
end

local function followUpInteraction(interactionToken, content)
	return makeRequest("POST", "/webhooks/@me/" .. interactionToken, { content = content })
end

local function getGuild(guildId)
	return makeRequest("GET", "/guilds/" .. guildId)
end

local function getGuildEmojis(guildId)
	return makeRequest("GET", "/guilds/" .. guildId .. "/emojis")
end

local function createInvite(channelId, maxAge, maxUses)
	return makeRequest("POST", "/channels/" .. channelId .. "/invites", {
		max_age = maxAge or 86400, max_uses = maxUses or 0
	})
end

local function handleCommand(message)
	if message.author.bot then return end
	currentMessage = message
	local args = {}
	for word in message.content:gmatch("%S+") do table.insert(args, word) end
	if #args == 0 then return end
	local commandName = args[1]:sub(#PREFIX + 1):lower()
	table.remove(args, 1)
	local command = COMMANDS[commandName]
	if not command or not command.execute then
		sendMessage(message.channel_id, "❌ Unknown command. Type `" .. PREFIX .. "help` for a list of commands.")
		return
	end
	local success, result = pcall(function() return command.execute(message, table.unpack(args)) end)
	if not success then
		sendMessage(message.channel_id, "❌ An error occurred: " .. tostring(result))
		return
	end
	if result then
		if type(result) == "table" and result.embed then
			sendEmbed(message.channel_id, result.embed)
		elseif type(result) == "table" and result.reply then
			replyToMessage(message.channel_id, message.id, result.reply)
		else
			sendMessage(message.channel_id, tostring(result))
		end
	end
end

local function processMessages(channelId, messages)
	if not messages or type(messages) ~= "table" or #messages == 0 then return end
	local newestId = messages[1].id
	for _, msg in ipairs(messages) do
		if msg.id > newestId then newestId = msg.id end
	end
	if not lastProcessedIds[channelId] then
		lastProcessedIds[channelId] = newestId
		return
	end
	for _, message in ipairs(messages) do
		if message.id > lastProcessedIds[channelId] then
			DebugConsole("[#" .. channelId .. "] " .. message.author.username .. ": " .. message.content)
			if not message.author.bot and string.sub(message.content or "", 1, #PREFIX) == PREFIX then
				handleCommand(message)
			end
		end
	end
	lastProcessedIds[channelId] = newestId
end

local function pollAllChannels()
	local channels = getGuildChannels(GUILD_ID)
	if not channels then return end
	for _, channel in ipairs(channels) do
		if channel.type == 0 then
			local messages = getMessages(channel.id, 10, lastProcessedIds[channel.id])
			if messages and type(messages) == "table" then
				processMessages(channel.id, messages)
			end
			task.wait(0.2)
		end
	end
end

function bot.cleanup()
	if bot.running then
		bot.running = false
		if BotConfig.channel then
			pcall(function() sendMessage(BotConfig.channel, "Bot is going offline. Bye! 👋") end)
		end
	end
end
bot.sendMessage            = sendMessage
bot.sendEmbed              = sendEmbed
bot.replyToMessage         = replyToMessage
bot.replyWithEmbed         = replyWithEmbed
bot.editMessage            = editMessage
bot.deleteMessage          = deleteMessage
bot.pinMessage             = pinMessage
bot.getMessages            = getMessages
bot.addReaction            = addReaction
bot.removeReaction         = removeReaction
bot.clearReactions         = clearReactions
bot.onReaction             = onReaction
bot.dmUser                 = dmUser
bot.dmRaw                  = dmRaw
bot.getGuildChannels       = getGuildChannels
bot.createChannel          = createChannel
bot.deleteChannel          = deleteChannel
bot.setChannelTopic        = setChannelTopic
bot.sendToAllChannels      = sendToAllChannels
bot.getGuildRoles          = getGuildRoles
bot.addRole                = addRole
bot.removeRole             = removeRole
bot.createRole             = createRole
bot.deleteRole             = deleteRole
bot.getMember              = getMember
bot.getMembers             = getMembers
bot.kickMember             = kickMember
bot.banMember              = banMember
bot.unbanMember            = unbanMember
bot.setNickname            = setNickname
bot.timeoutMember          = timeoutMember
bot.registerSlashCommand   = registerSlashCommand
bot.getSlashCommands       = getSlashCommands
bot.deleteSlashCommand     = deleteSlashCommand
bot.onSlashCommand         = onSlashCommand
bot.respondToInteraction   = respondToInteraction
bot.respondWithEmbed       = respondWithEmbed
bot.deferInteraction       = deferInteraction
bot.followUpInteraction    = followUpInteraction
bot.getGuild               = getGuild
bot.getGuildEmojis         = getGuildEmojis
bot.createInvite           = createInvite
_G.BOT_INSTANCE = bot
task.spawn(function()
	DebugConsole("[Bot] Starting up...")
	if BotConfig.channel then
		pcall(function() sendMessage(BotConfig.channel, "✅ Bot online! Type `" .. PREFIX .. "help` for commands.") end)
	end
	local channels = getGuildChannels(GUILD_ID)
	if channels then
		for _, channel in ipairs(channels) do
			if channel.type == 0 then
				local msgs = getMessages(channel.id, 1)
				if msgs and type(msgs) == "table" and #msgs > 0 then
					lastProcessedIds[channel.id] = msgs[1].id
				end
			end
		end
		DebugConsole("[Bot] Seeded " .. #channels .. " channels")
	end
	while bot.running do
		local ok, err = pcall(pollAllChannels)
		if not ok then DebugConsole("[Bot] Poll error: " .. tostring(err), "warn") end
		task.wait(3)
	end
	bot.cleanup()
end)
return bot
