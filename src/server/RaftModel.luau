--[[
	RaftModel — плот из примитивов: брёвна, поперечины, верёвочные леера, флаг.
	Физика: все детали приварены к невидимому Hull; Hull ведут AlignPosition и
	AlignOrientation (RigidityEnabled), владелец физики — сервер.
	Персонажи на палубе едут за счёт обычной физики Humanoid.
]]

local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared.Make)
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)

local RaftModel = {}

RaftModel.Group = "Raft"
RaftModel.TerrainGroup = "Terrain"

function RaftModel.setupGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(RaftModel.Group)
		PhysicsService:RegisterCollisionGroup(RaftModel.TerrainGroup)
		PhysicsService:CollisionGroupSetCollidable(RaftModel.Group, RaftModel.Group, false)
		PhysicsService:CollisionGroupSetCollidable(RaftModel.Group, RaftModel.TerrainGroup, false)
		Workspace.Terrain.CollisionGroup = RaftModel.TerrainGroup
	end)
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function weldTo(hull: BasePart, p: BasePart)
	Make("WeldConstraint", { Part0 = hull, Part1 = p, Parent = p })
end

function RaftModel.build(id: number, cf: CFrame): Model
	local W, L = Config.Raft.Width, Config.Raft.Length
	local model = Make("Model", { Name = "Raft" .. id, Attributes = { RaftId = id } })
	local hull = Make("Part", {
		Name = "Hull",
		Size = Vector3.new(W, 1, L),
		CFrame = cf,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Massless = false,
		CollisionGroup = RaftModel.Group,
		Parent = model,
	})
	model.PrimaryPart = hull

	local function piece(props, role: string)
		local p = {
			Anchored = false,
			CanTouch = false,
			Massless = true,
			CollisionGroup = RaftModel.Group,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
			Parent = model,
		}
		for k, v in props do
			p[k] = v
		end
		local part = Make("Part", p)
		part:SetAttribute("Role", role)
		weldTo(hull, part)
		return part
	end

	-- брёвна вдоль течения (цилиндр лежит вдоль своей оси X → поворачиваем на 90° вокруг Y)
	local n = 7
	local d = W / n
	for i = 1, n do
		local x = -W / 2 + d * (i - 0.5)
		local len = L - (if i == 1 or i == n then 1.5 else 0) + ((i * 37) % 5) * 0.2
		piece({
			Name = "Log",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(len, d * 1.02, d * 1.02),
			CFrame = cf * CFrame.new(x, 0.5, 0) * CFrame.Angles(0, math.rad(90), 0),
			CanCollide = true,
		}, "Log")
	end
	-- поперечины
	for _, z in { -L / 2 + 2, 0, L / 2 - 2 } do
		piece({
			Name = "Beam",
			Size = Vector3.new(W + 0.6, 0.5, 1.1),
			CFrame = cf * CFrame.new(0, 1.35, z),
			CanCollide = true,
		}, "Beam")
	end
	-- плоский невидимый пол, чтобы не спотыкаться о брёвна
	piece({
		Name = "Deck",
		Size = Vector3.new(W, 0.4, L),
		CFrame = cf * CFrame.new(0, 1.4, 0),
		Transparency = 1,
		CanCollide = true,
	}, "Deck")
	-- столбики и леера (справа посередине — проход с причала)
	local posts = {
		{ -W / 2, -L / 2 },
		{ W / 2, -L / 2 },
		{ -W / 2, L / 2 },
		{ W / 2, L / 2 },
		{ -W / 2, 0 },
		{ W / 2, -L / 4 },
		{ W / 2, L / 4 },
	}
	for _, pt in posts do
		piece({
			Name = "Post",
			Size = Vector3.new(0.6, 3, 0.6),
			CFrame = cf * CFrame.new(pt[1], 2.9, pt[2]),
			CanCollide = true,
		}, "Rope")
	end
	local function rope(x0, z0, x1, z1)
		local a, b = Vector3.new(x0, 3.9, z0), Vector3.new(x1, 3.9, z1)
		local mid = (a + b) / 2
		piece({
			Name = "Rail",
			Size = Vector3.new(0.3, 0.3, (b - a).Magnitude),
			CFrame = cf * CFrame.lookAt(mid, b),
			CanCollide = true,
		}, "Rope")
	end
	rope(-W / 2, -L / 2, W / 2, -L / 2)
	rope(-W / 2, L / 2, W / 2, L / 2)
	rope(-W / 2, -L / 2, -W / 2, L / 2)
	rope(W / 2, -L / 2, W / 2, -L / 4)
	rope(W / 2, L / 4, W / 2, L / 2)
	-- флаг на корме
	piece({
		Name = "Mast",
		Size = Vector3.new(0.4, 9, 0.4),
		CFrame = cf * CFrame.new(-W / 2 + 1, 5.9, L / 2 - 1),
		CanCollide = false,
	}, "Mast")
	piece({
		Name = "Flag",
		Size = Vector3.new(0.12, 2.6, 4),
		CFrame = cf * CFrame.new(-W / 2 + 1, 9, L / 2 + 1),
		CanCollide = false,
	}, "Flag")
	-- светящаяся окантовка (видна только у «неоновых» раскрасок)
	for _, x in { -W / 2 - 0.05, W / 2 + 0.05 } do
		piece({
			Name = "Trim",
			Size = Vector3.new(0.25, 0.25, L - 1),
			CFrame = cf * CFrame.new(x, 1.2, 0),
			CanCollide = false,
			Material = Enum.Material.Neon,
		}, "Trim")
	end
	-- брызги у носа
	local att = Make("Attachment", { Name = "Bow", Position = Vector3.new(0, 0.2, -L / 2), Parent = hull })
	Make("ParticleEmitter", {
		Name = "Spray",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 0,
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(6, 10),
		SpreadAngle = Vector2.new(60, 20),
		Size = NumberSequence.new(1.2, 3),
		Transparency = NumberSequence.new(0.3, 1),
		Acceleration = Vector3.new(0, -30, 0),
		EmissionDirection = Enum.NormalId.Front,
		Parent = att,
	})

	-- привод
	local a0 = Make("Attachment", { Name = "Drive", Parent = hull })
	Make("AlignPosition", {
		Name = "AlignPosition",
		Mode = Enum.PositionAlignmentMode.OneAttachment,
		Attachment0 = a0,
		RigidityEnabled = true,
		Position = cf.Position,
		Parent = hull,
	})
	Make("AlignOrientation", {
		Name = "AlignOrientation",
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		Attachment0 = a0,
		RigidityEnabled = true,
		CFrame = cf.Rotation,
		Parent = hull,
	})

	RaftModel.applySkin(model, Catalog.Default.raft)
	model.Parent = Workspace:FindFirstChild("Rafts") or Make("Folder", { Name = "Rafts", Parent = Workspace })
	pcall(function()
		hull:SetNetworkOwner(nil)
	end)
	return model
