--[[
	DebugPanel — кнопка DBG справа сверху, только в Studio.
	Автопилот, перенос плота по участкам, урон, монеты, сброс профиля, самотест, язык.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Ui = require(script.Parent.Ui)
local Lang = require(script.Parent.Lang)

local DebugPanel = {}

function DebugPanel.build()
	if not RunService:IsStudio() then
		return
	end
	local root = Ui.screen()
	local toggle = Ui.button({
		Name = "DebugToggle",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64),
		Size = UDim2.fromOffset(56, 30),
		TextSize = 14,
		BackgroundColor3 = Color3.fromRGB(90, 40, 90),
		Text = "DBG",
		Parent = root,
	})
	local panel = Ui.panel({
		Name = "Debug",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 100),
		Size = UDim2.fromOffset(200, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = root,
	})
	Ui.Make("UIListLayout", { Padding = UDim.new(0, 4), Parent = panel })
	Ui.Make("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		Parent = panel,
	})
	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	local function cmd(text: string, c: string, arg: any?)
		local b = Ui.button({ Size = UDim2.new(1, 0, 0, 28), TextSize = 14, Text = text, Parent = panel })
		b.Activated:Connect(function()
			Net.ClientAction:FireServer({ t = "debug", cmd = c, arg = arg })
		end)
	end
	cmd("Autopilot on/off", "auto")
	cmd("→ Canyon", "skip", "canyon")
	cmd("→ Whirlpool", "skip", "pool")
	cmd("→ Teeth", "skip", "teeth")
	cmd("→ Waterfall", "skip", "falls")
	cmd("Hull → 1", "damage", 1)
	cmd("+1000 coins", "coins", 1000)
	cmd("Reset profile", "reset")
	cmd("Self-test", "selftest")
	local lang = Ui.button({ Size = UDim2.new(1, 0, 0, 28), TextSize = 14, Text = "RU / EN", Parent = panel })
	lang.Activated:Connect(Lang.toggle)
end

return DebugPanel
