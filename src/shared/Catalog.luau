--[[
	Catalog — косметика: спасательные жилеты (на персонаже) и раскраски плота.
	Шансы сундука считаются в целых «сотых процента» (Config.WeightTotal = 10000),
	поэтому показанные игроку проценты точные, без округления.
]]

local Shared = script.Parent
local Config = require(Shared.Config)

local Catalog = {}

export type Item = {
	id: string,
	kind: "vest" | "raft",
	rarity: string, -- Common | Rare | Epic | Legendary | Default | Vip
	color: { number }, -- основной цвет RGB
	accent: { number }, -- второй цвет (полосы жилета, верёвки плота)
	material: string, -- имя Enum.Material
	neon: boolean?, -- светящиеся полосы
}

Catalog.Items = {
	-- по умолчанию, у всех
	{
		id = "vest_orange",
		kind = "vest",
		rarity = "Default",
		color = { 255, 120, 30 },
		accent = { 240, 240, 240 },
		material = "SmoothPlastic",
	},
	{
		id = "raft_pine",
		kind = "raft",
		rarity = "Default",
		color = { 160, 112, 66 },
		accent = { 210, 190, 140 },
		material = "Wood",
	},
	-- Common
	{
		id = "vest_lime",
		kind = "vest",
		rarity = "Common",
		color = { 150, 220, 60 },
		accent = { 30, 40, 30 },
		material = "SmoothPlastic",
	},
	{
		id = "vest_sky",
		kind = "vest",
		rarity = "Common",
		color = { 90, 180, 250 },
		accent = { 250, 250, 250 },
		material = "SmoothPlastic",
	},
	{
		id = "vest_pink",
		kind = "vest",
		rarity = "Common",
		color = { 255, 130, 190 },
		accent = { 255, 240, 120 },
		material = "SmoothPlastic",
	},
	{
		id = "raft_birch",
		kind = "raft",
		rarity = "Common",
		color = { 225, 220, 205 },
		accent = { 60, 55, 50 },
		material = "Wood",
	},
	{
		id = "raft_darkoak",
		kind = "raft",
		rarity = "Common",
		color = { 92, 62, 40 },
		accent = { 190, 160, 110 },
		material = "Wood",
	},
	-- Rare
	{
		id = "vest_camo",
		kind = "vest",
		rarity = "Rare",
		color = { 92, 110, 60 },
		accent = { 60, 70, 40 },
		material = "Fabric",
	},
	{
		id = "vest_stripes",
		kind = "vest",
		rarity = "Rare",
		color = { 250, 250, 250 },
		accent = { 220, 40, 40 },
		material = "SmoothPlastic",
	},
	{
		id = "vest_navy",
		kind = "vest",
		rarity = "Rare",
		color = { 30, 45, 90 },
		accent = { 255, 200, 40 },
		material = "Fabric",
	},
	{
		id = "raft_bamboo",
		kind = "raft",
		rarity = "Rare",
		color = { 196, 190, 96 },
		accent = { 90, 120, 40 },
		material = "Wood",
	},
	{
		id = "raft_barrels",
		kind = "raft",
		rarity = "Rare",
		color = { 180, 60, 40 },
		accent = { 70, 70, 75 },
		material = "WoodPlanks",
	},
	-- Epic
	{
		id = "vest_neon",
		kind = "vest",
		rarity = "Epic",
		color = { 30, 30, 40 },
		accent = { 0, 255, 230 },
		material = "SmoothPlastic",
		neon = true,
	},
	{
		id = "vest_lava",
		kind = "vest",
		rarity = "Epic",
		color = { 40, 20, 20 },
		accent = { 255, 110, 20 },
		material = "Basalt",
		neon = true,
	},
	{
		id = "raft_ice",
		kind = "raft",
		rarity = "Epic",
		color = { 170, 220, 255 },
		accent = { 240, 250, 255 },
		material = "Ice",
	},
	{
		id = "raft_lava",
		kind = "raft",
		rarity = "Epic",
		color = { 50, 30, 28 },
		accent = { 255, 100, 20 },
		material = "Basalt",
		neon = true,
	},
	-- Legendary
	{
		id = "vest_aurora",
		kind = "vest",
		rarity = "Legendary",
		color = { 120, 60, 200 },
		accent = { 80, 255, 170 },
		material = "Glass",
		neon = true,
	},
	{
		id = "raft_crystal",
		kind = "raft",
		rarity = "Legendary",
		color = { 170, 120, 255 },
		accent = { 255, 255, 255 },
		material = "Glass",
		neon = true,
	},
	-- только VIP
	{
		id = "vest_gold",
		kind = "vest",
		rarity = "Vip",
		color = { 255, 200, 50 },
		accent = { 255, 255, 255 },
		material = "Foil",
	},
	{
		id = "raft_gold",
		kind = "raft",
		rarity = "Vip",
		color = { 240, 190, 60 },
		accent = { 255, 240, 180 },
		material = "Foil",
	},
}

Catalog.Default = { vest = "vest_orange", raft = "raft_pine" }

local byId: { [string]: Item } = {}
local byRarity: { [string]: { Item } } = {}
for _, item in Catalog.Items do
	byId[item.id] = item
	byRarity[item.rarity] = byRarity[item.rarity] or {}
	table.insert(byRarity[item.rarity], item)
end

function Catalog.get(id: string): Item?
	return byId[id]
end

function Catalog.ofRarity(rarity: string): { Item }
	return byRarity[rarity] or {}
end

-- Предмет можно получить из сундука или купить (за монеты/Robux)
function Catalog.isTradable(item: Item): boolean
	return Config.Rarity[item.rarity] ~= nil
end

function Catalog.price(id: string): number?
	local item = byId[id]
	local r = item and Config.Rarity[item.rarity]
	return r and r.price
end

function Catalog.refund(id: string): number
	local item = byId[id]
	local r = item and Config.Rarity[item.rarity]
	return if r then r.refund else 0
end

--[[
	Точные шансы сундука: { {id, rarity, bp} }, bp — сотые доли процента.
	Сумма bp = Config.WeightTotal. Вес редкости делится между её предметами поровну;
	тест проверяет, что деление без остатка.
]]
function Catalog.odds(): { { id: string, rarity: string, bp: number } }
	local out = {}
	for _, rarity in Config.RarityOrder do
		local items = byRarity[rarity] or {}
		local w = Config.Rarity[rarity].weight
		for _, item in items do
			table.insert(out, { id = item.id, rarity = rarity, bp = math.floor(w / #items) })
		end
	end
	return out
end

function Catalog.rarityPercent(rarity: string): string
	return Catalog.formatBp(Config.Rarity[rarity].weight)
end

-- 1250 → "12.5%", 560 → "5.6%", 100 → "1%"
function Catalog.formatBp(bp: number): string
	local s = string.format("%.2f", bp / 100)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s .. "%"
end

--[[
	Бросок сундука. randInt(a, b) — целое в [a, b] (на сервере — Random.new():NextInteger).
	Возвращает id предмета.
]]
function Catalog.roll(randInt: (number, number) -> number): string
	local odds = Catalog.odds()
	local r = randInt(1, Config.WeightTotal)
	local acc = 0
	for _, o in odds do
		acc += o.bp
		if r <= acc then
			return o.id
		end
	end
	return odds[#odds].id
end

return Catalog
