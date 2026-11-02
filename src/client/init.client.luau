--[[
	Клиент: интерфейс, эффекты, реакции на события сервера.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rewards = require(Shared.Rewards)

local Ui = require(script.Ui)
local Lang = require(script.Lang)
local Hud = require(script.Hud)
local Shop = require(script.Shop)
local Fx = require(script.Fx)
local DebugPanel = require(script.DebugPanel)

local player = Players.LocalPlayer
local C = Ui.colors

-- ждём мир
while not Workspace:GetAttribute("WorldReady") do
	task.wait(0.2)
end

Ui.watchViewport()
Hud.build()
Shop.build()
Fx.build()
DebugPanel.build()

local function invite()
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and can then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end

Hud.onShop = function(tab)
	if tab then
		Shop.open(tab)
	else
		Shop.toggle()
	end
end
Hud.onInvite = invite
Fx.onShopPrompt = function()
	Shop.open("items")
end

local handlers = {}

handlers.profile = function(p)
	Hud.setProfile(p)
	Shop.setProfile(p)
end

handlers.toast = function(p)
	Hud.toast(Lang.t(p.key, p.vars))
end

handlers.board = function(p)
	Hud.boardedRaft = p.raftId
end

handlers.unboard = function()
	Hud.boardedRaft = nil
end

handlers.depart = function(p)
	Hud.boardedRaft = nil
	Fx.resetCoins()
	Hud.showSection("dock")
	Hud.toast(Lang.t("ui.depart"), C.gold)
	if p.crew > 1 then
		Hud.toast(
			Lang.t(
				"ui.crewBonus",
				{ n = p.crew, m = string.format("%.2f", Rewards.multiplier(p.crew, false, false)) }
			),
			C.good
		)
	end
	if p.sturdy then
		Hud.toast(Lang.t("ui.sturdy"), C.good)
	end
	Fx.play("Splash")
end

handlers.coin = function(p)
	Fx.hideCoin(p.id)
	Hud.coinPop(p.got)
	Fx.play("Coin")
end

handlers.gate = function(p)
	Hud.toast(Lang.t("ui.gate", { n = p.got }), C.gold)
	Hud.coinPop(p.got)
	Fx.play("Coin")
end

handlers.gateMiss = function()
	Hud.toast(Lang.t("ui.gateMiss"), C.dim)
end

handlers.hit = function(p)
	local key = if p.kind == "rock" then "ui.rock" elseif p.kind == "bank" then "ui.bank" else "ui.dropBad"
	Hud.toast(Lang.t(key, { n = p.damage }), C.danger)
	Fx.shake(if p.kind == "bank" then 0.3 else 1.2)
	Fx.play(if p.kind == "dropBad" then "Splash" else "Hit")
end

handlers.dropSafe = function()
	Hud.toast(Lang.t("ui.dropSafe"), C.good)
	Fx.play("Splash")
	Fx.shake(0.5)
end

handlers.warn = function(p)
	Hud.warn(Lang.t(p.key), if p.key == "warn.drop" then 6 else 4)
end

handlers.section = function(p)
	Hud.showSection(p.id)
end

handlers.rescued = function()
	Hud.toast(Lang.t("ui.rescued"), C.warn)
	Fx.play("Splash")
end

handlers.wreck = function(p)
	Hud.showWreck(p.deadline, p.canRevive)
	Fx.shake(1.5)
	Fx.play("Hit")
end

handlers.revived = function(p)
	Hud.hideWreck()
	Hud.toast(Lang.t("ui.revived", { name = p.by }), C.good)
end

handlers.sunk = function()
	Hud.hideWreck()
	Hud.toast(Lang.t("ui.sunk"), C.danger)
	Fx.play("Splash")
end

handlers.left = function()
	Hud.toast(Lang.t("ui.leftRaft"))
	Hud.hideWreck()
end

handlers.results = function(p)
	Hud.showResults(p)
	if p.finished then
		Hud.coinPop(p.bonus)
		Fx.play("Coin")
	end
end

handlers.chestResult = function(p)
	Shop.showReward(p.id, Lang.t("shop.chestGot"), if p.dup then p.refund else nil)
end

handlers.directResult = function(p)
	Shop.showReward(p.id, Lang.t("shop.directGot"), nil)
end

handlers.selftest = function(p)
	for _, line in p.lines do
		print(line)
	end
	Hud.toast(p.lines[#p.lines] or "selftest")
end

Net.ServerEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	local h = handlers[payload.t]
	if h then
		local ok, err = pcall(h, payload)
		if not ok then
			warn("[Client]", payload.t, err)
		end
	end
end)

Net.ClientAction:FireServer({ t = "profile" })

RunService.RenderStepped:Connect(function(dt)
	Hud.update()
	Fx.update(dt)
end)
