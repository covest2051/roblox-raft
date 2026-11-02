--[[
	Shop — магазин: косметика (за монеты и напрямую за Robux), сундук с точными шансами
	(только если PolicyService разрешает), геймпассы и пакеты монет.
	Все покупки — запросом на сервер; промпты открывает сервер.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Ui = require(script.Parent.Ui)
local Lang = require(script.Parent.Lang)

local Make = Ui.Make
local C = Ui.colors

local Shop = {}

local refs: { [string]: any } = {}
local profile = {
	coins = 0,
	owned = {},
	equipped = { vest = Catalog.Default.vest, raft = Catalog.Default.raft },
	passes = {},
	chestAllowed = false,
	available = {},
}
local ownedSet: { [string]: boolean } = {}
local tab = "items"
local prices: { [string]: number } = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Реальная цена из Creator Hub (если товар создан), иначе рекомендуемая из Config
local function robuxOf(kind: "pass" | "product", key: string): number
	local cfg = if kind == "pass" then Config.Passes[key] else Config.Products[key]
	if prices[key] then
		return prices[key]
	end
	if cfg.id ~= 0 then
		prices[key] = cfg.robux
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(
					cfg.id,
					if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
				)
			end)
			if ok and info and type(info.PriceInRobux) == "number" then
				prices[key] = info.PriceInRobux
				if refs.panel and refs.panel.Visible then
					Shop.render()
				end
			end
		end)
	end
	return cfg.robux
end

local function send(payload)
	Net.ClientAction:FireServer(payload)
end

local function swatch(parent: Instance, item, size: UDim2, pos: UDim2)
	local f = Make("Frame", {
		Size = size,
		Position = pos,
		BackgroundColor3 = rgb(item.color),
		BorderSizePixel = 0,
		Parent = parent,
	})
	Make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = f })
	if item.kind == "vest" then
		for _, y in { 0.35, 0.6 } do
			Make("Frame", {
				Size = UDim2.fromScale(1, 0.1),
				Position = UDim2.fromScale(0, y),
				BackgroundColor3 = rgb(item.accent),
				BorderSizePixel = 0,
				Parent = f,
			})
		end
	else
		for i = 1, 5 do
			Make("Frame", {
				Size = UDim2.new(0, 2, 1, -8),
				Position = UDim2.new(i / 6, -1, 0, 4),
				BackgroundColor3 = rgb(item.accent),
				BorderSizePixel = 0,
				Parent = f,
			})
		end
	end
	if item.neon then
		Ui.stroke(f, rgb(item.accent), 2)
	end
	return f
end

-------------------------------------------------------------------------------
-- Вкладки
-------------------------------------------------------------------------------
local function itemCard(parent: Instance, item)
	local card = Ui.panel({ BackgroundColor3 = C.panel2, BackgroundTransparency = 0, Parent = parent })
	card.Name = item.id
	swatch(card, item, UDim2.new(1, -20, 0, 62), UDim2.fromOffset(10, 10))
	Ui.label({
		Size = UDim2.new(1, -12, 0, 36),
		Position = UDim2.fromOffset(6, 74),
		TextSize = 15,
		Font = Ui.fontBold,
		Text = Lang.t("item." .. item.id),
		Parent = card,
	})
	Ui.label({
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(6, 108),
		TextSize = 13,
		TextColor3 = Ui.rarityColor(item.rarity),
		Text = Lang.t("rarity." .. item.rarity),
		Parent = card,
	})
	local equipped = profile.equipped[item.kind] == item.id
	local owned = ownedSet[item.id]
	local function btn(text: string, color: Color3, x: number, w: number, fn: (() -> ())?)
		local b = Ui.button({
			Size = UDim2.new(w, -8, 0, 32),
			Position = UDim2.new(x, 4, 1, -38),
			BackgroundColor3 = color,
			TextSize = 15,
			Text = text,
			AutoButtonColor = fn ~= nil,
			Parent = card,
		})
		if fn then
			b.Activated:Connect(fn)
		end
		return b
	end
	if item.rarity == "Vip" then
		if profile.passes.Vip then
			if equipped then
				btn(Lang.t("shop.equipped"), Color3.fromRGB(70, 80, 90), 0, 1, nil)
			else
				btn(Lang.t("shop.equip"), C.button, 0, 1, function()
					send({ t = "equip", id = item.id })
				end)
			end
		else
			btn("★ " .. Lang.t("shop.vipOnly"), Color3.fromRGB(170, 120, 20), 0, 1, function()
				send({ t = "pass", key = "Vip" })
			end)
		end
	elseif owned then
		if equipped then
			btn(Lang.t("shop.equipped"), Color3.fromRGB(70, 80, 90), 0, 1, nil)
		else
			btn(Lang.t("shop.equip"), C.button, 0, 1, function()
				send({ t = "equip", id = item.id })
			end)
		end
	else
		local price = Catalog.price(item.id)
		local directKey = "Direct" .. item.rarity
		local hasDirect = Config.Products[directKey] ~= nil and profile.available[directKey]
		local w = if hasDirect then 0.55 else 1
		btn("● " .. tostring(price), Color3.fromRGB(150, 110, 20), 0, w, function()
			send({ t = "buyCoins", id = item.id })
		end)
		if hasDirect then
			btn(
				Lang.t("shop.buyRobux", { n = robuxOf("product", directKey) }),
				C.robux,
				0.55,
				0.45,
				function()
					send({ t = "product", key = directKey, item = item.id })
				end
			)
		end
	end
	return card
