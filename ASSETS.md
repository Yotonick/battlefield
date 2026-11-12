# Бесплатные ассеты для проекта

Сейчас в игре **нет ни одного стороннего ассета**: модели — серые блоки, звуки сгенерированы кодом.
Ниже — что понадобится по этапам дорожной карты и где это взять бесплатно.

**Как добавлять:** скачать архив → распаковать в `assets/<тип>/<имя_пакета>/` → положить рядом файл
лицензии из архива (или `LICENSE.txt` со ссылкой) → открыть Godot (он сам импортирует) → push в GitHub.
Форматы: для 3D лучше **glTF/GLB** (`.glb`, `.gltf`), FBX тоже работает. Для звука — `.wav` или `.ogg`.
Большие паки (Sonniss) целиком не кладём — только нужные файлы, иначе репозиторий раздуется.

Лицензии: **CC0** — можно всё, без указания автора. **Royalty-free** — бесплатно, но нельзя
перепродавать сами файлы. Для нашего проекта (некоммерческий, для друзей) подходят обе.

---

## 1. Нужно для v0.2 «Ощущения от оружия» — качать первыми

### Модели оружия
| Что | Где | Лицензия | Куда положить |
|---|---|---|---|
| **50+ LowPoly Guns** (Quaternius) — АК, M4, пистолеты, дробовик, снайперка | https://quaternius.itch.io/50-lowpoly-guns (зеркало: https://opengameart.org/content/low-poly-guns-pack) | CC0 | `assets/weapons/quaternius_guns/` |
| Запасной вариант: **Guns Asset Pack** (styloo), есть тег Godot | https://styloo.itch.io/guns-asset-pack | CC0 | `assets/weapons/styloo_guns/` |

### Звуки оружия
| Что | Где | Лицензия | Куда |
|---|---|---|---|
| **The Free Firearm Sound Library** — записи настоящих выстрелов, в т.ч. автоматы | https://opengameart.org/content/the-free-firearm-sound-library | CC0 | `assets/audio/firearms/` |
| **Snake's Authentic Gun Sounds** — 5.56, 7.62×39, звуки перезарядки | https://f8studios.itch.io/snakes-authentic-gun-sounds | бесплатно (условия — на странице) | `assets/audio/firearms_snake/` |
| **Kenney Impact Sounds** — удары пуль о металл, дерево, камень | https://kenney.nl/assets/impact-sounds | CC0 | `assets/audio/impacts/` |
| **Sonniss GDC 2026 Game Audio Bundle** — 7+ ГБ студийных звуков (взрывы, окружение, оружие) | https://sonniss.com/gameaudiogdc | royalty-free | брать по 5–10 файлов в `assets/audio/sonniss/` |

### Руки от первого лица (по желанию)
В low-poly шутерах можно обойтись без рук — только ствол (как сейчас). Если захотим руки:
| Что | Где | Лицензия |
|---|---|---|
| Low Poly FPS Rifle and Hands (руки + винтовка + анимация выстрела) | https://opengameart.org/content/low-poly-fps-rifle-and-hands | CC0 |
| FPS arms (rigged only) | https://opengameart.org/content/fps-arms-rigged-only | CC0 |
| FPS Arms PSX style | https://cemckrc.itch.io/fps-arms-psx-style | CC0 |

---

## 2. Для v0.2–v0.3: модель бойца и анимации (вместо серой капсулы, нужно и для ботов)

| Что | Где | Лицензия | Куда |
|---|---|---|---|
| **Universal Base Characters** (Quaternius) — 6 базовых фигур, гуманоидный риг | https://quaternius.itch.io/universal-base-characters | CC0 | `assets/characters/base/` |
| **Universal Animation Library** (Quaternius) — 120+ анимаций: ходьба в 8 направлениях, бег, присед, смерти | https://quaternius.itch.io/universal-animation-library | CC0 | `assets/animations/ual1/` |
| **Universal Animation Library 2** — ещё 130+ анимаций, в т.ч. боевые | https://quaternius.itch.io/universal-animation-library-2 | CC0 | `assets/animations/ual2/` |
| **Mixamo** — анимации «с автоматом» (rifle walk/run/aim/reload), есть персонажи | https://www.mixamo.com (нужен бесплатный аккаунт Adobe) | бесплатно для игр | `assets/animations/mixamo/` |

