return function(t)
	local Catalog = t.shared("Catalog")
	local Config = t.shared("Config")

	t.test("odds are exact and sum to 100%", function()
		local sum = 0
		local perRarity = {}
		for _, o in Catalog.odds() do
			sum += o.bp
			perRarity[o.rarity] = (perRarity[o.rarity] or 0) + o.bp
			t.ok(o.bp > 0, o.id)
		end
		t.eq(sum, Config.WeightTotal, "sum of item odds")
		for _, r in Config.RarityOrder do
			t.eq(perRarity[r], Config.Rarity[r].weight, r .. " weight divides evenly between its items")
		end
	end)

	t.test("percent formatting", function()
		t.eq(Catalog.formatBp(1200), "12%")
		t.eq(Catalog.formatBp(560), "5.6%")
		t.eq(Catalog.formatBp(250), "2.5%")
		t.eq(Catalog.formatBp(100), "1%")
		t.eq(Catalog.formatBp(6000), "60%")
		t.eq(Catalog.formatBp(1), "0.01%")
	end)

	t.test("roll covers the whole range deterministically", function()
		local odds = Catalog.odds()
		t.eq(
			Catalog.roll(function()
				return 1
			end),
			odds[1].id
		)
		t.eq(
			Catalog.roll(function()
				return Config.WeightTotal
			end),
			odds[#odds].id
		)
		-- граница между Common и Rare
		local common = Config.Rarity.Common.weight
		local id = Catalog.roll(function()
			return common + 1
		end)
		t.eq(Catalog.get(id).rarity, "Rare")
	end)

	t.test("roll distribution matches the displayed odds (Monte Carlo)", function()
		local seed = 12345
		local function randInt(a, b)
			seed = (seed * 48271) % 2147483647
			return a + seed % (b - a + 1)
		end
		local N = 200000
		local counts = {}
		for _ = 1, N do
			local id = Catalog.roll(randInt)
			counts[id] = (counts[id] or 0) + 1
		end
		for _, o in Catalog.odds() do
			local p = o.bp / Config.WeightTotal
			local got = (counts[o.id] or 0) / N
			local sigma = math.sqrt(p * (1 - p) / N)
			t.ok(math.abs(got - p) < 5 * sigma, string.format("%s: %.4f vs %.4f", o.id, got, p))
		end
	end)

	t.test("default and VIP items are never in the chest or the shop", function()
		for _, o in Catalog.odds() do
			local r = Catalog.get(o.id).rarity
			t.ok(r ~= "Default" and r ~= "Vip", o.id)
		end
		t.eq(Catalog.price("vest_orange"), nil)
		t.eq(Catalog.price("raft_gold"), nil)
		t.ok(Catalog.price("vest_lime") ~= nil)
	end)

	t.test("every item has a valid kind, colors and material", function()
		local Enum = (require :: any)("@lune/roblox").Enum
		local ids = {}
		for _, it in Catalog.Items do
			t.ok(not ids[it.id], "unique id " .. it.id)
			ids[it.id] = true
			t.ok(it.kind == "vest" or it.kind == "raft", it.id)
			t.ok(string.sub(it.id, 1, #it.kind) == it.kind, "id prefix " .. it.id)
			t.eq(#it.color, 3)
			t.eq(#it.accent, 3)
			t.ok(
				pcall(function()
					return Enum.Material[it.material]
				end),
				"material " .. it.material
			)
		end
		t.ok(Catalog.get(Catalog.Default.vest) and Catalog.get(Catalog.Default.raft), "defaults exist")
	end)

	t.test("refund is less than the direct price", function()
		for _, r in Config.RarityOrder do
			t.ok(Config.Rarity[r].refund < Config.Rarity[r].price, r)
		end
	end)
end
