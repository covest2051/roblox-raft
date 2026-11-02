--[[
	Выгружает реку в JSON для карты: lune run scripts/export_map.luau build/map.json
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/lib/Loader")

local River = Loader.shared("River")
local Config = Loader.shared("Config")
local RaftSim = Loader.shared("RaftSim")

local out = { banks = {}, rocks = {}, coins = {}, gates = {}, sections = {}, path = {} }
for s = 0, River.length, 8 do
	local lx, lz = River.point(s, -River.width(s) / 2)
	local rx, rz = River.point(s, River.width(s) / 2)
	table.insert(out.banks, { s = s, lx = lx, lz = lz, rx = rx, rz = rz })
end
for _, r in River.rocks do
	local x, z = River.point(r.s, r.x)
	table.insert(out.rocks, { x = x, z = z, r = r.r })
end
for _, c in River.coins do
	local x, z = River.point(c.s, c.x)
	table.insert(out.coins, { x = x, z = z, gold = c.gold })
end
for _, g in River.gates do
	local ax, az = River.point(g.s, g.x - g.half)
	local bx, bz = River.point(g.s, g.x + g.half)
	table.insert(out.gates, { ax = ax, az = az, bx = bx, bz = bz })
end
for _, sec in River.Sections do
	local x, z = River.point(sec.startS + sec.length / 2, River.width(sec.startS + sec.length / 2) / 2 + 30)
	table.insert(out.sections, { id = sec.id, x = x, z = z })
end
local wp = River.whirlpool
if wp then
	local x, z = River.point(wp.s, wp.x)
	out.whirlpool = { x = x, z = z, r = wp.r }
end
local function at(s, x)
	local px, pz = River.point(s, x or 0)
	return { x = px, z = pz }
end
out.drop =
	{ a = at(River.dropS, -River.width(River.dropS) / 2), b = at(River.dropS, River.width(River.dropS) / 2) }
out.finish = { a = at(River.finishS, -30), b = at(River.finishS, 30) }
out.dock = at(River.dockS, 0)
-- путь внимательного экипажа (автопилот)
local st = RaftSim.new()
local n = 0
while not st.finished and not st.broken do
	local bx, bz = RaftSim.autopilot(st)
	RaftSim.step(st, bx, bz, Config.Timing.SimStep)
	n += 1
	if n % 15 == 0 then
		table.insert(out.path, at(st.s, st.x))
	end
end
local path = process.args[1] or "build/map.json"
fs.writeFile(path, serde.encode("json", out))
print("saved " .. path)
