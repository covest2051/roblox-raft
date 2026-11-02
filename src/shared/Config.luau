--[[
	Config — все числа баланса и ID товаров в одном месте.
	После правки: `lune run tests/run.luau` (тест баланса проверит, что река проходима).
]]

local Config = {}

Config.Version = "1.0.0"

-- Плот (studs). Локальные оси: X — вправо, Z — к корме (как у CFrame), «вперёд» = −Z.
Config.Raft = {
	Width = 14, -- поперёк течения
	Length = 18, -- вдоль течения
	Radius = 7, -- радиус для столкновений с камнями
	DeckY = 1.6, -- высота палубы над водой
	MaxCrew = 6,
	BaseHp = 100,
	SturdyBonus = 0.5, -- геймпасс «Прочный плот»: +50%
	MaxRafts = 4, -- одновременно на реке
}

-- Управление весом
Config.Lean = {
	Deadzone = 0.08, -- мелкие смещения у центра не считаются
	Steer = 18, -- поперечное ускорение при полном крене, studs/s²
	LatDrag = 1.25, -- сопротивление поперечному движению
	MaxLat = 14, -- предел поперечной скорости
	ForwardBoost = 0.3, -- вес на носу: +30% к скорости течения
	BackDrag = 0.2, -- вес на корме: −20%
	SpeedRate = 0.8, -- как быстро скорость догоняет целевую, 1/с
	MaxRoll = 9, -- градусы крена
	MaxPitch = 6,
	TiltRate = 4,
	BendDrift = 0.25, -- снос к внешнему берегу на поворотах (× кривизна × v²)
}

Config.Damage = {
	RockBase = 9,
	RockPerSpeed = 0.55,
	RockSpeedKeep = 0.45, -- после удара остаётся 45% скорости
	RockCooldown = 1.2,
	Bank = 2,
	BankCooldown = 1.0,
	DropBad = 30, -- водопад без веса на корме
	DropSafeLean = 0.25, -- нужно bz ≤ −0.25 (центр масс в задней половине)
	DropFallTime = 1.1,
}

Config.Rewards = {
	Coin = 1,
	Gate = 3,
	Finish = 25,
	HpPerCoin = 4, -- +1 монета за каждые 4 оставшиеся прочности
	CrewBonus = 0.15, -- +15% за каждого игрока сверх первого
	CrewBonusMax = 0.75,
	DoubleCoins = 2, -- геймпасс
	VipBonus = 0.1,
}

Config.Timing = {
	Countdown = 12, -- от первого на борту до отплытия
	CountdownAllAboard = 3, -- если на борту все свободные игроки
	NextRaftDelay = 3,
	OverboardGrace = 1.5,
	WreckRevive = 10, -- секунд на «Второй шанс»
	ResultsTime = 6, -- после финиша — назад к причалу
	SimStep = 1 / 30,
	AttrRate = 0.1, -- как часто публиковать состояние плота атрибутами
}

-- Цены косметики в монетах и возврат за дубликат
Config.Rarity = {
	Common = { weight = 6000, price = 250, refund = 60, color = { 200, 205, 215 } },
	Rare = { weight = 2800, price = 600, refund = 150, color = { 90, 170, 255 } },
	Epic = { weight = 1000, price = 1500, refund = 400, color = { 190, 110, 255 } },
	Legendary = { weight = 200, price = 4000, refund = 1000, color = { 255, 190, 60 } },
}
Config.RarityOrder = { "Common", "Rare", "Epic", "Legendary" }
Config.WeightTotal = 10000 -- веса в сотых долях процента: 6000 = 60.00%

--[[
	ID товаров из Creator Hub (Monetization → Passes / Developer Products).
	Пока ID = 0: в Studio покупка эмулируется, в живой игре кнопка неактивна («скоро»).
	Robux — рекомендуемые цены (меняются в Creator Hub, код их только показывает).
]]
Config.Passes = {
	DoubleCoins = { id = 0, robux = 149 },
	Sturdy = { id = 0, robux = 99 },
	Vip = { id = 0, robux = 249 },
}
Config.Products = {
	Revive = { id = 0, robux = 19 },
	Coins500 = { id = 0, robux = 25, coins = 500 },
	Coins3000 = { id = 0, robux = 99, coins = 3000 },
	Chest = { id = 0, robux = 35 },
	DirectRare = { id = 0, robux = 49, rarity = "Rare" },
	DirectEpic = { id = 0, robux = 99, rarity = "Epic" },
	DirectLegendary = { id = 0, robux = 199, rarity = "Legendary" },
}
Config.ProductOrder =
	{ "Revive", "Coins500", "Coins3000", "Chest", "DirectRare", "DirectEpic", "DirectLegendary" }
Config.ReviveFallbackCoins = 150 -- если плот уже не спасти к моменту оплаты
Config.ChestFallbackCoins = 500 -- если сундук недоступен игроку по политике

Config.DataStore = {
	Name = "RaftProfiles_v1",
	AutosaveEvery = 90,
	Retries = 4,
	ReceiptLog = 100,
}

-- Встроенные звуки клиента (rbxasset://). Свои — rbxassetid://<id>.
Config.Sounds = {
	River = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.12, Speed = 0.5 },
	Splash = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.8, Speed = 1.0 },
	Coin = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Speed = 1.3 },
	Hit = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1.0, Speed = 0.55 },
	Button = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.2, Speed = 0.8 },
}

return Config
