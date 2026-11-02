--[[
	Hud — игровой интерфейс: монеты, прогресс по реке, прочность плота, схема веса
	экипажа, отсчёт у причала, предупреждения, крушение («Второй шанс»), итоги заплыва.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local River = require(Shared.River)
local RaftSim = require(Shared.RaftSim)

local Ui = require(script.Parent.Ui)
local Lang = require(script.Parent.Lang)

local Make = Ui.Make
local C = Ui.colors
local player = Players.LocalPlayer

local Hud = {}

Hud.boardedRaft = nil :: number? -- плот у причала, на котором стоим
Hud.onShop = nil :: ((string?) -> ())?
Hud.onInvite = nil :: (() -> ())?

local refs: { [string]: any } = {}
local profile = { coins = 0, best = 0, available = {} }
local toasts: { Frame } = {}
local warnUntil = 0
local sectionUntil = 0
local coinShown = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

-------------------------------------------------------------------------------
-- Плоты
-------------------------------------------------------------------------------
function Hud.raftModel(id: number?): Model?
	if not id then
		return nil
	end
	local folder = Workspace:FindFirstChild("Rafts")
	return folder and folder:FindFirstChild("Raft" .. id) :: Model?
end

function Hud.myRaftId(): number?
	return player:GetAttribute("RaftId") or Hud.boardedRaft
end

function Hud.isCrew(): boolean
	return player:GetAttribute("RaftId") ~= nil
end

local function dockRaft(): Model?
	local folder = Workspace:FindFirstChild("Rafts")
	if not folder then
		return nil
	end
	for _, m in folder:GetChildren() do
		local ph = m:GetAttribute("Phase")
		if ph == "dock" or ph == "countdown" then
			return m
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- Построение
-------------------------------------------------------------------------------
local function buildTopLeft(root: Instance)
	local box = Ui.scaled(Make("Frame", {
		Name = "TopLeft",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(190, 200),
		Parent = root,
	}))
	local pill = Ui.panel({ Name = "Coins", Size = UDim2.fromOffset(190, 46), Parent = box })
	local icon = Make("Frame", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(10, 9),
		BackgroundColor3 = C.gold,
		Parent = pill,
	})
	Make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = icon })
	Ui.stroke(icon, Color3.fromRGB(200, 140, 20), 2)
	refs.coins = Ui.label({
		Size = UDim2.new(1, -96, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		Font = Ui.fontBold,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "0",
		Parent = pill,
	})
	local plus = Ui.button({
		Name = "Plus",
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.new(1, -41, 0, 5),
		BackgroundColor3 = C.robux,
		Text = "+",
		TextSize = 26,
		Parent = pill,
	})
	plus.Activated:Connect(function()
		if Hud.onShop then
			Hud.onShop("passes")
		end
	end)
	refs.coinPop = Ui.label({
		Size = UDim2.fromOffset(120, 30),
		Position = UDim2.fromOffset(196, 8),
		Font = Ui.fontBold,
		TextSize = 24,
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = box,
	})
	local shop = Ui.button({
		Name = "ShopButton",
		Size = UDim2.fromOffset(190, 44),
		Position = UDim2.fromOffset(0, 56),
		BackgroundColor3 = Color3.fromRGB(196, 120, 30),
		Text = "",
		Parent = box,
	})
	refs.shopText = shop
	shop.Activated:Connect(function()
		if Hud.onShop then
			Hud.onShop(nil)
		end
	end)
	local invite = Ui.button({
		Name = "InviteButton",
		Size = UDim2.fromOffset(190, 44),
		Position = UDim2.fromOffset(0, 108),
		Text = "",
		Parent = box,
	})
	refs.inviteText = invite
	invite.Activated:Connect(function()
		if Hud.onInvite then
			Hud.onInvite()
		end
	end)
	refs.saveWarn = Ui.label({
		Size = UDim2.fromOffset(240, 40),
		Position = UDim2.fromOffset(0, 158),
		TextSize = 14,
		TextColor3 = C.warn,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = box,
	})
end

local function buildProgress(root: Instance)
	local W = 560
	local box = Ui.scaled(Make("Frame", {
		Name = "Progress",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(W, 90),
		Parent = root,
	}))
	local bar = Ui.panel({
		Name = "Bar",
		Size = UDim2.fromOffset(W, 16),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.fromRGB(20, 60, 80),
		Parent = box,
	})
	refs.sectionLabels = {}
	for _, sec in River.Sections do
		local x0 = sec.startS / River.length
		local w = sec.length / River.length
		local seg = Make("Frame", {
			Name = sec.id,
			BackgroundColor3 = if sec.rock then Color3.fromRGB(60, 110, 130) else C.water,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(x0, 0.2),
			Size = UDim2.new(w, -2, 0.6, 0),
			Parent = bar,
		})
		_ = seg
		refs.sectionLabels[sec.id] = Ui.label({
			Size = UDim2.new(w, 0, 0, 16),
			Position = UDim2.new(x0, 0, 0, 18),
			TextSize = 12,
			TextColor3 = C.dim,
			Text = "",
			Parent = box,
		})
	end
	-- водопад
	Make("Frame", {
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(River.dropS / River.length, 0),
		Size = UDim2.new(0, 2, 1, 0),
		Parent = bar,
	})
	-- финиш
	Make("Frame", {
		BackgroundColor3 = C.good,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(River.finishS / River.length, 0),
		Size = UDim2.new(0, 4, 1, 0),
		Parent = bar,
	})
	refs.markers = Make(
		"Frame",
		{ Name = "Markers", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = bar }
	)
	refs.time = Ui.label({
		Size = UDim2.fromOffset(80, 16),
		Position = UDim2.new(1, 8, 0, 0),
		TextSize = 16,
		Font = Ui.fontBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = box,
	})
	-- прочность
	local hp = Ui.panel({
		Name = "Hp",
		Size = UDim2.fromOffset(W, 20),
		Position = UDim2.fromOffset(0, 38),
		BackgroundColor3 = Color3.fromRGB(40, 20, 16),
		Visible = false,
		Parent = box,
	})
	refs.hp = hp
	refs.hpFill = Make("Frame", {
		BackgroundColor3 = C.good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = hp,
	}, { Make("UICorner", { CornerRadius = UDim.new(0, 12) }) })
	refs.hpText =
		Ui.label({ Size = UDim2.fromScale(1, 1), TextSize = 14, Font = Ui.fontBold, Text = "", Parent = hp })
	refs.toastBox = Make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.fromOffset(W, 120),
		Parent = box,
	}, {
		Make(
			"UIListLayout",
			{ Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center }
		),
	})
