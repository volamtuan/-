#!/bin/bash

# Hàm lấy tên card mạng và cấu hình IPv6 dựa trên IPv4 hiện tại
get_network_info() {
    echo "Đang lấy thông tin giao diện mạng và cấu hình IPv6..."

    # Kiểm tra hệ điều hành để quyết định cách cấu hình
    if [ -f /etc/centos-release ]; then
        # CentOS

        YUM=$(which yum)

        if [ "$YUM" ]; then
            # Lấy tên giao diện mạng phù hợp
            INTERFACE=$(ip -o link show | awk -F': ' '$2 ~ /^(en|eth)/ {print $2; exit}')

            if [ -z "$INTERFACE" ]; then
                echo "Không tìm thấy giao diện mạng phù hợp."
                exit 1
            fi

            # Lấy địa chỉ IPv4 và IPv6 (loại bỏ địa chỉ link-local fe80::)
            IP4=$(ip -4 addr show dev $INTERFACE | grep inet | awk '{print $2}' | cut -d/ -f1)
            IP6=$(ip -6 addr show dev $INTERFACE | grep inet6 | awk '{print $2}' | cut -d/ -f1 | grep -v ^fe80)

            # Lấy gateway IPv4 và IPv6
            GATEWAY4=$(ip route | grep default | awk '{print $3}')
            GATEWAY6=$(ip -6 route | grep default | awk '{print $3}')

            # Cấu hình IPv6 cho CentOS
            echo "Cấu hình IPv6 cho CentOS..."

            # Xóa nội dung của /etc/sysctl.conf và thêm cấu hình IPv6
            echo > /etc/sysctl.conf
            tee -a /etc/sysctl.conf <<EOF
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
EOF

            # Tải lại cấu hình sysctl
            sysctl -p

            # Cấu hình file ifcfg-<INTERFACE> dựa trên địa chỉ IPv4 hiện tại
            IPC=$(echo "$IP4" | cut -d"." -f3)
            IPD=$(echo "$IP4" | cut -d"." -f4)

            if [ "$IPC" == "4" ]; then
                IPV6_ADDRESS="2403:6a40:0:40::$IPD:0000/64"
                IPV6_DEFAULTGW="2403:6a40:0:40::1"
            elif [ "$IPC" == "5" ]; then
                IPV6_ADDRESS="2403:6a40:0:41::$IPD:0000/64"
                IPV6_DEFAULTGW="2403:6a40:0:41::1"
            elif [ "$IPC" == "244" ]; then
                IPV6_ADDRESS="2403:6a40:2000:244::$IPD:0000/64"
                IPV6_DEFAULTGW="2403:6a40:2000:244::1"
            else
                IPV6_ADDRESS="2403:6a40:0:$IPC::$IPD:0000/64"
                IPV6_DEFAULTGW="2403:6a40:0:$IPC::1"
            fi

            # Tạo hoặc chỉnh sửa file ifcfg-<INTERFACE>
            tee -a "/etc/sysconfig/network-scripts/ifcfg-$INTERFACE" <<-EOF

TYPE=Ethernet
BOOTPROTO=none
NAME=$INTERFACE
DEVICE=$INTERFACE
ONBOOT=yes
IPADDR=$IP4
PREFIX=24
IPV6ADDR=$IP6/64
GATEWAY=$GATEWAY4
DNS1=8.8.8.8
DNS2=8.8.4.4
IPV6INIT=yes
IPV6_AUTOCONF=no
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
IPV6ADDR=$IPV6_ADDRESS
IPV6_DEFAULTGW=$IPV6_DEFAULTGW
EOF

            # Khởi động lại dịch vụ mạng để áp dụng cấu hình
            systemctl restart network

            echo "Giao diện mạng: $INTERFACE"
            echo "IPv4: $IP4"
            echo "IPv6: $IP6"
            echo "Gateway IPv4: $GATEWAY4"
            echo "Gateway IPv6: $GATEWAY6"
            echo "Cấu hình IPv6 cho CentOS hoàn tất."

        else
            echo "Không tìm thấy YUM trên hệ thống."
            exit 1
        fi

    elif [ -f /etc/lsb-release ]; then
        # Ubuntu

        # Lấy IPv4 hiện tại và phần IP3, IP4 từ nó
        ipv4=$(curl -4 -s icanhazip.com)
        IPC=$(echo "$ipv4" | cut -d"." -f3)
        IPD=$(echo "$ipv4" | cut -d"." -f4)

        # Lấy tên giao diện mạng phù hợp
        INTERFACE=$(ls /sys/class/net | grep 'e')

        # Cấu hình địa chỉ IPv6 và gateway dựa trên giá trị của IPC
        if [ "$IPC" == "4" ]; then
            IPV6_ADDRESS="2403:6a40:0:40::$IPD:0000/64"
            GATEWAY="2403:6a40:0:40::1"
        elif [ "$IPC" == "5" ]; then
            IPV6_ADDRESS="2403:6a40:0:41::$IPD:0000/64"
            GATEWAY="2403:6a40:0:41::1"
        elif [ "$IPC" == "244" ]; then
            IPV6_ADDRESS="2403:6a40:2000:244::$IPD:0000/64"
            GATEWAY="2403:6a40:2000:244::1"
        else
            IPV6_ADDRESS="2403:6a40:0:$IPC::$IPD:0000/64"
            GATEWAY="2403:6a40:0:$IPC::1"
        fi

        # Xác định đường dẫn tệp cấu hình Netplan phù hợp
        if [ "$INTERFACE" == "ens160" ]; then
            NETPLAN_PATH="/etc/netplan/99-netcfg-vmware.yaml"
        elif [ "$INTERFACE" == "eth0" ]; then
            NETPLAN_PATH="/etc/netplan/50-cloud-init.yaml"
        else
            echo "Không tìm thấy card mạng phù hợp."
            exit 1
        fi

        # Đọc và cập nhật tệp cấu hình Netplan
        NETPLAN_CONFIG=$(cat "$NETPLAN_PATH")
        NEW_NETPLAN_CONFIG=$(sed "/gateway4:/i \ \ \ \ \ \ \  - $IPV6_ADDRESS" <<< "$NETPLAN_CONFIG")
        NEW_NETPLAN_CONFIG=$(sed "/gateway4:.*/a \ \ \ \ \  gateway6: $GATEWAY" <<< "$NEW_NETPLAN_CONFIG")
        echo "$NEW_NETPLAN_CONFIG" > "$NETPLAN_PATH"

        # Áp dụng cấu hình Netplan
        sudo netplan apply

        echo "Giao diện mạng: $INTERFACE"
        echo "IPv4: $IP4"
        echo "IPv6: $IP6"
        echo "Gateway IPv4: $GATEWAY4"
        echo "Gateway IPv6: $GATEWAY6"
        echo "Cấu hình IPv6 cho Ubuntu hoàn tất."

    else
        echo "Hệ điều hành không được hỗ trợ."
        exit 1
    fi
}

# Gọi hàm để lấy thông tin và cấu hình IPv6
get_network_info
