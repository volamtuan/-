#!/bin/bash

# Function to get IP, IPv6, and network interface name on CentOS
get_network_info_centos() {
    # Get network interface name
    INTERFACE=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')

    # Get IPv4 address
    IPV4_ADDRESS=$(ip -4 addr show dev "$INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

    # Get IPv6 address
    IPV6_ADDRESS=$(ip -6 addr show dev "$INTERFACE" | grep "inet6.*global" | awk '{print $2}' | head -n 1)

    # Print the results
    echo "Tên card mạng: $INTERFACE"
    echo "Địa chỉ IP: $IPV4_ADDRESS"
    echo "Địa chỉ IPv6: $IPV6_ADDRESS"
}

# Function to set up IPv6 on CentOS
setup_ipv6() {
    # Get network interface name
    INTERFACE=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')

    # Get IPv6 address
    IPV6_ADDRESS=$(ip -6 addr show dev "$INTERFACE" | grep "inet6.*global" | awk '{print $2}' | head -n 1)

    # Kiểm tra xem có địa chỉ IPv6 nào được tìm thấy không
    if [ -z "$IPV6_ADDRESS" ]; then
        echo "Không tìm thấy địa chỉ IPv6 trên giao diện $INTERFACE"
        exit 1
    fi

    # Lấy địa chỉ gateway IPv6 từ routing table
    GATEWAY6_ADDRESS=$(ip -6 route show default | awk '{print $3}')

    # Kiểm tra xem có gateway IPv6 nào được tìm thấy không
    if [ -z "$GATEWAY6_ADDRESS" ]; then
        echo "Không tìm thấy gateway IPv6"
        exit 1
    fi

    # Phát hiện hệ điều hành
    OS=$(grep ^ID= /etc/os-release | cut -d= -f2)

    if [[ "$OS" == "ubuntu" ]]; then
        # Đường dẫn đến tệp cấu hình Netplan
        NETPLAN_PATH="/etc/netplan"

        # Kiểm tra và cập nhật cấu hình Netplan cho các phiên bản Ubuntu khác nhau
        if [ -d "$NETPLAN_PATH" ]; then
            if [ -f "$NETPLAN_PATH/01-netcfg.yaml" ]; then
                NETPLAN_CONFIG="$NETPLAN_PATH/01-netcfg.yaml"
            elif [ -f "$NETPLAN_PATH/50-cloud-init.yaml" ]; then
                NETPLAN_CONFIG="$NETPLAN_PATH/50-cloud-init.yaml"
            elif [ -f "$NETPLAN_PATH/99-netcfg.yaml" ]; then
                NETPLAN_CONFIG="$NETPLAN_PATH/99-netcfg.yaml"
            else
                echo "Không tìm thấy tệp cấu hình Netplan"
                exit 1
            fi
        else
            echo "Thư mục $NETPLAN_PATH không tồn tại"
            exit 1
        fi

        # Tạo đoạn cấu hình IPv6 mới
        NEW_NETPLAN_CONFIG=$(cat "$NETPLAN_CONFIG")
        NEW_NETPLAN_CONFIG+="
        ethernets:
            $INTERFACE:
                dhcp4: no
                dhcp6: no
                addresses:
                    - $IPV6_ADDRESS
                gateway6: $GATEWAY6_ADDRESS
                nameservers:
                    addresses: [2001:4860:4860::8888, 2001:4860:4860::8844]
    "

        # Ghi đè cấu hình Netplan
        echo -e "$NEW_NETPLAN_CONFIG" > "$NETPLAN_CONFIG"

        # Áp dụng cấu hình Netplan
        netplan apply
    elif [[ "$OS" == "centos" ]]; then
        # Đường dẫn đến tệp cấu hình mạng trên CentOS
        NETWORK_CONFIG_PATH="/etc/sysconfig/network-scripts/ifcfg-$INTERFACE"

        # Kiểm tra xem tệp cấu hình mạng có tồn tại không
        if [ ! -f "$NETWORK_CONFIG_PATH" ]; then
            echo "Không tìm thấy tệp cấu hình mạng cho $INTERFACE"
            exit 1
        fi

        # Tạo đoạn cấu hình IPv6 mới
        NEW_NETWORK_CONFIG=$(cat "$NETWORK_CONFIG_PATH")
        NEW_NETWORK_CONFIG+="
        IPV6INIT=yes
        IPV6ADDR=$IPV6_ADDRESS
        IPV6_DEFAULTGW=$GATEWAY6_ADDRESS
    "

        # Ghi đè cấu hình mạng
        echo -e "$NEW_NETWORK_CONFIG" > "$NETWORK_CONFIG_PATH"

        # Khởi động lại mạng

    else
        echo "Hệ điều hành không được hỗ trợ"
        exit 1
    fi

    # Ping đến địa chỉ IPv6 gateway để kiểm tra kết nối
    ping6 -c 4 "$GATEWAY6_ADDRESS"

    # Kết quả ping
    PING_RESULT=$?
    if [ $PING_RESULT -eq 0 ]; then
        echo "Ping thành công đến gateway IPv6: $GATEWAY6_ADDRESS"
    else
        echo "Ping thất bại đến gateway IPv6: $GATEWAY6_ADDRESS"
    fi

    systemctl restart network
    sudo systemctl restart network


    ip -6 addr | grep inet6 | wc -l

    # Kiểm tra kết nối IPv6 bằng cách ping Google
    ping_google6
}

# Function to ping Google over IPv6
ping_google6() {
    # Thực hiện ping Google qua IPv6
    ping6 -c 4 ipv6.google.com

    # Kiểm tra kết quả ping
    PING_RESULT=$?
    if [ $PING_RESULT -eq 0 ]; then
        echo "Ping thành công đến Google qua IPv6"
    else
        echo "Ping thất bại đến Google qua IPv6"
    fi
}

# Gọi hàm để lấy thông tin mạng trên CentOS và thiết lập IPv6
get_network_info_centos
setup_ipv6
