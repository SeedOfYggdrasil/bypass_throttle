#!/bin/bash


# Configuration

bypass_config() {
    UPSTREAM_IFACE="wlan0"
    DOWNSTREAM_IFACE="wlan1"
    SSH_USER="a0_a230"
    SSH_PORT="8022"
    IP_PREFIX="10.0.0"

    read -p "Server IP: " SERVER_IP
    
    read -p "Upstream SSID: " UPSTREAM_SSID
    read -s -p "Password: " UPSTREAM_PASSWORD
    
}
install_package() {
    local pkg=$1
    printf "    Installing $pkg..."
    if sudo apt install -y $pkg &>/dev/null; then
        printf "\r    Installing $pkg...DONE\n"
    else
        printf "\r    Installing $pkg...FAIL\n"
    fi
}

check_packages() {
    printf "Installing required packages..."

    sudo apt update &>/dev/null
    sudo apt upgrade -y &>/dev/null

    if ! command -v nmcli &> /dev/null; then
        install_package nmcli
    fi
    if ! command -v sshuttle &> /dev/null; then
        install_package sshuttle
    fi
    if ! command -v hostapd &> /dev/null; then
        install_package hostapd
    fi
    if ! command -v dnsmasq &> /dev/null; then
        install_package dnsmasq
    fi

    printf "\rInstalling required packages...DONE\n"
}

cleanup() {
    printf "Cleaning up..."
    
    sudo pkill -f "sshuttle -r $SSH_USER@$SERVER_IP"
    sudo systemctl stop hostapd 2>/dev/null
    sudo systemctl stop dnsmasq 2>/dev/null
    
    sudo ip addr flush dev "$DOWNSTREAM_IFACE" 2>/dev/null
    sudo ip link set dev "$DOWNSTREAM_IFACE" down 2>/dev/null
    
    # sudo iptables -t nat -F POSTROUTING
    # sudo iptables -F FORWARD
    
    printf "\rCleaning up...DONE\n"
}
trap cleanup EXIT SIGINT SIGTERM

connect_to_upstream() {
    printf "Connecting to upstream hotspot..."

    sudo nmcli dev disconnect "$UPSTREAM_IFACE" 2>/dev/null
    sleep 2

  if ! sudo nmcli dev wifi connect "$UPSTREAM_SSID" password "$UPSTREAM_PASSWORD" ifname "$UPSTREAM_IFACE"; then
    printf "\rConnecting to upstream hotspot...FAIL\n
    exit 1 &>/dev/null
  fi
  
  printf "\rConnecting to upstream hotspot...DONE\n
}

start_ssh_tunnel() {
    SSH_KEY="$HOME/.ssh/bypass_throttle"
    printf "Obfuscating traffic..."
    if ! sudo sshuttle --dns -D -r "$SSH_USER@$SERVER_IP:$SSH_PORT" 0/0 --exclude "$SERVER_IP" --pidfile=/var/run/sshuttle.pid --ssh-cmd "ssh -i $SSH_KEY"; then
        printf "\rObfuscating traffic...FAIL\n"
        exit 1 &>/dev/null
    fi
    sleep 5
    if ! curl -s --max-time 5 ifconfig.me &>/dev/null; then
        printf "\rObfuscating traffic...FAIL\n"
        exit 1 &>/dev/null
    fi
    
    printf "\rObfuscating traffic...DONE\n"
    echo ""
    echo "Throttle bypassed!"
}

configure_downstream() {
    printf "Configuring downstream hotspot..."

    read -p "Downstream SSID: " DOWNSTREAM_SSID
    read -s -p "Password: " DOWNSTREAM_PASSWORD

    if ip link show "$DOWNSTREAM_IFACE" &> /dev/null; then
    sudo ip link set dev "$DOWNSTREAM_IFACE" down
    sudo ip addr flush dev "$DOWNSTREAM_IFACE"
    sudo ip addr add "${IP_PREFIX}.1/24" dev "$DOWNSTREAM_IFACE"
   if ! sudo ip link set dev "$DOWNSTREAM_IFACE" up; then
   printf "\rConfiguring downstream hotspot...FAIL\n"    exit 1 &>/dev/null    
   fi
else
    # TODO: automatically create interface
   printf "\rConfiguring downstream hotspot...FAIL\n" echo "Manually create the interface, then try again."
    exit 1 &>/dev/null    
fi

# IP ROUTES
    sudo sysctl -w net.ipv4.ip_forward=1 &>/dev/null
    sudo iptables -t nat -A POSTROUTING -o "$UPSTREAM_IFACE" -j MASQUERADE
    sudo iptables -A FORWARD -i "$DOWNSTREAM_IFACE" -o "$UPSTREAM_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -i "$UPSTREAM_IFACE" -o "$DOWNSTREAM_IFACE" -j ACCEPT

# DNSMASQ
    sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
interface=$DOWNSTREAM_IFACE
dhcp-range=${IP_PREFIX}.50,${IP_PREFIX}.150,12h/
dhcp-option=3,${IP_PREFIX}.1
dhcp-option=6,${IP_PREFIX}.1
dhcp-option=6,1.1.1.1,1.0.0.1
server=1.1.1.1
server=1.0.0.1
listen-address=127.0.0.1,${IP_PREFIX}.1
bind-interfaces
log-dhcp
EOF
    sudo systemctl restart dnsmasq

# HOSTAPD
    sudo bash -c "cat > /etc/hostapd/hostapd.conf" <<EOF
interface=$DOWNSTREAM_IFACE
driver=nl80211
ssid=$DOWNSTREAM_SSID
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$DOWNSTREAM_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
ieee80211n=1
require_ht=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40]
EOF

    if [ -f /etc/default/hostapd ]; then
        sudo sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
        sudo sed -i 's|^DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    fi
    
    sudo systemctl unmask hostapd 2>/dev/null
    sudo systemctl restart hostapd
       
   printf "\rConfiguring downstream hotspot...DONE\n"
   echo ""
   echo ""
   echo "--DOWNSTREAM HOTSPOT--"
   echo "SSID: $DOWNSTREAM_SSID"
   echo "PASS: $DOWNSTREAM_PASSWORD"
   echo ""
   echo "Press Ctrl+C to shutdown."
   echo ""
}

choose_if_forward() {
    choice_made="no"
    while [ "$choice_made" != "yes" ]; do
        read -p "Attempt to forward obfuscated hotspot? [y/N]: " choice

        if [ -z "$choice" ]; then
            choice="no"
        fi

        case $choice in
            n|N|no|NO|No) choice_made=yes ;;
         y|Y|yes|YES|Yes)
                        choice_made=yes
                        configure_downstream
                    ;;    
     *) echo "Invalid. Choose yes or no (defaults to no)."    ;;
    done
}

start_bypass() {

    connect_to_upstream
    start_ssh_tunnel

    choose_if_forward

    wait
}
