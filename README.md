# base-gui

Базовый проект для ComputerCraft (CC:Tweaked) с выводом на монитор.

## Структура проекта

```
base-gui/
├── update.lua        ← Принудительное обновление всех файлов с дев-сервера
├── startup.lua       ← Запускается автоматически при старте компьютера
├── dev-server.bat    ← Запуск HTTP-сервера (два клика)
├── dev-server.js     ← HTTP-сервер на Node.js (встроенный модуль http)
└── README.md         ← Эта инструкция
```

## Быстрый старт

1. Запустите `dev-server.bat` (два клика) — или вручную: `node dev-server.js`
2. В игре поставьте компьютер, а справа от него — монитор
3. В компьютере выполните: `wget http://localhost:8000/startup.lua startup.lua`
4. Запустите: `startup.lua`
5. При перезагрузке компьютера скрипт выполнится сам

## Настройка дев-сервера

### Способ 1: Node.js HTTP-сервер (рекомендуемый)

**Требования:** Node.js (установлен)

Запустите `dev-server.bat` двойным кликом. Батник выполнит:

```powershell
node dev-server.js
```

Сервер написан на чистом Node.js без сторонних пакетов — работает сразу.

Сервер будет раздавать файлы проекта по адресу `http://localhost:8000`.

В игре на компьютере выполните:

```lua
wget http://localhost:8000/startup.lua startup.lua
```

### Способ 2: Прямое копирование в мир (без сервера)

Найдите папку с компьютерами вашего мира. Для FreesmLauncher / Prism:

```
%appdata%\FreesmLauncher\instances\Create Aeronautics\minecraft\saves\<НАЗВАНИЕ_МИРА>\computers\<ID_КОМПЬЮТЕРА>\
```

Скопируйте `startup.lua` напрямую в эту папку. ID компьютера можно узнать, запустив на нём:

```lua
print(os.getComputerID())
```

После этого перезагрузите компьютер.

### Способ 3: CC:Tweaked CLI (продвинутый — с live reload)

```powershell
npx @cc-tweaked/cli serve
```

Подробнее: https://tweaked.cc/guide/

## Настройка Minecraft (CC:Tweaked Config)

Для HTTP-сервера нужно разрешить `http` API в конфиге CC:Tweaked.

Файл конфига: `config/computercraft-server.toml` (не `cc-tweaked.toml` — зависит от лаунчера).

Убедитесь, что:

```toml
[http]
enabled = true
```

И добавьте разрешение для `localhost:8000` **перед** правилом `$private` (которое блокирует все локальные адреса):

```toml
[[http.rules]]
host = "localhost"
port = 8000
action = "allow"

[[http.rules]]
host = "$private"
action = "deny"
```

> **Порядок важен:** правила применяются сверху вниз. Если `$private` стоит раньше — `localhost` будет заблокирован.

> **Где искать конфиг:** лаунчеры (FreesmLauncher / Prism) хранят конфиги внутри папки инстанса: `instances\<ИНСТАНС>\minecraft\config\computercraft-server.toml`.

## Запуск на компьютере в игре

1. Поставьте компьютер (Computer) на любую поверхность
2. Поставьте монитор (Monitor) **справа от компьютера** (со стороны, куда смотрит правый бок компьютера)
3. Подключите компьютер к сети (модему), если нужно
4. Загрузите `startup.lua` (см. выше)
5. Перезагрузите компьютер — `startup.lua` выполнится автоматически

Либо выполните вручную:

```lua
shell.run("startup")
```

## Обновление файлов

`wget` в CC:Tweaked **не перезаписывает** существующие файлы. Чтобы обновить скрипты после изменений — используйте `update.lua`:

```lua
update
```

Скрипт сам удалит старые файлы и скачает свежие с дев-сервера.

Если нужно обновить только один файл вручную:

```lua
fs.delete("startup.lua")
wget http://localhost:8000/startup.lua startup.lua
```

---

## Беспроводная система мониторинга баков

### Схема

```
[Бак Create]──[Комп #2]──модем~~   ~~модем──[Комп #1]──[Монитор справа]
[Бак Create]──[Комп #3]──модем~~   ~~модем──[Комп #1]──[Монитор справа]
[Бак Create]──[Комп #4]──модем~~   ~~модем──[Комп #1]──[Монитор справа]
```

### Что куда ставить

**Центральный ПК (Комп #1):**
- Поставить компьютер
- Справа — монитор (Advanced Monitor)
- На любую свободную сторону — **Wireless Modem**
- Скрипт: `startup.lua` (автозапуск)
- Загрузить: `wget http://localhost:8000/startup.lua startup.lua`

**На каждый бак (Комп #2, #3, #4...):**
- Поставить компьютер **вплотную к Create Fluid Tank**
- На компьютер — **Wireless Modem**
- Скрипт: `tank_sender.lua`
- Загрузить: `wget http://localhost:8000/tank_sender.lua tank_sender.lua`
- Запустить: `tank_sender.lua`

> Для автозапуска на компьютере бака — сделай `startup.lua` копией `tank_sender.lua`:
> ```lua
> fs.delete("startup.lua")
> wget http://localhost:8000/tank_sender.lua startup.lua
> ```
> Теперь после перезагрузки он сам начнёт передавать данные.

### Назначение имён бакам

Чтобы на мониторе было понятно, какой где:

```lua
label set "Lava Tank"
```

После перезапуска `tank_sender.lua` на мониторе появится `Lava Tank`.

### Как это работает

| Компьютер | Что делает |
|---|---|
| **Каждый бак** | Читает `fluid_storage.tanks()` → шлёт broadcast с протоколом `"tank_data"` раз в 3 секунды |
| **Центральный ПК** | `rednet.receive("tank_data")` → хранит данные от всех → рисует на мониторе |

### Пример вывода на мониторе

```
+-------------------- base observer --------------------+
|> Lava Tank                                             |
|   lava                             32000 mB            |
|> Water Tank                                            |
|   water                             8000 mB            |
|                                                        |
|                                   [2 tank(s) connected]|
+--------------------------------------------------------+
```

### Добавление нового бака

1. Поставить компьютер + модем рядом с новым баком
2. Загрузить: `wget http://localhost:8000/tank_sender.lua tank_sender.lua`
3. Запустить: `tank_sender.lua`
4. Центральный ПК сам подхватит данные в течение 3 секунд