end

local function buildBalance(root: Instance)
	local box = Ui.scaled(Ui.panel({
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(190, 258),
		Visible = false,
		Parent = root,
	}))
	refs.balance = box
	refs.balanceTitle = Ui.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 4),
		Font = Ui.fontBold,
		TextSize = 16,
		Text = "",
		Parent = box,
	})
	local W, L = 110, 140
	local deck = Make("Frame", {
		Name = "Deck",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(W, L),
		BackgroundColor3 = Color3.fromRGB(150, 108, 66),
		BorderSizePixel = 0,
		Parent = box,
	})
	Make("UICorner", { CornerRadius = UDim.new(0, 6), Parent = deck })
	for i = 1, 6 do
		Make("Frame", {
			BackgroundColor3 = Color3.fromRGB(110, 78, 46),
			BorderSizePixel = 0,
			Position = UDim2.new(i / 7, -1, 0, 4),
			Size = UDim2.new(0, 2, 1, -8),
			Parent = deck,
		})
	end
	-- нос
	Ui.label({
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, -16),
		Text = "▲",
		TextSize = 14,
		TextColor3 = C.dim,
		Parent = deck,
	})
	refs.deck = deck
	refs.dots = Make(
		"Frame",
		{ Name = "Dots", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = deck }
	)
	local marker = Make("Frame", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = deck,
	})
	Make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = marker })
	Ui.stroke(marker, C.danger, 3)
	refs.marker = marker
	local function hint(name, text, pos, anchor)
		refs[name] = Ui.label({
			AnchorPoint = anchor,
			Position = pos,
			Size = UDim2.fromOffset(84, 16),
			TextSize = 13,
			TextColor3 = C.dim,
			Text = text,
			Parent = box,
		})
	end
	hint("hintFwd", "", UDim2.new(0.5, 0, 0, 30), Vector2.new(0.5, 0))
	hint("hintBack", "", UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1))
	hint("hintLeft", "", UDim2.fromOffset(2, 52 + L + 6), Vector2.new(0, 0))
	hint("hintRight", "", UDim2.new(1, -2, 0, 52 + L + 6), Vector2.new(1, 0))
