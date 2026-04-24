# xwrt — прозрачный прокси для OpenWRT на базе mihomo

Устанавливает [mihomo](https://github.com/MetaCubeX/mihomo) (Clash Meta) на роутер OpenWRT с прозрачным проксированием всех клиентов через tproxy + nftables. Весь трафик идёт через прокси автоматически — без настройки браузеров или устройств.

Протестировано на **OpenWRT 25.12 / Xiaomi AX3600 (aarch64)**.

## Установка

```sh
curl -L https://raw.githubusercontent.com/tuefalek/xwrt/main/install-xwrt.sh | sh
```

Или скачать и запустить файлом (рекомендуется — работает надёжнее через pipe):

```sh
curl -L https://raw.githubusercontent.com/tuefalek/xwrt/main/install-xwrt.sh -o /tmp/install-xwrt.sh
sh /tmp/install-xwrt.sh
```

Скрипт задаст два вопроса: подтверждение архитектуры и ссылка на подписку.

### Требования

- OpenWRT 23.05+ (`apk`) или старше (`opkg`)
- ~30 МБ свободного места
- Подписка в формате mihomo / Clash Meta

## Что делает установщик

1. Определяет архитектуру роутера (`amd64` / `arm64` / `armv7` / `mipsle-softfloat` / `mips-softfloat`)
2. Устанавливает зависимости: `curl`, `kmod-nft-tproxy`
3. Скачивает актуальный бинарник mihomo с GitHub
4. Создаёт `/etc/mihomo/config.yaml` с готовыми rule-sets для РФ
5. Создаёт procd init-скрипт `/etc/init.d/mihomo` (START=99, автозапуск)
6. При старте поднимает nftables-таблицу `inet mihomo` и ip rule для tproxy
7. Устанавливает CLI-утилиту `/usr/bin/xwrt`

Весь трафик клиентов (TCP + UDP) перехватывается через tproxy на порт 7893. Приватные диапазоны и адреса из `exclude.lst` идут напрямую.

## После установки

1. Откройте веб-интерфейс: `http://<IP роутера>:9090/ui`
2. В группе **"Blocked"** выберите нужный прокси-сервер
3. Остальные группы (YouTube, Telegram, AI…) используют этот же выбор по умолчанию

## Управление — xwrt

| Команда | Действие |
|---|---|
| `xwrt start` | Запустить |
| `xwrt stop` | Остановить |
| `xwrt restart` | Перезапустить |
| `xwrt status` | Статус процесса, nftables, маршрутизация |
| `xwrt log [N]` | Последние N строк лога (default 30) |
| `xwrt watch` | Лог в реальном времени (Ctrl+C для выхода) |
| `xwrt debug` | Включить подробный лог уровня info (в RAM, не на флеш) |
| `xwrt nodebug` | Вернуть лог на уровень warning |
| `xwrt update-sub` | Обновить прокси из подписки |
| `xwrt update-rules` | Обновить все rule-sets |
| `xwrt update-bin` | Обновить бинарник mihomo до последней версии |
| `xwrt version` | Версии mihomo и xwrt |

## Исключение клиентов

Файл `/etc/mihomo/exclude.lst` — список IP-адресов и CIDR, которые обходят прокси и ходят напрямую. Формат: один адрес на строку, `#` — комментарий.

```
# Телевизор и игровая консоль — без прокси
192.168.1.50
192.168.1.51

# Отдельный сегмент
192.168.2.0/24
```

После изменения файла: `xwrt restart`.

## Свои правила маршрутизации

В `config.yaml` секция `user@classical` — добавляйте домены и IP, которые должны идти через прокси:

```yaml
  user@classical:
    type: inline
    behavior: classical
    payload:
      - DOMAIN-SUFFIX,example.com
      - DOMAIN-SUFFIX,2ip.io
      - IP-CIDR,1.2.3.4/32,no-resolve
```

После изменения конфига: `xwrt restart`.

## Уровни логирования

По умолчанию `log-level: warning` — логи почти не пишутся, flash-память не изнашивается. Для диагностики:

```sh
xwrt debug   # переключить на info (через API, без перезапуска, в RAM)
xwrt watch   # смотреть поток логов в реальном времени
xwrt nodebug # вернуть warning
```

## Поддерживаемые архитектуры

| Платформа | `uname -m` | mihomo бинарь |
|---|---|---|
| x86_64 (PC, VM, x86 роутер) | `x86_64` | `amd64` |
| Qualcomm IPQ8071A, RPi 4, AArch64 | `aarch64` | `arm64` |
| Xiaomi AX3600, большинство современных | `aarch64` | `arm64` |
| Старые ARM (Cortex-A7/A9) | `armv7l` | `armv7` |
| MIPS little-endian (MT7620, MT7621) | `mipsel` | `mipsle-softfloat` |
| MIPS big-endian (AR9xxx, QCA9xxx) | `mips` | `mips-softfloat` |

## Технические детали

**TProxy + nftables:**
- nftables таблица `inet mihomo`, цепочка `prerouting` (priority mangle)
- tproxy на порт 7893, fwmark `0x162`
- ip rule: `fwmark 0x162 → table 100`; ip route table 100: `local default via lo`
- защита от петли через fwmark check

**DNS:** mihomo слушает на 0.0.0.0:7874 в режиме fake-ip (198.18.0.0/16). DNS роутера не трогается.

**Запись на флеш:** только при обновлении подписки (~раз в час) и rule-sets (~раз в сутки). Постоянной записи нет.

## Удаление

```sh
xwrt stop
/etc/init.d/mihomo disable
rm /usr/bin/mihomo /usr/bin/xwrt /etc/init.d/mihomo
rm -rf /etc/mihomo
```

nftables-таблица и ip rule удаляются автоматически при `xwrt stop`.
