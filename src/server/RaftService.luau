--[[
	RaftService — жизненный цикл плотов:
	  dock (ждёт экипаж) → countdown → run (сплав) → finished | wrecked → назад к причалу.
	Плот ведёт RaftSim с фиксированным шагом; вход — центр масс экипажа на палубе.
	Состояние плота публикуется атрибутами модели (клиент рисует HUD),
	события заплыва уходят экипажу через ServerEvent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Profile = require(Shared.Profile)
local RaftSim = require(Shared.RaftSim)
local Rewards = require(Shared.Rewards)
local River = require(Shared.River)

local Data = require(script.Parent.DataService)
local Monetization = require(script.Parent.Monetization)
local Cosmetics = require(script.Parent.Cosmetics)
local RaftModel = require(script.Parent.RaftModel)

local RaftService = {}

export type Raft = {
	id: number,
	model: Model,
	hull: BasePart,
	sim: RaftSim.State,
	phase: string, -- dock | countdown | run | wrecked | finished | sunk
	crew: { Player },
	captain: Player?,
	boardedAt: { [Player]: number },
	countdownEnd: number,
	wreckEnd: number,
	doneAt: number,
	base: { [Player]: number }, -- «сырые» монеты заплыва
	paid: { [Player]: number }, -- уже начислено
	offSince: { [Player]: number },
	falls: { [Player]: number },
	gates: number,
	revives: number,
	auto: boolean,
	acc: number,
	attrAt: number,
	bob: number,
	debris: { BasePart }?,
}

local rafts: { [number]: Raft } = {}
local byPlayer: { [Player]: Raft } = {}
local nextId = 1
local dockRaft: Raft? = nil
local spawnCF = CFrame.new(0, 60, 0)
local spawnPending = false

RaftService.rafts = rafts

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function send(player: Player, payload)
	Net.ServerEvent:FireClient(player, payload)
end

local function sendCrew(raft: Raft, payload)
	for _, p in raft.crew do
		if p.Parent then
			Net.ServerEvent:FireClient(p, payload)
		end
	end
end

local function rootOf(player: Player): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function dockCF(): CFrame
	local st = RaftSim.new(Config.Raft.BaseHp, River.dockS)
	local x, y, z, h = RaftSim.pose(st)
	return RaftModel.poseCFrame(x, y, z, h, 0, 0, 0)
end

-- Игрок на палубе? Возвращает локальную точку (x, z) или nil
local function onDeck(raft: Raft, player: Player): Vector3?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local lp = raft.hull.CFrame:PointToObjectSpace(root.CFrame.Position)
	local W, L = Config.Raft.Width, Config.Raft.Length
	if math.abs(lp.X) <= W / 2 + 1 and math.abs(lp.Z) <= L / 2 + 1 and lp.Y > -1 and lp.Y < 9 then
		return lp
	end
	return nil
end

local function maxHpFor(crew: { Player }): number
	for _, p in crew do
		if Monetization.hasPass(p, "Sturdy") then
			return math.floor(Config.Raft.BaseHp * (1 + Config.Raft.SturdyBonus))
		end
	end
	return Config.Raft.BaseHp
end

local function publish(raft: Raft)
	local m, st = raft.model, raft.sim
	m:SetAttribute("Phase", raft.phase)
	m:SetAttribute("Hp", math.max(0, math.floor(st.hp + 0.5)))
	m:SetAttribute("MaxHp", st.maxHp)
	m:SetAttribute("S", math.floor(st.s * 10) / 10)
	m:SetAttribute("X", math.floor(st.x * 10) / 10)
	m:SetAttribute("Speed", math.floor(st.v * 10) / 10)
	m:SetAttribute("CountdownEnd", raft.countdownEnd)
	m:SetAttribute("WreckEnd", raft.wreckEnd)
	m:SetAttribute("Crew", #raft.crew)
	m:SetAttribute("Captain", if raft.captain then raft.captain.DisplayName else "")
	m:SetAttribute("Time", math.floor(st.t * 10) / 10)
end

-------------------------------------------------------------------------------
-- Монеты
-------------------------------------------------------------------------------
local function multiplierFor(raft: Raft, p: Player): number
	return Rewards.multiplier(
		#raft.crew,
		Monetization.hasPass(p, "DoubleCoins"),
		Monetization.hasPass(p, "Vip")
	)
end

-- Начислить «сырые» монеты всему экипажу; возвращает сколько получил каждый
local function award(raft: Raft, amount: number): { [Player]: number }
	local got = {}
	for _, p in raft.crew do
		local prev = raft.base[p] or 0
		local nxt = prev + amount
		raft.base[p] = nxt
		local delta = Rewards.delta(prev, nxt, multiplierFor(raft, p))
		if delta > 0 then
			raft.paid[p] = (raft.paid[p] or 0) + delta
			local d = Data.get(p)
			if d then
				Profile.addCoins(d, delta)
				d.earned += delta
				Data.changed(p)
			end
		end
		got[p] = delta
	end
	return got
end

-------------------------------------------------------------------------------
-- Возврат к причалу
-------------------------------------------------------------------------------
local function toShore(player: Player)
	local c = player.Character
	if c then
		local off = Vector3.new(math.random(-4, 4), 3, math.random(-4, 4))
		c:PivotTo(spawnCF + off)
	end
end

local function leaveRaft(player: Player)
	local raft = byPlayer[player]
	byPlayer[player] = nil
	player:SetAttribute("RaftId", nil)
	if raft then
		local i = table.find(raft.crew, player)
		if i and raft.phase ~= "finished" and raft.phase ~= "sunk" then
			table.remove(raft.crew, i)
		end
	end
end

local function destroyRaft(raft: Raft)
	for _, p in table.clone(raft.crew) do
		if byPlayer[p] == raft then
			leaveRaft(p)
		end
	end
	rafts[raft.id] = nil
	if dockRaft == raft then
		dockRaft = nil
	end
	raft.model:Destroy()
end

local function results(raft: Raft, finished: boolean)
	local time = raft.sim.t
	local bonusOf = if finished then award(raft, Rewards.finishBonus(raft.sim.hp)) else {}
	for _, p in raft.crew do
		if p.Parent then
			local bonus = bonusOf[p] or 0
			local d = Data.get(p)
			local newBest = false
			if d then
				-- монеты уже начислены по ходу, здесь только статистика
				newBest = Profile.recordRun(d, finished, time, 0)
				Data.changed(p)
			end
			send(p, {
				t = "results",
				finished = finished,
				time = time,
				coins = raft.paid[p] or 0,
				bonus = bonus,
				hp = math.max(0, math.floor(raft.sim.hp)),
				maxHp = raft.sim.maxHp,
				gates = raft.gates,
				gatesTotal = #River.gates,
				falls = raft.falls[p] or 0,
				crew = #raft.crew,
				best = d and d.best or 0,
				newBest = newBest,
				mult = multiplierFor(raft, p),
			})
		end
	end
end

-------------------------------------------------------------------------------
-- Создание и отплытие
-------------------------------------------------------------------------------
local function activeCount(): number
	local n = 0
	for _ in rafts do
		n += 1
	end
	return n
end

function RaftService.spawnDockRaft(): Raft?
	if dockRaft or activeCount() >= Config.Raft.MaxRafts then
		return dockRaft
	end
	local id = nextId
	nextId += 1
	local cf = dockCF()
	local model = RaftModel.build(id, cf)
	local raft: Raft = {
		id = id,
		model = model,
		hull = model.PrimaryPart :: BasePart,
		sim = RaftSim.new(Config.Raft.BaseHp, River.dockS),
		phase = "dock",
		crew = {},
		captain = nil,
		boardedAt = {},
		countdownEnd = 0,
		wreckEnd = 0,
		doneAt = 0,
		base = {},
		paid = {},
		offSince = {},
		falls = {},
		gates = 0,
		revives = 0,
		auto = false,
		acc = 0,
		attrAt = 0,
		bob = 0,
	}
	rafts[id] = raft
	dockRaft = raft
	publish(raft)
	return raft
end

local function scheduleDockRaft()
	if spawnPending then
		return
	end
	spawnPending = true
	task.delay(Config.Timing.NextRaftDelay, function()
		spawnPending = false
		RaftService.spawnDockRaft()
	end)
end

local function setCaptain(raft: Raft, p: Player?)
	if raft.captain == p then
		return
	end
	raft.captain = p
	RaftModel.applySkin(raft.model, if p then Cosmetics.effective(p, "raft") else "raft_pine")
end

local function depart(raft: Raft, aboard: { Player })
	local crew = {}
	table.sort(aboard, function(a, b)
		return (raft.boardedAt[a] or 0) < (raft.boardedAt[b] or 0)
	end)
	for i, p in aboard do
		if i <= Config.Raft.MaxCrew then
			table.insert(crew, p)
		else
			toShore(p)
			send(p, { t = "toast", key = "ui.raftFull" })
		end
	end
	raft.crew = crew
	local hp = maxHpFor(crew)
	raft.sim = RaftSim.new(hp, River.dockS)
	raft.phase = "run"
	dockRaft = nil
	for _, p in crew do
		byPlayer[p] = raft
		p:SetAttribute("RaftId", raft.id)
		raft.base[p] = 0
		raft.paid[p] = 0
		raft.falls[p] = 0
	end
	sendCrew(raft, {
		t = "depart",
		raftId = raft.id,
		crew = #crew,
		mult = Rewards.multiplier(#crew, false, false),
		sturdy = hp > Config.Raft.BaseHp,
	})
	publish(raft)
	scheduleDockRaft()
end

-------------------------------------------------------------------------------
-- Шаги фаз
-------------------------------------------------------------------------------
local function freePlayers(): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		if not byPlayer[p] and p.Character then
			table.insert(out, p)
		end
	end
	return out
end

local function stepDock(raft: Raft, dt: number)
	local aboard = {}
	for _, p in Players:GetPlayers() do
		if not byPlayer[p] and onDeck(raft, p) then
			table.insert(aboard, p)
			if not raft.boardedAt[p] then
				raft.boardedAt[p] = now()
				send(p, { t = "board", raftId = raft.id })
			end
		elseif raft.boardedAt[p] then
			raft.boardedAt[p] = nil
			send(p, { t = "unboard" })
		end
	end
	-- капитан — первый взошедший
	local first, firstT = nil, math.huge
	for _, p in aboard do
		if raft.boardedAt[p] < firstT then
			first, firstT = p, raft.boardedAt[p]
		end
	end
	setCaptain(raft, first)

	local t = now()
	if #aboard == 0 then
		raft.phase = "dock"
		raft.countdownEnd = 0
	else
		if raft.phase == "dock" then
			raft.phase = "countdown"
			raft.countdownEnd = t + Config.Timing.Countdown
		end
		if #aboard >= #freePlayers() then
			raft.countdownEnd = math.min(raft.countdownEnd, t + Config.Timing.CountdownAllAboard)
		end
		if t >= raft.countdownEnd then
			depart(raft, aboard)
			return
		end
	end
	-- лёгкая качка у причала
	raft.bob += dt
	local x, y, z, h = RaftSim.pose(raft.sim)
	RaftModel.drive(
		raft.model,
		RaftModel.poseCFrame(
			x,
			y + math.sin(raft.bob * 1.3) * 0.12,
			z,
			h,
			0,
			math.sin(raft.bob * 0.9) * 1.2,
			0
		)
	)
end

local function rescue(raft: Raft, p: Player)
	local c = p.Character
	if not c then
		return
	end
	local W, L = Config.Raft.Width, Config.Raft.Length
	local off = CFrame.new((math.random() - 0.5) * (W - 6), 4.5, (math.random() - 0.5) * (L - 8))
	c:PivotTo(raft.hull.CFrame * off)
	local root = rootOf(p)
	if root then
		root.AssemblyLinearVelocity = raft.hull.AssemblyLinearVelocity
	end
	raft.falls[p] = (raft.falls[p] or 0) + 1
	raft.offSince[p] = nil
	send(p, { t = "rescued" })
end

local function handleEvents(raft: Raft, events)
	for _, e in events do
		local k = e.kind
		if k == "coin" then
			local got = award(raft, e.value)
			for p, n in got do
				send(p, { t = "coin", id = e.id, value = e.value, got = n })
			end
		elseif k == "gate" then
			raft.gates += 1
			local got = award(raft, e.value)
			for p, n in got do
				send(p, { t = "gate", id = e.id, got = n })
			end
		elseif k == "gateMiss" then
			sendCrew(raft, { t = "gateMiss", id = e.id })
		elseif k == "rock" or k == "bank" or k == "dropBad" then
			sendCrew(raft, { t = "hit", kind = k, damage = e.damage })
		elseif k == "dropSafe" then
			sendCrew(raft, { t = "dropSafe" })
		elseif k == "warn" then
			sendCrew(raft, { t = "warn", key = e.key })
		elseif k == "section" then
			sendCrew(raft, { t = "section", id = e.key })
		elseif k == "broken" then
			raft.phase = "wrecked"
			raft.wreckEnd = now() + Config.Timing.WreckRevive
			sendCrew(raft, {
				t = "wreck",
				deadline = raft.wreckEnd,
				canRevive = Monetization.available("product", "Revive"),
			})
		elseif k == "finish" then
			raft.phase = "finished"
			raft.doneAt = now()
			results(raft, true)
		end
	end
end

local function crewBalance(raft: Raft): (number, number)
	local pts = {}
	local t = now()
	for _, p in raft.crew do
		local lp = onDeck(raft, p)
		if lp then
			raft.offSince[p] = nil
			table.insert(pts, { x = lp.X, z = lp.Z })
		elseif p.Character then
			raft.offSince[p] = raft.offSince[p] or t
			if t - raft.offSince[p] > Config.Timing.OverboardGrace then
				rescue(raft, p)
			end
		end
	end
	return RaftSim.balance(pts)
end

local function stepRun(raft: Raft, dt: number)
	local bx, bz = crewBalance(raft)
	if raft.auto then
		bx, bz = RaftSim.autopilot(raft.sim)
	end
	raft.model:SetAttribute("Bx", math.floor(bx * 100) / 100)
	raft.model:SetAttribute("Bz", math.floor(bz * 100) / 100)
	raft.acc += dt
	local step = Config.Timing.SimStep
	while raft.acc >= step and raft.phase == "run" do
		raft.acc -= step
		handleEvents(raft, RaftSim.step(raft.sim, bx, bz, step))
	end
	local st = raft.sim
	local x, y, z, h, yaw = RaftSim.pose(st)
	RaftModel.drive(raft.model, RaftModel.poseCFrame(x, y, z, h, yaw, st.roll, st.pitch))
	RaftModel.setSpray(raft.model, if st.v > 14 then (st.v - 14) * 3 else 0)
end

local function sink(raft: Raft)
	raft.phase = "sunk"
	raft.doneAt = now()
	results(raft, false)
	raft.debris = RaftModel.breakApart(raft.model)
	sendCrew(raft, { t = "sunk" })
end

local function stepWrecked(raft: Raft)
	crewBalance(raft) -- спасаем выпавших, пока ждём «Второй шанс»
	if now() >= raft.wreckEnd then
		sink(raft)
	end
end

local function stepDone(raft: Raft, dt: number)
	local t = now() - raft.doneAt
	if raft.phase == "finished" then
		-- медленно дрейфуем по озеру
		local st = raft.sim
		st.v = math.max(0, st.v - 6 * dt)
		st.s += st.v * dt
		local x, y, z, h = RaftSim.pose(st)
		RaftModel.drive(raft.model, RaftModel.poseCFrame(x, y, z, h, 0, 0, 0))
		if t >= Config.Timing.ResultsTime then
			for _, p in table.clone(raft.crew) do
				leaveRaft(p)
				toShore(p)
			end
			destroyRaft(raft)
			scheduleDockRaft()
		end
	else -- sunk: брёвна расходятся и тонут
		if raft.debris then
			for i, p in raft.debris do
				local dir = if i % 2 == 0 then 1 else -1
				p.CFrame = p.CFrame
					* CFrame.new(dir * dt * 1.5, -dt * 0.8, 0)
					* CFrame.Angles(0, dt * 0.3 * dir, 0)
			end
		end
		if t >= 2 and #raft.crew > 0 then
			for _, p in table.clone(raft.crew) do
				leaveRaft(p)
				toShore(p)
			end
			raft.crew = {}
		end
		if t >= 5 then
			destroyRaft(raft)
			scheduleDockRaft()
		end
	end
end

function RaftService.step(dt: number)
	for _, raft in table.clone(rafts) do
		local ok, err = pcall(function()
			local ph = raft.phase
			if ph == "dock" or ph == "countdown" then
				stepDock(raft, dt)
			elseif ph == "run" then
				stepRun(raft, dt)
			elseif ph == "wrecked" then
				stepWrecked(raft)
			else
				stepDone(raft, dt)
			end
			local t = os.clock()
			if t - raft.attrAt >= Config.Timing.AttrRate and raft.model.Parent then
				raft.attrAt = t
				publish(raft)
			end
		end)
		if not ok then
			warn("[Raft] tick error:", err)
		end
	end
	if not dockRaft then
		scheduleDockRaft()
	end
end

-------------------------------------------------------------------------------
-- Публичные действия
-------------------------------------------------------------------------------
function RaftService.raftOf(player: Player): Raft?
	return byPlayer[player]
end

-- «Второй шанс»: вызывает Monetization после оплаты. true — плот спасён.
function RaftService.revive(player: Player): boolean
	local raft = byPlayer[player]
	if not raft or raft.phase ~= "wrecked" then
		return false
	end
	local st = raft.sim
	st.broken = false
	st.hp = math.floor(st.maxHp * 0.5)
	st.v = 0
	raft.revives += 1
	raft.phase = "run"
	raft.wreckEnd = 0
	sendCrew(raft, { t = "revived", by = player.DisplayName })
	publish(raft)
	return true
end

function RaftService.leave(player: Player)
	local raft = byPlayer[player]
	if raft and (raft.phase == "run" or raft.phase == "wrecked") then
		leaveRaft(player)
		toShore(player)
		send(player, { t = "left" })
		if #raft.crew == 0 then
			raft.phase = "sunk"
			raft.doneAt = now() - 4
		end
	end
end

-- Отладка (Studio): автопилот, перенос плота вперёд, урон
function RaftService.debug(player: Player, cmd: string, arg: any): string?
	local raft = byPlayer[player]
	if cmd == "auto" then
		if raft then
			raft.auto = not raft.auto
			return "auto " .. tostring(raft.auto)
		end
		return "not on a raft"
	elseif cmd == "skip" then
		if not raft then
			return "not on a raft"
		end
		local sec = River.section(tostring(arg))
		local s = if sec then sec.startS - 15 else tonumber(arg)
		if not s then
			return "unknown section"
		end
		local old = raft.hull.CFrame
		local st = raft.sim
		st.s, st.x, st.vx = s, 0, 0
		st.dropped = s >= River.dropS
		st.y = River.waterLevel(s)
		local x, y, z, h = RaftSim.pose(st)
		local cf = RaftModel.poseCFrame(x, y, z, h, 0, 0, 0)
		raft.model:PivotTo(cf)
		RaftModel.drive(raft.model, cf)
		for _, p in raft.crew do
			local c = p.Character
			if c then
				c:PivotTo(cf * old:ToObjectSpace(c:GetPivot()))
			end
		end
		return "skip to " .. s
	elseif cmd == "damage" then
		if raft then
			raft.sim.hp = math.min(raft.sim.hp, tonumber(arg) or 1)
			return "hp " .. raft.sim.hp
		end
		return "not on a raft"
	end
	return nil
end

function RaftService.start(spawn: SpawnLocation?)
	if spawn then
		spawnCF = spawn.CFrame
	end
	Monetization.reviveHandler = RaftService.revive
	Players.PlayerRemoving:Connect(function(p)
		local raft = byPlayer[p]
		leaveRaft(p)
		if raft and #raft.crew == 0 and (raft.phase == "run" or raft.phase == "wrecked") then
			raft.phase = "sunk"
			raft.doneAt = now() - 4
		end
		for _, r in rafts do
			r.boardedAt[p] = nil
		end
	end)
	RaftService.spawnDockRaft()
	RunService.Heartbeat:Connect(RaftService.step)
end

return RaftService
