# xwrt — прозрачный прокси для OpenWRT на базе mihomo

Устанавливает [mihomo](https://github.com/MetaCubeX/mihomo) (Clash Meta) на роутер OpenWRT с прозрачным проксированием через tproxy + nftables. Трафик идёт через прокси автоматически — без настройки браузеров или устройств.

Протестировано на **OpenWRT 25.12 / Xiaomi AX3600 (aarch64)**.

## Установка

```sh
curl -sL https://raw.githubusercontent.com/tuefalek/xwrt/main/install-xwrt.sh | sh
```

Или скачать файлом (надёжнее при нестабильном соединении):

```sh
curl -sL https://raw.githubusercontent.com/tuefalek/xwrt/main/install-xwrt.sh -o /tmp/install-xwrt.sh
sh /tmp/install-xwrt.sh
```

Скрипт задаст три вопроса: подтверждение архитектуры, ссылка на подписку, режим работы.

### Требования

- OpenWRT 23.05+ с `apk` (или `opkg` для более старых версий)
- ~35 МБ свободного места
- Подписка в формате mihomo / Clash Meta

## Режимы работы

| Режим | Описание |
|---|---|
| `vpn` | Весь трафик через VPN, кроме российских сайтов (`category-ru`) |
| `direct` | Только заблокированные сайты через VPN, остальное — напрямую |

Переключение в любой момент без переустановки:

```sh
xwrt mode vpn
xwrt mode direct
```

## После установки

1. Откройте веб-интерфейс: `http://<IP роутера>:9090/ui`
2. В режиме **vpn** — выберите прокси в группе **"Заблок. сервисы"**
3. В режиме **direct** — выберите прокси в группе **"PROXY"**

## Управление — xwrt

| Команда | Действие |
|---|---|
| `xwrt start` | Запустить |
| `xwrt stop` | Остановить |
| `xwrt restart` | Перезапустить |
| `xwrt status` | Статус: процесс, nftables, маршрутизация, текущий режим |
| `xwrt log [N]` | Последние N строк лога (default 30) |
| `xwrt watch` | Лог в реальном времени |
| `xwrt debug` | Включить подробный лог info (в RAM, без перезапуска) |
| `xwrt nodebug` | Вернуть лог на уровень warning |
| `xwrt mode vpn` | Переключиться в режим VPN |
| `xwrt mode direct` | Переключиться в режим Direct |
| `xwrt sub` | Показать текущую ссылку на подписку |
| `xwrt sub <url>` | Обновить подписку и перегенерировать конфиг |
| `xwrt update-sub` | Перезагрузить подписку через API (без рестарта) |
| `xwrt update-rules` | Обновить все rule-sets |
| `xwrt update-bin` | Обновить бинарник mihomo до последней версии |
| `xwrt version` | Версии mihomo и xwrt |

## Исключение клиентов

Файл `/etc/mihomo/exclude.lst` — IP-адреса клиентов, которые обходят прокси. Формат: один адрес или CIDR на строку, `#` — комментарий.

```
# Телевизор, игровая консоль — без прокси
192.168.1.50
192.168.1.51

# Отдельный сегмент
192.168.2.0/24
```

После изменения: `xwrt restart`.

## Свои правила маршрутизации

В каждом шаблоне есть секция `user@classical` — добавляйте домены/IP для принудительного проксирования:

```yaml
  user@classical:
    type: inline
    behavior: classical
    payload:
      - DOMAIN-SUFFIX,example.com
      - IP-CIDR,1.2.3.4/32,no-resolve
```

Файлы шаблонов: `/etc/mihomo/templates/config-vpn.yaml` и `config-direct.yaml`.  
После правки шаблона: `xwrt mode vpn` (или `direct`) — пересоздаст конфиг из обновлённого шаблона.

> **Внимание:** `xwrt mode ...` перегенерирует `config.yaml` из шаблона. Если вы редактировали `config.yaml` напрямую — изменения будут потеряны. Редактируйте только шаблоны.

## Уровни логирования

По умолчанию `log-level: warning` — на флеш почти ничего не пишется.

```sh
xwrt debug   # включить info-лог (через API, без перезапуска, всё в RAM)
xwrt watch   # смотреть поток в реальном времени
xwrt nodebug # вернуть warning
```

## Совместимость с zapret

[zapret](https://github.com/bol-van/zapret) и xwrt работают одновременно без конфликтов:

- **mihomo** (приоритет mangle, до routing decision) перехватывает трафик в PREROUTING и направляет его через VPN-туннель или помечает как DIRECT
- **zapret** работает в цепочках FORWARD/OUTPUT (приоритет filter, после mangle) и применяет DPI-обход к DIRECT-трафику, который mihomo не взял в туннель

Порядок обработки пакета:
```
клиент → PREROUTING (mihomo tproxy) → [VPN туннель]
                                    ↘ FORWARD → zapret DPI-обход → интернет
```

**Рекомендация:** если VPN-сервер использует порт 443 и zapret перехватывает весь TCP/443 в OUTPUT — добавьте IP VPN-серверов в исключения zapret (`/etc/zapret/config`), чтобы zapret не трогал шифрованный туннель mihomo.

DNS (порт 53) явно исключён из tproxy — роутерный резолвер работает как обычно.

## Поддерживаемые архитектуры

| Платформа | `uname -m` | mihomo бинарь |
|---|---|---|
| x86_64 (PC, VM, x86 роутер) | `x86_64` | `amd64` |
| Qualcomm IPQ8071A, AArch64 | `aarch64` | `arm64` |
| Xiaomi AX3600, RPi 4 и др. | `aarch64` | `arm64` |
| Старые ARM (Cortex-A7/A9) | `armv7l` | `armv7` |
| MIPS little-endian (MT7620, MT7621) | `mipsel` | `mipsle-softfloat` |
| MIPS big-endian (AR9xxx, QCA9xxx) | `mips` | `mips-softfloat` |

## Технические детали

**TProxy + nftables:**
- Таблица `inet mihomo`, цепочка `prerouting` (priority mangle)
- tproxy порт 7893, fwmark `0x162`
- ip rule: `fwmark 0x162 → table 100`; ip route table 100: `local default via lo`
- Порт 53 (DNS) явно исключён → роутерный резолвер не затронут
- Приватные диапазоны всегда обходят mihomo

**Запись на флеш:** только при обновлении подписки (~раз в час) и rule-sets (~раз в сутки). Постоянной записи логов нет.

## Структура файлов на роутере

```
/usr/bin/mihomo                       ← бинарник
/usr/bin/xwrt                         ← CLI менеджер
/etc/init.d/mihomo                    ← procd init script
/etc/mihomo/
  config.yaml                         ← активный конфиг (генерируется из шаблона)
  sub.txt                             ← ссылка на подписку
  mode.txt                            ← текущий режим (vpn/direct)
  exclude.lst                         ← IP-адреса клиентов-исключений
  templates/
    config-vpn.yaml                   ← шаблон режима VPN
    config-direct.yaml                ← шаблон режима Direct
  proxy-providers/proxy-sub.yml       ← кешированная подписка
  ui/                                 ← веб-интерфейс zashboard
```

## Удаление

```sh
xwrt stop
/etc/init.d/mihomo disable
rm /usr/bin/mihomo /usr/bin/xwrt /etc/init.d/mihomo
rm -rf /etc/mihomo
```

nftables-таблица и ip rule удаляются автоматически при `xwrt stop`.

---

## Thanks

- [zxc-rv/assets](https://github.com/zxc-rv/assets) — шаблоны конфигов mihomo и rule-sets для РФ
- [jameszeroX/XKeen](https://github.com/jameszeroX/XKeen) — вдохновение и архитектурные идеи
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) — ядро прокси
