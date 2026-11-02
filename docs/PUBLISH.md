# Публикация и монетизация «Плота на порогах»

Общий путь «код → Studio → публикация → открыть для всех» тот же, что в `roblox/docs/PUBLISH.md` (аккаунт старше 2 дней, проверка возраста, анкета Maturity & Compliance, Manage Audience). Здесь — только то, что отличается: товары, ID, настройки места.

> Меню Creator Hub и Studio часто переименовывают. Если пункт называется иначе, ищи по смыслу; официальные страницы: [Passes](https://create.roblox.com/docs/production/monetization/game-passes), [Developer products](https://create.roblox.com/docs/production/monetization/developer-products), [PolicyService](https://create.roblox.com/docs/reference/engine/classes/PolicyService).

## 1. Первая публикация (приватно)
1. `rojo build -o game.rbxl`, открой в Studio.
2. **File → Publish to Roblox** → новая игра. Название и описание — ниже.
3. Creator Hub → игра → **Places** → стартовое место → **Server size: 12**.
4. В Studio: **Game Settings → Security → Enable Studio Access to API Services** — иначе в Studio профиль не сохраняется (самотест покажет WARN `player data saves`).

С этого момента работай с облачным местом: Creator Hub → **Edit in Studio** → `rojo serve` → **Connect**.

## 2. Товары: создать и вписать ID
Creator Hub → игра → **Monetization**.

### Геймпассы (Passes → Create a Pass)
| Ключ в `Config.Passes` | Название | Цена (рекоменд.) | Иконка |
|---|---|---|---|
| `DoubleCoins` | ×2 Coins / ×2 Монеты | 149 R$ | золотая монета «×2» |
| `Sturdy` | Sturdy Raft / Прочный плот | 99 R$ | плот с бронёй |
| `Vip` | VIP | 249 R$ | золотая звезда |

После создания: вкладка **Sales** → **Item for Sale** → цена → Save. ID — в адресе страницы пасса или в меню «…» → **Copy Asset ID**.

### Developer Products (Developer Products → Create)
| Ключ в `Config.Products` | Название | Цена (рекоменд.) |
|---|---|---|
| `Revive` | Second chance / Второй шанс | 19 R$ |
| `Coins500` | 500 coins | 25 R$ |
| `Coins3000` | 3000 coins | 99 R$ |
| `Chest` | Rafter's Chest / Сундук сплавщика | 35 R$ |
| `DirectRare` | Rare item / Редкий предмет | 49 R$ |
| `DirectEpic` | Epic item / Эпический предмет | 99 R$ |
| `DirectLegendary` | Legendary item / Легендарный предмет | 199 R$ |

### Вписать ID
`src/shared/Config.luau`:
```lua
Config.Passes = {
	DoubleCoins = { id = 123456789, robux = 149 },
	...
}
Config.Products = {
	Revive = { id = 987654321, robux = 19 },
	...
}
```
`robux` — запасная цена для интерфейса: игра сама запрашивает настоящую цену у Roblox (`GetProductInfo`), так что менять цену можно только в Creator Hub.

**Пока ID = 0:** в Studio покупка эмулируется (тост «Studio: покупка эмулирована»), в живой игре кнопка показывает «скоро». Самотест выводит WARN со списком товаров без ID.

## 3. Сундук и правила Roblox о случайных наградах
Уже сделано в коде:
- шанс **каждого** предмета показан до покупки (вкладка «Сундук»), сумма ровно 100%;
- дубликат превращается в монеты, сумма показана заранее;
- сервер спрашивает `PolicyService:GetPolicyInfoForPlayerAsync`; если `ArePaidRandomItemsRestricted` или запрос упал, сундук скрыт и сервер **отказывается** открыть промпт; остаётся прямая покупка любого предмета за монеты и за Robux.

Что сделать тебе:
- в анкете **Maturity & Compliance** честно отметить, что в игре есть **платные случайные предметы** (paid random items), если такой вопрос есть в анкете;
- если меняешь шансы в `Config.Rarity`, запусти `lune run tests/run.luau`: тест не даст сломать сумму 100%.

## 4. Robux и Беларусь
DevEx (вывод в деньги) недоступен, Robux копятся на балансе группы/аккаунта. Их можно тратить на рекламу игры (Ads Manager) и на то, что ускоряет рост: спонсорские показы в первые недели дают первых игроков, а без игроков монетизация не работает.

## 5. Страница игры
**Название:** `Rapids Raft: Steer With Your Weight` (EN), `Плот на порогах` (RU — через перевод в Creator Hub → Localization).

**Описание (EN):**
> No paddles, no buttons — the raft goes where your crew stands! Lean left, lean right, rush to the bow for speed and EVERYONE to the stern before the waterfall. Dodge rocks, slalom through canyon gates, escape the whirlpool and reach the lake. Play solo or bring friends: every extra crew member adds +15% coins. Collect life vests and raft skins.

**Описание (RU):**
> Ни вёсел, ни кнопок — плот идёт туда, где стоит команда! Наклоняй его весом, беги на нос за скоростью и все на корму перед водопадом. Уворачивайся от камней, проходи ворота в каньоне, вырвись из омута и доплыви до озера. Можно одному, но с друзьями выгоднее: каждый в экипаже даёт +15% монет. Собирай жилеты и раскраски плота.

**Жанр:** Adventure (или Obby & Platformer, если в каталоге так ближе). **Иконка 512×512:** плот с тремя персонажами у одного борта на фоне порогов. **Скриншоты 1920×1080:** причал с плотом, каньон с воротами, омут, водопад сверху, озеро с финишем, магазин с шансами сундука.

## 6. Перед открытием для всех
- [ ] Все ID вписаны, самотест без FAIL и без WARN о товарах.
- [ ] Покупка каждого товара проверена в живом клиенте (Creator Hub → Play) с тестовым аккаунтом; Robux списываются, товар выдаётся один раз.
- [ ] «Второй шанс» куплен во время крушения — плот чинится; куплен поздно — пришли 150 монет.
- [ ] Перезаход: монеты, косметика, рекорд на месте.
- [ ] Server size = 12.
