--[[
	WorldBuilder — строит реку кодом: Terrain (берега, русло, вода), камни, монеты,
	ворота, водоворот, водопад, причал, финиш, деревья, таблички.
	Всё детерминировано (River + Rng), одинаково на каждом сервере.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared.Make)
local River = require(Shared.River)
local Rng = require(Shared.Rng)
local Config = require(Shared.Config)

local WorldBuilder = {}

local CHUNK = 8
local BANK_W = 70 -- ширина берега от кромки воды
local BED = 9 -- глубина русла

local function chunkCF(s: number, y: number): CFrame
	local x, z, h = River.center(s)
	return CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x + math.cos(h), y, z + math.sin(h)))
end

-- Блок вдоль реки: ширина поперёк (X), высота от y0 до y1, длина вдоль (Z)
local function fill(
	terrain: Terrain,
	s: number,
	width: number,
	y0: number,
	y1: number,
	material: Enum.Material
)
	if y1 - y0 < 0.5 then
		return
	end
	local cf = chunkCF(s, (y0 + y1) / 2)
	terrain:FillBlock(cf, Vector3.new(width, y1 - y0, CHUNK + 2.5), material)
end

function WorldBuilder.terrain()
	local terrain = Workspace.Terrain
	terrain:Clear()
	pcall(function()
		terrain.WaterWaveSize = 0.35
		terrain.WaterWaveSpeed = 14
		terrain.WaterReflectance = 0.4
		terrain.WaterTransparency = 0.55
		terrain.WaterColor = Color3.fromRGB(40, 110, 120)
		terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 140, 70))
		terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(120, 116, 110))
		terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(170, 158, 120))
	end)
	local low = River.LevelLow
	local from, to = -40, River.length + 60

	-- 1. Берега (до самой высокой точки участка)
	for s = from, to, CHUNK do
		local level = River.waterLevel(s)
		local top = level + River.bankHeight(s)
		local w = River.width(s)
		local rocky = River.sectionAt(s).rock
		fill(
			terrain,
			s,
			w + BANK_W * 2,
			low - 30,
			top,
			if rocky then Enum.Material.Rock else Enum.Material.Ground
		)
		if not rocky then
			fill(terrain, s, w + BANK_W * 2, top - 3, top, Enum.Material.Grass)
		end
	end
	-- 2. Русло: вырезаем, кладём песок, наливаем воду
	for s = math.max(from, -8), math.min(to, River.length + 4), CHUNK do
		local level = River.waterLevel(s)
		local w = River.width(s)
		local top = level + River.bankHeight(s)
		fill(terrain, s, w, level - BED, top + 60, Enum.Material.Air)
		if not River.sectionAt(s).rock then
			fill(terrain, s, w + 12, level + 1.2, top + 60, Enum.Material.Air) -- полоска пляжа
		end
	end
	for s = math.max(from, -8), math.min(to, River.length + 4), CHUNK do
		local level = River.waterLevel(s)
		local w = River.width(s)
		fill(terrain, s, w + 0.5, level - BED - 2, level - BED + 0.5, Enum.Material.Sand)
		fill(terrain, s, w, level - BED + 0.5, level, Enum.Material.Water)
	end
end

-------------------------------------------------------------------------------
-- Детали
-------------------------------------------------------------------------------
local function worldAt(s: number, x: number, y: number): Vector3
	local wx, wz = River.point(s, x)
	return Vector3.new(wx, y, wz)
end

local function facing(s: number, x: number, y: number): CFrame
	local p = worldAt(s, x, y)
	local h = River.heading(s)
	return CFrame.lookAt(p, p + Vector3.new(math.cos(h), 0, math.sin(h)))
end

local function part(props)
	local p = {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}
	for k, v in props do
		p[k] = v
	end
	return Make("Part", p)
end

