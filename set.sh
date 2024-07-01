#!/bin/sh

# Thiết lập biến PATH
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

setup_ipv6() {
    echo "Thiết lập IPv6..."
    ip -6 addr flush dev eth0
    ip -6 addr flush dev ens33
}

# Gọi hàm thiết lập IPv6
setup_ipv6

# Lấy tên interface mạng
NETWORK_INTERFACE_NAME=$(ip route get 8.8.8.8 | awk '{print $5}')

# Tự động lấy địa chỉ IPv4 từ thiết bị
IP4=$(ip addr show | grep -oP '(?<=inet\s)192(\.\d+){2}\.\d+' | head -n 1)

# Tự động lấy địa chỉ IPv6/64
IPV6ADDR=$(ip -6 addr show | grep -oP '(?<=inet6\s)[\da-fA-F:]+(?=/64)' | head -n 1)

# Kiểm tra card mạng eth0
if ip link show eth0 &> /dev/null; then
    echo "Card mạng eth0 đã được tìm thấy."
    
    # Thiết lập cấu hình mạng cho eth0
    cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
    TYPE=Ethernet
    NAME=eth0
    DEVICE=eth0
    ONBOOT=yes
    BOOTPROTO=dhcp
    IPV6_INIT=yes
    IPV6_AUTOCONF=yes
    IPV6_DEFROUTE=yes
    IPV6_FAILURE_FATAL=no
    IPV6_ADDR_GEN_MODE=eui64
    IPADDR=$IP4
    NETMASK=255.255.255.0
    GATEWAY=192.168.1.1
    DNS1=8.8.8.8
    IPV6ADDR=$IPV6ADDR/64
    IPV6_DEFAULTGW=2001:ee0:4f9b:92b0::1
EOF

    # Kiểm tra kết nối IPv6
    if ip -6 route get 2001:ee0:4f9b:92b0::8888 &> /dev/null; then
        echo "Kết nối IPv6 cho eth0 hoạt động."
    else
        echo "Lỗi: Kết nối IPv6 cho eth0 không hoạt động."
    fi

    # Cấp quyền cho địa chỉ IPv4 của eth0
    firewall-cmd --zone=public --add-source="$IP4" --permanent
    firewall-cmd --reload

# Kiểm tra card mạng ens33
elif ip link show ens33 &> /dev/null; then
    echo "Card mạng ens33 đã được tìm thấy."
    
    # Thiết lập cấu hình mạng cho ens33
    cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-ens33
    TYPE=Ethernet
    NAME=ens33
    DEVICE=ens33
    ONBOOT=yes
    BOOTPROTO=dhcp
    IPV6_INIT=yes
    IPV6_AUTOCONF=yes
    IPV6_DEFROUTE=yes
    IPV6_FAILURE_FATAL=no
    IPV6_ADDR_GEN_MODE=eui64
    IPADDR=$IP4
    NETMASK=255.255.255.0
    GATEWAY=192.168.1.1
    DNS1=8.8.8.8
    IPV6ADDR=$IPV6ADDR/64
    IPV6_DEFAULTGW=2001:ee0:4f9b:92b0::1
EOF

    # Kiểm tra kết nối IPv6
    if ip -6 route get 2001:ee0:4f9b:92b0::8888 &> /dev/null; then
        echo "Kết nối IPv6 cho ens33 hoạt động."
    else
        echo "Lỗi: Kết nối IPv6 cho ens33 không hoạt động."
    fi

    # Cấp quyền cho địa chỉ IPv4 của ens33
    firewall-cmd --zone=public --add-source="$IP4" --permanent
    firewall-cmd --reload 
fi

# Khởi động lại dịch vụ mạng
sudo systemctl restart network

# Kiểm tra kết nối IPv6 bằng cách ping Google
ping6 -c 3 google.com

