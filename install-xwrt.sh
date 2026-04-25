#!/bin/sh
# install-xwrt.sh — установщик mihomo + xwrt для OpenWRT

MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_CFG="/etc/mihomo"
INIT_SCRIPT="/etc/init.d/mihomo"
XWRT_BIN="/usr/bin/xwrt"
REPO="https://raw.githubusercontent.com/tuefalek/xwrt/main"

ok()   { printf '  \x1b[92m+\x1b[0m %s\n' "$1"; }
info() { printf '  \x1b[96m>\x1b[0m %s\n' "$1"; }
warn() { printf '  \x1b[93m!\x1b[0m %s\n' "$1"; }
err()  { printf '  \x1b[91mx\x1b[0m %s\n' "$1"; exit 1; }

printf '\n\x1b[96m%s\x1b[0m\n' "╔══════════════════════════════════════════╗"
printf     '\x1b[96m%s\x1b[0m\n' "║     xwrt installer — mihomo for OpenWRT  ║"
printf     '\x1b[96m%s\x1b[0m\n' "╚══════════════════════════════════════════╝"
printf '\n'

# ─── Архитектура ─────────────────────────────────────────────────────────────
RAW_ARCH=$(uname -m)
case "$RAW_ARCH" in
    x86_64)         ARCH="amd64" ;;
    aarch64)        ARCH="arm64" ;;
    armv7*|armv7l)  ARCH="armv7" ;;
    mipsel|mipsle)  ARCH="mipsle-softfloat" ;;
    mips)           ARCH="mips-softfloat" ;;
    *)              err "Неизвестная архитектура: $RAW_ARCH" ;;
esac

info "Архитектура: ${RAW_ARCH} -> mihomo-linux-${ARCH}"
printf '  \x1b[96m?\x1b[0m Верно? [Y/n]: '
read -r ARCH_OK < /dev/tty
case "$ARCH_OK" in
    n|N) err "Прервано. Укажите архитектуру вручную." ;;
esac

printf '\n'

# ─── Проверяем: уже установлен? ──────────────────────────────────────────────
MODE_INSTALL="install"
if [ -f "$MIHOMO_BIN" ]; then
    CURRENT_VER=$("$MIHOMO_BIN" -v 2>/dev/null | awk '{print $3}')
    warn "mihomo уже установлен (${CURRENT_VER})"
    printf '  \x1b[96m?\x1b[0m Переустановить? config.yaml будет сохранён как .bak [y/N]: '
    read -r REINSTALL < /dev/tty
    case "$REINSTALL" in
        y|Y) MODE_INSTALL="reinstall" ;;
        *)
            warn "Отменено. Для обновления: xwrt update-bin"
            exit 0
            ;;
    esac
fi

printf '\n'

# ─── LAN IP роутера ──────────────────────────────────────────────────────────
DETECTED_IP=$(uci get network.lan.ipaddr 2>/dev/null | cut -d'/' -f1)
[ -z "$DETECTED_IP" ] && DETECTED_IP="192.168.1.1"
printf '  \x1b[96m?\x1b[0m Адрес роутера [%s]: ' "$DETECTED_IP"
read -r LAN_IP < /dev/tty
[ -z "$LAN_IP" ] && LAN_IP="$DETECTED_IP"
ok "Адрес роутера: $LAN_IP"

printf '\n'

# ─── Ссылка на подписку ──────────────────────────────────────────────────────
EXISTING_SUB=$(cat "${MIHOMO_CFG}/sub.txt" 2>/dev/null)
if [ -n "$EXISTING_SUB" ] && [ "$MODE_INSTALL" = "reinstall" ]; then
    printf '  \x1b[96m?\x1b[0m Подписка [Enter = оставить текущую]: '
    read -r SUB_URL < /dev/tty
    [ -z "$SUB_URL" ] && SUB_URL="$EXISTING_SUB"
else
    printf '  \x1b[96m?\x1b[0m Ссылка на подписку mihomo: '
    read -r SUB_URL < /dev/tty
    [ -z "$SUB_URL" ] && err "Ссылка не может быть пустой"
fi

printf '\n'