end

local function buildCenter(root: Instance)
	refs.warn = Ui.label({
		Name = "Warn",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.new(0.9, 0, 0, 60),
		Font = Ui.fontBold,
		TextSize = 44,
		TextColor3 = C.warn,
		TextStrokeTransparency = 0.2,
		Text = "",
		Visible = false,
		Parent = root,
	})
	refs.section = Ui.label({
		Name = "Section",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.6, 0, 0, 50),
		Font = Ui.fontBold,
		TextSize = 38,
		TextStrokeTransparency = 0.4,
		Text = "",
		Visible = false,
		Parent = root,
	})
	refs.dockInfo = Ui.label({
		Name = "DockInfo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.new(0.8, 0, 0, 70),
		Font = Ui.fontBold,
		TextSize = 26,
		TextStrokeTransparency = 0.3,
		Text = "",
		Parent = root,
	})
	local leave = Ui.scaled(Ui.button({
		Name = "LeaveButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(170, 40),
		BackgroundColor3 = Color3.fromRGB(80, 50, 40),
		TextSize = 16,
		Text = "",
		Visible = false,
		Parent = root,
	}))
	refs.leave = leave
	leave.Activated:Connect(function()
		Net.ClientAction:FireServer({ t = "leave" })
	end)
end

local function buildWreck(root: Instance)
	local p = Ui.scaled(Ui.panel({
		Name = "Wreck",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(380, 210),
		Visible = false,
		Parent = root,
	}))
	Ui.stroke(p, C.danger, 2)
	refs.wreck = p
	refs.wreckTitle = Ui.label({
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 10),
		Font = Ui.fontBold,
		TextSize = 30,
		TextColor3 = C.danger,
		Text = "",
		Parent = p,
	})
	refs.wreckTimer = Ui.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 56),
		TextSize = 18,
		Text = "",
		Parent = p,
	})
	local revive = Ui.button({
		Name = "Revive",
		Size = UDim2.new(1, -40, 0, 54),
		Position = UDim2.fromOffset(20, 90),
		BackgroundColor3 = C.robux,
		TextSize = 22,
		Text = "",
		Parent = p,
	})
	refs.revive = revive
	revive.Activated:Connect(function()
		Net.ClientAction:FireServer({ t = "product", key = "Revive" })
	end)
	local giveUp = Ui.button({
		Name = "GiveUp",
		Size = UDim2.new(1, -40, 0, 36),
		Position = UDim2.fromOffset(20, 156),
		BackgroundColor3 = Color3.fromRGB(70, 60, 60),
		TextSize = 16,
		Text = "",
		Parent = p,
	})
	refs.giveUp = giveUp
	giveUp.Activated:Connect(function()
		Net.ClientAction:FireServer({ t = "leave" })
		p.Visible = false
	end)
	refs.wreckDeadline = 0
end

