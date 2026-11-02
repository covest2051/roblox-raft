--[[
	River — геометрия реки и раскладка препятствий. Чистые числа, без инстансов:
	тот же модуль строит мир на сервере, рисует HUD на клиенте и гоняется в тестах.

	Координаты: s — расстояние вдоль оси реки от начала, x — смещение вправо от оси
	(смотря вниз по течению). Ось лежит в плоскости XZ, течёт примерно вдоль +X.
]]

local Shared = script.Parent
local Rng = require(Shared.Rng)

local River = {}

River.Step = 4 -- шаг выборки оси
River.Seed = 20261102
River.Blend = 40 -- плавный переход ширины/течения между участками

--[[
	Участки: длина, ширина русла, скорость течения (studs/s), берега и повороты.
	turns: куски {len, turn} — поворот в градусах за кусок (+ вправо).
]]
River.Sections = {
	{ id = "dock", width = 56, current = 9, bank = 1.5, turns = { { 200, 0 } } },
	{
		id = "riffles",
		width = 50,
		current = 16,
		bank = 8,
		turns = { { 180, 18 }, { 200, -30 }, { 160, 12 } },
	},
	{
		id = "canyon",
		width = 34,
		current = 20,
		bank = 30,
		rock = true,
		turns = { { 160, -14 }, { 160, 22 }, { 160, -8 } },
	},
	{ id = "pool", width = 92, current = 10, bank = 9, turns = { { 280, 0 } } },
	{
		id = "teeth",
		width = 52,
		current = 24,
		bank = 12,
		rock = true,
		turns = { { 200, 24 }, { 200, -20 }, { 200, -10 } },
	},
	{ id = "falls", width = 44, current = 22, bank = 14, rock = true, turns = { { 230, 6 } } },
	{ id = "lake", width = 130, current = 9, bank = 6, turns = { { 330, 0 } } },
}

River.LevelHigh = 40 -- уровень воды выше водопада
River.DropHeight = 14
River.LevelLow = River.LevelHigh - River.DropHeight

-------------------------------------------------------------------------------
-- Ось
-------------------------------------------------------------------------------
local xs, zs, hs = {}, {}, {}
local total = 0
do
	local x, z, h = 0, 0, 0
	table.insert(xs, x)
	table.insert(zs, z)
	table.insert(hs, h)
	for i, sec in River.Sections do
		local secLen = 0
		for _, piece in sec.turns do
			local len, turn = piece[1], piece[2]
			local steps = math.floor(len / River.Step + 0.5)
			local dh = math.rad(turn) / steps
			for _ = 1, steps do
				h += dh
				x += math.cos(h) * River.Step
				z += math.sin(h) * River.Step
				table.insert(xs, x)
				table.insert(zs, z)
				table.insert(hs, h)
			end
			secLen += steps * River.Step
		end
		sec.startS = total
		sec.length = secLen
		total += secLen
		sec.endS = total
		sec.index = i
	end
end

River.length = total
River.dockS = 40 -- где стоит плот у причала
River.dropS = River.Sections[6].endS -- водопад в конце участка falls
River.finishS = River.Sections[7].startS + 220
River.warnDropS = River.dropS - 150

local byId = {}
for _, sec in River.Sections do
	byId[sec.id] = sec
end
function River.section(id: string)
	return byId[id]
end

local function sampleIndex(s: number): (number, number)
	local f = math.clamp(s, 0, River.length) / River.Step
	local i = math.floor(f)
	if i >= #xs - 1 then
		return #xs - 1, 1
	end
	return i + 1, f - i
end

-- Ось реки в точке s: x, z, курс (радианы)
function River.center(s: number): (number, number, number)
	local i, t = sampleIndex(s)
	local x = xs[i] + (xs[i + 1] - xs[i]) * t
	local z = zs[i] + (zs[i + 1] - zs[i]) * t
	local h = hs[i] + (hs[i + 1] - hs[i]) * t
	if s > River.length then -- продолжаем прямо за концом
		local d = s - River.length
		x += math.cos(h) * d
		z += math.sin(h) * d
	elseif s < 0 then
		x += math.cos(h) * s
		z += math.sin(h) * s
	end
	return x, z, h
