--[[
	Сервер + клиент в одном DataModel на заглушке движка.
	Проверяет: весь UI строится (свойства валидирует @lune/roblox), клиент переживает
	все события сервера, магазин показывает точные шансы, PolicyService прячет сундук,
	схема веса видит игрока на палубе.
	Запуск (после rojo build): lune run tests/engine/client_sim.luau build/game.rbxl
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./Sim")

local failures = {}
local function check(cond, msg)
	print((if cond then "  ✓ " else "  ✗ ") .. msg)
	if not cond then
		table.insert(failures, msg)
	end
end
local function waitUntil(fn, timeout)
	local t0 = os.clock()
	while not fn() do
		if os.clock() - t0 > timeout then
			return false
		end
		task.wait(0.05)
	end
	return true
end

roblox.implementMethod("SocialService", "CanSendGameInviteAsync", function()
	return true
end)

local game = Sim.loadPlace(process.args[1] or "build/game.rbxl")
local ws = game:GetService("Workspace")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Catalog = Sim.require(RS.Shared.Catalog)

local player = Sim.addPlayer("Tester")
Players.LocalPlayer = player
Sim.localPlayer = player
Sim.clientMode = true
roblox.Instance.new("PlayerGui").Parent = player
local cam = roblox.Instance.new("Camera")
cam.Parent = ws
ws.CurrentCamera = cam

local clientErrors = {}
local server = game:GetService("ServerScriptService").Server
Sim.runScript(server)
check(
	waitUntil(function()
		return ws:GetAttribute("WorldReady") == true and player.Character ~= nil
	end, 60),
	"server ready, character spawned"
)

local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local ok, err = pcall(function()
	Sim.runScript(client)
end)
check(ok, "client script starts" .. (if ok then "" else ": " .. tostring(err)))

-- кадры клиента и сервера
local rendering = true
task.spawn(function()
	local rs = game:GetService("RunService")
	while rendering do
		local okF, errF = pcall(function()
			Sim.signalOf(rs, "Heartbeat"):Fire(1 / 30)
			Sim.signalOf(rs, "RenderStepped"):Fire(1 / 30)
			Sim.stepPhysics()
		end)
		if not okF then
			table.insert(clientErrors, tostring(errF))
		end
		task.wait(1 / 30)
	end
end)

local gui = player.PlayerGui
check(
	waitUntil(function()
		return gui:FindFirstChild("RaftUI") ~= nil and gui.RaftUI:FindFirstChild("Hud") ~= nil
	end, 10),
	"HUD built"
)
local ui = gui.RaftUI
local hud = ui.Hud
check(
	ui:FindFirstChild("Shop") ~= nil
		and ui:FindFirstChild("Results") ~= nil
		and ui:FindFirstChild("Wreck") ~= nil,
	"panels built"
)
check(
	waitUntil(function()
		return hud.TopLeft.Coins:FindFirstChildWhichIsA("TextLabel").Text == "0"
	end, 5),
	"coins shown from profile"
)

print("== world text is localized")
local signText
for _, d in ws:GetDescendants() do
	if d.ClassName == "TextLabel" and d:GetAttribute("TextKey") then
		signText = d
		break
	end
end
check(
	signText and signText.Text ~= signText:GetAttribute("TextKey"),
	"sign text localized: " .. tostring(signText and signText.Text)
)
local prompt = ws.Dock.Chest:FindFirstChildOfClass("ProximityPrompt")
check(prompt.ActionText ~= "prompt.shop", "prompt localized: " .. prompt.ActionText)

print("== boarding shows the crew weight")
local RaftService = Sim.require(server.RaftService)
local raft
for _, r in RaftService.rafts do
	raft = r
end
local root = player.Character.HumanoidRootPart
root.CFrame = raft.hull.CFrame * roblox.CFrame.new(4, 4, 0)
check(
	waitUntil(function()
		return hud.Balance.Visible == true
	end, 3),
	"balance widget appears on deck"
)
check(#hud.Balance.Deck.Dots:GetChildren() == 1, "my dot is drawn")
local marker = hud.Balance.Deck.Center
check(marker.Position.X.Scale > 0.6, "center of mass marker moves right (" .. marker.Position.X.Scale .. ")")
check(
	waitUntil(function()
		return string.find(hud.DockInfo.Text, "%d") ~= nil
	end, 3),
	"countdown shown: " .. hud.DockInfo.Text
)

check(
	waitUntil(function()
		return player:GetAttribute("RaftId") ~= nil
	end, 8),
	"raft departs with me aboard"
)

print("== server events")
local RE = RS.Remotes.ServerEvent
local function ev(payload)
	Sim.signalOf(RE, "OnClientEvent"):Fire(payload)
	task.wait(0.05)
end
ev({ t = "depart", raftId = raft.id, crew = 3, mult = 1.3, sturdy = true })
ev({ t = "coin", id = 1, value = 1, got = 1 })
local coin = ws.River.Coins:FindFirstChild("1")
check(coin.Transparency == 1, "collected coin hidden for me")
ev({ t = "gate", id = 1, got = 3 })
ev({ t = "gateMiss", id = 2 })
ev({ t = "hit", kind = "rock", damage = 20 })
ev({ t = "hit", kind = "bank", damage = 2 })
ev({ t = "hit", kind = "dropBad", damage = 30 })
ev({ t = "dropSafe" })
ev({ t = "warn", key = "warn.drop" })
check(hud.Warn.Visible and hud.Warn.Text ~= "warn.drop", "waterfall warning shown")
ev({ t = "section", id = "canyon" })
check(hud.Section.Visible, "section title shown")
ev({ t = "rescued" })
ev({ t = "toast", key = "shop.coinsAdded", vars = { n = 500 } })
ev({ t = "wreck", deadline = ws:GetServerTimeNow() + 10, canRevive = true })
check(ui.Wreck.Visible and ui.Wreck.Revive.Visible, "wreck panel with second chance")
check(hud.TopLeft.LeaveButton ~= nil, "leave button in the left column")
ev({ t = "revived", by = "Bob" })
check(not ui.Wreck.Visible, "wreck panel hides after revive")
ev({ t = "sunk" })
ev({ t = "left" })
ev({ t = "depart", raftId = raft.id, crew = 1, mult = 1, sturdy = false })
check(coin.Transparency == 0, "coins visible again on a new run")
ev({
	t = "results",
	finished = true,
	time = 152.4,
	coins = 118,
	bonus = 50,
	hp = 100,
	maxHp = 100,
	gates = 5,
	gatesTotal = 5,
	falls = 1,
	crew = 2,
	best = 150,
	newBest = true,
	mult = 1.15,
})
check(
	ui.Results.Visible and string.find(ui.Results:FindFirstChildWhichIsA("TextLabel").Text, "!") ~= nil,
	"results panel"
)
ev({ t = "selftest", lines = { "[SELFTEST] RESULT 1/1 passed, 0 warnings" } })

print("== shop")
hud.TopLeft.ShopButton:FindFirstChildWhichIsA("UICorner")
Sim.signalOf(hud.TopLeft.ShopButton, "Activated"):Fire()
task.wait(0.3)
local shop = ui.Shop
check(shop.Visible, "shop opens from the HUD button")
local cards = 0
for _, d in shop.Body:GetDescendants() do
	if d.ClassName == "Frame" and Catalog.get(d.Name) then
		cards += 1
	end
end
check(cards == #Catalog.Items, "all items shown (" .. cards .. ")")
-- купить за монеты без монет
local function limeBuy()
	for _, d in shop.Body:GetDescendants() do
		if d.Name == "vest_lime" then
			return d:FindFirstChildWhichIsA("TextButton")
		end
	end
	return nil
end
Sim.signalOf(limeBuy(), "Activated"):Fire()
task.wait(0.2)
local Data = Sim.require(server.DataService)
check(not Data.get(player).owned.vest_lime, "no coins → not bought")
Data.get(player).coins = 999
task.wait(1.1) -- лимит частоты запросов
Sim.signalOf(limeBuy(), "Activated"):Fire()
check(
	waitUntil(function()
		return Data.get(player).owned.vest_lime == true
	end, 2),
	"buy for coins through the UI"
)

Sim.signalOf(shop.Tab_chest, "Activated"):Fire()
task.wait(0.3)
local odds = 0
for _, d in shop.Body:GetChildren() do
	if string.sub(d.Name, 1, 5) == "Odds_" then
		odds += 1
		check(string.find(d.Text, "%%") ~= nil, "odds line has a percent: " .. d.Text)
		break
	end
end
for _, d in shop.Body:GetChildren() do
	if string.sub(d.Name, 1, 5) == "Odds_" then
		odds += 1
	end
end
check(odds - 1 == #Catalog.odds(), "every chest item has its exact chance (" .. (odds - 1) .. ")")
check(shop.Body:FindFirstChild("OpenChest") ~= nil, "chest button shown where allowed")
Sim.signalOf(shop.Body.OpenChest, "Activated"):Fire()
check(
	waitUntil(function()
		return ui.Reward.Visible == true
	end, 3),
	"chest result popup"
)

-- регион с запретом
Sim.policyRestricted = true
local Monetization = Sim.require(server.Monetization)
Sim.policyFail = false
-- сбрасываем кэш политики: игрок «перезашёл»
Sim.signalOf(Players, "PlayerRemoving"):Fire(player)
task.wait(0.1)
Sim.signalOf(Players, "PlayerAdded"):Fire(player)
task.wait(0.3)
Data.load(player)
task.wait(0.2)
Sim.signalOf(shop.Tab_chest, "Activated"):Fire()
task.wait(0.4)
check(shop.Body:FindFirstChild("OpenChest") == nil, "restricted region: no chest button")
_ = Monetization
Sim.policyRestricted = false

Sim.signalOf(shop.Tab_passes, "Activated"):Fire()
task.wait(0.2)
check(
	shop.Body:FindFirstChild("Vip") ~= nil and shop.Body:FindFirstChild("Coins3000") ~= nil,
	"passes and coin packs"
)
Sim.signalOf(shop.Close, "Activated"):Fire()
check(not shop.Visible, "shop closes")

print("== invite")
Sim.signalOf(hud.TopLeft.InviteButton, "Activated"):Fire()
task.wait(0.1)
check((Sim.invites or 0) >= 1, "invite prompt")

print("== debug panel")
local dbg = ui:FindFirstChild("DebugToggle")
check(dbg ~= nil, "debug button in Studio")

task.wait(0.5)
rendering = false
task.wait(0.1)
for _, e in clientErrors do
	print("    " .. e)
end
check(#clientErrors == 0, "no errors in frame loop")
local clientWarns = 0
for _, w in Sim.warnings or {} do
	if string.find(w, "[Client]", 1, true) or string.find(w, "error", 1, true) then
		clientWarns += 1
		print("    " .. w)
	end
end
check(clientWarns == 0, "no client handler errors")
print(string.format("\n%d failures", #failures))
process.exit(if #failures > 0 then 1 else 0)
