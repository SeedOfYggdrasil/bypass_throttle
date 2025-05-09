#!/data/data/com.termux/files/usr/bin/env bash
#
# bypass_throttle_server.sh
# ver. 1.0
#
#----START----

install_package() {
    local package_name="$1"
    printf "    Installing $package_name..."
    if pkg install -y "$package_name" &>/dev/null; then
        printf "\r  Installing $package_name...DONE\n"
    else
        printf "\r  Installing $package_name...FAIL\n"
    fi
}

initial_setup() {
    printf "Installing required packages..."

    pkg update -y &>/dev/null
    pkg upgrade -y &>/dev/null

    install_package "git"
    install_package "openssh"
    install_package "net-tools"
    install_package "termux-api"

    printf "\rInstalling required packages...DONE\n"

    printf "Requesting storage access..."
    termux-setup-storage
    printf "\rRequesting storage access...DONE\n"

    SSH_DIR="$HOME/.ssh"
    printf "Performing initial setup..."

    if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi

    local dest_auth_keys="$SSH_DIR/authorized_keys"

    echo "$PUBLIC_KEY" | tee "$dest_auth_keys" &>/dev/null
    chmod 600 "$dest_auth_keys"

    local sshd_config_file="$PREFIX/etc/ssh/sshd_config"

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

    APP_DIR="$HOME/.bypass"
    SETUP_FILE="$APP_DIR/setup_complete"

    [ ! -d "$APP_DIR" ] && mkdir -p "$APP_DIR"
    [ ! -f "$SETUP_FILE" ] && touch "$SETUP_FILE"

    printf "\rPerforming initial setup...DONE\n"
    echo ""
}

start_server() {
    printf "Starting..."
    if pgrep -f "sshd -D" > /dev/null || pgrep -f "$PREFIX/bin/sshd" > /dev/null; then
        pkill sshd
        sleep 1
    fi
    if sshd -p "$SSH_PORT"; then
        printf "\rStarting...DONE\n"
    else
        printf "\rStarting...FAIL\n"
        exit 1 &>/dev/null
    fi
}

server_ip() {
  if [ -z "$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')" ]; then
    if command -v ifconfig &> /dev/null; then
    IP="$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')"
    fi
  else
      IP="$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1'")
  fi

  echo "$IP"
}

display_info() {
    SERVER_IP=$(server_ip)
    echo ""
    echo "BYPASSING HOTSPOT THROTTLE..."
    echo ""
    echo "  SERVER INFO"
    echo "    IP:       $SERVER_IP"
    echo "    Port:     $SSH_PORT"
    echo "    User:     $(whoami)"
    echo ""
    echo "   Notes:"
    echo "      - Make sure your phone's hotspot is turned ON"
    echo "      - Then use the client script to connect a device."
    echo "      - To keep running, open another Termux session and run 'termux-wake-lock'"
    echo "      - To deactivate the server, run 'pkill sshd'"
    echo -e "     \033[91m- I love you!\033[0m"
    echo ""
    echo "Press Ctrl=C to exit (server will continue running in background)."
}

bypass_throttle() {
    SSH_PORT=8022
    FILES="$HOME/.bypass"
    REPO="https://github.com/SeedOfYggdrasil/bypass_throttle.git"
PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEygw1nByVqsEF+T6sbAsSBJgEk1itWy6WvNJvXlRJq8"
    APP_DIR="$HOME/.bypass"
    SETUP_FILE="$APP_DIR/setup_complete"

    if [ ! -f "$SETUP_FILE" ]; then
        initial_setup
    fi

    start_server
    display_info

    wait
    exit 0
}
bypass_throttle
