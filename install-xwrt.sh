#!/bin/sh
# install-xwrt.sh — установщик mihomo + xwrt для OpenWRT

MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_CFG="/etc/mihomo"
INIT_SCRIPT="/etc/init.d/mihomo"
XWRT_BIN="/usr/bin/xwrt"
XWRT_VERSION="1.0.0"
CTRL_PORT="9090"

R='\033[91m'; G='\033[92m'; Y='\033[93m'; B='\033[96m'; N='\033[0m'
ok()   { echo "${G}  ✓ $1${N}"; }
info() { echo "${B}  → $1${N}"; }
warn() { echo "${Y}  ! $1${N}"; }
err()  { echo "${R}  ✗ $1${N}"; exit 1; }

echo ""
echo "${B}╔══════════════════════════════════════════╗"
echo "║     xwrt installer — mihomo for OpenWRT  ║"
echo "╚══════════════════════════════════════════╝${N}"
echo ""

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

info "Архитектура: ${RAW_ARCH} → mihomo-linux-${ARCH}"
printf "${B}  ? Верно? [Y/n]: ${N}"
read -r ARCH_OK
case "$ARCH_OK" in
    n|N) err "Прервано. Укажите архитектуру вручную." ;;
esac

echo ""

# ─── Уже установлен? ─────────────────────────────────────────────────────────
MODE="install"
if [ -f "$MIHOMO_BIN" ]; then
    CURRENT_VER=$("$MIHOMO_BIN" -v 2>/dev/null | awk '{print $3}')
    warn "mihomo уже установлен (${CURRENT_VER})"
    printf "${B}  ? Переустановить? Конфиг будет сохранён в config.yaml.bak [y/N]: ${N}"
    read -r REINSTALL
    case "$REINSTALL" in
        y|Y) MODE="reinstall" ;;
        *)
            warn "Установка отменена. Для обновления бинаря: xwrt update-bin"
            exit 0
            ;;
    esac
fi

echo ""

# ─── Подписка ────────────────────────────────────────────────────────────────
printf "${B}  ? Ссылка на подписку mihomo: ${N}"
read -r SUB_URL
[ -z "$SUB_URL" ] && err "Ссылка не может быть пустой"

echo ""

# ─── Бэкап конфига при переустановке ────────────────────────────────────────
if [ "$MODE" = "reinstall" ]; then
    if [ -f "${MIHOMO_CFG}/config.yaml" ]; then
        cp "${MIHOMO_CFG}/config.yaml" "${MIHOMO_CFG}/config.yaml.bak"
        ok "Конфиг сохранён: ${MIHOMO_CFG}/config.yaml.bak"
    fi
    info "Останавливаем текущий mihomo..."
    "$INIT_SCRIPT" stop 2>/dev/null || true
fi

# ─── Зависимости ────────────────────────────────────────────────────────────
info "Устанавливаем зависимости..."
apk update -q 2>/dev/null && apk add -q curl kmod-nft-tproxy 2>/dev/null
ok "Зависимости установлены"

# ─── Скачиваем михомо ────────────────────────────────────────────────────────
info "Определяем последнюю версию mihomo..."
LATEST=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
[ -z "$LATEST" ] && err "Не удалось получить версию"

info "Загружаем mihomo ${LATEST}..."
URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST}/mihomo-linux-${ARCH}-${LATEST}.gz"
cd /tmp || exit 1
curl -L "$URL" -o mihomo.gz || err "Ошибка загрузки"
gunzip -f mihomo.gz
mv /tmp/mihomo "$MIHOMO_BIN"
chmod +x "$MIHOMO_BIN"
ok "mihomo ${LATEST} установлен"

# ─── Конфиг ─────────────────────────────────────────────────────────────────
mkdir -p "${MIHOMO_CFG}/proxy-providers"

info "Создаём config.yaml..."
cat > "${MIHOMO_CFG}/config.yaml" << YAML
log-level: warning
allow-lan: true
redir-port: 7892
tproxy-port: 7893
mixed-port: 7890
find-process-mode: off
unified-delay: true
external-controller: 0.0.0.0:${CTRL_PORT}
external-ui: ${MIHOMO_CFG}/ui
external-ui-url: https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip
profile: { store-selected: true }

dns:
  enable: true
  listen: 0.0.0.0:7874
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/16
  nameserver:
    - 8.8.8.8
    - 1.1.1.1

sniffer:
  enable: true
  sniff:
    HTTP: { ports: [80, 8080] }
    TLS: { ports: [443, 8443] }
  skip-dst-address: [rule-set:telegram@ipcidr]

