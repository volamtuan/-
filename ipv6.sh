#!/bin/bash

# Hàm kiểm tra và chọn tên giao diện mạng tự động
auto_detect_interface() {
    INTERFACE=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')
}

# Kiểm tra và chọn giao diện mạng tự động
auto_detect_interface

# Get IPv6 address
ipv6_address=$(ip addr show "$INTERFACE" | awk '/inet6/{print $2}' | grep -v '^fe80' | head -n1)

# Check if IPv6 address is obtained
if [ -n "$ipv6_address" ]; then
    echo "IPv6 address obtained: $ipv6_address"

    # Declare associative arrays to store IPv6 addresses and gateways
    declare -A ipv6_addresses=(
        [4]="2001:ee0:4f9b::$IPD:0000/64"
        [5]="2001:ee0:4f9b::$IPD:0000/64"
        [244]="2001:ee0:4f9b::$IPD:0000/64"
        ["default"]="2001:ee0:4f9b::$IPC::$IPD:0000/64"
    )

    declare -A gateways=(
        [4]="2001:ee0:4f9b:$IPC::1"
        [5]="2001:ee0:4f9b:$IPC::1"
        [244]="2001:ee0:4f9b:$IPC::1"
        ["default"]="2001:ee0:4f9b:$IPC::1"
    )

    # Get IPv4 third and fourth octets
    IPC=$(echo "$ipv6_address" | cut -d":" -f5)
    IPD=$(echo "$ipv6_address" | cut -d":" -f6)

    # Set IPv6 address and gateway based on IPv4 third octet
    IPV6_ADDRESS="${ipv6_addresses[$IPC]}"
    GATEWAY="${gateways[$IPC]}"

    echo "Configuring interface: $INTERFACE"

    # Configure IPv6 settings
    echo "IPV6_ADDR_GEN_MODE=stable-privacy" > /etc/network/interfaces
    echo "IPV6ADDR=$ipv6_address/64" >> /etc/network/interfaces
    echo "IPV6_DEFAULTGW=$GATEWAY" >> /etc/network/interfaces

    # Restart networking service
    service networking restart
    systemctl restart NetworkManager.service
    service network restart
    # Hiển thị cấu hình mạng của giao diện
    ip addr show "$INTERFACE"

    echo "Done!"
else
    echo "No IPv6 address obtained."
fi
