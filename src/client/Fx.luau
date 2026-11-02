--[[
	Fx — всё, что видит и слышит только этот игрок: свои собранные монеты прячутся,
	монеты и водоворот крутятся, перевод табличек, звуки, тряска камеры при ударе.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Make = require(Shared.Make)

local Lang = require(script.Parent.Lang)

local player = Players.LocalPlayer

local Fx = {}

Fx.onShopPrompt = nil :: (() -> ())?

local hidden: { [string]: boolean } = {}
local sounds: { [string]: Sound } = {}
local shakeUntil, shakePower = 0, 0
local spin = 0
local baseCF: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function baseOf(p: BasePart): CFrame
	local cf = baseCF[p]
	if not cf then
		cf = p.CFrame
		baseCF[p] = cf
	end
	return cf
end

local function coinsFolder(): Instance?
	local river = Workspace:FindFirstChild("River")
	return river and river:FindFirstChild("Coins")
end

function Fx.hideCoin(id: number)
	local f = coinsFolder()
	local p = f and f:FindFirstChild(tostring(id)) :: BasePart?
	if p then
		hidden[p.Name] = true
		p.Transparency = 1
		local light = p:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = false
		end
	end
end

function Fx.resetCoins()
	local f = coinsFolder()
	if not f then
		return
	end
	for name in hidden do
		local p = f:FindFirstChild(name) :: BasePart?
		if p then
			p.Transparency = 0
			local light = p:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = true
			end
		end
	end
	hidden = {}
end

-- Таблички и подсказки на текущем языке
function Fx.localize()
	for _, d in Workspace:GetDescendants() do
		if d:IsA("TextLabel") then
			local key = d:GetAttribute("TextKey")
			if key then
				d.Text = Lang.t(key)
			end
		elseif d:IsA("ProximityPrompt") then
			local key = d:GetAttribute("ActionKey") or d.ActionText
			if string.find(key, "^prompt%.") then
				d:SetAttribute("ActionKey", key)
				d.ActionText = Lang.t(key)
			end
		end
	end
end

function Fx.play(name: string)
	local s = sounds[name]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

function Fx.shake(power: number)
	shakePower = math.max(shakePower, power)
	shakeUntil = os.clock() + 0.35
end

function Fx.build()
	for name, cfg in Config.Sounds do
		sounds[name] = Make("Sound", {
			Name = "Fx_" .. name,
			SoundId = cfg.Id,
			Volume = cfg.Volume,
			PlaybackSpeed = cfg.Speed or 1,
			Looped = name == "River",
			Parent = SoundService,
		})
	end
	if sounds.River then
		sounds.River:Play()
	end
	Fx.localize()
	Lang.onChange(Fx.localize)
	-- на случай StreamingEnabled: таблички, подгруженные позже, тоже переводим
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("TextLabel") and d:GetAttribute("TextKey") then
			d.Text = Lang.t(d:GetAttribute("TextKey"))
		end
	end)
	-- сундук на причале открывает магазин
	local dock = Workspace:FindFirstChild("Dock")
	local chest = dock and dock:FindFirstChild("Chest")
	local prompt = chest and chest:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function()
			if Fx.onShopPrompt then
				Fx.onShopPrompt()
			end
		end)
	end
end

function Fx.update(dt: number)
	spin += dt
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	-- монеты рядом с камерой покачиваются
	local f = coinsFolder()
	if f then
		for _, p in f:GetChildren() do
			if p:IsA("BasePart") and not hidden[p.Name] then
				local base = baseOf(p)
				if (base.Position - camPos).Magnitude < 160 then
					local k = tonumber(p.Name) or 0
					p.CFrame = base
						* CFrame.new(0, math.sin(spin * 2 + k) * 0.3, 0)
						* CFrame.Angles(0, spin * 2 + k, 0)
				end
			end
		end
	end
	-- водоворот: полосы пены бегут по кругу, у центра быстрее
	local river = Workspace:FindFirstChild("River")
	local wp = river and river:FindFirstChild("Whirlpool")
	if wp then
		local center =
			Vector3.new(wp:GetAttribute("CX") or 0, wp:GetAttribute("CY") or 0, wp:GetAttribute("CZ") or 0)
		if (center - camPos).Magnitude < 300 then
			for _, p in wp:GetChildren() do
				local r, a0 = p:GetAttribute("R"), p:GetAttribute("A")
				if p:IsA("BasePart") and r and a0 then
					local a = a0 + spin * (14 / math.max(r, 4))
					local pos = center + Vector3.new(math.cos(a) * r, 0.2, math.sin(a) * r)
					local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
					p.CFrame = CFrame.lookAt(pos, pos + tangent)
				end
			end
		end
	end
	-- тряска камеры
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		if os.clock() < shakeUntil then
			local p = shakePower
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * p, (math.random() - 0.5) * p, 0)
		elseif shakePower > 0 then
			shakePower = 0
			hum.CameraOffset = Vector3.zero
		end
	end
end

return Fx