end

-- Мировая точка (x, z) для координат реки (s, lateral)
function River.point(s: number, lateral: number): (number, number)
	local x, z, h = River.center(s)
	return x - math.sin(h) * lateral, z + math.cos(h) * lateral
end

function River.heading(s: number): number
	local _, _, h = River.center(s)
	return h
end

-- Кривизна, рад/stud (+ — поворот вправо)
function River.curvature(s: number): number
	return (River.heading(s + River.Step) - River.heading(s - River.Step)) / (2 * River.Step)
end

function River.sectionAt(s: number)
	for i = #River.Sections, 1, -1 do
		if s >= River.Sections[i].startS then
			return River.Sections[i]
		end
	end
	return River.Sections[1]
end

-- Плавно смешивает параметр участка на границах
local function blended(s: number, key: string): number
	local sec = River.sectionAt(s)
	local v = sec[key]
	local half = River.Blend / 2
	local i = sec.index
	if i > 1 and s < sec.startS + half then
		local prev = River.Sections[i - 1][key]
		local t = (s - (sec.startS - half)) / River.Blend
		return prev + (v - prev) * math.clamp(t, 0, 1)
	end
	if i < #River.Sections and s > sec.endS - half then
		local nxt = River.Sections[i + 1][key]
		local t = (s - (sec.endS - half)) / River.Blend
		return v + (nxt - v) * math.clamp(t, 0, 1)
	end
	return v
end

function River.width(s: number): number
	return blended(s, "width")
end

function River.current(s: number): number
	return blended(s, "current")
end

function River.bankHeight(s: number): number
	return blended(s, "bank")
end

function River.waterLevel(s: number): number
	return if s < River.dropS then River.LevelHigh else River.LevelLow
end

-- Насколько плот может отойти от оси, не касаясь берега
function River.halfFree(s: number, raftHalf: number): number
	return River.width(s) / 2 - raftHalf
end

-------------------------------------------------------------------------------
-- Препятствия и награды (детерминированно)
-------------------------------------------------------------------------------
River.rocks = {} :: { { id: number, s: number, x: number, r: number } }
River.coins = {} :: { { id: number, s: number, x: number, value: number, gold: boolean } }
River.gates = {} :: { { id: number, s: number, x: number, half: number } }
River.rows = {} :: { { s: number, gap: number, gapW: number } } -- для тестов и автопилота
River.whirlpool = nil :: { s: number, x: number, r: number, pull: number, slow: number }?
River.signs = {} :: { { s: number, side: number, key: string } }

local RAFT_HALF = 7
local GAP_W = 22 -- свободный проход между краями камней