end

local function renderItems(body: ScrollingFrame)
	local list = Make(
		"UIListLayout",
		{ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body }
	)
	_ = list
	local order = 0
	for _, kind in { "vest", "raft" } do
		order += 1
		Ui.label({
			LayoutOrder = order,
			Size = UDim2.new(1, -10, 0, 26),
			TextSize = 18,
			Font = Ui.fontBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = Lang.t(if kind == "vest" then "shop.vests" else "shop.rafts"),
			Parent = body,
		})
		order += 1
		local grid = Make("Frame", {
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = body,
		})
		Make("UIGridLayout", {
			CellSize = UDim2.fromOffset(158, 196),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		local rank = { Default = 0, Common = 1, Rare = 2, Epic = 3, Legendary = 4, Vip = 5 }
		for _, item in Catalog.Items do
			if item.kind == kind then
				local card = itemCard(grid, item)
				card.LayoutOrder = rank[item.rarity] or 9
			end
		end
	end
end

local function renderChest(body: ScrollingFrame)
	Make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	local order = 0
	local function line(props)
		order += 1
		props.LayoutOrder = order
		props.Parent = body
		return Ui.label(props)
	end
	line({
		Size = UDim2.new(1, -10, 0, 34),
		TextSize = 26,
		Font = Ui.fontBold,
		TextColor3 = C.gold,
		Text = Lang.t("shop.chestTitle"),
	})
	if not profile.chestAllowed then
		line({ Size = UDim2.new(1, -10, 0, 90), TextSize = 18, Text = Lang.t("shop.chestNo") })
		order += 1
		local b = Ui.button({
			LayoutOrder = order,
			Size = UDim2.fromOffset(260, 44),
			Text = Lang.t("shop.tabItems"),
			Parent = body,
		})
		b.Activated:Connect(function()
			Shop.open("items")
		end)
		return
	end
	line({
		Size = UDim2.new(1, -10, 0, 24),
		TextSize = 17,
		TextColor3 = C.dim,
		Text = Lang.t("shop.chestDesc"),
	})
	order += 1
	local open = Ui.button({
		Name = "OpenChest",
		LayoutOrder = order,
		Size = UDim2.fromOffset(300, 52),
		BackgroundColor3 = C.robux,
		TextSize = 22,
		Text = if profile.available.Chest
			then Lang.t("shop.chestOpen", { n = robuxOf("product", "Chest") })
			else Lang.t("shop.soon"),
		AutoButtonColor = profile.available.Chest == true,
		Parent = body,
	})
	open.Activated:Connect(function()
		if profile.available.Chest then
			send({ t = "product", key = "Chest" })
		end
	end)
	-- точные шансы
	local odds = Catalog.odds()
	for _, rarity in Config.RarityOrder do
		line({
			Size = UDim2.new(1, -10, 0, 26),
			TextSize = 19,
			Font = Ui.fontBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.rarityColor(rarity),
			Text = Lang.t("rarity." .. rarity) .. " — " .. Catalog.rarityPercent(rarity),
		})
		for _, o in odds do
			if o.rarity == rarity then
				local mark = if ownedSet[o.id] then "  ✓" else ""
				line({
					Name = "Odds_" .. o.id,
					Size = UDim2.new(1, -10, 0, 20),
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = "     "
						.. Lang.t("item." .. o.id)
						.. "  ·  <b>"
						.. Catalog.formatBp(o.bp)
						.. "</b>"
						.. mark,
				})
			end
		end
	end
	local refunds = {}
	for _, r in Config.RarityOrder do
		table.insert(refunds, Lang.t("rarity." .. r) .. " " .. Config.Rarity[r].refund)
	end
	line({
		Size = UDim2.new(1, -10, 0, 44),
		TextSize = 15,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = Lang.t("shop.chestDup", { list = table.concat(refunds, " · ") }),
	})
end

local function renderPasses(body: ScrollingFrame)
	Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(330, 150),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})
	local cards = {
		{ kind = "pass", key = "DoubleCoins", title = "shop.passDouble", desc = "shop.passDoubleDesc" },
		{ kind = "pass", key = "Sturdy", title = "shop.passSturdy", desc = "shop.passSturdyDesc" },
		{ kind = "pass", key = "Vip", title = "shop.passVip", desc = "shop.passVipDesc" },
		{ kind = "product", key = "Coins500", title = "shop.coins500", desc = nil },
		{ kind = "product", key = "Coins3000", title = "shop.coins3000", desc = nil },
	}
	for i, c in cards do
		local card = Ui.panel({
			Name = c.key,
			LayoutOrder = i,
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0,
			Parent = body,
		})
		Ui.label({
			Size = UDim2.new(1, -20, 0, 30),
			Position = UDim2.fromOffset(10, 8),
			TextSize = 22,
			Font = Ui.fontBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if c.kind == "pass" then C.gold else C.text,
			Text = Lang.t(c.title),
			Parent = card,
		})
		if c.desc then
			Ui.label({
				Size = UDim2.new(1, -20, 0, 54),
				Position = UDim2.fromOffset(10, 40),
				TextSize = 15,
				TextColor3 = C.dim,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Text = Lang.t(c.desc),
				Parent = card,
			})
		end
		local owned = c.kind == "pass" and profile.passes[c.key]
		local avail = profile.available[c.key]
		local text = if owned
			then Lang.t("shop.ownedShort")
			elseif avail then "R$ " .. robuxOf(c.kind, c.key)
			else Lang.t("shop.soonShort")
		local b = Ui.button({
			Name = "Buy",
			Size = UDim2.new(1, -20, 0, 40),
			Position = UDim2.new(0, 10, 1, -48),
			BackgroundColor3 = if owned then Color3.fromRGB(70, 80, 90) else C.robux,
			AutoButtonColor = not owned and avail == true,
			Text = text,
			Parent = card,
		})
		b.Activated:Connect(function()
			if owned or not avail then
				return
			end
			send({ t = c.kind, key = c.key })
		end)
	end
