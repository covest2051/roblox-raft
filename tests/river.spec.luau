return function(t)
	local River = t.shared("River")
	local Config = t.shared("Config")

	t.test("sections are contiguous and long enough", function()
		local prev = 0
		for _, sec in River.Sections do
			t.eq(sec.startS, prev, sec.id .. " start")
			t.ok(sec.length >= 150, sec.id .. " too short")
			prev = sec.endS
		end
		t.eq(prev, River.length)
		t.ok(River.length > 2200 and River.length < 3200, "river length " .. River.length)
	end)

	t.test("centerline is continuous (no jumps between samples)", function()
		local px, pz = River.center(0)
		for s = 2, River.length, 2 do
			local x, z = River.center(s)
			local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
			t.ok(d > 1.9 and d < 2.1, "step at s=" .. s .. " is " .. d)
			px, pz = x, z
		end
	end)

	t.test("river never crosses itself (banks stay apart)", function()
		local pts = {}
		for s = 0, River.length, 20 do
			local x, z = River.center(s)
			table.insert(pts, { s = s, x = x, z = z })
		end
		for i, a in pts do
			for j = i + 1, #pts do
				local b = pts[j]
				if b.s - a.s > 200 then
					local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
					local need = (River.width(a.s) + River.width(b.s)) / 2 + 60
					t.ok(d > need, string.format("s=%d and s=%d too close (%.0f)", a.s, b.s, d))
				end
			end
		end
	end)

	t.test("raft fits everywhere with room to steer", function()
		for s = 0, River.length, 5 do
			t.ok(River.halfFree(s, Config.Raft.Width / 2) >= 8, "narrow at s=" .. s)
		end
	end)

	t.test("rocks and coins lie inside the river", function()
		for _, r in River.rocks do
			t.ok(math.abs(r.x) + r.r <= River.width(r.s) / 2 + 0.5, "rock " .. r.id .. " outside")
			t.ok(r.s < River.dropS - 60 or r.s > River.dropS + 60, "rock next to the waterfall")
		end
		for _, c in River.coins do
			t.ok(
				math.abs(c.x) <= River.halfFree(c.s, Config.Raft.Width / 2) + Config.Raft.Width / 2 - 1,
				"coin " .. c.id .. " unreachable"
			)
		end
		t.ok(#River.rocks >= 40, "enough rocks: " .. #River.rocks)
		t.ok(River.totalCoins() >= 90, "enough coins: " .. River.totalCoins())
	end)

	t.test("every rock row leaves a passage for the raft", function()
		local need = 2 * Config.Raft.Radius + 2
		for _, row in River.rows do
			-- свободные отрезки поперёк реки в полосе ±10 studs от ряда
			local blocks = {}
			for _, r in River.rocks do
				if math.abs(r.s - row.s) < 10 then
					table.insert(blocks, { r.x - r.r, r.x + r.r })
				end
			end
			table.sort(blocks, function(a, b)
				return a[1] < b[1]
			end)
			local half = River.width(row.s) / 2
			local x, widest = -half, 0
			for _, b in blocks do
				widest = math.max(widest, b[1] - x)
				x = math.max(x, b[2])
			end
			widest = math.max(widest, half - x)
			t.ok(widest >= need, string.format("row at s=%.0f: widest gap %.1f < %d", row.s, widest, need))
		end
	end)

	t.test("water level drops once, at the waterfall", function()
		t.eq(River.waterLevel(River.dropS - 1), River.LevelHigh)
		t.eq(River.waterLevel(River.dropS + 1), River.LevelLow)
		t.ok(River.finishS > River.dropS + 100 and River.finishS < River.length - 60, "finish in the lake")
		t.ok(River.warnDropS < River.dropS - 100, "warning well before the drop")
	end)

	t.test("point() is center + right-hand offset", function()
		local s = 900
		local cx, cz, h = River.center(s)
		local x, z = River.point(s, 10)
		t.near(x, cx - math.sin(h) * 10, 1e-6)
		t.near(z, cz + math.cos(h) * 10, 1e-6)
	end)
end