local function buildResults(root: Instance)
	local p = Ui.scaled(Ui.panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(400, 380),
		Visible = false,
		Parent = root,
	}))
	Ui.stroke(p, C.gold, 2)
	refs.results = p
	refs.resTitle = Ui.label({
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.fromOffset(0, 12),
		Font = Ui.fontBold,
		TextSize = 34,
		Text = "",
		Parent = p,
	})
	refs.resBody = Ui.label({
		Size = UDim2.new(1, -40, 0, 220),
		Position = UDim2.fromOffset(20, 62),
		TextSize = 19,
		LineHeight = 1.15,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = p,
	})
	local again = Ui.button({
		Name = "Again",
		Size = UDim2.new(0.5, -26, 0, 46),
		Position = UDim2.new(0, 20, 1, -64),
		BackgroundColor3 = Color3.fromRGB(40, 140, 90),
		Text = "",
		Parent = p,
	})
	refs.again = again
	again.Activated:Connect(function()
		p.Visible = false
	end)
	local invite = Ui.button({
		Name = "Invite",
		Size = UDim2.new(0.5, -26, 0, 46),
		Position = UDim2.new(0.5, 6, 1, -64),
		Text = "",
		Parent = p,
	})
	refs.resInvite = invite
	invite.Activated:Connect(function()
		if Hud.onInvite then
			Hud.onInvite()
		end
	end)
end

function Hud.relabel()
	refs.shopText.Text = "🛒  " .. Lang.t("ui.shop")
	refs.inviteText.Text = "👥  " .. Lang.t("ui.invite")
	refs.leave.Text = Lang.t("ui.leave")
	refs.balanceTitle.Text = Lang.t("ui.balance")
	refs.hintFwd.Text = Lang.t("ui.fwd")
	refs.hintBack.Text = Lang.t("ui.back")
	refs.hintLeft.Text = Lang.t("ui.left")
	refs.hintRight.Text = Lang.t("ui.right")
	refs.wreckTitle.Text = Lang.t("wreck.title")
	refs.giveUp.Text = Lang.t("wreck.giveUp")
	refs.again.Text = Lang.t("results.again")
	refs.resInvite.Text = Lang.t("ui.invite")
	refs.saveWarn.Text = Lang.t("shop.dataOff")
	for id, l in refs.sectionLabels do
		l.Text = Lang.t("section." .. id)
	end
	local price = Config.Products.Revive.robux
	refs.revive.Text = Lang.t("wreck.revive") .. "  ·  R$ " .. price
end