end

function Shop.render()
	if not refs.panel then
		return
	end
	local body = refs.body :: ScrollingFrame
	for _, l in body:GetChildren() do
		l:Destroy()
	end
	body.CanvasPosition = Vector2.zero
	if tab == "items" then
		renderItems(body)
	elseif tab == "chest" then
		renderChest(body)
	else
		renderPasses(body)
	end
	for name, b in refs.tabs do
		b.BackgroundColor3 = if name == tab then Color3.fromRGB(196, 120, 30) else C.button
	end
	refs.tabs.items.Text = Lang.t("shop.tabItems")
	refs.tabs.chest.Text = Lang.t("shop.tabChest")
	refs.tabs.passes.Text = Lang.t("shop.tabPasses")
	refs.coins.Text = "● " .. tostring(profile.coins)
end

function Shop.build()
	local root = Ui.screen()
	local panel = Ui.scaled(Ui.panel({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(740, 540),
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 5,
		Parent = root,
	}))
	Ui.stroke(panel, C.gold, 2)
	refs.panel = panel
	refs.tabs = {}
	local names = { "items", "chest", "passes" }
	for i, name in names do
		local b = Ui.button({
			Name = "Tab_" .. name,
			Size = UDim2.fromOffset(170, 40),
			Position = UDim2.fromOffset(14 + (i - 1) * 178, 12),
			TextSize = 18,
			Text = name,
			Parent = panel,
		})
		b.Activated:Connect(function()
			Shop.open(name)
		end)
		refs.tabs[name] = b
	end
	refs.coins = Ui.label({
		Size = UDim2.fromOffset(120, 40),
		Position = UDim2.new(1, -184, 0, 12),
		TextSize = 20,
		Font = Ui.fontBold,
		TextColor3 = C.gold,
		Text = "",
		Parent = panel,
	})
	local close = Ui.button({
		Name = "Close",
		Size = UDim2.fromOffset(44, 40),
		Position = UDim2.new(1, -56, 0, 12),
		BackgroundColor3 = Color3.fromRGB(110, 50, 44),
		Text = "✕",
		Parent = panel,
	})
	close.Activated:Connect(Shop.close)
	refs.body = Make("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(14, 64),
		Size = UDim2.new(1, -28, 1, -78),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	})
	-- окно результата сундука / прямой покупки
	local pop = Ui.scaled(Ui.panel({
		Name = "Reward",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 280),
		Visible = false,
		ZIndex = 10,
		Parent = root,
	}))
	refs.pop = pop
	refs.popStroke = Ui.stroke(pop, C.gold, 3)
	refs.popTitle = Ui.label({
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 12),
		TextSize = 20,
		Text = "",
		Parent = pop,
	})
	refs.popSwatch = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = pop })
	refs.popName = Ui.label({
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 150),
		TextSize = 24,
		Font = Ui.fontBold,
		Text = "",
		Parent = pop,
	})
	refs.popRarity = Ui.label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 180),
		TextSize = 18,
		Text = "",
		Parent = pop,
	})
	refs.popDup = Ui.label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 204),
		TextSize = 16,
		TextColor3 = C.gold,
		Text = "",
		Parent = pop,
	})
	local ok = Ui.button({
		Size = UDim2.new(1, -40, 0, 36),
		Position = UDim2.new(0, 20, 1, -46),
		Text = "OK",
		Parent = pop,
	})
	ok.Activated:Connect(function()
		pop.Visible = false
	end)
	Lang.onChange(Shop.render)
