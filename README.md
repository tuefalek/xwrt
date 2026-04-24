# xwrt — прозрачный прокси для OpenWRT на базе mihomo

Устанавливает [mihomo](https://github.com/MetaCubeX/mihomo) (Clash Meta) на роутер OpenWRT с прозрачным проксированием всех клиентов через tproxy + nftables. Весь трафик идёт через прокси автоматически — без настройки браузеров или устройств.

Протестировано на OpenWRT 25.12 / Xiaomi AX3600 (aarch64).

## Установка

```sh
curl -L https://raw.githubusercontent.com/tuefalek/xwrt/main/install-xwrt.sh | sh
```

Скрипт задаст два вопроса: подтверждение архитектуры и ссылка на подписку.

### Требования

- OpenWRT 23.05 или новее (с `apk`)
- ~30 МБ свободного места на `/`
- Подписка в формате mihomo/Clash Meta

## Что делает установщик

1. Определяет архитектуру роутера (`amd64` / `arm64` / `armv7` / `mipsle-softfloat` / `mips-softfloat`)
2. Устанавливает зависимости: `curl`, `kmod-nft-tproxy`
3. Скачивает актуальный бинарник mihomo с GitHub
4. Создаёт `/etc/mihomo/config.yaml` с готовыми rule-sets
5. Создаёт procd init-скрипт `/etc/init.d/mihomo` (START=99)
6. При старте поднимает nftables-таблицу `inet mihomo` и маршрутизацию tproxy
7. Устанавливает CLI-утилиту `/usr/bin/xwrt`
8. Включает автозапуск и запускает сервис

Весь трафик клиентов (TCP + UDP) перехватывается через tproxy на порт 7893. Приватные диапазоны и клиенты из `exclude.lst` идут напрямую.

## После установки

1. Откройте веб-интерфейс: `http://<IP роутера>:9090/ui`
2. В группе **"Заблок. сервисы"** выберите нужный прокси-сервер
3. Остальные группы (YouTube, Telegram, AI…) по умолчанию наследуют этот выбор

## Управление — xwrt

| Команда | Действие |
|---|---|
| `xwrt start` | Запустить |
| `xwrt stop` | Остановить |
| `xwrt restart` | Перезапустить |
| `xwrt status` | Статус процесса, nftables, маршрутизация |
| `xwrt log [N]` | Последние N строк лога (по умолчанию 30) |
| `xwrt watch` | Лог в реальном времени |
| `xwrt debug` | Включить подробный лог (уровень info) |
| `xwrt nodebug` | Вернуть лог на уровень warning |
| `xwrt update-sub` | Обновить прокси из подписки |
| `xwrt update-rules` | Обновить все rule-sets |
| `xwrt update-bin` | Обновить бинарник mihomo до последней версии |
| `xwrt version` | Версии mihomo и xwrt |

## Исключение клиентов

Файл `/etc/mihomo/exclude.lst` — список IP-адресов, которые обходят прокси и ходят напрямую. Формат: один адрес или CIDR на строку, `#` — комментарий.

```
# Телевизор и игровая консоль — без прокси
192.168.1.50
192.168.1.51

# Отдельный сегмент
192.168.2.0/24
```

После изменения файла выполните `xwrt restart`.

## Свои правила маршрутизации

В `config.yaml` есть секция `user@classical` (тип `inline`) — добавляйте сюда домены и IP, которые должны идти через группу **"Заблок. сервисы"**:

```yaml
  user@classical:
    type: inline
    behavior: classical
    payload:
      - DOMAIN-SUFFIX,example.com
      - DOMAIN-SUFFIX,2ip.io
      - IP-CIDR,1.2.3.4/32
```

После изменения конфига выполните `xwrt restart`.

## Уровни логирования

По умолчанию mihomo работает с `log-level: warning` — логи не пишутся постоянно, flash-память не изнашивается. Для диагностики:

```sh
xwrt debug   # переключить на info (через API, без перезапуска)
xwrt watch   # смотреть лог в реальном времени
xwrt nodebug # вернуть warning
```

## Поддерживаемые архитектуры

| Роутер / платформа | uname -m | mihomo |
|---|---|---|
| x86_64 (PC, VM) | `x86_64` | `amd64` |
| Xiaomi AX3600, RPi 4, большинство современных | `aarch64` | `arm64` |
| Старые ARM роутеры | `armv7l` | `armv7` |
| MIPS little-endian (MT7620, MT7621) | `mipsel` | `mipsle-softfloat` |
| MIPS big-endian (AR9xxx, QCA9xxx) | `mips` | `mips-softfloat` |

## Удаление

```sh
xwrt stop
/etc/init.d/mihomo disable
rm /usr/bin/mihomo /usr/bin/xwrt /etc/init.d/mihomo
rm -rf /etc/mihomo
```

Нftables-таблица и маршруты удаляются автоматически при `xwrt stop`.