anchors:
  a1: &domain    { type: http, format: mrs,  behavior: domain,   interval: 86400 }
  a2: &ipcidr    { type: http, format: mrs,  behavior: ipcidr,   interval: 86400 }
  a3: &classical { type: http, format: text, behavior: classical, interval: 86400 }
  a4: &inline    { type: inline, behavior: classical }

proxy-providers:
  proxy-sub:
    type: http
    url: "${SUB_URL}"
    path: ${MIHOMO_CFG}/proxy-providers/proxy-sub.yml
    interval: 3600
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 300
      timeout: 2000
      lazy: false
      expected-status: 204
    override:
      udp: true
      tfo: true

proxy-groups:
  - { name: "Заблок. сервисы", type: select, include-all: true }
  - { name: "YouTube",  type: select, include-all: true, proxies: [Заблок. сервисы, DIRECT] }
  - { name: "Discord",  type: select, include-all: true, proxies: [Заблок. сервисы, DIRECT] }
  - { name: "Twitch",   type: select, include-all: true, proxies: [DIRECT, Заблок. сервисы] }
  - { name: "Reddit",   type: select, include-all: true, proxies: [DIRECT, Заблок. сервисы] }
  - { name: "Meta",     type: select, include-all: true, proxies: [Заблок. сервисы, DIRECT] }
  - { name: "Spotify",  type: select, include-all: true, exclude-filter: "🇷🇺", proxies: [Заблок. сервисы, DIRECT] }
  - { name: "Speedtest",type: select, include-all: true, proxies: [Заблок. сервисы, DIRECT] }
  - { name: "Telegram", type: select, include-all: true, proxies: [Заблок. сервисы, DIRECT] }
  - { name: "Steam",    type: select, include-all: true, proxies: [DIRECT, Заблок. сервисы] }
  - { name: "CDN",      type: select, include-all: true, proxies: [Заблок. сервисы, PASS] }
  - { name: "Google",   type: select, include-all: true, proxies: [PASS, Заблок. сервисы] }
  - { name: "GitHub",   type: select, include-all: true, proxies: [PASS, Заблок. сервисы] }
  - { name: "AI",       type: select, include-all: true, exclude-filter: "🇷🇺", proxies: [Заблок. сервисы] }
  - { name: "Twitter",  type: select, include-all: true, proxies: [Заблок. сервисы, DIRECT] }

