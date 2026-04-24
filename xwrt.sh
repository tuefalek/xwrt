#!/bin/sh
# xwrt — mihomo manager for OpenWRT

MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_CFG="/etc/mihomo"
MIHOMO_API="http://127.0.0.1:9090"
INIT="/etc/init.d/mihomo"
TEMPLATES_DIR="/etc/mihomo/templates"
SUB_FILE="/etc/mihomo/sub.txt"
MODE_FILE="/etc/mihomo/mode.txt"
VERSION="1.1.0"

_help() {
    echo "xwrt $VERSION -- mihomo manager for OpenWRT"
    echo ""
    echo "  xwrt start            Запустить"
    echo "  xwrt stop             Остановить"
    echo "  xwrt restart          Перезапустить"
    echo "  xwrt status           Статус процесса, nftables, маршрутизация"
    echo "  xwrt log [N]          Последние N строк лога (default 30)"
    echo "  xwrt watch            Лог в реальном времени"
    echo "  xwrt debug            Включить подробный лог (в RAM)"
    echo "  xwrt nodebug          Выключить подробный лог"
    echo ""
    echo "  xwrt mode vpn         Режим: весь трафик через VPN, кроме RU"
    echo "  xwrt mode direct      Режим: только заблокированное через VPN"
    echo ""
    echo "  xwrt sub              Показать текущую ссылку на подписку"
    echo "  xwrt sub <url>        Обновить ссылку и перегенерировать конфиг"
    echo "  xwrt update-sub       Перезагрузить подписку через API (без рестарта)"
    echo "  xwrt update-rules     Обновить rule-sets через API"
    echo "  xwrt update-bin       Обновить бинарник mihomo"
    echo "  xwrt version          Версии"
}

_detect_arch() {
    case "$(uname -m)" in
        x86_64)         echo "amd64" ;;
        aarch64)        echo "arm64" ;;
        armv7*|armv7l)  echo "armv7" ;;
        mipsel|mipsle)  echo "mipsle-softfloat" ;;
        mips)           echo "mips-softfloat" ;;
        *)              echo "amd64" ;;
    esac
}

_start()   { echo "Starting...";   "$INIT" start   && echo "OK"; }
_stop()    { echo "Stopping...";   "$INIT" stop    && echo "OK"; }
_restart() { echo "Restarting..."; "$INIT" restart && echo "OK"; }

_status() {
    local pid
    pid=$(pgrep -f "mihomo -d" 2>/dev/null)
    if [ -n "$pid" ]; then
        local mode
        mode=$(cat "$MODE_FILE" 2>/dev/null || echo "unknown")
        echo "mihomo RUNNING (pid $pid, mode: $mode)"
        echo ""
        echo "--- nftables ---"
        nft list table inet mihomo 2>/dev/null | grep -v "^table" | head -15
        echo ""
        echo "--- routing ---"
        ip rule show | grep "0x162" || echo "(no fwmark rule)"
    else
        echo "mihomo STOPPED"
    fi
}

_log()   { logread | grep -i mihomo | tail -"${1:-30}"; }
_watch() { echo "Ctrl+C to stop..."; logread -f | grep -i mihomo; }

_debug_on() {
    local res
    res=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$MIHOMO_API/configs" \
        -H "Content-Type: application/json" -d '{"log-level":"info"}')
    [ "$res" = "204" ] && echo "Debug ON -- run: xwrt watch" || echo "Error (HTTP $res, is mihomo running?)"
}

_debug_off() {
    local res
    res=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$MIHOMO_API/configs" \
        -H "Content-Type: application/json" -d '{"log-level":"warning"}')
    [ "$res" = "204" ] && echo "Debug OFF" || echo "Error (HTTP $res)"
}

# Применить шаблон: подставить URL из sub.txt в __SUB_URL__
# Использует awk split — безопасно для URL со спецсимволами (& / \ etc)
_apply_template() {
    local template="$1"
    local output="$2"
    local url
    url=$(tr -d '\r\n' < "$SUB_FILE" 2>/dev/null)
    [ -z "$url" ] && { echo "Error: $SUB_FILE is empty"; return 1; }
    [ ! -f "$template" ] && { echo "Error: template not found: $template"; return 1; }

    awk -v url="$url" '
    {
        n = split($0, parts, "__SUB_URL__")
        line = parts[1]
        for (i = 2; i <= n; i++) line = line url parts[i]
        print line
    }' "$template" > "$output"
}