end

function RaftModel.applySkin(model: Model, skinId: string)
	local item = Catalog.get(skinId) or Catalog.get(Catalog.Default.raft)
	assert(item, "default raft skin missing")
	local main, accent = rgb(item.color), rgb(item.accent)
	local material = (Enum.Material :: any)[item.material]
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			local role = p:GetAttribute("Role")
			if role == "Log" then
				p.Color = main
				p.Material = material
				p.Transparency = if item.material == "Glass" then 0.2 else 0
			elseif role == "Beam" or role == "Rope" then
				p.Color = accent
				p.Material = if role == "Rope" then Enum.Material.Fabric else Enum.Material.Wood
			elseif role == "Mast" then
				p.Color = Color3.fromRGB(80, 60, 40)
				p.Material = Enum.Material.Wood
			elseif role == "Flag" then
				p.Color = accent
				p.Material = if item.neon then Enum.Material.Neon else Enum.Material.Fabric
			elseif role == "Trim" then
				p.Color = accent
				p.Transparency = if item.neon then 0 else 1
			end
		end
	end
	model:SetAttribute("Skin", item.id)
end

-- Поза плота по модели RaftSim
function RaftModel.poseCFrame(
	x: number,
	y: number,
	z: number,
	heading: number,
	yaw: number,
	roll: number,
	pitch: number
): CFrame
	local h = heading + yaw
	local pos = Vector3.new(x, y, z)
	return CFrame.lookAt(pos, pos + Vector3.new(math.cos(h), 0, math.sin(h)))
		* CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
end

function RaftModel.drive(model: Model, cf: CFrame)
	local hull = model.PrimaryPart :: BasePart
	local ap = hull:FindFirstChild("AlignPosition") :: AlignPosition
	local ao = hull:FindFirstChild("AlignOrientation") :: AlignOrientation
	ap.Position = cf.Position
	ao.CFrame = cf.Rotation
end

function RaftModel.setSpray(model: Model, rate: number)
	local hull = model.PrimaryPart
	local bow = hull and hull:FindFirstChild("Bow")
	local e = bow and bow:FindFirstChild("Spray") :: ParticleEmitter?
	if e then
		e.Rate = rate
	end
end

-- Развал: снимаем сварку и привод, детали якорим — дальше их разносит RaftService
function RaftModel.breakApart(model: Model): { BasePart }
	local parts = {}
	local hull = model.PrimaryPart
	if hull then
		for _, c in hull:GetChildren() do
			if c:IsA("AlignPosition") or c:IsA("AlignOrientation") then
				c:Destroy()
			end
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("WeldConstraint") then
			p:Destroy()
		elseif p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			if p ~= hull and p:GetAttribute("Role") ~= "Deck" then
				table.insert(parts, p)
			end
		end
	end
	return parts
end

return RaftModel
