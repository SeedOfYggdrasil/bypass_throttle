#!#/bin/bash
#
# bypass_throttle_server.sh
# ver. 1.0
#
#----START----

SSH_PORT=8022
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEygw1nByVqsEF+T6sbAsSBJgEk1itWy6WvNJvXlRJq8"
APP_DIR="$HOME/.bypass"
SETUP_FILE="$APP_DIR/setup_complete"

install_package() {
    local package_name="$1"
    printf ' Installing %s...' "$package_name..."
    if pkg install -y "$package_name" &> /dev/null; then
        printf '\r  Installing %s...DONE\n' "$package_name"
    else
        printf '\r  Installing %s...FAIL\n' "$package_name"
    fi
}

initial_setup() {
    printf "Installing required packages..."

    pkg update -y &> /dev/null

    install_package "openssh"
    install_package "net-tools"
    install_package "termux-api"

    printf "\rInstalling required packages...DONE\n"

    SSH_DIR="$HOME/.ssh"
    printf "Performing initial setup..."
    
    [ ! -d "$APP_DIR" ] && mkdir -p "$APP_DIR"
    local BACKUP_DIR="$APP_DIR/.backups"
    [ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR"

    if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi

    local auth_keys="$SSH_DIR/authorized_keys"
    [ -f "$auth_keys" ] && cp "$auth_keys" "$BACKUP_DIR/authorized_keys.backup"

    local auth_a=$(cat "$auth_keys")
    local auth_b=$(cat "$auth_keys" | grep "$PUBKEY")

    if [ -n "$auth_a" ] && [ ! -n "$auth_b" ] ; then 
        echo "$PUBKEY" | tee -a "$auth_keys" &> /dev/null
    elif [ ! -f "$auth_keys" ] || [ ! -n "$auth_a" ]; then
        echo "$PUBKEY" | tee "$auth_keys" &>/dev/null
    fi

    chmod 600 "$auth_keys"

    local sshd_config_file="$PREFIX/etc/ssh/sshd_config"
    cp "$sshd_config_file" "$BACKUP_DIR/sshd_config.backup"

    if ! grep -q "^PubkeyAuthentication yes" "$sshd_config_file"; then
       if grep -q "^#PubkeyAuthentication yes" "$sshd_config_file"; then
         sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' "$sshd_config_file"
       else
            echo "PubkeyAuthentication yes" >> "$sshd_config_file"
       fi
    fi

    if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
        if grep -q "^PasswordAuthentication yes" "$sshd_config_file"; then
            sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$sshd_config_file"
        elif ! grep -q "^PasswordAuthentication no" "$sshd_config_file"; then
            echo "PasswordAuthentication no" >> "$sshd_config_file"
        fi
        sed -i 's/^#PasswordAuthentication no/PasswordAuthentication no/' "$sshd_config_file"
    fi

    local BASHRC="$HOME/.bashrc"
    cp "$BASHRC" "$BACKUP_DIR/bashrc.backup"

    if ! cat "$BASHRC" | grep "alias bypass=" &>/dev/null; then
        echo "" | tee -a "$BASHRC"
        echo -e "\# --Bypass Hotspot Throttle-- " | tee -a "$BASHRC"
        echo "alias bypass='bash -c $(curl -fsSL https://raw.githubusercontent.com/SeedOfYggdrasil/bypass_throttle/refs/heads/main/server.sh)'" | tee -a "$BASHRC
        echo "" | tee -a "$BASHRC"
    fi

    [ ! -f "$SETUP_FILE" ] && touch "$SETUP_FILE"
    printf "\rPerforming initial setup...DONE\n"
}

start_server() {
    echo ""
    printf "Starting..."
    if pgrep -f "sshd -D" > /dev/null || pgrep -f "$PREFIX/bin/sshd" > /dev/null; then
        pkill sshd
        sleep 1
    fi
    if sshd -p "$SSH_PORT"; then
        printf "\rStarting...DONE\n"
    else
        printf "\rStarting...FAIL\n"
        exit 1
    fi
}

server_ip() {
    local IP=""
    IP_a="$(ip -4 addr show 2> /dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)"
    if [ -n "$IP_a" ]; then
        IP="$IP_a"
    elif command -v ifconfig &> /dev/null; then
        IP_b="$(ifconfig 2> /dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)"
        if [ -n "$IP_b" ]; then
            IP="$IP_b"
        fi
    fi
    echo "$IP"
}

display_info() {
    SERVER_IP=$(server_ip)

    echo ""
    echo "  SERVER INFO"
    echo "    IP:       $SERVER_IP"
    echo "    Port:     $SSH_PORT"
    echo "    User:     $(whoami)"
    echo ""
    echo "   Notes:"
    echo "      - Turn your hotspot ON as usual."
    echo "      - Then use the client script to connect a device."
    echo "      - To keep running, open another Termux session and run 'termux-wake-lock'"
    echo "      - To deactivate the server, run 'pkill sshd'"
    echo -e "     \033[91m- I love you!\033[0m"
    echo ""
    echo "Press Ctrl=C to exit (server will continue running in background)."
}

bypass_throttle() {
    if [ ! -f "$SETUP_FILE" ]; then
        initial_setup
    fi

    start_server
    display_info

    wait
    exit 0
}
bypass_throttle
