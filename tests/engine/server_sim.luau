--[[
	Прогон сервера на заглушке движка: мир строится, игроки садятся на плот,
	боты правят ВЕСОМ (встают в нужные точки палубы), плот проходит реку,
	монеты начисляются, покупки и PolicyService работают.
	Запуск (после rojo build): lune run tests/engine/server_sim.luau build/game.rbxl
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./Sim")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local failures = {}
local function check(cond, msg)
	print((if cond then "  ✓ " else "  ✗ ") .. msg)
	if not cond then
		table.insert(failures, msg)
	end
end

local game = Sim.loadPlace(process.args[1] or "build/game.rbxl")
local RS = game:GetService("ReplicatedStorage")
local ws = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = RS.Shared
local River = Sim.require(Shared.River)
local RaftSim = Sim.require(Shared.RaftSim)
local Config = Sim.require(Shared.Config)
local Catalog = Sim.require(Shared.Catalog)

Sim.virtualTime = 1000
local alice = Sim.addPlayer("Alice")
local bob = Sim.addPlayer("Bob")

-- один «кадр» сервера: dt виртуального времени
local function tick(dt)
	Sim.virtualTime += dt
	Sim.signalOf(RunService, "Heartbeat"):Fire(dt)
	task.wait()
	Sim.stepPhysics()
end
local function waitUntil(fn, timeout)
	local t0 = os.clock()
	while not fn() do
		if os.clock() - t0 > timeout then
			return false
		end
		task.wait(0.02)
	end
	return true
end
local function sentTo(player, kind)
	local out = {}
	for _, s in Sim.sent do
		if (s.player == player or s.player == "all") and s.payload and s.payload.t == kind then
			table.insert(out, s.payload)
		end
	end
	return out
end
local function last(player, kind)
	local l = sentTo(player, kind)
	return l[#l]
end
local function action(player, payload)
	Sim.signalOf(RS.Remotes.ClientAction, "OnServerEvent"):Fire(player, payload)
	task.wait(0.03)
end

print("== boot")
local server = game:GetService("ServerScriptService").Server
Sim.runScript(server)
check(
	waitUntil(function()
		return ws:GetAttribute("WorldReady") == true
	end, 60),
	"world builds"
)
if not ws:GetAttribute("WorldReady") then
	process.exit(1)
end
print(string.format(
	"  terrain: %d FillBlock (%s)",
	Sim.fills.count,
	(function()
		local parts = {}
		for k, v in Sim.fills.materials do
			table.insert(parts, k .. "=" .. v)
		end
		table.sort(parts)
		return table.concat(parts, " ")
	end)()
))
check(Sim.fills.materials.Water and Sim.fills.materials.Water > 200, "river water filled")
check(
	waitUntil(function()
		return alice.Character ~= nil and bob.Character ~= nil
	end, 5),
	"characters spawn after the world is ready"
)
local riverFolder = ws:FindFirstChild("River")
check(riverFolder and #riverFolder.Coins:GetChildren() == #River.coins, "coins placed")
check(riverFolder and #riverFolder.Rocks:GetChildren() == #River.rocks, "rocks placed")
check(Sim.collidable["Raft|Raft"] == false, "rafts don't collide with each other")
check(
	waitUntil(function()
		return alice:FindFirstChild("leaderstats") ~= nil and #sentTo(alice, "profile") > 0
	end, 5),
	"profile loaded, leaderstats created"
)
local vest = alice.Character:FindFirstChild("LifeVest")
check(
	waitUntil(function()
		return alice.Character:FindFirstChild("LifeVest") ~= nil
	end, 5),
	"life vest on the character"
)

local RaftService = Sim.require(server.RaftService)
local Data = Sim.require(server.DataService)
local function dockRaft()
	for _, r in RaftService.rafts do
		if r.phase == "dock" or r.phase == "countdown" then
			return r
		end
	end
	return nil
end
local raft = dockRaft()
check(raft ~= nil, "raft waits at the dock")
tick(0.1)

-- бот стоит в точке палубы (lx, lz) — так он и правит
local stand = {}
local function placeBots(r)
	for p, pos in stand do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = r.hull.CFrame * CFrame.new(pos.X, 4, pos.Z)
		end
	end
end

print("== boarding")
stand[alice] = Vector3.new(0, 0, 0)
placeBots(raft)
tick(0.1)
check(raft.phase == "countdown", "countdown starts when someone is aboard")
check(raft.captain == alice, "first aboard is the captain")
check(last(alice, "board") ~= nil, "board event sent")
stand[bob] = Vector3.new(2, 0, 2)
placeBots(raft)
tick(0.1)
check(
	raft.countdownEnd - Sim.virtualTime <= Config.Timing.CountdownAllAboard + 0.01,
	"everyone aboard → short countdown"
)
for _ = 1, 40 do
	placeBots(raft)
	tick(0.1)
	if raft.phase == "run" then
		break
	end
end
check(raft.phase == "run", "raft departs")
check(#raft.crew == 2 and alice:GetAttribute("RaftId") == raft.id, "crew of two")
check(last(bob, "depart") ~= nil, "depart event sent")

print("== steering by weight")
local x0 = raft.sim.x
stand[alice] = Vector3.new(Config.Raft.Width / 2 - 1, 0, 0)
stand[bob] = Vector3.new(Config.Raft.Width / 2 - 1, 0, 0)
for _ = 1, 15 do
	placeBots(raft)
	tick(0.1)
end
check(
	raft.sim.x > x0 + 3,
	string.format("both on the right → raft moves right (%.1f → %.1f)", x0, raft.sim.x)
)
check((raft.model:GetAttribute("Bx") or 0) > 0.5, "balance published")
stand[alice] = Vector3.new(-(Config.Raft.Width / 2 - 1), 0, 0)
for _ = 1, 15 do
	placeBots(raft)
	tick(0.1)
end
check(
	math.abs(raft.model:GetAttribute("Bx") or 1) < 0.05,
	"opposite sides cancel out (Bx = " .. tostring(raft.model:GetAttribute("Bx")) .. ")"
)

print("== overboard")
stand[bob] = nil
local broot = bob.Character.HumanoidRootPart
broot.CFrame = raft.hull.CFrame * CFrame.new(30, -3, 0)
for _ = 1, 20 do
	placeBots(raft)
	tick(0.1)
end
local lp = raft.hull.CFrame:PointToObjectSpace(broot.CFrame.Position)
check(math.abs(lp.X) < Config.Raft.Width / 2 and lp.Y > 0, "fallen player is pulled back on deck")
check(last(bob, "rescued") ~= nil and raft.falls[bob] == 1, "fall counted")

print("== run the river (bots follow the autopilot with their feet)")
local coinsBefore = Data.get(alice).coins
stand[bob] = Vector3.new(0, 0, 0)
local hits = 0
local steps = 0
while raft.phase == "run" and steps < 6000 do
	local bx, bz = RaftSim.autopilot(raft.sim)
	local W, L = Config.Raft.Width, Config.Raft.Length
	local pos = Vector3.new(bx * (W / 2 - 0.5), 0, -bz * (L / 2 - 0.5))
	stand[alice] = pos
	stand[bob] = pos
	placeBots(raft)
	tick(0.1)
	steps += 1
end
for _, h in sentTo(alice, "hit") do
	if h.kind == "rock" then
		hits += 1
	end
end
check(
	raft.phase == "finished",
	"raft reaches the finish (phase " .. raft.phase .. ", s=" .. math.floor(raft.sim.s) .. ")"
)
check(hits <= 1, "rocks hit: " .. hits)
check(#sentTo(alice, "coin") >= 50, "coins collected: " .. #sentTo(alice, "coin"))
check(#sentTo(alice, "gate") >= 4, "gates passed: " .. #sentTo(alice, "gate"))
check(last(alice, "dropSafe") ~= nil, "waterfall: crew on the stern → clean landing")
local res = last(alice, "results")
check(res ~= nil and res.finished and res.time > 100, "results sent")
local gained = Data.get(alice).coins - coinsBefore
check(res and gained == res.coins and gained > 60, "coins credited = results (" .. gained .. ")")
check(res and math.abs(res.mult - 1.15) < 1e-6, "crew of 2 → ×1.15")
check(Data.get(alice).best > 0 and Data.get(alice).finishes == 1, "best time saved in the profile")
for _ = 1, Config.Timing.ResultsTime * 10 + 5 do
	tick(0.1)
end
check(alice:GetAttribute("RaftId") == nil, "crew returned to the dock")
check(RaftService.rafts[raft.id] == nil, "finished raft removed")
task.wait(Config.Timing.NextRaftDelay + 0.3)
tick(0.1)
check(dockRaft() ~= nil, "a new raft waits at the dock")

print("== wreck and second chance")
raft = dockRaft()
stand = { [alice] = Vector3.new(0, 0, 0) }
for _ = 1, 150 do
	placeBots(raft)
	tick(0.1)
	if raft.phase == "run" then
		break
	end
end
check(raft.phase == "run" and #raft.crew == 1, "solo departure")
action(alice, { t = "debug", cmd = "damage", arg = 1 })
action(alice, { t = "debug", cmd = "skip", arg = "teeth" })
stand[alice] = Vector3.new(Config.Raft.Width / 2 - 1, 0, 0) -- прямо в берег
for _ = 1, 200 do
	placeBots(raft)
	tick(0.1)
	if raft.phase == "wrecked" then
		break
	end
end
check(raft.phase == "wrecked", "raft wrecked on the rocks")
local w = last(alice, "wreck")
check(w ~= nil and w.canRevive == true, "wreck event offers the second chance")
action(alice, { t = "product", key = "Revive" })
check(raft.phase == "run" and raft.sim.hp == math.floor(raft.sim.maxHp / 2), "second chance repairs the raft")
check(last(alice, "revived") ~= nil, "revived event")
action(alice, { t = "debug", cmd = "damage", arg = 1 })
for _ = 1, 200 do
	placeBots(raft)
	tick(0.1)
	if raft.phase == "wrecked" then
		break
	end
end
for _ = 1, (Config.Timing.WreckRevive + 3) * 10 do
	tick(0.1)
end
check(raft.phase == "sunk", "no revive → raft sinks")
local r2 = last(alice, "results")
check(r2 and r2.finished == false, "results after sinking")
for _ = 1, 40 do
	tick(0.1)
end
check(alice:GetAttribute("RaftId") == nil, "crew back ashore")
check(RaftService.rafts[raft.id] == nil, "wreck removed")
local c0 = Data.get(alice).coins
action(alice, { t = "product", key = "Revive" })
check(Data.get(alice).coins == c0, "revive can't be bought when not wrecked")

print("== shop: coins")
local d = Data.get(alice)
d.coins = 0
action(alice, { t = "buyCoins", id = "vest_lime" })
check(last(alice, "toast").key == "shop.noCoins" and not d.owned.vest_lime, "can't buy without coins")
d.coins = 1000
action(alice, { t = "buyCoins", id = "vest_lime" })
check(d.owned.vest_lime and d.coins == 1000 - Config.Rarity.Common.price, "bought for coins")
check(d.equipped.vest == "vest_lime", "auto-equipped")
check(alice.Character.LifeVest:GetAttribute("Vest") == "vest_lime", "vest changed on the character")
action(alice, { t = "buyCoins", id = "raft_gold" })
check(not d.owned.raft_gold, "VIP item not for sale")
action(alice, { t = "equip", id = "vest_gold" })
check(d.equipped.vest == "vest_lime", "can't wear VIP without the pass")

print("== shop: chest and PolicyService")
local before = 0
for _ in d.owned do
	before += 1
end
d.coins = 0
action(alice, { t = "product", key = "Chest" })
local cr = last(alice, "chestResult")
check(cr ~= nil and Catalog.get(cr.id) ~= nil, "chest gives an item: " .. tostring(cr and cr.id))
check(d.chests == 1, "chest counted")
-- запрет
Sim.policyRestricted = true
local carol = Sim.addPlayer("Carol")
Sim.signalOf(Players, "PlayerAdded"):Fire(carol)
check(
	waitUntil(function()
		return Data.get(carol) ~= nil and #sentTo(carol, "profile") > 0
	end, 5),
	"late joiner gets a profile"
)
task.wait(0.2)
action(carol, { t = "profile" })
check(last(carol, "profile").chestAllowed == false, "restricted region: chest hidden")
action(carol, { t = "product", key = "Chest" })
check(
	last(carol, "toast").key == "shop.chestRestricted" and last(carol, "chestResult") == nil,
	"restricted region: chest refused by the server"
)
action(carol, { t = "product", key = "DirectEpic", item = "raft_ice" })
check(Data.get(carol).owned.raft_ice == true, "restricted region: direct purchase works")
check(last(carol, "directResult").id == "raft_ice", "direct result sent")
action(carol, { t = "product", key = "DirectEpic", item = "vest_lime" })
check(not Data.get(carol).owned.vest_lime, "direct purchase checks rarity")
Sim.policyRestricted = false
Sim.policyFail = true
local dave = Sim.addPlayer("Dave")
Sim.signalOf(Players, "PlayerAdded"):Fire(dave)
waitUntil(function()
	return Data.get(dave) ~= nil
end, 5)
task.wait(0.2)
action(dave, { t = "product", key = "Chest" })
check(last(dave, "chestResult") == nil, "policy request fails → chest treated as restricted")
Sim.policyFail = false

print("== receipts are idempotent")
local Monetization = Sim.require(server.Monetization)
local c1 = d.coins
check(Monetization.grant(alice, "Coins500", "PID-1"), "grant ok")
check(Monetization.grant(alice, "Coins500", "PID-1"), "repeat ok")
check(d.coins == c1 + 500, "coins added once (" .. (d.coins - c1) .. ")")
Config.Products.Coins500.id = 777
local fake = { PlayerId = alice.UserId, ProductId = 777, PurchaseId = "PID-2", CurrencySpent = 25 }
-- ProcessReceipt назначен на старте, ID читаются там же, поэтому проверяем напрямую grant + решение
local dec = Monetization.processReceipt(fake)
check(
	dec == roblox.Enum.ProductPurchaseDecision.NotProcessedYet
		or dec == roblox.Enum.ProductPurchaseDecision.PurchaseGranted,
	"processReceipt returns a decision"
)
Config.Products.Coins500.id = 0
check(Sim.processReceipt ~= nil, "ProcessReceipt is set")

print("== passes")
action(alice, { t = "pass", key = "Vip" })
check(alice:GetAttribute("Pass_Vip") == true, "VIP emulated in Studio")
check(alice.Character.Head:FindFirstChild("VipTag") ~= nil, "VIP tag over the head")
action(alice, { t = "equip", id = "vest_gold" })
check(d.equipped.vest == "vest_gold", "VIP can wear the golden vest")
action(alice, { t = "pass", key = "Sturdy" })
raft = dockRaft() or RaftService.spawnDockRaft()
stand = { [alice] = Vector3.new(0, 0, 0) }
for _ = 1, 150 do
	placeBots(raft)
	tick(0.1)
	if raft.phase == "run" then
		break
	end
end
check(raft.sim.maxHp == math.floor(Config.Raft.BaseHp * 1.5), "Sturdy pass → +50% hull")
check(raft.model:GetAttribute("Skin") == "raft_pine", "captain's skin on the raft")

print("== data saving")
local Data2 = Data
check(Data2.save(alice), "save works")
local stored = Sim.dataStores[Config.DataStore.Name]["u_" .. alice.UserId]
check(stored and stored.coins == d.coins and stored.owned.vest_lime, "profile stored")
Sim.dataFail = true
local erin = Sim.addPlayer("Erin")
Sim.signalOf(Players, "PlayerAdded"):Fire(erin)
check(
	waitUntil(function()
		return Data.get(erin) ~= nil
	end, 15),
	"data outage: player still gets a temp profile"
)
check(erin:GetAttribute("DataSaved") == false, "temp profile is marked unsaved")
Sim.dataFail = false

print("== selftest")
action(alice, { t = "debug", cmd = "selftest" })
check(
	waitUntil(function()
		return #sentTo(alice, "selftest") > 0
	end, 20),
	"selftest finished"
)
local st = last(alice, "selftest")
local fails = 0
for _, line in st and st.lines or {} do
	print("    " .. line)
	if string.find(line, "FAIL", 1, true) then
		fails += 1
	end
end
check(fails == 0, "selftest has no FAIL")

print("== warnings")
local errs = 0
for _, w in Sim.warnings or {} do
	if string.find(w, "error", 1, true) or string.find(w, "[Actions]", 1, true) then
		errs += 1
		print("    " .. w)
	end
end
check(errs == 0, "no runtime errors")
_ = vest
print(string.format("\n%d failures", #failures))
process.exit(if #failures > 0 then 1 else 0)
