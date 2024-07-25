#!/bin/bash

# Variables
WORKDIR="/home/proxy"
WORKDATA="${WORKDIR}/data.txt"
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
FIRST_PORT=20000
LAST_PORT=20500
MAIN_INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5}')

# Function to generate random strings
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Function to generate IPv6 address segment
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Function to install and configure 3proxy
install_3proxy() {
    echo "Installing 3proxy..."
    mkdir -p /3proxy
    cd /3proxy
    URL="https://github.com/z3APA3A/3proxy/archive/0.9.3.tar.gz"
    wget -qO- $URL | tar -xzvf -
    cd 3proxy-0.9.3
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    mv /3proxy/3proxy-0.9.3/bin/3proxy /usr/local/etc/3proxy/bin/
    cp /3proxy/3proxy-0.9.3/scripts/3proxy.service-Centos8 /usr/lib/systemd/system/3proxy.service
    systemctl daemon-reload
    echo "* hard nofile 999999" >> /etc/security/limits.conf
    echo "* soft nofile 999999" >> /etc/security/limits.conf
    echo "net.ipv6.conf.$MAIN_INTERFACE.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
    sysctl -p
    systemctl stop firewalld
    systemctl disable firewalld
    cd $WORKDIR
}

# Function to generate 3proxy configuration
gen_3proxy() {
    cat <<EOF
daemon
maxconn 10000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
flush
auth none
$(awk -F "/" '{print "allow *" $1 "\n" "proxy -6 -n -a -p" $4 " -i" $3 " -e"$5 "\n" "flush"}' ${WORKDATA})
EOF
}

# Function to generate proxy data
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "$(random)/$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# Function to generate iptables rules
gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}
}

# Function to configure IPv6 addresses
gen_ifconfig() {
    awk -F "/" '{print "ifconfig '$MAIN_INTERFACE' inet6 add " $5 "/64"}' ${WORKDATA}
}

# Function to rotate IPv6 addresses
rotate_ipv6() {
    echo "Rotating IPv6 addresses..."
    gen_data > $WORKDATA
    gen_ifconfig > ${WORKDIR}/boot_ifconfig.sh
    bash ${WORKDIR}/boot_ifconfig.sh
    echo "Restarting 3proxy service..."
    systemctl restart 3proxy
    if [ $? -eq 0 ]; then
        echo "IPv6 addresses rotated successfully."
    else
        echo "Failed to rotate IPv6 addresses!"
        exit 1
    fi
}

# Function to reset and update configurations
reset_and_update() {
    # Stop 3proxy service
    systemctl stop 3proxy

    # Reset 3proxy configuration directory
    rm -rf /usr/local/etc/3proxy/*
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}

    # Install and configure 3proxy
    install_3proxy

    # Generate new configurations
    gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg
    gen_data > $WORKDATA
    gen_iptables > ${WORKDIR}/boot_iptables.sh
    gen_ifconfig > ${WORKDIR}/boot_ifconfig.sh

    # Apply configurations
    systemctl start NetworkManager.service
    bash ${WORKDIR}/boot_iptables.sh
    bash ${WORKDIR}/boot_ifconfig.sh
    ulimit -n 65535
    systemctl disable --now firewalld
    service iptables stop
    killall 3proxy
    service 3proxy start
    if [ $? -eq 0 ]; then
        echo "Configurations reset and updated successfully."
    else
        echo "Failed to reset and update configurations!"
        exit 1
    fi
}
ip -6 addr | grep inet6 | wc -l
# Function to periodically rotate IPv6 addresses
periodic_rotate() {
    while true; do
        rotate_ipv6
        sleep 600  # Rotate every 10 minutes (600 seconds)
    done
}

# Main script flow
case "$1" in
    rotate)
        rotate_ipv6
        ;;
    reset)
        reset_and_update
        ;;
    auto)
        periodic_rotate &
        ;;
    *)
        echo $"Usage: $0 {rotate|reset|auto}"
        exit 1
esac

exit 0