rule-providers:
  adlist@domain:       { <<: *domain,    url: https://github.com/zxc-rv/ad-filter/releases/latest/download/adlist.mrs }
  akamai@domain:       { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/akamai.mrs }
  akamai@ipcidr:       { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/akamai@ipcidr.mrs }
  amazon@domain:       { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/amazon.mrs }
  amazon@ipcidr:       { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/amazon@ipcidr.mrs }
  category-ai@domain:  { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ai-!cn.mrs }
  cdn77@ipcidr:        { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/cdn77@ipcidr.mrs }
  category-ru@domain:  { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ru.mrs }
  cloudflare@domain:   { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/cloudflare.mrs }
  cloudflare@ipcidr:   { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/cloudflare@ipcidr.mrs }
  digitalocean@domain: { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/digitalocean.mrs }
  digitalocean@ipcidr: { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/digitalocean@ipcidr.mrs }
  discord@classical:   { <<: *classical, url: https://github.com/zxc-rv/assets/raw/main/rules/discord.list }
  fastly@domain:       { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/fastly.mrs }
  fastly@ipcidr:       { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/fastly@ipcidr.mrs }
  gcore@ipcidr:        { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/gcore@ipcidr.mrs }
  github@domain:       { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github.mrs }
  google@domain:       { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/google.mrs }
  google@ipcidr:       { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/google@ipcidr.mrs }
  hetzner@domain:      { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/hetzner.mrs }
  hetzner@ipcidr:      { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/hetzner@ipcidr.mrs }
  meta@domain:         { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/meta.mrs }
  meta@ipcidr:         { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/meta@ipcidr.mrs }
  oracle@domain:       { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/oracle.mrs }
  oracle@ipcidr:       { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/oracle@ipcidr.mrs }
  ovh@ipcidr:          { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/ovh@ipcidr.mrs }
  reddit@domain:       { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/reddit.mrs }
  refilter@domain:     { <<: *domain,    url: https://github.com/legiz-ru/mihomo-rule-sets/raw/main/re-filter/domain-rule.mrs }
  scaleway@ipcidr:     { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/scaleway@ipcidr.mrs }
  spotify@domain:      { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/spotify.mrs }
  steam@domain:        { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/steam.mrs }
  speedtest@domain:    { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/speedtest.mrs }
  telegram@domain:     { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/telegram.mrs }
  telegram@ipcidr:     { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/telegram@ipcidr.mrs }
  twitch@domain:       { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/twitch.mrs }
  twitter@domain:      { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/twitter.mrs }
  vodafone@ipcidr:     { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/vodafone@ipcidr.mrs }
  vultr@ipcidr:        { <<: *ipcidr,    url: https://github.com/zxc-rv/zkeenip-rulesets/releases/latest/download/vultr@ipcidr.mrs }
  youtube@domain:      { <<: *domain,    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/youtube.mrs }
  quic@inline:         { <<: *inline,    payload: ['AND,((DST-PORT,443),(NETWORK,UDP))'] }
  user@classical:
    type: inline
    behavior: classical
    payload:
      - DOMAIN-SUFFIX,2ip.io

rules:
  - RULE-SET,adlist@domain,REJECT
  - RULE-SET,quic@inline,REJECT-DROP
  - OR,((DOMAIN-SUFFIX,gql.twitch.tv),(DOMAIN-SUFFIX,usher.ttvnw.net)),Заблок. сервисы
  - RULE-SET,category-ai@domain,AI
  - RULE-SET,steam@domain,Steam
  - RULE-SET,spotify@domain,Spotify
  - RULE-SET,reddit@domain,Reddit
  - RULE-SET,youtube@domain,YouTube
  - RULE-SET,twitch@domain,Twitch
  - RULE-SET,twitter@domain,Twitter
  - RULE-SET,discord@classical,Discord
  - RULE-SET,speedtest@domain,Speedtest
  - OR,((RULE-SET,meta@domain),(RULE-SET,meta@ipcidr,no-resolve)),Meta
  - OR,((RULE-SET,telegram@domain),(RULE-SET,telegram@ipcidr,no-resolve)),Telegram
  - OR,((RULE-SET,refilter@domain),(RULE-SET,user@classical)),Заблок. сервисы
  - RULE-SET,github@domain,GitHub
  - OR,((RULE-SET,google@domain),(RULE-SET,google@ipcidr)),Google
  - RULE-SET,category-ru@domain,DIRECT
  - OR,((RULE-SET,amazon@domain),(RULE-SET,amazon@ipcidr)),CDN
  - OR,((RULE-SET,akamai@domain),(RULE-SET,akamai@ipcidr)),CDN
  - OR,((RULE-SET,cloudflare@domain),(RULE-SET,cloudflare@ipcidr)),CDN
  - OR,((RULE-SET,digitalocean@domain),(RULE-SET,digitalocean@ipcidr)),CDN
  - OR,((RULE-SET,fastly@domain),(RULE-SET,fastly@ipcidr)),CDN
  - OR,((RULE-SET,oracle@domain),(RULE-SET,oracle@ipcidr)),CDN
  - OR,((RULE-SET,hetzner@domain),(RULE-SET,hetzner@ipcidr)),CDN
  - RULE-SET,scaleway@ipcidr,CDN
  - RULE-SET,ovh@ipcidr,CDN
  - RULE-SET,vultr@ipcidr,CDN
  - RULE-SET,vodafone@ipcidr,CDN
  - RULE-SET,gcore@ipcidr,CDN
  - RULE-SET,cdn77@ipcidr,CDN
  - MATCH,DIRECT
YAML
ok "config.yaml создан"

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

# ─── Init script ─────────────────────────────────────────────────────────────
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
    nft add rule inet mihomo prerouting meta mark "$FWMARK" return

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

    nft add rule inet mihomo prerouting \
        ip daddr '{ 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 }' return
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

# ─── xwrt ────────────────────────────────────────────────────────────────────
info "Устанавливаем xwrt..."
cat > "$XWRT_BIN" << XWRTEOF
#!/bin/sh
MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_CFG="/etc/mihomo"
MIHOMO_API="http://127.0.0.1:${CTRL_PORT}"
INIT="/etc/init.d/mihomo"
ARCH="${ARCH}"
VERSION="${XWRT_VERSION}"

_help() {
    echo "xwrt \$VERSION — mihomo manager for OpenWRT"
    echo ""
    echo "  xwrt start          Запустить"
    echo "  xwrt stop           Остановить"
    echo "  xwrt restart        Перезапустить"
    echo "  xwrt status         Статус"
    echo "  xwrt log [N]        Последние N логов (default 30)"
    echo "  xwrt watch          Следить за логом в реальном времени"
    echo "  xwrt debug          Включить подробный лог (в RAM)"
    echo "  xwrt nodebug        Выключить подробный лог"
    echo "  xwrt update-sub     Обновить подписку"
    echo "  xwrt update-rules   Обновить rule-sets"
    echo "  xwrt update-bin     Обновить бинарник михомо"
    echo "  xwrt version        Версии"
}

_start()   { echo "Starting...";   "\$INIT" start   && echo "OK"; }
_stop()    { echo "Stopping...";   "\$INIT" stop    && echo "OK"; }
_restart() { echo "Restarting..."; "\$INIT" restart && echo "OK"; }

_status() {
    local pid
    pid=\$(pgrep -f "mihomo -d" 2>/dev/null)
    if [ -n "\$pid" ]; then
        echo "● mihomo RUNNING (pid \$pid)"
        echo ""
        echo "--- nftables ---"
        nft list table inet mihomo 2>/dev/null | grep -v "^table" | head -15
        echo ""
        echo "--- routing ---"
        ip rule show | grep "0x162" || echo "(no fwmark rule)"
    else
        echo "○ mihomo STOPPED"
    fi
}

_log()   { logread | grep -i mihomo | tail -"\${1:-30}"; }
_watch() { echo "Ctrl+C to stop..."; logread -f | grep -i mihomo; }

_debug_on() {
    local res
    res=\$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "\$MIHOMO_API/configs" \
        -H "Content-Type: application/json" -d '{"log-level":"info"}')
    [ "\$res" = "204" ] && echo "Debug ON — run: xwrt watch" || echo "Error (HTTP \$res)"
}

_debug_off() {
    local res
    res=\$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "\$MIHOMO_API/configs" \
        -H "Content-Type: application/json" -d '{"log-level":"warning"}')
    [ "\$res" = "204" ] && echo "Debug OFF" || echo "Error (HTTP \$res)"
}

_update_sub() {
    local res
    res=\$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "\$MIHOMO_API/providers/proxies/proxy-sub")
    [ "\$res" = "204" ] && echo "Subscription updated" || echo "Error (HTTP \$res)"
}

_update_rules() {
    local res
    res=\$(curl -s -o /dev/null -w "%{http_code}" -X PUT "\$MIHOMO_API/providers/rules")
    echo "Rules update triggered (HTTP \$res)"
}

_update_bin() {
    local latest current
    latest=\$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    current=\$("\$MIHOMO_BIN" -v 2>/dev/null | awk '{print \$3}')
    echo "Current: \$current  Latest: \$latest"
    [ "\$latest" = "\$current" ] && { echo "Already up to date."; return 0; }
    "\$INIT" stop 2>/dev/null
    cd /tmp || return 1
    local url="https://github.com/MetaCubeX/mihomo/releases/download/\${latest}/mihomo-linux-\${ARCH}-\${latest}.gz"
    if curl -L "\$url" -o mihomo.gz && gunzip -f mihomo.gz; then
        mv /tmp/mihomo "\$MIHOMO_BIN"
        chmod +x "\$MIHOMO_BIN"
        echo "Updated to \$latest"
        "\$INIT" start
    else
        echo "Download failed"
        "\$INIT" start
    fi
}

_version() {
    echo "mihomo: \$(\$MIHOMO_BIN -v 2>/dev/null | awk '{print \$3, \$4, \$5}')"
    echo "xwrt:   \$VERSION"
}

case "\$1" in
    start)        _start ;;
    stop)         _stop ;;
    restart)      _restart ;;
    status)       _status ;;
    log)          _log "\$2" ;;
    watch)        _watch ;;
    debug)        _debug_on ;;
    nodebug)      _debug_off ;;
    update-sub)   _update_sub ;;
    update-rules) _update_rules ;;
    update-bin)   _update_bin ;;
    version)      _version ;;
    *)            _help ;;
esac
XWRTEOF
chmod +x "$XWRT_BIN"
ok "xwrt установлен"

# ─── Автозапуск и старт ──────────────────────────────────────────────────────
info "Включаем автозапуск..."
"$INIT_SCRIPT" enable
info "Запускаем mihomo..."
"$INIT_SCRIPT" start
sleep 2

# ─── Итог ────────────────────────────────────────────────────────────────────
LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
echo ""
echo "${G}╔══════════════════════════════════════════╗"
echo "║           Установка завершена!           ║"
echo "╚══════════════════════════════════════════╝${N}"
echo ""
xwrt status
echo ""
ok "Веб-интерфейс: http://${LAN_IP}:${CTRL_PORT}/ui"
ok "Управление:    xwrt help"
ok "Исключения:    ${MIHOMO_CFG}/exclude.lst"
echo ""