# ─── Выбор режима ────────────────────────────────────────────────────────────
EXISTING_MODE=$(cat "${MIHOMO_CFG}/mode.txt" 2>/dev/null)
if [ -n "$EXISTING_MODE" ] && [ "$MODE_INSTALL" = "reinstall" ]; then
    printf '  \x1b[96m?\x1b[0m Режим [Enter = оставить текущий: %s]: ' "$EXISTING_MODE"
    read -r MODE_INPUT < /dev/tty
    [ -z "$MODE_INPUT" ] && MODE_INPUT="$EXISTING_MODE"
else
    printf '  \x1b[96m?\x1b[0m Режим работы:\n'
    printf '       1) vpn    -- весь трафик через VPN, кроме RU (рекомендуется)\n'
    printf '       2) direct -- только заблокированное через VPN\n'
    printf '  \x1b[96m?\x1b[0m Выбор [1/2]: '
    read -r MODE_INPUT < /dev/tty
    case "$MODE_INPUT" in
        2|direct) MODE_INPUT="direct" ;;
        *)        MODE_INPUT="vpn" ;;
    esac
fi

printf '\n'

# ─── Бэкап при переустановке ─────────────────────────────────────────────────
if [ "$MODE_INSTALL" = "reinstall" ]; then
    if [ -f "${MIHOMO_CFG}/config.yaml" ]; then
        cp "${MIHOMO_CFG}/config.yaml" "${MIHOMO_CFG}/config.yaml.bak"
        ok "Конфиг сохранён: config.yaml.bak"
    fi
    info "Останавливаем mihomo..."
    "$INIT_SCRIPT" stop 2>/dev/null || true
fi

# ─── Зависимости ─────────────────────────────────────────────────────────────
info "Устанавливаем зависимости..."
apk update -q 2>/dev/null && apk add -q curl kmod-nft-tproxy 2>/dev/null
ok "Зависимости установлены"

# ─── Скачиваем mihomo ────────────────────────────────────────────────────────
info "Определяем последнюю версию mihomo..."
LATEST=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
[ -z "$LATEST" ] && err "Не удалось получить версию mihomo"

info "Загружаем mihomo ${LATEST} (${ARCH})..."
URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST}/mihomo-linux-${ARCH}-${LATEST}.gz"
cd /tmp || exit 1
curl -sL "$URL" -o mihomo.gz || err "Ошибка загрузки mihomo"
gunzip -f mihomo.gz
mv /tmp/mihomo "$MIHOMO_BIN"
chmod +x "$MIHOMO_BIN"
ok "mihomo ${LATEST} установлен"

# ─── Директории ──────────────────────────────────────────────────────────────
mkdir -p "${MIHOMO_CFG}/proxy-providers" "${MIHOMO_CFG}/templates"

# ─── Скачиваем шаблоны ───────────────────────────────────────────────────────
info "Скачиваем шаблоны конфигов..."
curl -sL "${REPO}/templates/config-vpn.yaml" \
    -o "${MIHOMO_CFG}/templates/config-vpn.yaml" \
    || err "Ошибка загрузки config-vpn.yaml"
curl -sL "${REPO}/templates/config-direct.yaml" \
    -o "${MIHOMO_CFG}/templates/config-direct.yaml" \
    || err "Ошибка загрузки config-direct.yaml"
ok "Шаблоны установлены"

# ─── Сохраняем подписку и применяем шаблон ───────────────────────────────────
printf '%s\n' "$SUB_URL" > "${MIHOMO_CFG}/sub.txt"
printf '%s\n' "$MODE_INPUT" > "${MIHOMO_CFG}/mode.txt"

info "Генерируем config.yaml (режим: ${MODE_INPUT})..."
awk -v url="$SUB_URL" -v lan_ip="$LAN_IP" '
{
    n = split($0, parts, "__SUB_URL__")
    line = parts[1]
    for (i = 2; i <= n; i++) line = line url parts[i]
    n = split(line, parts, "__LAN_IP__")
    line = parts[1]
    for (i = 2; i <= n; i++) line = line lan_ip parts[i]
    print line
}' "${MIHOMO_CFG}/templates/config-${MODE_INPUT}.yaml" > "${MIHOMO_CFG}/config.yaml" \
    || err "Ошибка генерации config.yaml"
ok "config.yaml создан (режим: ${MODE_INPUT})"

# ─── exclude.lst ─────────────────────────────────────────────────────────────
if [ ! -f "${MIHOMO_CFG}/exclude.lst" ]; then
    cat > "${MIHOMO_CFG}/exclude.lst" << 'EOF'
