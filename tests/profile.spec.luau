return function(t)
	local Profile = t.shared("Profile")
	local Config = t.shared("Config")
	local Rewards = t.shared("Rewards")

	t.test("new profile owns and wears the defaults", function()
		local d = Profile.new()
		t.ok(d.owned.vest_orange and d.owned.raft_pine)
		t.eq(d.equipped.vest, "vest_orange")
		t.eq(d.coins, 0)
	end)

	t.test("migrate: garbage, old fields, unknown items", function()
		t.eq(Profile.migrate(nil).coins, 0)
		t.eq(Profile.migrate("x").coins, 0)
		local d = Profile.migrate({
			coins = 12.7,
			owned = { vest_lime = true, bogus = true },
			equipped = { vest = "raft_pine", raft = "raft_birch" },
			receipts = { "a", 5 },
		})
		t.eq(d.coins, 12)
		t.ok(d.owned.vest_lime and not d.owned.bogus)
		t.eq(d.equipped.vest, "vest_orange", "wrong kind falls back")
		t.eq(d.equipped.raft, "raft_birch")
		t.eq(#d.receipts, 1)
	end)

	t.test("duplicates refund coins", function()
		local d = Profile.new()
		local a = Profile.grantItem(d, "vest_lime")
		t.ok(not a.dup)
		local b = Profile.grantItem(d, "vest_lime")
		t.ok(b.dup)
		t.eq(b.refund, Config.Rarity.Common.refund)
		t.eq(d.coins, Config.Rarity.Common.refund)
	end)

	t.test("buying with coins", function()
		local d = Profile.new()
		local ok, err = Profile.buyWithCoins(d, "vest_lime")
		t.ok(not ok and err == "shop.noCoins")
		d.coins = 1000
		ok = Profile.buyWithCoins(d, "vest_lime")
		t.ok(ok)
		t.eq(d.coins, 1000 - Config.Rarity.Common.price)
		ok, err = Profile.buyWithCoins(d, "vest_lime")
		t.ok(not ok and err == "shop.owned")
		ok, err = Profile.buyWithCoins(d, "raft_gold")
		t.ok(not ok and err == "shop.notForSale")
	end)

	t.test("equip rules and VIP items", function()
		local d = Profile.new()
		t.ok(not Profile.equip(d, "vest_lime", false), "not owned")
		t.ok(not Profile.equip(d, "vest_gold", false), "VIP without pass")
		t.ok(Profile.equip(d, "vest_gold", true), "VIP with pass")
		t.eq(Profile.effective(d, "vest", true), "vest_gold")
		t.eq(Profile.effective(d, "vest", false), "vest_orange", "pass gone → default")
	end)

	t.test("direct purchase picks the wanted item or any missing one", function()
		local d = Profile.new()
		t.eq(Profile.pickDirect(d, "Epic", "raft_ice"), "raft_ice")
		t.ok(Profile.pickDirect(d, "Epic", "vest_lime") ~= "vest_lime", "wrong rarity ignored")
		d.owned.raft_ice = true
		t.ok(Profile.pickDirect(d, "Epic", "raft_ice") ~= "raft_ice", "owned → another one")
		d.owned.vest_aurora = true
		d.owned.raft_crystal = true
		t.eq(Profile.pickDirect(d, "Legendary", nil), nil, "all owned")
	end)

	t.test("receipt log is bounded and idempotent", function()
		local d = Profile.new()
		for i = 1, Config.DataStore.ReceiptLog + 20 do
			Profile.addReceipt(d, "p" .. i)
		end
		t.eq(#d.receipts, Config.DataStore.ReceiptLog)
		t.ok(not Profile.hasReceipt(d, "p1"))
		t.ok(Profile.hasReceipt(d, "p" .. (Config.DataStore.ReceiptLog + 20)))
	end)

	t.test("best time only improves", function()
		local d = Profile.new()
		t.ok(Profile.recordRun(d, true, 150, 40))
		t.ok(not Profile.recordRun(d, true, 160, 40))
		t.ok(Profile.recordRun(d, true, 140, 40))
		t.ok(not Profile.recordRun(d, false, 10, 5), "unfinished runs never set a record")
		t.eq(d.best, 140)
		t.eq(d.coins, 125)
		t.eq(d.runs, 4)
	end)

	t.test("rewards: crew bonus, passes and fractional coins", function()
		t.eq(Rewards.multiplier(1, false, false), 1)
		t.near(Rewards.multiplier(3, false, false), 1.3, 1e-9)
		t.near(Rewards.multiplier(6, false, false), 1 + Config.Rewards.CrewBonusMax, 1e-9)
		t.near(Rewards.multiplier(9, false, false), 1 + Config.Rewards.CrewBonusMax, 1e-9, "capped")
		t.near(Rewards.multiplier(1, true, true), 2.2, 1e-9)
		-- 10 монет по 1 при ×1.3 → ровно 13, без потерь на округлении
		local total, base = 0, 0
		for _ = 1, 10 do
			total += Rewards.delta(base, base + 1, 1.3)
			base += 1
		end
		t.eq(total, 13)
		t.eq(Rewards.finishBonus(100), Config.Rewards.Finish + 25)
		t.eq(Rewards.finishBonus(-5), Config.Rewards.Finish)
	end)
end
