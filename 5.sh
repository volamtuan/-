#!/usr/local/bin/bash

auto_detect_interface() {
    IFCFG=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')
}

# Function to generate IPv6 addresses and configure iptables
gen_ipv6_64() {
    rm $WORKDIR/ipv6.txt
    count_ipv6=1
    while [ "$count_ipv6" -le $MAXCOUNT ]; do
        array=( 1 2 3 4 5 6 7 8 9 0 a b c d e f )
        ip64() {
            echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
        }
        echo $IP6:$(ip64):$(ip64):$(ip64):$(ip64) >> $WORKDIR/ipv6.txt
        let "count_ipv6 += 1"
    done
}

# Function to install and configure 3proxy
install_3proxy() {
    echo "Installing 3proxy..."
    sudo yum install gcc make nano git -y
    git clone https://github.com/z3apa3a/3proxy
    cd 3proxy
    ln -s Makefile.Linux Makefile
    make
    sudo make install
    systemctl daemon-reload
    echo "* hard nofile 999999" >> /etc/security/limits.conf
    echo "* soft nofile 999999" >> /etc/security/limits.conf
    systemctl stop firewalld
    systemctl disable firewalld
    ulimit -n 65535
    chkconfig 3proxy on
    cd $WORKDIR
}

# Function to generate 3proxy configuration
gen_3proxy_cfg() {
    echo "daemon"
    echo "maxconn 10000"
    echo "nserver 1.1.1.1"
    echo "nserver [2606:4700:4700::1111]"
    echo "nserver [2606:4700:4700::1001]"
    echo "nserver [2001:4860:4860::8888]"
    echo "nscache 65536"
    echo "timeouts 1 5 30 60 180 1800 15 60"
    echo "setgid 65535"
    echo "setuid 65535"
    echo "stacksize 6291456"
    echo "flush"
    echo "auth none"
    echo "allow *"
    port=$START_PORT
    while read ip; do
        echo "proxy -6 -n -a -p$port -i$IP4 -e$ip"
        ((port+=1))
    done < $WORKDIR/ipv6.txt
}

# Function to generate ifconfig commands for IPv6
gen_ifconfig() {
    while read line; do
        echo "ifconfig $IFCFG inet6 add $line/64"
    done < $WORKDIR/ipv6.txt
}

# Function to export configuration to text file
export_txt() {
    port=$START_PORT
    for ((i=1; i<=$MAXCOUNT; i++)); do
        echo "$IP4:$port"
        ((port+=1))
    done
}

# Main script starts here
if [ "x$(id -u)" != 'x0' ]; then
    echo 'Error: this script can only be executed by root'
    exit 1
fi

# Main variables
mkdir -p /home/xpx/vivucloud
chmod -R 777 /home/xpx/vivucloud
install_3proxy
service network restart
systemctl stop firewalld
ulimit -n 65535
yum -y install gcc net-tools bsdtar zip psmisc wget >/dev/null

# Check and retrieve IPv4 and IPv6 addresses
if ping6 -c3 icanhazip.com &> /dev/null; then
    IP4=$(curl ifconfig.me)
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
WORKDIR="/home/xpx/vivucloud"
START_PORT=50000
MAXCOUNT=1000

# Generate IPv6 addresses and configurations
echo "Đang tạo $MAXCOUNT IPV6 > ipv6.txt"
gen_ipv6_64
echo "Đang tạo IPV6 gen_ifconfig.sh"
gen_ifconfig > $WORKDIR/boot_ifconfig.sh

# Setup 3proxy and iptables
systemctl disable --now firewalld
service iptables stop
gen_3proxy_cfg > /etc/3proxy/3proxy.cfg
killall 3proxy
service 3proxy start

# Export configuration to text file
echo "Export $IP4.txt"
export_txt > $IP4.txt

# Function to upload proxy text file
upload_proxy() {
    URL=$(curl -s --upload-file $IP4.txt https://transfer.sh/$IP4.txt)
    echo "Tạo Proxy thành công! Định dạng IP:PORT"
    echo "Tải Proxy tại: ${URL}"
}
upload_proxy

# Function to generate rotation script
gen_xoay() {
    cat <<EOF > /home/xpx/vivucloud/xoay.sh
#!/usr/bin/bash
echo "Đang tạo $MAXCOUNT IPV6 > ipv6.txt"
gen_ipv6_64
echo "Đang tạo IPV6 gen_ifconfig.sh"
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
echo "3proxy Start"
gen_3proxy_cfg > /etc/3proxy/3proxy.cfg
killall 3proxy
service 3proxy start
echo "Đã Reset IP"
EOF
    chmod +x /home/xpx/vivucloud/xoay.sh
}
gen_xoay

echo "Tạo cấu hình xoay.sh"
echo "1.sh done"

# Tạo file cấu hình cho dịch vụ 3proxy
cat <<EOF > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
RestartSec=5   # Thời gian chờ giữa các lần khởi động lại (tùy chọn)
ExecStop=/bin/kill -SIGINT \$MAINPID   # Lệnh dừng dịch vụ 3proxy

[Install]
WantedBy=multi-user.target
EOF

# Tải lại systemctl
systemctl daemon-reload

# Bật dịch vụ 3proxy và cài đặt tự động khởi động cùng hệ thống
systemctl enable 3proxy
systemctl start 3proxy
