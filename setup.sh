#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Thiết lập IPv6
setup_ipv6() {
    echo "Thiết lập IPv6..."
    ip -6 addr flush dev eth0
    ip -6 addr flush dev ens33
        bash <(curl -s "https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh")
    yum install make wget curl jq git iptables-services -y
}
setup_ipv6

# Tự động phát hiện giao diện mạng
auto_detect_interface() {
    IFCFG=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')
}

# Tạo địa chỉ IPv6 và cấu hình iptables
gen_ipv6_64() {
    rm "$WORKDIR/ipv6.txt" 2>/dev/null || true
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
    echo "Đang cài đặt 3proxy..."
    git clone https://github.com/z3apa3a/3proxy
    cd 3proxy || exit 1
    ln -s Makefile.Linux Makefile >/dev/null 2>&1
    make >/dev/null 2>&1
    sudo make install >/dev/null 2>&1
    cd "$WORKDIR" || exit 1
    sudo cp -R 3proxy/scripts/init.d/3proxy /etc/init.d/
    sudo chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    service 3proxy start
    systemctl stop firewalld
    systemctl disable firewalld
    ulimit -n 65535
    systemctl daemon-reload
    systemctl enable 3proxy
    systemctl start 3proxy
    echo "fs.file-max = 1000000" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.ip_local_port_range = 1024 65000" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_fin_timeout = 30" | sudo tee -a /etc/sysctl.conf
    echo "net.core.somaxconn = 4096" | sudo tee -a /etc/sysctl.conf
    echo "net.core.netdev_max_backlog = 4096" | sudo tee -a /etc/sysctl.conf
    echo "* hard nofile 999999" | sudo tee -a /etc/security/limits.conf
    echo "* soft nofile 999999" | sudo tee -a /etc/security/limits.conf
    sudo sed -i "/Description=/c\Description=3 Proxy optimized by VLT PRO" /etc/sysctl.conf
    sudo sed -i "/LimitNOFILE=/c\LimitNOFILE=9999999" /etc/sysctl.conf
    sudo sed -i "/LimitNPROC=/c\LimitNPROC=9999999" /etc/sysctl.conf
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

# Kiểm tra và lấy địa chỉ IPv4 và IPv6
if ping -4 icanhazip.com &> /dev/null; then
    IP4=$(curl -4 -s icanhazip.com)
    IP6=$(ip addr show dev "${IFCFG}" | sed -e's/^.*inet6 \([^ ]*\)\/.*$/\1/;t;d' | head -1 | cut -f1-4 -d':')
    echo "[OKE]: Thành công"
    echo "IPv4: ${IP4}"
    echo "IPv6: ${IP6}"
    echo "Giao diện mạng chính: ${IFCFG}"
    echo "Cổng proxy: $START_PORT"
    echo "Số Lượng Tạo: $MAXCOUNT"
else
    echo "[ERROR]: Thất bại!"
    exit 1
fi

# Tạo địa chỉ IPv6 và cấu hình
echo "Đang tạo $MAXCOUNT IPv6 > ipv6.txt"
gen_ipv6_64
echo "Đang tạo IPV6 gen_ifconfig.sh"
gen_ifconfig > "$WORKDIR/boot_ifconfig.sh"
chmod +x "$WORKDIR/boot_ifconfig.sh"

# Cài đặt 3proxy và cấu hình
install_3proxy
gen_3proxy_cfg > /etc/3proxy/3proxy.cfg
service 3proxy restart

# Xuất cấu hình ra tập tin văn bản
echo "Xuất $IP4.txt"
export_txt > "$WORKDIR/$IP4.txt"

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
gen_xoay

echo "Cấu hình Xoay thành công"

cat <<EOF >/etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=/bin/kill -TERM \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Create rc.local service file if it doesn't exist
cat <<EOF >/etc/systemd/system/rc-local.service
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

Create rc.local file if it doesn’t exist

cat </etc/rc.local
#!/bin/bash
systemctl start NetworkManager.service
killall 3proxy
service 3proxy start
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg &
EOF

Đảm bảo script khởi động cùng hệ thống

chmod +x /etc/rc.local
bash /etc/rc.local

echo “Starting Proxy”

echo “Tổng số IPv6 hiện tại:”
ip -6 addr | grep inet6 | wc -l