local function sign(parent: Instance, cf: CFrame, key: string, color: Color3?)
	local board = part({
		Name = "Sign",
		Size = Vector3.new(12, 5, 0.6),
		CFrame = cf * CFrame.new(0, 5.5, 0),
		Color = color or Color3.fromRGB(120, 84, 50),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
		Parent = parent,
	})
	part({
		Name = "Post",
		Size = Vector3.new(0.8, 6, 0.8),
		CFrame = cf * CFrame.new(0, 2.5, 0.4),
		Color = Color3.fromRGB(90, 62, 40),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local gui = Make("SurfaceGui", {
		Face = Enum.NormalId.Front,
		CanvasSize = Vector2.new(480, 200),
		LightInfluence = 0.6,
		Parent = board,
	})
	Make("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.BuilderSansBold,
		TextColor3 = Color3.fromRGB(255, 244, 220),
		TextScaled = true,
		TextWrapped = true,
		Text = key,
		Attributes = { TextKey = key },
		Parent = gui,
	})
	return board
end

local function boulder(parent: Instance, rng, rock, level: number)
	local m = Make("Model", { Name = "Rock" .. rock.id, Attributes = { S = rock.s, X = rock.x } })
	local base = worldAt(rock.s, rock.x, level)
	local n = 3
	for i = 1, n do
		local r = rock.r * (if i == 1 then 1 else rng:range(0.55, 0.8))
		local off = if i == 1
			then Vector3.zero
			else Vector3.new(rng:range(-1, 1), 0, rng:range(-1, 1)) * rock.r * 0.5
		part({
			Name = "Stone",
			Size = Vector3.new(r * 1.9, r * rng:range(1.3, 2.0), r * 1.8),
			CFrame = CFrame.new(base + off + Vector3.new(0, r * 0.25, 0))
				* CFrame.Angles(rng:range(-0.4, 0.4), rng:range(0, math.pi), rng:range(-0.4, 0.4)),
			Color = Color3.fromRGB(105 + rng:int(-10, 10), 104 + rng:int(-10, 10), 100 + rng:int(-10, 10)),
			Material = Enum.Material.Slate,
			CastShadow = true,
			Parent = m,
		})
	end
	-- пена вокруг
	part({
		Name = "Foam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, rock.r * 2 + 4, rock.r * 2 + 4),
		CFrame = CFrame.new(base + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(240, 250, 255),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.45,
		Parent = m,
	})
	m.Parent = parent
end

local function tree(parent: Instance, rng, pos: Vector3)
	local h = rng:range(14, 26)
	local m = Make("Model", { Name = "Tree" })
	part({
		Name = "Trunk",
		Size = Vector3.new(1.4, h * 0.45, 1.4),
		CFrame = CFrame.new(pos + Vector3.new(0, h * 0.2, 0)),
		Color = Color3.fromRGB(96, 70, 48),
		Material = Enum.Material.Wood,
		CanCollide = true,
		Parent = m,
	})
	local green = Color3.fromRGB(40 + rng:int(-8, 8), 92 + rng:int(-12, 12), 52 + rng:int(-8, 8))
	for i = 0, 2 do
		local w = h * (0.42 - i * 0.11)
		part({
			Name = "Crown",
			Size = Vector3.new(w, h * 0.32, w),
			CFrame = CFrame.new(pos + Vector3.new(0, h * (0.4 + i * 0.2), 0))
				* CFrame.Angles(0, rng:range(0, 1.5), 0),
			Color = green,
			Material = Enum.Material.Grass,
			CastShadow = true,
			Parent = m,
		})
	end
	m.Parent = parent
end

function WorldBuilder.props(): Folder
	local old = Workspace:FindFirstChild("River")
	if old then
		old:Destroy()
	end
	local folder = Make("Folder", { Name = "River" })
	local rng = Rng.new(River.Seed + 1)

	-- камни
	local rocks = Make("Folder", { Name = "Rocks", Parent = folder })
	for _, rock in River.rocks do
		boulder(rocks, rng, rock, River.waterLevel(rock.s))
	end

	-- монеты (видимость своих собранных монет клиент прячет сам)
	local coins = Make("Folder", { Name = "Coins", Parent = folder })
	for _, c in River.coins do
		local size = if c.gold then 4.2 else 3
		local p = part({
			Name = tostring(c.id),
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, size, size),
			CFrame = facing(c.s, c.x, River.waterLevel(c.s) + 3.4) * CFrame.Angles(0, math.rad(90), 0),
			Color = if c.gold then Color3.fromRGB(255, 196, 40) else Color3.fromRGB(255, 214, 90),
			Material = Enum.Material.Neon,
			CanQuery = false,
			Attributes = { Value = c.value },
			Parent = coins,
		})
		if c.gold then
			Make(
				"PointLight",
				{ Color = Color3.fromRGB(255, 200, 80), Range = 10, Brightness = 1.5, Parent = p }
			)
		end
	end

	-- ворота-слалом: два шеста с флажками и перекладина
	local gates = Make("Folder", { Name = "Gates", Parent = folder })
	for _, g in River.gates do
		local level = River.waterLevel(g.s)
		local m = Make("Model", { Name = "Gate" .. g.id, Parent = gates })
		for _, side in { -1, 1 } do
			local base = facing(g.s, g.x + side * g.half, level)
			part({
				Name = "Pole",
				Size = Vector3.new(0.8, 12, 0.8),
				CFrame = base * CFrame.new(0, 5, 0),
				Color = Color3.fromRGB(240, 240, 240),
				Material = Enum.Material.SmoothPlastic,
				Parent = m,
			})
			for k = 0, 2 do
				part({
					Name = "Stripe",
					Size = Vector3.new(0.9, 1.2, 0.9),
					CFrame = base * CFrame.new(0, 1 + k * 3.4, 0),
					Color = Color3.fromRGB(220, 40, 40),
					Material = Enum.Material.SmoothPlastic,
					Parent = m,
				})
			end
			part({
				Name = "Buoy",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(2.4, 2.4, 2.4),
				CFrame = base,
				Color = Color3.fromRGB(255, 120, 30),
				Material = Enum.Material.SmoothPlastic,
				Parent = m,
			})
		end
		part({
			Name = "Banner",
			Size = Vector3.new(g.half * 2, 1.6, 0.3),
			CFrame = facing(g.s, g.x, level + 10.6),
			Color = Color3.fromRGB(255, 200, 40),
			Material = Enum.Material.Neon,
			Parent = m,
		})
	end

	-- водоворот: тёмная воронка и полосы пены (клиент вращает их вокруг центра)
	local wp = River.whirlpool
	if wp then
		local level = River.waterLevel(wp.s)
		local c = worldAt(wp.s, wp.x, level)
		local m = Make("Model", {
			Name = "Whirlpool",
			Attributes = { CX = c.X, CY = c.Y, CZ = c.Z },
			Parent = folder,
		})
		part({
			Name = "Funnel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, wp.r * 1.2, wp.r * 1.2),
			CFrame = CFrame.new(c + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(20, 60, 74),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.35,
			Parent = m,
		})
		local n = 0
		for ring = 1, 3 do
			local r = wp.r * ring / 3.2
			for k = 1, 4 + ring * 2 do
				n += 1
				local a = (k / (4 + ring * 2)) * math.pi * 2 + ring
				part({
					Name = "Streak",
					Size = Vector3.new(0.6, 0.12, 3 + ring * 2),
					CFrame = CFrame.new(c + Vector3.new(math.cos(a) * r, 0.2, math.sin(a) * r)),
					Color = Color3.fromRGB(235, 248, 255),
					Material = Enum.Material.SmoothPlastic,
					Transparency = 0.3,
					Attributes = { A = a, R = r },
					Parent = m,
				})
			end
		end
		_ = n
	end

	-- водопад: струи и пена внизу
	do
		local m = Make("Model", { Name = "Waterfall", Parent = folder })
		local w = River.width(River.dropS - 2)
		local top, bottom = River.LevelHigh, River.LevelLow
		part({
			Name = "Sheet",
			Size = Vector3.new(w, top - bottom, 1),
			CFrame = facing(River.dropS + 1, 0, (top + bottom) / 2),
			Color = Color3.fromRGB(210, 235, 245),
			Material = Enum.Material.Glass,
			Transparency = 0.35,
			Parent = m,
		})
		local foam = part({
			Name = "Foam",
			Size = Vector3.new(w + 6, 1, 14),
			CFrame = facing(River.dropS + 8, 0, bottom + 0.2),
			Color = Color3.fromRGB(245, 250, 255),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.3,
			Parent = m,
		})
		Make("ParticleEmitter", {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Rate = 40,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(4, 8),
			SpreadAngle = Vector2.new(40, 40),
			Size = NumberSequence.new(4, 9),
			Transparency = NumberSequence.new(0.4, 1),
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			Parent = foam,
		})
	end

	-- таблички
	local signs = Make("Folder", { Name = "Signs", Parent = folder })
	for _, sg in River.signs do
		local x = sg.side * (River.width(sg.s) / 2 + 4)
		local level = River.waterLevel(sg.s)
		local y = level + River.bankHeight(sg.s)
		if River.sectionAt(sg.s).rock then
			y = level + 1 -- в каньоне — на воде у стены, на плавучей опоре
			x = sg.side * (River.width(sg.s) / 2 - 2)
		end
		local cf = facing(sg.s, x, y) * CFrame.Angles(0, math.rad(180), 0)
		sign(signs, cf, sg.key)
	end

	-- финиш: арка через озеро
	do
		local m = Make("Model", { Name = "Finish", Parent = folder })
		local level = River.LevelLow
		local w = math.min(River.width(River.finishS), 70)
		for _, side in { -1, 1 } do
			part({
				Name = "Tower",
				Size = Vector3.new(3, 22, 3),
				CFrame = facing(River.finishS, side * w / 2, level + 9),
				Color = Color3.fromRGB(110, 76, 46),
				Material = Enum.Material.Wood,
				Parent = m,
			})
		end
		local banner = part({
			Name = "Banner",
			Size = Vector3.new(w, 4, 0.6),
			CFrame = facing(River.finishS, 0, level + 18) * CFrame.Angles(0, math.rad(180), 0),
			Color = Color3.fromRGB(40, 160, 90),
			Material = Enum.Material.SmoothPlastic,
			Parent = m,
		})
		local gui = Make(
			"SurfaceGui",
			{ Face = Enum.NormalId.Front, CanvasSize = Vector2.new(800, 60), Parent = banner }
		)
		Make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.BuilderSansBold,
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = true,
			Text = "sign.finish",
			Attributes = { TextKey = "sign.finish" },
			Parent = gui,
		})
	end

	-- лес по берегам
	local trees = Make("Folder", { Name = "Trees", Parent = folder })
	for s = -30, River.length + 40, 9 do
		for _, side in { -1, 1 } do
			if rng:next() < 0.55 then
				local w = River.width(s)
				local x = side * (w / 2 + rng:range(16, BANK_W - 8))
				local y = River.waterLevel(s) + River.bankHeight(s)
				-- у причала оставляем поляну
				local nearDock = s < River.dockS + 50 and side == 1 and math.abs(x) < w / 2 + 40
				if not nearDock then
					tree(trees, rng, worldAt(s, x, y))
				end
			end
		end
	end

	folder.Parent = Workspace
	return folder