end

function Shop.open(which: string?)
	if which then
		tab = which
	end
	refs.panel.Visible = true
	send({ t = "profile" }) -- свежая проверка PolicyService и цен
	Shop.render()
end

function Shop.close()
	refs.panel.Visible = false
end

function Shop.toggle()
	if refs.panel.Visible then
		Shop.close()
	else
		Shop.open(nil)
	end
end

function Shop.isOpen(): boolean
	return refs.panel ~= nil and refs.panel.Visible
end

function Shop.setProfile(p)
	profile = p
	ownedSet = {}
	for _, id in p.owned or {} do
		ownedSet[id] = true
	end
	if refs.panel and refs.panel.Visible then
		Shop.render()
	end
end

function Shop.showReward(id: string, title: string, dupRefund: number?)
	local item = Catalog.get(id)
	if not item then
		return
	end
	for _, c in refs.popSwatch:GetChildren() do
		c:Destroy()
	end
	swatch(refs.popSwatch, item, UDim2.fromOffset(160, 90), UDim2.new(0.5, -80, 0, 50))
	refs.popTitle.Text = title
	refs.popName.Text = Lang.t("item." .. id)
	refs.popRarity.Text = Lang.t("rarity." .. item.rarity)
	refs.popRarity.TextColor3 = Ui.rarityColor(item.rarity)
	refs.popStroke.Color = Ui.rarityColor(item.rarity)
	refs.popDup.Text = if dupRefund and dupRefund > 0
		then Lang.t("shop.chestDupGot", { n = dupRefund })
		else ""
	refs.pop.Visible = true
end

return Shop
