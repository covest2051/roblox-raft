--[[
	Точка входа сервера: строим мир, запускаем сервисы.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldBuilder = require(script.WorldBuilder)
local RaftModel = require(script.RaftModel)
local DataService = require(script.DataService)
local Monetization = require(script.Monetization)
local Cosmetics = require(script.Cosmetics)
local RaftService = require(script.RaftService)
local Actions = require(script.Actions)
local SelfTest = require(script.SelfTest)

-- данные и покупки — сразу: ProcessReceipt должен быть назначен как можно раньше
DataService.start()
Monetization.start()
Cosmetics.start()
Actions.selfTest = SelfTest.run
Actions.start()

local t0 = os.clock()
WorldBuilder.lighting()
RaftModel.setupGroups()
local ok, err = pcall(WorldBuilder.terrain)
if not ok then
	warn("[World] terrain failed:", err)
end
WorldBuilder.props()
local _, spawn = WorldBuilder.dock()
RaftService.start(spawn)
Workspace:SetAttribute("WorldReady", true)
print(string.format("[World] built in %.1fs", os.clock() - t0))

-- персонажи появляются только когда мир готов (CharacterAutoLoads = false)
local function spawnLoop(player: Player)
	player.CharacterAdded:Connect(function(character)
		local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				task.wait(2)
				if player.Parent then
					player:LoadCharacter()
				end
			end)
		end
	end)
	player:LoadCharacter()
end
Players.PlayerAdded:Connect(spawnLoop)
for _, p in Players:GetPlayers() do
	task.spawn(spawnLoop, p)
end

if RunService:IsStudio() then
	task.delay(4, SelfTest.run)
end
