--[[
	Rewards — сколько монет получает игрок. Монеты начисляются сразу по ходу заплыва
	(вышел посреди реки — заработанное не пропадает), дробная часть множителя
	не теряется: начисляется разница floor(base·mult) до и после события.
]]

local Shared = script.Parent
local Config = require(Shared.Config)

local Rewards = {}

function Rewards.crewBonus(crew: number): number
	local R = Config.Rewards
	return math.min(R.CrewBonusMax, R.CrewBonus * math.max(0, crew - 1))
end

function Rewards.multiplier(crew: number, double: boolean, vip: boolean): number
	local R = Config.Rewards
	local m = 1 + Rewards.crewBonus(crew)
	if double then
		m *= R.DoubleCoins
	end
	if vip then
		m *= 1 + R.VipBonus
	end
	return m
end

-- Сколько начислить, когда «сырые» монеты заплыва выросли с prevBase до newBase
function Rewards.delta(prevBase: number, newBase: number, mult: number): number
	return math.floor(newBase * mult + 1e-9) - math.floor(prevBase * mult + 1e-9)
end

function Rewards.finishBonus(hp: number): number
	local R = Config.Rewards
	return R.Finish + math.floor(math.max(0, hp) / R.HpPerCoin)
end

return Rewards
