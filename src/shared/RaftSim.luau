--[[
	RaftSim — детерминированная модель плота. Сервер шагает её с фиксированным dt
	и переносит результат на физический плот (AlignPosition/AlignOrientation).
	Тесты гоняют ту же модель: проходима ли река, важен ли вес, как бьют камни.

	Вход каждого шага — баланс экипажа (bx, bz ∈ [−1, 1]):
	  bx > 0 — центр масс у правого борта → плот уходит вправо;
	  bz > 0 — центр масс на носу → быстрее; bz < 0 — на корме (нужно на водопаде).
]]

local Shared = script.Parent
local Config = require(Shared.Config)
local River = require(Shared.River)

local RaftSim = {}

export type State = {
	s: number,
	x: number,
	vx: number,
	v: number,
	hp: number,
	maxHp: number,
	roll: number,
	pitch: number,
	t: number,
	y: number, -- уровень воды под плотом (с учётом падения с водопада)
	fallT: number?, -- время с начала падения
	dropped: boolean,
	finished: boolean,
	broken: boolean,
	coins: { [number]: boolean },
	gates: { [number]: boolean },
	nextGate: number,
	rockHitAt: { [number]: number },
	bankHitAt: number,
	section: string,
	warned: { [string]: boolean },
}

export type Event = {
	kind: string, -- coin | gate | gateMiss | rock | bank | dropSafe | dropBad | section | warn | finish | broken
	id: number?,
	value: number?,
	damage: number?,
	key: string?,
}

function RaftSim.new(maxHp: number?, s: number?): State
	local hp = maxHp or Config.Raft.BaseHp
	local s0 = s or River.dockS
	local first = 1
	while River.gates[first] and River.gates[first].s < s0 do
		first += 1
	end
	return {
		s = s0,
		x = 0,
		vx = 0,
		v = 0,
		hp = hp,
		maxHp = hp,
		roll = 0,
		pitch = 0,
		t = 0,
		y = River.waterLevel(s0),
		fallT = nil,
		dropped = s0 >= River.dropS,
		finished = false,
		broken = false,
		coins = {},
		gates = {},
		nextGate = first,
		rockHitAt = {},
		bankHitAt = -math.huge,
		section = River.sectionAt(s0).id,
		warned = {},
	}
end

-- Баланс по локальным позициям экипажа. points: { {x=, z=} } — Z к корме (как в CFrame).
function RaftSim.balance(points: { { x: number, z: number } }): (number, number)
	local n = #points
	if n == 0 then
		return 0, 0
	end
	local hx, hz = Config.Raft.Width / 2, Config.Raft.Length / 2
	local sx, sz = 0, 0
	for _, p in points do
		sx += math.clamp(p.x / hx, -1, 1)
		sz += math.clamp(-p.z / hz, -1, 1) -- вперёд = −Z
	end
	local bx, bz = sx / n, sz / n
	local dz = Config.Lean.Deadzone
	local function dead(v)
		if math.abs(v) < dz then
			return 0
		end
		return (v - math.sign(v) * dz) / (1 - dz)
	end
	return dead(bx), dead(bz)
end

local function approach(cur: number, target: number, rate: number, dt: number): number
	return cur + (target - cur) * math.min(1, rate * dt)
end

