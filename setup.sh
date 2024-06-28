#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Thiết lập IPv6
setup_ipv6() {
    echo "Thiết lập IPv6..."
    ip -6 addr flush dev eth0
    ip -6 addr flush dev ens33
    bash <(curl -s "https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh")
}
setup_ipv6

# Tự động phát hiện giao diện mạng
auto_detect_interface() {
    IFCFG=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')
}

# Tạo địa chỉ IPv6 và cấu hình iptables
gen_ipv6_64() {
    rm -f "$WORKDIR/ipv6.txt"
    count_ipv6=1
    while [ "$count_ipv6" -le "$MAXCOUNT" ]; do
        array=( 1 2 3 4 5 6 7 8 9 0 a b c d e f )
        ip64() {
            echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
        }
        echo "$IP6:$(ip64):$(ip64):$(ip64):$(ip64)" >> "$WORKDIR/ipv6.txt"
        let "count_ipv6 += 1"
    done
}

# Cài đặt và cấu hình 3proxy
install_3proxy() {
    echo "Installing 3proxy..."
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf- >/dev/null 2>&1
    cd 3proxy-0.9.4
    make -f Makefile.Linux >/dev/null 2>&1
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat} >/dev/null 2>&1
    cp src/3proxy /usr/local/etc/3proxy/bin/ >/dev/null 2>&1
    cd $WORKDIR  # Đã sửa thành đường dẫn tuyệt đối
    systemctl link /usr/lib/systemd/system/3proxy.service
    systemctl daemon-reload
    systemctl enable 3proxy
    echo "* hard nofile 999999" >>  /etc/security/limits.conf
    echo "* soft nofile 999999" >>  /etc/security/limits.conf
    echo "net.ipv6.conf.${NETWORK_INTERFACE_NAME}.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
    sysctl -p
    systemctl stop firewalld
    systemctl disable firewalld
    echo "fs.file-max = 1000000" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.ip_local_port_range = 1024 65000" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_fin_timeout = 30" | sudo tee -a /etc/sysctl.conf
    echo "net.core.somaxconn = 4096" | sudo tee -a /etc/sysctl.conf
    echo "net.core.netdev_max_backlog = 4096" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
}

# Tạo cấu hình 3proxy
gen_3proxy_cfg() {
    echo "daemon"
    echo "maxconn 10000"
    echo "nserver 1.1.1.1"
    echo "nserver 8.8.4.4"
    echo "nserver [2606:4700:4700::1111]"
    echo "nserver [2606:4700:4700::1001]"
    echo "nserver 2001:4860:4860::8888"
    echo "nserver 2001:4860:4860::8844"
    echo "nscache 65536"
    echo "timeouts 1 5 30 60 180 1800 15 60"
    echo "setgid 65535"
    echo "setuid 65535"
    echo "stacksize 6291456"
    echo "flush"
    echo "auth none"
    echo "allow 127.0.0.1"

    port="$START_PORT"
    while read -r ip; do
        echo "proxy -6 -n -a -p$port -i$IP4 -e$ip"
        ((port+=1))
    done < "$WORKDIR/ipv6.txt"
}

# Tạo lệnh ifconfig cho IPv6
gen_ifconfig() {
    while read -r line; do
        echo "ifconfig $IFCFG inet6 add $line/64"
    done < "$WORKDIR/ipv6.txt"
}

# Xuất cấu hình ra tập tin văn bản
export_txt() {
    port="$START_PORT"
    for ((i=1; i<=$MAXCOUNT; i++)); do
        echo "$IP4:$port"
        ((port+=1))
    done
}

# Tạo script xoay để cập nhật địa chỉ IPv6
gen_xoay() {
    cat <<EOF > "$WORKDIR/xoay.sh"
#!/bin/bash
echo "Đang tạo $MAXCOUNT IPv6 > ipv6.txt"
gen_ipv6_64
echo "Đang tạo IPV6 gen_ifconfig.sh"
gen_ifconfig > "$WORKDIR/boot_ifconfig.sh"
echo "Khởi động lại 3proxy"
gen_3proxy_cfg > /etc/3proxy/3proxy.cfg
service 3proxy restart
echo "Đã đặt lại địa chỉ IP"
EOF
    chmod +x "$WORKDIR/xoay.sh"
}

# Kiểm tra quyền root và khởi động chính script
if [ "$(id -u)" != '0' ]; then
    echo 'Lỗi: Script này cần chạy với quyền root'
    exit 1
fi

# Các biến chính
WORKDIR="/home/proxy"
START_PORT=10000
MAXCOUNT=2000
mkdir -p "$WORKDIR"
chmod -R 777 "$WORKDIR"
auto_detect_interface
yum -y install gcc net-tools bsdtar zip psmisc wget >/dev/null

# Check and retrieve IPv4 and IPv6 addresses
if ping6 -c3 icanhazip.com &> /dev/null; then
    IP4=$(curl -4 -s icanhazip.com)
    IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
    main_interface=$(ip route get 8.8.8.8 | sed -nr 's/.*dev ([^\ ]+).*/\1/p')

    echo "[OKE]: Thành công"
    echo "IPV4: $IP4"
    echo "IPV6: $IP6"
    echo "Mạng chính: $main_interface"
else
    echo "[ERROR]: Thất bại!"
    exit 1
fi

IFCFG="$main_interface"

# Tạo địa chỉ IPv6 và cấu hình
echo "Đang tạo $MAXCOUNT IPv6 > ipv6.txt"
gen_ipv6_64
echo "Đang tạo IPV6 gen_ifconfig.sh"
gen_ifconfig > "$WORKDIR/boot_ifconfig.sh"

# Cài đặt 3proxy và cấu hình
install_3proxy
gen_3proxy_cfg > /etc/3proxy/3proxy.cfg
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

# Xuất cấu hình ra tập tin văn bản
echo "Xuất $IP4.txt"
export_txt > "$WORKDIR/$IP4.txt"

# Tạo script xoay để cập nhật địa chỉ IPv6
gen_xoay

echo "Cấu hình Xoay thành công"

cat <<EOF >/etc/rc.local
#!/bin/bash
systemctl start NetworkManager.service
ifup ${main_interface}
killall -s QUIT 3proxy
systemctl start 3proxy
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy.cfg &
EOF

# Đảm bảo script khởi động cùng hệ thống
chmod +x /etc/rc.local
bash /etc/rc.local

echo "Reset khởi động 3proxy..."

echo "Tổng số IPv6 hiện tại:"
ip -6 addr | grep inet6 | wc -l