end

-- Причал: настил от берега к плоту, точка появления, сундук-витрина
function WorldBuilder.dock(): (Model, SpawnLocation)
	local m = Make("Model", { Name = "Dock" })
	local level = River.LevelHigh
	local s = River.dockS
	local deckY = level + Config.Raft.DeckY - 0.4
	local x0 = Config.Raft.Width / 2 + 0.6
	local x1 = River.width(s) / 2 + 14
	local len = x1 - x0
	part({
		Name = "Pier",
		Size = Vector3.new(len, 0.8, 10),
		CFrame = facing(s, (x0 + x1) / 2, deckY),
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
		Parent = m,
	})
	for k = 0, math.floor(len / 6) do
		for _, dz in { -4.4, 4.4 } do
			part({
				Name = "Pile",
				Size = Vector3.new(1, 8, 1),
				CFrame = facing(s, x0 + 1 + k * 6, deckY - 4) * CFrame.new(0, 0, dz),
				Color = Color3.fromRGB(90, 64, 42),
				Material = Enum.Material.Wood,
				Parent = m,
			})
		end
	end
	local bankY = level + River.bankHeight(s)
	local spawnCF = facing(s, x1 + 8, bankY + 0.6) * CFrame.Angles(0, math.rad(90), 0)
	local spawn = Make("SpawnLocation", {
		Name = "Spawn",
		Anchored = true,
		Size = Vector3.new(12, 1, 12),
		CFrame = spawnCF,
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.WoodPlanks,
		Duration = 0,
		Neutral = true,
		TopSurface = Enum.SurfaceType.Smooth,
		Parent = m,
	})
	-- сундук на причале: открывает магазин
	local chest = part({
		Name = "Chest",
		Size = Vector3.new(4, 3, 3),
		CFrame = facing(s, x1 - 3, deckY + 1.9) * CFrame.new(0, 0, -3.2),
		Color = Color3.fromRGB(120, 70, 30),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
		Parent = m,
	})
	part({
		Name = "Lid",
		Size = Vector3.new(4.2, 0.8, 3.2),
		CFrame = chest.CFrame * CFrame.new(0, 1.9, 0),
		Color = Color3.fromRGB(255, 196, 60),
		Material = Enum.Material.Foil,
		Parent = m,
	})
	Make("ProximityPrompt", {
		Name = "ShopPrompt",
		ActionText = "prompt.shop",
		ObjectText = "",
		HoldDuration = 0,
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
		Parent = chest,
	})
	sign(m, facing(s, x1 - 2, deckY) * CFrame.new(0, 0, 4.6), "sign.board")
	m.Parent = Workspace
	return m, spawn
end

function WorldBuilder.lighting()
	local Lighting = game:GetService("Lighting")
	for _, c in Lighting:GetChildren() do
		c:Destroy()
	end
	Make("Atmosphere", {
		Density = 0.28,
		Offset = 0.1,
		Color = Color3.fromRGB(199, 214, 225),
		Decay = Color3.fromRGB(110, 130, 150),
		Glare = 0.2,
		Haze = 1.2,
		Parent = Lighting,
	})
	Make("Sky", { Name = "Sky", SunAngularSize = 14, Parent = Lighting })
	Make("BloomEffect", { Intensity = 0.4, Size = 24, Threshold = 1.4, Parent = Lighting })
	Make("ColorCorrectionEffect", {
		Saturation = 0.12,
		Contrast = 0.06,
		TintColor = Color3.fromRGB(255, 250, 240),
		Parent = Lighting,
	})
	Make("SunRaysEffect", { Intensity = 0.06, Spread = 0.6, Parent = Lighting })
end

return WorldBuilder
