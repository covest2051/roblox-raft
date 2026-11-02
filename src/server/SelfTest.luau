--[[
	SelfTest — проверки внутри движка (запускается в Studio при старте и кнопкой DBG).
	Пишет в Output строки [SELFTEST] PASS/WARN/FAIL и итог RESULT.
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local River = require(Shared.River)
local RaftSim = require(Shared.RaftSim)

local RaftService = require(script.Parent.RaftService)
local RaftModel = require(script.Parent.RaftModel)

local SelfTest = {}

function SelfTest.run(): { string }
	local lines = {}
	local pass, warns, total = 0, 0, 0
	local function check(name: string, fn: () -> (boolean | string, string?))
		total += 1
		local ok, res, detail = pcall(fn)
		local line
		if not ok then
			line = "[SELFTEST] FAIL " .. name .. ": " .. tostring(res)
		elseif res == true then
			pass += 1
			line = "[SELFTEST] PASS " .. name .. (if detail then " (" .. detail .. ")" else "")
		elseif res == "warn" then
			pass += 1
			warns += 1
			line = "[SELFTEST] WARN " .. name .. (if detail then ": " .. detail else "")
		else
			line = "[SELFTEST] FAIL " .. name .. (if detail then ": " .. detail else "")
		end
		print(line)
		table.insert(lines, line)
	end

	check("river water at the dock", function()
		local x, z = River.point(River.dockS, 0)
		local y = River.LevelHigh - 2
		local region = Region3.new(Vector3.new(x - 2, y - 2, z - 2), Vector3.new(x + 2, y + 2, z + 2))
			:ExpandToGrid(4)
		local mats = Workspace.Terrain:ReadVoxels(region, 4)
		local m = mats[1][1][1]
		return m == Enum.Material.Water, tostring(m)
	end)

	check("rocks, coins, gates built", function()
		local f = Workspace:FindFirstChild("River")
		if not f then
			return false, "no River folder"
		end
		local r, c, g = #f.Rocks:GetChildren(), #f.Coins:GetChildren(), #f.Gates:GetChildren()
		return r == #River.rocks and c == #River.coins and g == #River.gates,
			string.format("%d rocks, %d coins, %d gates", r, c, g)
	end)

	check("raft exists and is driven by physics", function()
		for _, raft in RaftService.rafts do
			local hull = raft.hull
			local ap = hull:FindFirstChild("AlignPosition")
			if raft.phase == "sunk" then
				continue
			end
			return ap ~= nil and not hull.Anchored, "raft " .. raft.id .. " (" .. raft.phase .. ")"
		end
		return "warn", "no raft right now (next one spawns in a few seconds)"
	end)

	check("raft physics owned by the server", function()
		for _, raft in RaftService.rafts do
			local owner = raft.hull:GetNetworkOwner()
			return owner == nil, tostring(owner)
		end
		return "warn", "no raft"
	end)

	check("collision groups", function()
		return PhysicsService:IsCollisionGroupRegistered(RaftModel.Group), RaftModel.Group
	end)

	check("spawn on the dock", function()
		local dock = Workspace:FindFirstChild("Dock")
		return dock ~= nil and dock:FindFirstChild("Spawn") ~= nil
	end)

	check("river is passable (autopilot)", function()
		local st = RaftSim.new()
		while not st.finished and not st.broken and st.t < 400 do
			local bx, bz = RaftSim.autopilot(st)
			RaftSim.step(st, bx, bz, Config.Timing.SimStep)
		end
		return st.finished and st.hp > 50, string.format("%.0fs, hp %d", st.t, st.hp)
	end)

	check("products configured", function()
		local missing = {}
		for _, k in Config.ProductOrder do
			if Config.Products[k].id == 0 then
				table.insert(missing, k)
			end
		end
		for k, p in Config.Passes do
			if p.id == 0 then
				table.insert(missing, k)
			end
		end
		if #missing > 0 then
			return "warn", "ID = 0 (emulated in Studio): " .. table.concat(missing, ", ")
		end
		return true
	end)

	check("player data saves", function()
		local p = Players:GetPlayers()[1]
		if not p then
			return "warn", "no players"
		end
		if p:GetAttribute("DataSaved") ~= true then
			return "warn",
				"DataStore off: Game Settings → Security → Enable Studio Access to API Services"
		end
		return true
	end)

	check("PolicyService answers", function()
		local p = Players:GetPlayers()[1]
		if not p then
			return "warn", "no players"
		end
		local info = PolicyService:GetPolicyInfoForPlayerAsync(p)
		return true, "ArePaidRandomItemsRestricted=" .. tostring(info.ArePaidRandomItemsRestricted)
	end)

	local result = string.format("[SELFTEST] RESULT %d/%d passed, %d warnings", pass, total, warns)
	print(result)
	table.insert(lines, result)
	return lines
end

return SelfTest
