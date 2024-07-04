#!/bin/bash

# Lấy thông tin giao diện mạng và địa chỉ IP hiện tại
get_network_info() {
    echo "Đang lấy thông tin giao diện mạng và địa chỉ IP..."
    route -n
    ifconfig

    INTERFACE=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')
    IP4=$(ip -4 addr show dev $INTERFACE | grep inet | awk '{print $2}' | cut -d/ -f1)
    IP6=$(ip -6 addr show dev $INTERFACE | grep inet6 | awk '{print $2}' | cut -d/ -f1 | grep -v ^fe80)
    GATEWAY4=$(ip route | grep default | awk '{print $3}')
    GATEWAY6=$(ip -6 route | grep default | awk '{print $3}')
}

# Hàm cấu hình IP tĩnh cho Ubuntu
configure_ubuntu() {
    echo "Đang cấu hình IP tĩnh cho Ubuntu..."

    # Kiểm tra và cài đặt các gói cần thiết trên Ubuntu
    check_and_install_ubuntu

    # Tạo hoặc chỉnh sửa tệp cấu hình Netplan
    sudo bash -c "cat > /etc/netplan/00-installer-config.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      dhcp6: no
      addresses: [$IP4/24, $IP6/64]
      gateway4: $GATEWAY4
      nameservers:
          addresses: [8.8.8.8, 8.8.4.4]
EOF"

    # Thử cấu hình Netplan
    sudo netplan try

    # Tạo và áp dụng cấu hình Netplan
    sudo netplan generate
    sudo netplan apply

    echo "Cấu hình IP tĩnh trên Ubuntu hoàn tất."
}

# Hàm cấu hình IP tĩnh cho CentOS
configure_centos() {
    echo "Đang cấu hình IP tĩnh cho CentOS..."

    # Kiểm tra và cài đặt các gói cần thiết trên CentOS
    check_and_install_centos

    # Tạo hoặc chỉnh sửa tệp cấu hình mạng cho giao diện eth0
    sudo bash -c "cat > /etc/sysconfig/network-scripts/ifcfg-$INTERFACE <<EOF
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
EOF"

    # Khởi động lại dịch vụ mạng để áp dụng thay đổi
    sudo systemctl restart network

    echo "Cấu hình IP tĩnh trên CentOS hoàn tất."
}

# Kiểm tra và cài đặt các gói cần thiết trên Ubuntu
check_and_install_ubuntu() {
    echo "Kiểm tra và cài đặt các gói cần thiết trên Ubuntu..."

    if ! command -v netplan &> /dev/null; then
        sudo apt update
        sudo apt install -y netplan
    fi

    echo "Các gói cần thiết đã được cài đặt trên Ubuntu."
}

# Kiểm tra và cài đặt các gói cần thiết trên CentOS
check_and_install_centos() {
    echo "Kiểm tra và cài đặt các gói cần thiết trên CentOS..."

    if ! command -v firewalld &> /dev/null; then
        sudo yum install -y firewalld
        sudo systemctl enable firewalld
        sudo systemctl start firewalld
    fi

    echo "Các gói cần thiết đã được cài đặt trên CentOS."
}

# Kiểm tra hệ điều hành và gọi hàm cấu hình phù hợp
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
        # Ubuntu
        get_network_info
        configure_ubuntu
    elif [ "$ID" == "centos" ] || [ "$ID" == "rhel" ]; then
        # CentOS
        get_network_info
        configure_centos
    else
        echo "Hệ điều hành không được hỗ trợ bởi script này."
        exit 1
    fi
else
    echo "Không tìm thấy tệp /etc/os-release."
    exit 1
fi

# Ping kiểm tra kết nối sau khi cấu hình
echo "Ping kiểm tra kết nối..."
ping -c 4 8.8.8.8
ping -6 -c 4 google.com

# Khởi động lại dịch vụ mạng
echo "Khởi động lại dịch vụ mạng..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
        sudo systemctl restart network-manager
    elif [ "$ID" == "centos" ] || [ "$ID" == "rhel" ]; then
        sudo systemctl restart network
    fi
fi

echo "Cấu hình hoàn tất."
