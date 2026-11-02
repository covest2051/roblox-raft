return function(t)
	local River = t.shared("River")
	local RaftSim = t.shared("RaftSim")
	local Config = t.shared("Config")

	local DT = Config.Timing.SimStep

	local function run(policy, maxT)
		local st = RaftSim.new()
		local log = { coin = 0, rock = 0, gate = 0, bank = 0, dropSafe = 0, dropBad = 0 }
		while not st.finished and not st.broken and st.t < (maxT or 600) do
			local bx, bz = policy(st)
			for _, e in RaftSim.step(st, bx, bz, DT) do
				log[e.kind] = (log[e.kind] or 0) + (if e.kind == "coin" then e.value else 1)
			end
		end
		return st, log
	end

	t.test("balance: center of mass of the crew", function()
		local hx, hz = Config.Raft.Width / 2, Config.Raft.Length / 2
		local bx, bz = RaftSim.balance({})
		t.eq(bx, 0)
		t.eq(bz, 0)
		bx, bz = RaftSim.balance({ { x = hx, z = 0 } })
		t.near(bx, 1, 1e-9, "solo at the right edge = full right")
		bx = RaftSim.balance({ { x = hx, z = 0 }, { x = -hx, z = 0 } })
		t.eq(bx, 0, "opposite sides cancel out")
		bx = RaftSim.balance({ { x = hx, z = 0 }, { x = hx, z = 0 }, { x = -hx, z = 0 } })
		t.ok(bx > 0.25 and bx < 0.4, "2 vs 1 → partial right: " .. bx)
		bx, bz = RaftSim.balance({ { x = 0.3, z = -0.3 } })
		t.eq(bx, 0, "deadzone")
		bx, bz = RaftSim.balance({ { x = 0, z = -hz } })
		t.near(bz, 1, 1e-9, "front (−Z) = +bz")
		bx, bz = RaftSim.balance({ { x = 99, z = 99 } })
		t.near(bx, 1, 1e-9, "clamped")
		t.near(bz, -1, 1e-9, "clamped")
	end)

	t.test("weight steers: right lean moves the raft right, left — left", function()
		local a, b = RaftSim.new(), RaftSim.new()
		for _ = 1, 60 do
			RaftSim.step(a, 1, 0, DT)
			RaftSim.step(b, -1, 0, DT)
		end
		t.ok(a.x > 4, "right: " .. a.x)
		t.ok(b.x < -4, "left: " .. b.x)
	end)

	t.test("weight forward is faster, weight back is slower", function()
		local f, n, k = RaftSim.new(), RaftSim.new(), RaftSim.new()
		for _ = 1, 300 do
			RaftSim.step(f, 0, 1, DT)
			RaftSim.step(n, 0, 0, DT)
			RaftSim.step(k, 0, -1, DT)
		end
		t.ok(f.s > n.s + 5 and n.s > k.s + 5, string.format("%.0f %.0f %.0f", f.s, n.s, k.s))
	end)

	t.test("attentive crew finishes undamaged in 2–3.5 minutes", function()
		local st, log = run(RaftSim.autopilot)
		t.ok(st.finished, "finished (s=" .. math.floor(st.s) .. ")")
		t.eq(log.rock, 0, "rocks hit")
		t.eq(log.dropSafe, 1, "safe waterfall landing")
		t.ok(st.t > 120 and st.t < 210, "run time " .. st.t)
		t.ok(log.coin >= 60, "coins " .. log.coin)
		t.eq(log.gate, #River.gates, "all gates")
	end)

	t.test("crew that does nothing wrecks the raft", function()
		local st, log = run(function()
			return 0, 0
		end)
		t.ok(st.broken, "broken")
		t.ok(log.rock >= 4, "hit rocks: " .. log.rock)
	end)

	t.test("slow, sloppy crew still makes it (reaction 0.4 s, noisy, half strength)", function()
		local queue = {}
		local seed = 7
		local function noise()
			seed = (seed * 48271) % 2147483647
			return (seed / 2147483647) * 2 - 1
		end
		local st, log = run(function(st)
			local bx, bz = RaftSim.autopilot(st)
			table.insert(queue, { bx * 0.6 + noise() * 0.25, bz })
			if #queue > 12 then
				local v = table.remove(queue, 1)
				return v[1], v[2]
			end
			return 0, 0
		end)
		t.ok(st.finished, string.format("finished (s=%.0f hp=%d rocks=%d)", st.s, st.hp, log.rock))
		t.ok(st.hp > 20, "hp left " .. st.hp)
	end)

	t.test("waterfall: weight forward costs hull, weight back is safe", function()
		local function at(bz)
			local st = RaftSim.new(100, River.dropS - 30)
			st.v = 20
			local bad = false
			for _ = 1, 120 do
				for _, e in RaftSim.step(st, 0, bz, DT) do
					bad = bad or e.kind == "dropBad"
				end
			end
			return st, bad
		end
		local front, badF = at(0.5)
		local back, badB = at(-0.6)
		t.ok(badF and front.hp == 100 - Config.Damage.DropBad, "nose-dive damage")
		t.ok(not badB and back.hp == 100, "landing on the stern")
		t.ok(back.y < River.LevelHigh - River.DropHeight + 0.01, "raft is down in the lake")
	end)

	t.test("rock hit: damage grows with speed, raft slows and is pushed aside", function()
		local rock = River.rocks[10]
		local st = RaftSim.new(100, rock.s - 20)
		st.x = rock.x
		st.v = 24
		local hit
		for _ = 1, 60 do
			for _, e in RaftSim.step(st, 0, 0, DT) do
				if e.kind == "rock" and not hit then
					hit = e
				end
			end
		end
		t.ok(hit ~= nil, "hit the rock")
		t.ok(hit.damage >= 15 and hit.damage <= 30, "damage " .. tostring(hit and hit.damage))
		t.ok(math.abs(st.x - rock.x) > rock.r, "pushed aside")
	end)

	t.test("whirlpool pulls in and slows; full lean escapes", function()
		local wp = River.whirlpool
		local trapped = RaftSim.new(100, wp.s - wp.r)
		trapped.x = 6
		trapped.v = 10
		local esc = RaftSim.new(100, wp.s - wp.r)
		esc.x = 6
		esc.v = 10
		local minV = math.huge
		for _ = 1, 90 do
			RaftSim.step(trapped, 0, 0, DT)
			RaftSim.step(esc, 1, 0, DT)
			minV = math.min(minV, trapped.v)
		end
		t.ok(math.abs(trapped.x - wp.x) < 3, "dragged to the center: " .. trapped.x)
		t.ok(minV < River.current(wp.s) * 0.7, "slowed down: " .. minV)
		t.ok(esc.x > wp.r * 0.6, "escaped: " .. esc.x)
	end)

	t.test("banks: raft stays in the river and takes small damage", function()
		local st, log = run(function()
			return 1, 0
		end, 25)
		t.ok(log.bank >= 1, "touched the bank")
		t.ok(math.abs(st.x) <= River.halfFree(st.s, Config.Raft.Width / 2) + 1e-6, "inside")
	end)

	t.test("coins are taken once and gates count only between buoys", function()
		local st = RaftSim.new(100, River.gates[1].s - 30)
		st.x = River.gates[1].x
		st.v = 20
		local got, miss = 0, 0
		for _ = 1, 60 do
			for _, e in RaftSim.step(st, 0, 0, DT) do
				if e.kind == "gate" then
					got += 1
				elseif e.kind == "gateMiss" then
					miss += 1
				end
			end
		end
		t.eq(got, 1, "gate taken")
		t.eq(miss, 0)
		local before = 0
		for _ in st.coins do
			before += 1
		end
		RaftSim.step(st, 0, 0, DT)
		local after = 0
		for _ in st.coins do
			after += 1
		end
		t.eq(after, before, "no double pickups")
	end)
end
