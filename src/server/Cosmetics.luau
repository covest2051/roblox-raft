--[[
	Cosmetics — спасательный жилет на персонаже и табличка VIP над головой.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared.Make)
local Catalog = require(Shared.Catalog)
local Profile = require(Shared.Profile)

local Data = require(script.Parent.DataService)
local Monetization = require(script.Parent.Monetization)

local Cosmetics = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Cosmetics.effective(player: Player, kind: string): string
	local d = Data.get(player)
	if not d then
		return Catalog.Default[kind]
	end
	return Profile.effective(d, kind, Monetization.hasPass(player, "Vip"))
end

local function torsoOf(character: Model): BasePart?
	return (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
end

function Cosmetics.applyVest(character: Model, vestId: string)
	local old = character:FindFirstChild("LifeVest")
	if old then
		old:Destroy()
	end
	local torso = torsoOf(character)
	local item = Catalog.get(vestId) or Catalog.get(Catalog.Default.vest)
	if not torso or not item then
		return
	end
	local folder = Make("Model", { Name = "LifeVest", Attributes = { Vest = item.id } })
	local size = torso.Size
	local function piece(name, sz: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
		local p = Make("Part", {
			Name = name,
			Size = sz,
			CFrame = torso.CFrame * offset,
			Color = color,
			Material = material,
			Anchored = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Massless = true,
			CastShadow = false,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
			Parent = folder,
		})
		Make("WeldConstraint", { Part0 = torso, Part1 = p, Parent = p })
		return p
	end
	local main, accent = rgb(item.color), rgb(item.accent)
	local mat = (Enum.Material :: any)[item.material]
	local body = piece(
		"Body",
		Vector3.new(size.X * 1.08, size.Y * 0.82, size.Z * 1.45),
		CFrame.new(0, -size.Y * 0.04, 0),
		main,
		mat
	)
	if item.material == "Glass" then
		body.Transparency = 0.25
	end
	local stripeMat = if item.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for _, y in { -0.18, 0.12 } do
		piece(
			"Stripe",
			Vector3.new(size.X * 1.1, size.Y * 0.08, size.Z * 1.5),
			CFrame.new(0, size.Y * y, 0),
			accent,
			stripeMat
		)
	end
	piece(
		"Collar",
		Vector3.new(size.X * 0.7, size.Y * 0.18, size.Z * 1.3),
		CFrame.new(0, size.Y * 0.42, 0),
		main,
		mat
	)
	folder.Parent = character
end

function Cosmetics.applyTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("VipTag")
	if old then
		old:Destroy()
	end
	if not Monetization.hasPass(player, "Vip") then
		return
	end
	local gui = Make("BillboardGui", {
		Name = "VipTag",
		Size = UDim2.fromOffset(80, 26),
		StudsOffset = Vector3.new(0, 2.6, 0),
		AlwaysOnTop = false,
		MaxDistance = 80,
		Parent = head,
	})
	Make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 30, 10),
		BackgroundTransparency = 0.3,
		Font = Enum.Font.BuilderSansBold,
		Text = "★ VIP",
		TextColor3 = Color3.fromRGB(255, 205, 60),
		TextScaled = true,
		Parent = gui,
	}, { Make("UICorner", { CornerRadius = UDim.new(0, 6) }) })
end

function Cosmetics.refresh(player: Player)
	local character = player.Character
	if character then
		Cosmetics.applyVest(character, Cosmetics.effective(player, "vest"))
		Cosmetics.applyTag(player)
	end
end

function Cosmetics.start()
	local function onCharacter(player: Player, character: Model)
		local t0 = os.clock()
		while not torsoOf(character) and os.clock() - t0 < 5 do
			task.wait(0.1)
		end
		Data.get(player, 10)
		if player.Character == character then
			Cosmetics.refresh(player)
		end
	end
	local function added(player: Player)
		player.CharacterAdded:Connect(function(c)
			onCharacter(player, c)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Monetization.onPass(function(player, key)
		if key == "Vip" then
			Cosmetics.refresh(player)
		end
	end)
end

return Cosmetics