⚠️ **Чего бесплатно в нормальном виде НЕ нашлось:** низкополигонального *современного солдата*
(каска, бронежилет, форма) под свободной лицензией и в серьёзном стиле. Варианты:
базовая фигура Quaternius + каска/жилет/подсумки из простых блоков (сделаю сам), или солдат с Mixamo.
Решать владельцу, когда дойдём до v0.2.

---

## 3. Для v0.5: карта-городок

| Что | Где | Лицензия | Комментарий |
|---|---|---|---|
| **Downtown City MegaKit** (Quaternius, май 2026) — 300+ модульных деталей домов и улиц | https://quaternius.com/packs/downtowncitymegakit.html | CC0 | Стиль большого города (Бостон/Нью-Йорк) — для центра городка |
| **LowPoly Buildings Pack** (Quaternius) — модульные дома с атласом цветов | https://opengameart.org/content/lowpoly-buildings-pack | CC0 | |
| **LowPoly Modular Street** (Quaternius) — дороги, знаки, светофоры | https://quaternius.itch.io/lowpoly-modular-street | CC0 | |
| **City Kit (Suburban)** (Kenney) — частные дома, заборы, деревья | https://kenney-assets.itch.io/city-kit-suburban | CC0 | Стиль Kenney ближе к мультяшному — проверить, не спорит ли с решением 6 |
| **City Kit (Commercial)** (Kenney) — магазины, вывески | https://opengameart.org/content/city-kit-commercial | CC0 | то же |
| **Military FREE** (ithappy) — 30 моделей: ежи, мешки, бочки, вышка, палатка, вертолёт, танк | https://www.cgtrader.com/free-3d-models/military/other/military-7504879d-ec6e-45dd-8dc3-95f8da3d2a8c | royalty-free, коммерция разрешена | нужен бесплатный аккаунт CGTrader |
| **Poly Haven** — текстуры (асфальт, бетон, кирпич, трава), HDRI-небо | https://polyhaven.com | CC0 | |
| **ambientCG** — текстуры | https://ambientcg.com | CC0 | |

---

## 4. Для v0.6: техника

| Что | Где | Лицензия | Комментарий |
|---|---|---|---|
| **Low Poly Military Vehicles** (Zsky) | https://zsky2000.itch.io/low-poly-military-vehicles | бесплатно | |
| **3d Low Poly Military Vehicles** (widgeon) — танк, ударный вертолёт, бронемашина | https://widgeon.itch.io/3d-low-poly-military-vehicles | бесплатно | только `.obj` |
| **Low-Poly tank assets** + мешки с песком | https://opengameart.org/content/low-poly-tank-assets | CC0 | |

⚠️ Для езды нужны **отдельные** колёса, башня и ствол. Перед использованием проверить в Blender,
что модель разбита на части; иначе придётся резать самим.

---

## 5. Интерфейс
- Шрифты с кириллицей — Google Fonts (лицензия OFL): например, *Oswald*, *Russo One*, *Rubik*.
  Скачать `.ttf` в `assets/fonts/`.

---

## Что скачать первым (понадобится в v0.2; можно заранее — v0.1 ассеты не нужны)
1. **50+ LowPoly Guns** (Quaternius) → `assets/weapons/quaternius_guns/`
2. **The Free Firearm Sound Library** → `assets/audio/firearms/`
3. **Kenney Impact Sounds** → `assets/audio/impacts/`

Остальное — когда дойдём до соответствующей версии.

> Примечание: на сайте Quaternius встречаются сообщения о переходе на собственную лицензию
> (QAL); на страницах паков на itch.io указано CC0. Для некоммерческого проекта для друзей
> это ничего не меняет — использовать можно.

## Уже в проекте (v0.2)
| Что | Откуда | Лицензия | Где |
|---|---|---|---|
| M4A1, M16, SCAR, MP5, MP7, M1911, M1911 Tactical (FBX) | скачал владелец (папка `models\`) | бесплатные, проект некоммерческий | `assets/weapons/*.fbx` |
| АК, помповый дробовик, снайперская винтовка — из **Ultimate Gun Pack** (Quaternius): `AssaultRifle_2`, `Shotgun_1`, `SniperRifle_1` | Quaternius | CC0 | `assets/weapons/ak.fbx`, `shotgun_pump.fbx`, `sniper_bolt.fbx` |