function Hud.build()
	local root = Ui.screen()
	local hud = Make(
		"Frame",
		{ Name = "Hud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root }
	)
	refs.root = hud
	buildTopLeft(hud)
	buildProgress(hud)
	buildBalance(hud)
	buildCenter(hud)
	buildWreck(root)
	buildResults(root)
	Hud.relabel()
	Lang.onChange(Hud.relabel)
end

-------------------------------------------------------------------------------
-- Сообщения
-------------------------------------------------------------------------------
function Hud.toast(text: string, color: Color3?)
	local f = Ui.panel({
		Size = UDim2.fromOffset(460, 30),
		BackgroundTransparency = 0.3,
		Parent = refs.toastBox,
	})
	Ui.label({
		Size = UDim2.fromScale(1, 1),
		TextSize = 17,
		Text = text,
		TextColor3 = color or C.text,
		Parent = f,
	})
	table.insert(toasts, f)
	while #toasts > 3 do
		table.remove(toasts, 1):Destroy()
	end
	task.delay(3, function()
		local i = table.find(toasts, f)
		if i then
			table.remove(toasts, i)
		end
		f:Destroy()
	end)
end

function Hud.warn(text: string, seconds: number?)
	refs.warn.Text = text
	refs.warn.Visible = true
	warnUntil = os.clock() + (seconds or 4)
end

function Hud.showSection(id: string)
	refs.section.Text = Lang.t("section." .. id)
	refs.section.Visible = true
	sectionUntil = os.clock() + 2.5
end

function Hud.coinPop(n: number)
	if n <= 0 then
		return
	end
	coinShown += n
	refs.coinPop.Text = "+" .. coinShown
	local mark = coinShown
	task.delay(1.2, function()
		if coinShown == mark then
			coinShown = 0
			refs.coinPop.Text = ""
		end
	end)
end

function Hud.setProfile(p)
	profile = p
	refs.coins.Text = tostring(p.coins)
	refs.saveWarn.Visible = p.saved == false and not game:GetService("RunService"):IsStudio()
end

function Hud.showResults(r)
	local lines = {}
	table.insert(lines, Lang.t("results.time", { t = Lang.formatTime(r.time) }))
	table.insert(lines, "<b>" .. Lang.t("results.coins", { n = r.coins }) .. "</b>")
	if r.bonus > 0 then
		table.insert(lines, "   " .. Lang.t("results.bonus", { n = r.bonus }))
	end
	if r.mult and r.mult > 1.001 then
		table.insert(lines, Lang.t("results.mult", { m = string.format("%.2f", r.mult) }))
	end
	table.insert(lines, Lang.t("results.hull", { n = r.hp, max = r.maxHp }))
	table.insert(lines, Lang.t("results.gates", { n = r.gates, max = r.gatesTotal }))
	if r.falls > 0 then
		table.insert(lines, Lang.t("results.falls", { n = r.falls }))
	end
	if r.best and r.best > 0 then
		table.insert(lines, Lang.t("results.best", { t = Lang.formatTime(r.best) }))
	end
	if r.newBest then
		table.insert(lines, '<font color="#FFC83C"><b>' .. Lang.t("results.newBest") .. "</b></font>")
	end
	refs.resTitle.Text = Lang.t(if r.finished then "results.finish" else "results.sunk")
	refs.resTitle.TextColor3 = if r.finished then C.gold else C.danger
	refs.resBody.Text = table.concat(lines, "\n")
	refs.results.Visible = true
	refs.wreck.Visible = false
end

function Hud.showWreck(deadline: number, canRevive: boolean)
	refs.wreckDeadline = deadline
	refs.revive.Visible = canRevive
	refs.wreck.Visible = true
end

function Hud.hideWreck()
	refs.wreck.Visible = false
end

-------------------------------------------------------------------------------
-- Кадр
-------------------------------------------------------------------------------
local function updateMarkers(myId: number?)
	local folder = Workspace:FindFirstChild("Rafts")
	local seen = {}
	if folder then
		for _, m in folder:GetChildren() do
			local id = m:GetAttribute("RaftId")
			local s = m:GetAttribute("S")
			local ph = m:GetAttribute("Phase")
			if id and s and ph ~= "dock" and ph ~= "countdown" then
				local name = "R" .. id
				seen[name] = true
				local dot = refs.markers:FindFirstChild(name)
				local mine = id == myId
				if not dot then
					dot = Make("Frame", {
						Name = name,
						AnchorPoint = Vector2.new(0.5, 0.5),
						BorderSizePixel = 0,
						Parent = refs.markers,
					}, { Make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
				end
				dot.Size = if mine then UDim2.fromOffset(18, 18) else UDim2.fromOffset(10, 10)
				dot.BackgroundColor3 = if mine then C.gold else C.text
				dot.ZIndex = if mine then 3 else 2
				dot.Position = UDim2.fromScale(math.clamp(s / River.length, 0, 1), 0.5)
			end
		end
	end
	for _, d in refs.markers:GetChildren() do
		if not seen[d.Name] then
			d:Destroy()
		end
	end
end

local function updateBalance(model: Model?)
	local show = model ~= nil and model.PrimaryPart ~= nil
	refs.balance.Visible = show
	if not show then
		return
	end
	local hull = (model :: Model).PrimaryPart :: BasePart
	local W, L = Config.Raft.Width, Config.Raft.Length
	local pts = {}
	local seen = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local lp = hull.CFrame:PointToObjectSpace(root.CFrame.Position)
			if math.abs(lp.X) <= W / 2 + 1 and math.abs(lp.Z) <= L / 2 + 1 and lp.Y > -1 and lp.Y < 9 then
				table.insert(pts, { x = lp.X, z = lp.Z })
				local name = "P" .. p.UserId
				seen[name] = true
				local dot = refs.dots:FindFirstChild(name)
				if not dot then
					dot = Make("Frame", {
						Name = name,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.fromOffset(16, 16),
						BorderSizePixel = 0,
						BackgroundColor3 = if p == player then C.gold else C.text,
						ZIndex = 2,
						Parent = refs.dots,
					}, { Make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
					Ui.stroke(dot, Color3.new(0, 0, 0), 1.5)
				end
				dot.Position = UDim2.fromScale(
					0.5 + 0.5 * math.clamp(lp.X / (W / 2), -1, 1),
					0.5 + 0.5 * math.clamp(lp.Z / (L / 2), -1, 1)
				)
			end
		end
	end
	for _, d in refs.dots:GetChildren() do
		if not seen[d.Name] then
			d:Destroy()
		end
	end
	local bx, bz = RaftSim.balance(pts)
	refs.marker.Position = UDim2.fromScale(0.5 + 0.5 * bx, 0.5 - 0.5 * bz)
	local function hl(lbl: TextLabel, on: boolean)
		lbl.TextColor3 = if on then C.gold else C.dim
		lbl.Font = if on then Ui.fontBold else Ui.font
	end
	hl(refs.hintLeft, bx < -0.05)
	hl(refs.hintRight, bx > 0.05)
	hl(refs.hintFwd, bz > 0.05)
	hl(refs.hintBack, bz < -0.05)
end

function Hud.update()
	local myId = Hud.myRaftId()
	local model = Hud.raftModel(myId)
	updateMarkers(if Hud.isCrew() then myId else nil)
	updateBalance(model)

	local crew = Hud.isCrew() and model ~= nil
	local t = now()
	if crew and model then
		local hp, max = model:GetAttribute("Hp") or 0, model:GetAttribute("MaxHp") or 100
		refs.hp.Visible = true
		local k = math.clamp(hp / math.max(1, max), 0, 1)
		refs.hpFill.Size = UDim2.fromScale(k, 1)
		refs.hpFill.BackgroundColor3 = if k > 0.5 then C.good elseif k > 0.25 then C.warn else C.danger
		refs.hpText.Text = Lang.t("ui.hp", { n = hp, max = max })
		refs.time.Text = Lang.formatTime(model:GetAttribute("Time") or 0)
		local ph = model:GetAttribute("Phase")
		refs.leave.Visible = ph == "run"
		refs.dockInfo.Text = ""
		if refs.wreck.Visible then
			-- скрывают события revived/sunk/results; здесь только таймер
			-- (атрибут Phase приходит позже события, на него не смотрим)
			local left = math.max(0, math.ceil(refs.wreckDeadline - t))
			refs.wreckTimer.Text = Lang.t("wreck.timer", { n = left })
		end
	else
		refs.hp.Visible = false
		refs.time.Text = ""
		refs.leave.Visible = false
		refs.wreck.Visible = false
		-- у причала
		local dm = dockRaft()
		if Hud.boardedRaft and model then
			local ends = model:GetAttribute("CountdownEnd") or 0
			local lines = {}
			if ends > 0 then
				table.insert(lines, Lang.t("ui.countdown", { n = math.max(0, math.ceil(ends - t)) }))
			end
			local cap = model:GetAttribute("Captain")
			if cap and cap ~= "" then
				table.insert(lines, '<font size="18">' .. Lang.t("ui.captain", { name = cap }) .. "</font>")
			end
			refs.dockInfo.Text = table.concat(lines, "\n")
		elseif refs.results.Visible then
			refs.dockInfo.Text = ""
		elseif dm then
			refs.dockInfo.Text = '<font size="20">' .. Lang.t("ui.boardHint") .. "</font>"
		else
			refs.dockInfo.Text = '<font size="20">' .. Lang.t("ui.waitRaft") .. "</font>"
		end
	end
	if refs.warn.Visible then
		if os.clock() > warnUntil then
			refs.warn.Visible = false
		else
			refs.warn.TextTransparency = if math.floor(os.clock() * 4) % 2 == 0 then 0 else 0.35
		end
	end
	if refs.section.Visible and os.clock() > sectionUntil then
		refs.section.Visible = false
	end
	_ = profile
end

return Hud