function RaftSim.step(st: State, bx: number, bz: number, dt: number): { Event }
	local events: { Event } = {}
	if st.finished or st.broken then
		return events
	end
	local L, D, R = Config.Lean, Config.Damage, Config.Raft
	bx = math.clamp(bx, -1, 1)
	bz = math.clamp(bz, -1, 1)
	st.t += dt

	-- скорость вдоль течения
	local current = River.current(st.s)
	local lean = if bz > 0 then 1 + L.ForwardBoost * bz else 1 + L.BackDrag * bz
	local target = current * lean
	local ax = L.Steer * bx - L.LatDrag * st.vx
	ax -= River.curvature(st.s) * st.v * st.v * L.BendDrift -- снос к внешнему берегу на повороте

	local wp = River.whirlpool
	if wp then
		local ds, dx = st.s - wp.s, st.x - wp.x
		local d = math.sqrt(ds * ds + dx * dx)
		if d < wp.r then
			local k = 1 - d / wp.r
			target *= 1 - (1 - wp.slow) * k
			if d > 0.5 then
				ax += -dx / d * wp.pull * (0.4 + k)
			end
		end
	end

	st.v = approach(st.v, target, L.SpeedRate, dt)
	st.vx = math.clamp(st.vx + ax * dt, -L.MaxLat, L.MaxLat)
	st.x += st.vx * dt
	local prevS = st.s
	st.s += st.v * dt

	-- берега
	local half = River.halfFree(st.s, R.Width / 2)
	if math.abs(st.x) > half then
		local hitSpeed = math.abs(st.vx)
		st.x = math.sign(st.x) * half
		st.vx = -st.vx * 0.3
		if st.t - st.bankHitAt > D.BankCooldown and hitSpeed > 2 then
			st.bankHitAt = st.t
			st.hp -= D.Bank
			table.insert(events, { kind = "bank", damage = D.Bank })
		end
	end

	-- камни (плот — круг радиуса Raft.Radius в координатах (s, x))
	for _, rock in River.rocks do
		if rock.s > st.s + 12 then
			break
		end
		if rock.s > st.s - 12 then
			local ds, dx = st.s - rock.s, st.x - rock.x
			local d = math.sqrt(ds * ds + dx * dx)
			local minD = rock.r + R.Radius
			if d < minD and st.t - (st.rockHitAt[rock.id] or -math.huge) > D.RockCooldown then
				st.rockHitAt[rock.id] = st.t
				local dmg = math.floor(D.RockBase + D.RockPerSpeed * st.v + 0.5)
				st.hp -= dmg
				st.v *= D.RockSpeedKeep
				local away = if math.abs(dx) < 0.3 then (if rock.x > 0 then -1 else 1) else math.sign(dx)
				st.vx = away * 9
				st.x = rock.x
					+ away * math.max(math.abs(dx), math.sqrt(math.max(0, minD * minD - ds * ds)) * 0.6)
				table.insert(events, { kind = "rock", id = rock.id, damage = dmg })
			end
		end
	end

	-- монеты
	local reachX, reachS = R.Width / 2 - 1, R.Length / 2
	for _, coin in River.coins do
		if coin.s > st.s + reachS then
			break
		end
		if not st.coins[coin.id] and coin.s > st.s - reachS and math.abs(coin.x - st.x) < reachX then
			st.coins[coin.id] = true
			table.insert(events, { kind = "coin", id = coin.id, value = coin.value })
		end
	end

	-- ворота
	local gate = River.gates[st.nextGate]
	while gate and st.s >= gate.s do
		if math.abs(st.x - gate.x) < gate.half - 1 then
			st.gates[gate.id] = true
			table.insert(events, { kind = "gate", id = gate.id, value = Config.Rewards.Gate })
		else
			table.insert(events, { kind = "gateMiss", id = gate.id })
		end
		st.nextGate += 1
		gate = River.gates[st.nextGate]
	end

	-- предупреждения и смена участка
	if not st.warned.drop and st.s >= River.warnDropS then
		st.warned.drop = true
		table.insert(events, { kind = "warn", key = "warn.drop" })
	end
	if wp and not st.warned.whirl and st.s >= wp.s - wp.r - 60 then
		st.warned.whirl = true
		table.insert(events, { kind = "warn", key = "warn.whirl" })
	end
	local sec = River.sectionAt(st.s)
	if sec.id ~= st.section then
		st.section = sec.id
		table.insert(events, { kind = "section", key = sec.id })
	end

	-- водопад
	if not st.dropped and prevS < River.dropS and st.s >= River.dropS then
		st.dropped = true
		st.fallT = 0
		if bz <= -D.DropSafeLean then
			table.insert(events, { kind = "dropSafe" })
		else
			st.hp -= D.DropBad
			table.insert(events, { kind = "dropBad", damage = D.DropBad })
		end
	end
	if st.fallT then
		st.fallT += dt
		local k = math.clamp(st.fallT / D.DropFallTime, 0, 1)
		st.y = River.LevelHigh - River.DropHeight * k * k
		if k >= 1 then
			st.fallT = nil
		end
	else
		st.y = River.waterLevel(st.s)
	end

	-- крен и дифферент для картинки (градусы)
	st.roll = approach(st.roll, -bx * L.MaxRoll, L.TiltRate, dt)
	st.pitch = approach(st.pitch, -bz * L.MaxPitch, L.TiltRate, dt)

	if st.hp <= 0 then
		st.hp = 0
		st.broken = true
		table.insert(events, { kind = "broken" })
	elseif st.s >= River.finishS then
		st.finished = true
		table.insert(events, { kind = "finish" })
	end
	return events
end

-- Мировая поза плота: x, y, z, курс (рад), рысканье от бокового хода (рад)
function RaftSim.pose(st: State): (number, number, number, number, number)
	local wx, wz = River.point(st.s, st.x)
	local h = River.heading(st.s)
	local yaw = if st.v > 1 then math.atan2(st.vx, st.v) * 0.6 else 0
	return wx, st.y, wz, h, yaw
end

--[[
	Автопилот: целится в проход ближайшего ряда камней, в ворота, обходит омут,
	перед водопадом переносит вес на корму. Так играет внимательный игрок.
	Нужен тестам (река проходима) и кнопке DBG в Studio.
]]
function RaftSim.autopilot(st: State): (number, number)
	local target = 0
	for _, row in River.rows do
		if row.s > st.s - 8 then
			target = row.gap
			break
		end
	end
	local g = River.gates[st.nextGate]
	if g and g.s - st.s < 90 then
		target = g.x
	end
	local wp = River.whirlpool
	if wp and math.abs(wp.s - st.s) < wp.r + 70 then
		target = wp.x - (wp.r + 8)
	end
	if st.s > River.dropS - 150 and st.s < River.dropS then
		target = 0
	end
	local half = River.halfFree(st.s + 20, Config.Raft.Width / 2) - 1
	target = math.clamp(target, -half, half)
	local bx = math.clamp((target - st.x) * 0.3 - st.vx * 0.25, -1, 1)
	local bz = 0
	local toDrop = River.dropS - st.s
	if toDrop > 0 and toDrop < 60 then
		bz = -1
	end
	return bx, bz
end

return RaftSim