# Hiển thị thông tin địa chỉ mạng
ip addr show
ip route show
service network restart
ping_google6
echo 'IPv6 đã được cấu hình thành công!'

# Hàm random để tạo chuỗi ngẫu nhiên
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Hàm tạo địa chỉ IPv6 ngẫu nhiên
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Hàm cài đặt 3proxy
install_3proxy() {
    echo "Installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf- >/dev/null 2>&1
    cd 3proxy-3proxy-0.8.6  # Đã sửa thành đường dẫn tuyệt đối
    make -f Makefile.Linux >/dev/null 2>&1
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat} >/dev/null 2>&1
    cp src/3proxy /usr/local/etc/3proxy/bin/ >/dev/null 2>&1
    cd ${WORKDATA}
    rm -fr ${WORKDATA}/3proxy-3proxy-0.8.6
}

# Hàm tạo file cấu hình cho 3proxy
gen_3proxy() {
    cat <<EOF 
daemon
maxconn 5000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
nscache6 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth none
allow 127.0.0.1

$(awk -F "/" '{print "proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\nflush\n"}' ${WORKDATA})
EOF
}

# Hàm tạo file proxy cho người dùng
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4}' ${WORKDATA})
EOF
}

# Hàm tạo dữ liệu
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
        echo "$IP4:$port" >> "$WORKDIR/ipv4.txt"
        new_ipv6=$(gen64 $IP6)
        echo "$new_ipv6" >> "$WORKDIR/ipv6.txt"
    done
}

# Hàm tạo iptables
gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

# Hàm cấu hình ifconfig
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig '"$NETWORK_INTERFACE_NAME"' inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

Cài đặt các ứng dụng cần thiết

echo “Installing apps”
sudo yum install make wget curl jq git iptables-services -y >/dev/null 2>&1
sudo apt install make wget curl jq git iptables-services -y >/dev/null 2>&1
install_3proxy

Thiết lập thư mục làm việc

WORKDIR=”/home/proxy”
WORKDATA=”${WORKDIR}/data.txt”
mkdir $WORKDIR && cd $_

Lấy địa chỉ IP

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d’:’)

echo “IPv4 = ${IP4}”
echo “IPv6 = ${IP6}”

FIRST_PORT=10000
LAST_PORT=22222

echo “Cổng proxy: $FIRST_PORT”
echo “Số Lượng Tạo: $(($LAST_PORT - $FIRST_PORT + 1))”

l

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh

Tạo file cấu hình cho 3proxy

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

Tạo file dịch vụ systemd cho 3proxy

cat </etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/bin/kill -TERM $MAINPID
Restart=always
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

Tạo file dịch vụ systemd cho rc.local nếu chưa có

cat </etc/systemd/system/rc-local.service
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF

Tạo file rc.local nếu chưa tồn tại

cat </etc/rc.local
#!/bin/sh -e

rc.local

This script is executed at the end of each multiuser runlevel.

Make sure that the script will “exit 0” on success or any other

value on error.

bash /home/proxy/boot_iptables.sh
bash /home/proxy/boot_ifconfig.sh
ulimit -n 1000000
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

exit 0
EOF

chmod +x /etc/rc.local

Tối ưu hóa cấu hình kernel

cat <>/etc/sysctl.conf
fs.file-max = 1000000
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_fin_timeout = 30
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 4096
EOF

Áp dụng các thay đổi cấu hình kernel

sysctl -p

Kích hoạt và khởi động các dịch vụ

systemctl enable rc-local
systemctl enable 3proxy

systemctl start rc-local
systemctl start 3proxy

Kiểm tra trạng thái dịch vụ

systemctl status rc-local
systemctl status 3proxy

Tạo tập tin proxy cho người dùng

gen_proxy_file_for_user
rm -rf /root/3proxy-3proxy-0.8.6

echo “Starting Proxy”

echo “Tổng số IPv6 hiện tại:”
ip -6 addr | grep inet6 | wc -lp
