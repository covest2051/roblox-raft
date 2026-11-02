--[[
	Ui — общие стили и маленькие фабрики элементов интерфейса.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Make = require(Shared.Make)
local Config = require(Shared.Config)

local Ui = {}

Ui.Make = Make
Ui.font = Enum.Font.BuilderSans
Ui.fontBold = Enum.Font.BuilderSansBold

Ui.colors = {
	text = Color3.fromRGB(245, 248, 252),
	dim = Color3.fromRGB(180, 194, 210),
	panel = Color3.fromRGB(14, 32, 44),
	panel2 = Color3.fromRGB(24, 52, 68),
	button = Color3.fromRGB(36, 78, 98),
	gold = Color3.fromRGB(255, 200, 60),
	good = Color3.fromRGB(110, 220, 140),
	danger = Color3.fromRGB(255, 92, 72),
	warn = Color3.fromRGB(255, 170, 40),
	robux = Color3.fromRGB(40, 170, 90),
	water = Color3.fromRGB(70, 170, 200),
}

function Ui.rarityColor(rarity: string): Color3
	local r = Config.Rarity[rarity]
	if r then
		return Color3.fromRGB(r.color[1], r.color[2], r.color[3])
	end
	if rarity == "Vip" then
		return Ui.colors.gold
	end
	return Ui.colors.dim
end

local screen: ScreenGui? = nil

function Ui.screen(): ScreenGui
	if screen then
		return screen
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen = Make("ScreenGui", {
		Name = "RaftUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = pg,
	})
	return screen :: ScreenGui
end

-- Масштаб панелей под экран (макет 1280×720). UIScale вешается на панели, не на весь экран.
local scales: { UIScale } = {}
local currentScale = 1

local function computeScale()
	local ok, vp = pcall(function()
		return workspace.CurrentCamera.ViewportSize
	end)
	if ok and vp and vp.X > 0 then
		currentScale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.25)
	end
	for _, s in scales do
		s.Scale = currentScale
	end
end

function Ui.scaled<T>(obj: T): T
	local s = Make("UIScale", { Scale = currentScale, Parent = obj })
	table.insert(scales, s)
	return obj
end

function Ui.watchViewport()
	computeScale()
	pcall(function()
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(computeScale)
	end)
end

function Ui.isSmall(): boolean
	return currentScale < 0.8
end

function Ui.label(props)
	local p = {
		BackgroundTransparency = 1,
		Font = Ui.font,
		TextColor3 = Ui.colors.text,
		TextStrokeTransparency = 0.7,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextSize = 18,
		TextWrapped = true,
		RichText = true,
	}
	for k, v in props do
		p[k] = v
	end
	return Make("TextLabel", p)
end

function Ui.panel(props)
	local p = {
		BackgroundColor3 = Ui.colors.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}
	for k, v in props do
		p[k] = v
	end
	local f = Make("Frame", p)
	Make("UICorner", { CornerRadius = UDim.new(0, 12), Parent = f })
	return f
end

function Ui.button(props)
	local p = {
		BackgroundColor3 = Ui.colors.button,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Font = Ui.fontBold,
		TextColor3 = Ui.colors.text,
		TextSize = 18,
		AutoButtonColor = true,
	}
	for k, v in props do
		p[k] = v
	end
	local b = Make("TextButton", p)
	Make("UICorner", { CornerRadius = UDim.new(0, 10), Parent = b })
	return b
end

function Ui.stroke(obj: Instance, color: Color3, thickness: number?)
	return Make("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = obj,
	})
end

return Ui