# IP-адреса клиентов которые идут напрямую, минуя mihomo
# Один адрес или CIDR на строку, # — комментарий
# Пример:
# 192.168.1.100
# 192.168.1.50/32
EOF
    ok "exclude.lst создан"
fi

# ─── Скачиваем xwrt ──────────────────────────────────────────────────────────
info "Устанавливаем xwrt..."
curl -sL "${REPO}/xwrt.sh" -o "$XWRT_BIN" || err "Ошибка загрузки xwrt.sh"
chmod +x "$XWRT_BIN"
ok "xwrt установлен"

# ─── /etc/init.d/mihomo ──────────────────────────────────────────────────────
info "Создаём /etc/init.d/mihomo..."
cat > "$INIT_SCRIPT" << 'INITEOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=99
STOP=10

MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_CFG="/etc/mihomo"
EXCLUDE_LST="/etc/mihomo/exclude.lst"
FWMARK="0x162"
RT_TABLE="100"

_routing_up() {
    ip rule add fwmark "$FWMARK" table "$RT_TABLE" 2>/dev/null
    ip route add local 0.0.0.0/0 dev lo table "$RT_TABLE" 2>/dev/null
}

_routing_down() {
    ip rule del fwmark "$FWMARK" table "$RT_TABLE" 2>/dev/null
    ip route del local 0.0.0.0/0 dev lo table "$RT_TABLE" 2>/dev/null
}

_nft_up() {
    nft add table inet mihomo
    nft add chain inet mihomo prerouting \
        '{ type filter hook prerouting priority mangle; policy accept; }'

    # Защита от петли — трафик самого mihomo
    nft add rule inet mihomo prerouting meta mark "$FWMARK" return

    # DNS (порт 53) идёт через роутерный резолвер, не через mihomo
    nft add rule inet mihomo prerouting meta l4proto udp udp dport 53 return
    nft add rule inet mihomo prerouting meta l4proto tcp tcp dport 53 return

    # Клиенты из exclude.lst — напрямую
    local excludes
    excludes=$(grep -v '^\s*#' "$EXCLUDE_LST" 2>/dev/null \
        | grep -v '^\s*$' | tr -d ' ' | tr '\n' ',' \
        | sed 's/,$//' | sed 's/,/, /g')
    if [ -n "$excludes" ]; then
        nft add set inet mihomo bypass_src \
            '{ type ipv4_addr; flags interval; }'
        nft add element inet mihomo bypass_src "{ $excludes }"
        nft add rule inet mihomo prerouting ip saddr @bypass_src return
    fi

    # Приватные диапазоны — напрямую
    nft add rule inet mihomo prerouting \
        ip daddr '{ 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 }' return

    # Всё остальное → tproxy на mihomo
    nft add rule inet mihomo prerouting \
        meta l4proto '{ tcp, udp }' tproxy ip to :7893 meta mark set "$FWMARK"
}

_nft_down() {
    nft delete table inet mihomo 2>/dev/null
}

start_service() {
    _routing_up
    _nft_up
    procd_open_instance
    procd_set_param command "$MIHOMO_BIN" -d "$MIHOMO_CFG"
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    _nft_down
    _routing_down
}

reload_service() {
    stop
    start
}
INITEOF
chmod +x "$INIT_SCRIPT"
ok "Init script создан"

# ─── Автозапуск и старт ──────────────────────────────────────────────────────
info "Включаем автозапуск..."
"$INIT_SCRIPT" enable
info "Запускаем mihomo..."
"$INIT_SCRIPT" start
sleep 2

# ─── Итог ────────────────────────────────────────────────────────────────────
printf '\n\x1b[92m%s\x1b[0m\n' "╔══════════════════════════════════════════╗"
printf     '\x1b[92m%s\x1b[0m\n' "║           Установка завершена!           ║"
printf     '\x1b[92m%s\x1b[0m\n' "╚══════════════════════════════════════════╝"
printf '\n'
xwrt status
printf '\n'
ok "Режим:         ${MODE_INPUT}"
ok "Веб-интерфейс: http://${LAN_IP}:9090/ui"
ok "Управление:    xwrt help"
ok "Сменить режим: xwrt mode vpn|direct"
ok "Исключения:    ${MIHOMO_CFG}/exclude.lst"
printf '\n'
