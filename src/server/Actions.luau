--[[
	Actions — запросы клиента (ClientAction). Всё проверяется на сервере:
	типы аргументов, владение, цены, частота запросов.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Profile = require(Shared.Profile)

local Data = require(script.Parent.DataService)
local Monetization = require(script.Parent.Monetization)
local Cosmetics = require(script.Parent.Cosmetics)
local RaftService = require(script.Parent.RaftService)
local RaftModel = require(script.Parent.RaftModel)

local Actions = {}

Actions.selfTest = nil :: (() -> { string })?

local budget: { [Player]: { n: number, t: number } } = {}
local function allowed(player: Player): boolean
	local b = budget[player]
	local t = os.clock()
	if not b or t - b.t > 1 then
		budget[player] = { n = 1, t = t }
		return true
	end
	b.n += 1
	return b.n <= 15
end

local function toast(player: Player, key: string, vars: { [string]: any }?)
	Net.ServerEvent:FireClient(player, { t = "toast", key = key, vars = vars })
end

local function refreshSkins(player: Player)
	for _, raft in RaftService.rafts do
		if raft.captain == player and (raft.phase == "dock" or raft.phase == "countdown") then
			RaftModel.applySkin(raft.model, Cosmetics.effective(player, "raft"))
		end
	end
end

local handlers = {}

handlers.profile = function(player: Player)
	Monetization.sendProfile(player)
end

handlers.buyCoins = function(player: Player, payload)
	local id = payload.id
	if type(id) ~= "string" then
		return
	end
	local d = Data.get(player)
	if not d then
		return
	end
	local ok, err = Profile.buyWithCoins(d, id)
	if ok then
		Data.changed(player)
		Profile.equip(d, id, Monetization.hasPass(player, "Vip"))
		Cosmetics.refresh(player)
		refreshSkins(player)
		toast(player, "shop.bought", { item = "item." .. id })
	else
		toast(player, err or "shop.error")
	end
	Monetization.sendProfile(player)
end

handlers.equip = function(player: Player, payload)
	local id = payload.id
	if type(id) ~= "string" or not Catalog.get(id) then
		return
	end
	local d = Data.get(player)
	if d and Profile.equip(d, id, Monetization.hasPass(player, "Vip")) then
		Data.changed(player)
		Cosmetics.refresh(player)
		refreshSkins(player)
	end
	Monetization.sendProfile(player)
end

handlers.pass = function(player: Player, payload)
	if type(payload.key) == "string" and Config.Passes[payload.key] then
		Monetization.promptPass(player, payload.key)
	end
end

handlers.product = function(player: Player, payload)
	local key = payload.key
	if type(key) ~= "string" or not Config.Products[key] then
		return
	end
	local item = if type(payload.item) == "string" then payload.item else nil
	if key == "Revive" then
		local raft = RaftService.raftOf(player)
		if not raft or raft.phase ~= "wrecked" then
			return
		end
		RaftService.holdWreck(player)
	end
	Monetization.promptProduct(player, key, item)
end

handlers.leave = function(player: Player)
	RaftService.leave(player)
end

handlers.debug = function(player: Player, payload)
	if not RunService:IsStudio() then
		return
	end
	local cmd, arg = payload.cmd, payload.arg
	local msg
	if cmd == "coins" then
		local d = Data.get(player)
		if d then
			Profile.addCoins(d, tonumber(arg) or 1000)
			Data.changed(player)
			Monetization.sendProfile(player)
			msg = "coins " .. d.coins
		end
	elseif cmd == "selftest" then
		local fn = Actions.selfTest
		if fn then
			task.spawn(function()
				Net.ServerEvent:FireClient(player, { t = "selftest", lines = fn() })
			end)
		end
		return
	elseif cmd == "reset" then
		local d = Data.get(player)
		if d then
			local fresh = Profile.new()
			for k, v in fresh do
				(d :: any)[k] = v
			end
			Data.changed(player)
			Cosmetics.refresh(player)
			Monetization.sendProfile(player)
			msg = "profile reset"
		end
	else
		msg = RaftService.debug(player, tostring(cmd), arg)
	end
	if msg then
		toast(player, "debug.msg", { text = msg })
	end
end

function Actions.start()
	Net.ClientAction.OnServerEvent:Connect(function(player: Player, payload)
		if type(payload) ~= "table" or type(payload.t) ~= "string" then
			return
		end
		local h = handlers[payload.t]
		if not h or not allowed(player) then
			return
		end
		local ok, err = pcall(h, player, payload)
		if not ok then
			warn("[Actions]", payload.t, err)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		budget[p] = nil
	end)
end

return Actions