local function addRock(s, x, r)
	table.insert(River.rocks, { id = #River.rocks + 1, s = s, x = x, r = r })
end
local function addCoin(s, x, gold)
	table.insert(
		River.coins,
		{ id = #River.coins + 1, s = s, x = x, value = if gold then 5 else 1, gold = gold == true }
	)
end

-- Ряд камней с гарантированным проходом шириной GAP_W вокруг gap
local function rockRow(rng, s, gap, density)
	local half = River.width(s) / 2 - 1.5
	table.insert(River.rows, { s = s, gap = gap, gapW = GAP_W })
	local function fill(a, b) -- отрезок [a, b] поперёк реки
		local x = a
		while x < b - 2 do
			local r = rng:range(2.6, 4.6)
			local cx = math.min(x + r, b - r)
			if cx - r >= a - 0.01 and rng:next() < density then
				addRock(s + rng:range(-3, 3), cx, r)
			end
			x = cx + r + rng:range(2, 7)
		end
	end
	fill(-half, gap - GAP_W / 2)
	fill(gap + GAP_W / 2, half)
end

-- Цепочка проходов: следующий проход не дальше maxShift от предыдущего
local function rowsSection(rng, sec, firstS, spacing, density, maxShift, coinsOnPath)
	local s = sec.startS + firstS
	local prevGap = 0
	local prevS = nil
	while s < sec.endS - 30 do
		local lim = River.halfFree(s, RAFT_HALF) - 2
		local lo = math.max(-lim, prevGap - maxShift)
		local hi = math.min(lim, prevGap + maxShift)
		local gap = rng:range(lo, hi)
		rockRow(rng, s, gap, density)
		if coinsOnPath and prevS then
			local n = math.floor((s - prevS) / 12)
			for k = 1, n - 1 do
				local t = k / n
				addCoin(prevS + (s - prevS) * t, prevGap + (gap - prevGap) * t, false)
			end
		end
		prevGap, prevS = gap, s
		s += spacing * rng:range(0.85, 1.15)
	end
end

do
	local rng = Rng.new(River.Seed)

	-- 1. Причал: учебная дорожка монет справа, затем слева
	local dock = byId.dock
	for k = 0, 4 do
		addCoin(dock.startS + 90 + k * 10, 9, false)
	end
	for k = 0, 3 do
		addCoin(dock.startS + 160 + k * 10, -8, false)
	end
	table.insert(River.signs, { s = River.dockS + 26, side = 1, key = "sign.right" })
	table.insert(River.signs, { s = River.dockS + 26, side = -1, key = "sign.left" })

	-- 2. Перекаты: редкие ряды
	rowsSection(rng, byId.riffles, 40, 75, 0.7, 16, true)

	-- 3. Каньон: ворота-слалом и камни у стен
	local canyon = byId.canyon
	local side = 1
	local s = canyon.startS + 50
	while s < canyon.endS - 40 do
		local lim = River.halfFree(s, RAFT_HALF)
		local gx = side * math.min(7, lim - 3)
		table.insert(River.gates, { id = #River.gates + 1, s = s, x = gx, half = 7 })
		addCoin(s, gx, false)
		local wallX = -side * (River.width(s) / 2 - 3)
		addRock(s + 20, wallX, 3.2)
		side = -side
		s += 80
	end
	table.insert(River.signs, { s = canyon.startS - 10, side = 1, key = "sign.gates" })

	-- 4. Омут: водоворот в центре, монеты по левой дуге, золотая — в самой воронке
	local pool = byId.pool
	local ws = pool.startS + pool.length / 2
	River.whirlpool = { s = ws, x = 0, r = 28, pull = 10, slow = 0.35 }
	for k = -4, 4 do
		local a = k / 4 * math.rad(70)
		addCoin(ws + math.sin(a) * 36, -math.cos(a) * 36, false)
	end
	addCoin(ws, 0, true)
	table.insert(River.signs, { s = pool.startS - 10, side = -1, key = "sign.whirl" })

	-- 5. «Зубы»: частые ряды + золотые монеты у самых камней
	rowsSection(rng, byId.teeth, 30, 50, 0.9, 13, true)
	for i, row in River.rows do
		if row.s > byId.teeth.startS and i % 3 == 0 then
			local edge = row.gap + (if rng:next() < 0.5 then -1 else 1) * (GAP_W / 2 + 1)
			addCoin(row.s - 14, edge, true)
		end
	end

	-- 6. Перед водопадом: пара рядов и чистая вода
	local falls = byId.falls
	rowsSection(rng, { startS = falls.startS, endS = falls.startS + 130 }, 20, 60, 0.6, 14, true)
	for k = 0, 6 do
		addCoin(River.dropS - 70 + k * 9, 0, false)
	end
	table.insert(River.signs, { s = River.warnDropS, side = 1, key = "sign.drop" })
	table.insert(River.signs, { s = River.warnDropS, side = -1, key = "sign.drop" })

	-- 7. Озеро: последние монеты перед финишем
	for k = 0, 5 do
		addCoin(River.dropS + 40 + k * 14, math.sin(k) * 10, false)
	end
end

table.sort(River.rocks, function(a, b)
	return a.s < b.s
end)
for i, r in River.rocks do
	r.id = i
end
table.sort(River.coins, function(a, b)
	return a.s < b.s
end)
for i, c in River.coins do
	c.id = i
end

function River.totalCoins(): number
	local n = 0
	for _, c in River.coins do
		n += c.value
	end
	return n
end

return River
