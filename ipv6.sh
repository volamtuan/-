#!/bin/bash

# Hàm tự động phát hiện tên giao diện mạng
auto_detect_interface() {
    INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')
}

# Hàm cấu hình IPv6 cho CentOS/RHEL
configure_ipv6_centos() {
    echo > /etc/sysctl.conf
    tee -a /etc/sysctl.conf <<EOF
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
EOF
    sysctl -p

    IPC=$(curl -4 -s icanhazip.com | cut -d"." -f3)
    IPD=$(curl -4 -s icanhazip.com | cut -d"." -f4)

    if [ "$IPC" == "4" ]; then
        IPV6ADDR="2403:6a40:0:40::$IPD:0000/64"
        IPV6GW="2403:6a40:0:40::1"
    elif [ "$IPC" == "5" ]; then
        IPV6ADDR="2403:6a40:0:41::$IPD:0000/64"
        IPV6GW="2403:6a40:0:41::1"
    elif [ "$IPC" == "244" ]; then
        IPV6ADDR="2403:6a40:2000:244::$IPD:0000/64"
        IPV6GW="2403:6a40:2000:244::1"
    else
        IPV6ADDR="2403:6a40:0:$IPC::$IPD:0000/64"
        IPV6GW="2403:6a40:0:$IPC::1"
    fi

    tee -a /etc/sysconfig/network-scripts/ifcfg-$INTERFACE <<-EOF
    IPV6INIT=yes
    IPV6_AUTOCONF=no
    IPV6_DEFROUTE=yes
    IPV6_FAILURE_FATAL=no
    IPV6_ADDR_GEN_MODE=stable-privacy
    IPV6ADDR=$IPV6ADDR
    IPV6_DEFAULTGW=$IPV6GW
    EOF

    service network restart
}

# Hàm cấu hình IPv6 cho Ubuntu
configure_ipv6_ubuntu() {
    IPV4=$(curl -4 -s icanhazip.com)
    IPC=$(curl -4 -s icanhazip.com | cut -d"." -f3)
    IPD=$(curl -4 -s icanhazip.com | cut -d"." -f4)
    INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')

    if [ "$IPC" == "4" ]; then
        IPV6ADDR="2403:6a40:0:40::$IPD:0000/64"
        IPV6GW="2403:6a40:0:40::1"
    elif [ "$IPC" == "5" ]; then
        IPV6ADDR="2403:6a40:0:41::$IPD:0000/64"
        IPV6GW="2403:6a40:0:41::1"
    elif [ "$IPC" == "244" ]; then
        IPV6ADDR="2403:6a40:2000:244::$IPD:0000/64"
        IPV6GW="2403:6a40:2000:244::1"
    else
        IPV6ADDR="2403:6a40:0:$IPC::$IPD:0000/64"
        IPV6GW="2403:6a40:0:$IPC::1"
    fi

    netplan_config=$(cat /etc/netplan/50-cloud-init.yaml)
    new_netplan_config=$(sed "/gateway4:/i \ \ \ \ \ \ \ \ \ \ \ \ - $IPV6ADDR" <<< "$netplan_config")
    new_netplan_config=$(sed "/gateway4:.*/a \ \ \ \ \ \ \ \ \ \ \ \ gateway6: $IPV6GW" <<< "$new_netplan_config")
    
    echo "$new_netplan_config" > /etc/netplan/50-cloud-init.yaml
    netplan apply
}

# Kiểm tra và thực hiện cấu hình tương ứng với hệ thống
if [ "$(which yum)" ]; then
    auto_detect_interface
    configure_ipv6_centos
else
    configure_ipv6_ubuntu
fi

echo 'Đã tạo và cập nhật IPv6 thành công!'