_mode() {
    local new_mode="$1"
    case "$new_mode" in
        vpn|direct) ;;
        *)
            echo "Usage: xwrt mode vpn|direct"
            echo "  vpn    -- весь трафик через VPN, кроме RU"
            echo "  direct -- только заблокированные сайты через VPN"
            return 1
            ;;
    esac

    local template="${TEMPLATES_DIR}/config-${new_mode}.yaml"
    echo "Switching to mode: $new_mode..."
    _apply_template "$template" "${MIHOMO_CFG}/config.yaml" || return 1
    printf '%s\n' "$new_mode" > "$MODE_FILE"
    ok "Config applied"
    _restart
}

_sub_cmd() {
    if [ -z "$1" ]; then
        local url
        url=$(cat "$SUB_FILE" 2>/dev/null)
        if [ -n "$url" ]; then
            echo "Current subscription: $url"
            echo "Mode: $(cat "$MODE_FILE" 2>/dev/null || echo 'unknown')"
        else
            echo "No subscription set. Run: xwrt sub <url>"
        fi
        return 0
    fi

    local new_url="$1"
    printf '%s\n' "$new_url" > "$SUB_FILE"
    echo "Saved subscription URL"

    local mode
    mode=$(cat "$MODE_FILE" 2>/dev/null)
    if [ -n "$mode" ]; then
        echo "Applying to current mode ($mode)..."
        _apply_template "${TEMPLATES_DIR}/config-${mode}.yaml" "${MIHOMO_CFG}/config.yaml" || return 1
        _restart
    else
        echo "No mode set. Run: xwrt mode vpn|direct"
    fi
}

_update_sub() {
    local res
    res=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "$MIHOMO_API/providers/proxies/proxy-sub")
    [ "$res" = "204" ] && echo "Subscription reloaded" || echo "Error (HTTP $res)"
}

_update_rules() {
    local res
    res=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$MIHOMO_API/providers/rules")
    echo "Rules reload triggered (HTTP $res)"
}

_update_bin() {
    local arch latest current url
    arch=$(_detect_arch)
    latest=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    current=$("$MIHOMO_BIN" -v 2>/dev/null | awk '{print $3}')
    echo "Current: $current  Latest: $latest"
    [ "$latest" = "$current" ] && { echo "Already up to date."; return 0; }
    "$INIT" stop 2>/dev/null
    cd /tmp || return 1
    url="https://github.com/MetaCubeX/mihomo/releases/download/${latest}/mihomo-linux-${arch}-${latest}.gz"
    if curl -sL "$url" -o mihomo.gz && gunzip -f mihomo.gz; then
        mv /tmp/mihomo "$MIHOMO_BIN"
        chmod +x "$MIHOMO_BIN"
        echo "Updated to $latest"
        "$INIT" start
    else
        echo "Download failed"
        "$INIT" start
    fi
}

_version() {
    local arch
    arch=$(_detect_arch)
    echo "mihomo: $("$MIHOMO_BIN" -v 2>/dev/null | awk '{print $3, $4, $5}')"
    echo "xwrt:   $VERSION (arch: $arch)"
    echo "mode:   $(cat "$MODE_FILE" 2>/dev/null || echo 'not set')"
}

# совместимость: ok() на случай если вызван из installer-контекста
ok() { echo "  $1"; }

case "$1" in
    start)        _start ;;
    stop)         _stop ;;
    restart)      _restart ;;
    status)       _status ;;
    log)          _log "$2" ;;
    watch)        _watch ;;
    debug)        _debug_on ;;
    nodebug)      _debug_off ;;
    mode)         _mode "$2" ;;
    sub)          _sub_cmd "$2" ;;
    update-sub)   _update_sub ;;
    update-rules) _update_rules ;;
    update-bin)   _update_bin ;;
    version)      _version ;;
    *)            _help ;;
esac
