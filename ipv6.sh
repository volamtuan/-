#!/bin/bash

# Function to get network interface name
get_interface() {
    INTERFACE=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')
}

# Function to get IPv4 address
get_ipv4_address() {
    IPV4_ADDRESS=$(ip -4 addr show dev "$INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
}

# Function to get IPv6 address
get_ipv6_address() {
    IPV6_ADDRESS=$(ip -6 addr show dev "$INTERFACE" | awk '/inet6/{print $2}' | grep -v '^fe80' | head -n1)
}

# Function to get gateway IPv6 address
get_gateway6_address() {
    GATEWAY6_ADDRESS=$(ip -6 route show default | awk '{print $3}')
}

# Function to set up IPv6 on CentOS
setup_ipv6_centos() {
    # Check if IPv6 address exists
    if [ -z "$IPV6_ADDRESS" ]; then
        echo "Không tìm thấy địa chỉ IPv6 trên giao diện $INTERFACE"
        exit 1
    fi

    # Check if gateway IPv6 address exists
    if [ -z "$GATEWAY6_ADDRESS" ]; then
        echo "Không tìm thấy gateway IPv6"
        exit 1
    fi

    # Path to network configuration file on CentOS
    NETWORK_CONFIG_PATH="/etc/sysconfig/network-scripts/ifcfg-$INTERFACE"

    # Check if network configuration file exists
    if [ ! -f "$NETWORK_CONFIG_PATH" ]; then
        echo "Không tìm thấy tệp cấu hình mạng cho $INTERFACE"
        exit 1
    fi

    # Update network configuration for IPv6
    sed -i '/^IPV6/d' "$NETWORK_CONFIG_PATH"
    echo "IPV6INIT=yes" >> "$NETWORK_CONFIG_PATH"
    echo "IPV6ADDR=$IPV6_ADDRESS" >> "$NETWORK_CONFIG_PATH"
    echo "IPV6_DEFAULTGW=$GATEWAY6_ADDRESS" >> "$NETWORK_CONFIG_PATH"

    # Restart network service
    systemctl restart network
}

# Function to set up IPv6 on Ubuntu
setup_ipv6_ubuntu() {
    # Path to Netplan configuration file on Ubuntu
    NETPLAN_PATH="/etc/netplan"

    # Check if Netplan directory exists
    if [ -d "$NETPLAN_PATH" ]; then
        # Find Netplan configuration file
        NETPLAN_CONFIG=$(ls "$NETPLAN_PATH" | grep -E '^[0-9]+-.*\.yaml$' | head -n 1)

        # Check if Netplan configuration file exists
        if [ -n "$NETPLAN_CONFIG" ]; then
            # Update Netplan configuration for IPv6
            sed -i '/addresses:/a \ \ \ \ \ \ \ \ - '"$IPV6_ADDRESS"'' "$NETPLAN_PATH/$NETPLAN_CONFIG"
            sed -i '/gateway4:/a \ \ \ \ \ \ \ \ gateway6: '"$GATEWAY6_ADDRESS"'' "$NETPLAN_PATH/$NETPLAN_CONFIG"

            # Apply Netplan configuration
            netplan apply
        else
            echo "Không tìm thấy tệp cấu hình Netplan"
            exit 1
        fi
    else
        echo "Thư mục $NETPLAN_PATH không tồn tại"
        exit 1
    fi
}

# Function to ping Google over IPv6
ping_google6() {
    ping6 -c 4 ipv6.google.com > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Ping thành công đến Google qua IPv6"
    else
        echo "Ping thất bại đến Google qua IPv6"
    fi
}

# Main function
main() {
    # Get network interface name
    get_interface

    # Get IPv4 address
    get_ipv4_address

    # Get IPv6 address
    get_ipv6_address

    # Get gateway IPv6 address
    get_gateway6_address

    # Print network information
    echo "Tên card mạng: $INTERFACE"
    echo "Địa chỉ IP: $IPV4_ADDRESS"
    echo "Địa chỉ IPv6: $IPV6_ADDRESS"

    # Set up IPv6 based on operating system
    if [ -f "/etc/os-release" ]; then
        OS=$(grep ^ID= /etc/os-release | cut -d= -f2)
        if [ "$OS" == "ubuntu" ]; then
            setup_ipv6_ubuntu
        elif [ "$OS" == "centos" ]; then
            setup_ipv6_centos
        else
            echo "Hệ điều hành không được hỗ trợ"
            exit 1
        fi
    else
        echo "Không thể xác định hệ điều hành."
        exit 1
    fi

    # Ping Google over IPv6
    ping_google6
}

# Call main function
main
