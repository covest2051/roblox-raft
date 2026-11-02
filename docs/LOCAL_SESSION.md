# Локальная сессия Claude Code + Studio MCP

Подготовка Studio MCP — как в `roblox/docs/LOCAL_SESSION.md` (Assistant → Manage MCP Servers → Enable Studio as MCP server, Quick connect → Claude Code). Сначала пройди [`PLAYTEST.md`](PLAYTEST.md) руками — это не тратит лимиты. До 4 ноября найденное дешевле присылать в облачную сессию.

## Промпт для старта (скопируй целиком)

```
Проект — Roblox-игра «Плот на порогах», Rojo-проект в этом репозитории.
Studio открыта и синхронизирована через `rojo serve`, Studio MCP подключён.

Правила экономии:
- Не читай весь репозиторий: структура — в README.md, механики — в docs/DESIGN.md.
- Правь ТОЛЬКО src/**, Rojo синхронизирует сам. Не правь скрипты в Studio напрямую.
- screen_capture — только если я прошу или баг без картинки не понять.
- После каждой правки логики: `lune run tests/run.luau`.

Задача:
1. start_stop_play (Play), подожди ~10 с, get_console_output.
2. Найди строки [SELFTEST] и красные ошибки, пришли короткую сводку.
3. Исправляй ошибки по одной: правка → стоп/Play → Output.
4. Когда Output чистый, проверь плот в движке через execute_luau (datamodel Server):
     local RS = require(game.ServerScriptService.Server.RaftService)
     for id, r in RS.rafts do print(id, r.phase, r.hull.CFrame.Position, r.hull.AssemblyLinearVelocity) end
   Персонаж должен стоять на палубе (встань на плот у причала через телепорт):
     local p = game.Players:GetPlayers()[1]
     for _, r in RS.rafts do p.Character:PivotTo(r.hull.CFrame * CFrame.new(0, 5, 0)) break end
   Через 3 с плот отплывёт. Включи автопилот (та же команда, что у кнопки DBG):
     RS.debug(p, "auto")
   Через 20–30 с: get_console_output и screen_capture один раз — едет ли персонаж на плоту.
5. Коммить исправления с понятными сообщениями.
```

## Типичные проблемы, видимые только в движке

| Симптом | Где править |
|---|---|
| Персонаж соскальзывает с плота | `RaftModel.build`: трение палубы (`CustomPhysicalProperties` у `Deck`), высота леера |
| Плот дёргается или «плывёт» за целью | `RaftModel.build`: `RigidityEnabled` у AlignPosition/AlignOrientation; можно заменить на `Responsiveness = 60` |
| Плот застревает в берегу/падает сквозь воду | группы столкновений `RaftModel.setupGroups` (Terrain ↔ Raft) |
| Руление слишком резкое или вялое | `Config.Lean.Steer`, `LatDrag`, `MaxLat`, затем `lune run tests/run.luau` |
| Вода не там, берег «ступеньками» | `WorldBuilder.terrain` (`CHUNK`, `BED`, `BANK_W`) |
| Таблички задом наперёд | `WorldBuilder.props`, поворот `CFrame.Angles(0, math.rad(180), 0)` у `sign` |
| Монеты не видно или они не крутятся | `WorldBuilder.props` (Coins), `Fx.update` |
| Лагает | число деревьев в `WorldBuilder.props` (шаг `9` и вероятность `0.55`) |

## Звуки
`Config.Sounds` — встроенные `rbxasset://` звуки (плеск, удар, монета). Шума реки там нет: найди через `search_asset` бесплатный звук реки (автор Roblox или public), впиши `rbxassetid://<id>` в `Config.Sounds.River.Id`.
