#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Cấu hình ban đầu
WORKDIR="/home/vlt"
IPV6_FILE="${WORKDIR}/ipv6.txt"
START_PORT=30000
NUM_PORTS=1000

# Hàm tạo IPv6 ngẫu nhiên
gen64() {
    array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Cài đặt 3proxy
install_3proxy() {
    echo "Installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.8.13.tar.gz"
    wget -qO- $URL | tar -xz
    cd 3proxy-0.8.13
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

# Hàm tạo cấu hình 3proxy
gen_3proxy() {
    cat <<EOF
daemon
maxconn 4000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 60000
auth iponly strong cache
allow * * 127.0.0.0/8
allow 14.224.163.75
deny * * *
flush
EOF
}

# Địa chỉ IPv4 mặc định
IPV4=$(curl -4 -s icanhazip.com)
IPV6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

# Số lượng cổng
NUM_PORTS=1000

# Tên tệp chứa địa chỉ IPv6
IPV6_FILE="ipv6.txt"
# Tệp lưu trữ phụ
IPV6_USED_FILE="ipv6_used.txt"

# Tạo 1000 cổng từ 10000 đến 10999
START_PORT=10000
END_PORT=$((START_PORT + NUM_PORTS - 1))

# Kiểm tra nếu tệp lưu trữ phụ không tồn tại, tạo nó
if [ ! -e "$IPV6_USED_FILE" ]; then
    touch "$IPV6_USED_FILE"
fi

# Hàm để đảo ngược lại các địa chỉ IPv6 đã sử dụng và ghi đè lên tệp IPv6
rotate_ipv6() {
    echo "Đảo ngược lại các địa chỉ IPv6 đã sử dụng..."
    tac "$IPV6_USED_FILE" > "$IPV6_FILE"
    cp /dev/null "$IPV6_USED_FILE"
}

# Vòng lặp để tạo cổng và cung cấp IPv6 từ tệp
for ((port = START_PORT; port <= END_PORT; port++)); do
    # Đọc IPv6 từ tệp
    IPV6=$(sed -n "${port}p" $IPV6_FILE)

    # Kiểm tra nếu hết IPv6 trong tệp, đảo ngược lại các địa chỉ IPv6 đã sử dụng và đặt con trỏ về đầu tệp
    if [ -z "$IP6" ]; then
        echo "Hết địa chỉ IPv6 trong tệp. Đảo ngược lại các địa chỉ IPv6 đã sử dụng và đặt con trỏ về đầu tệp."
        rotate_ipv6
        IPV6=$(sed -n "${port}p" $IPV6_FILE)
    fi

    # Lưu IPv6 đã sử dụng vào tệp lưu trữ phụ
    echo "$IPV6" >> "$IPV6_USED_FILE"

    # In ra thông tin cổng và cặp IPv4/IPv6
    echo "Cổng: $port - IPv4: $IPV4, IPv6: $IPV6"

    # Thực hiện các thao tác khác ở đây, chẳng hạn như tạo lệnh proxy cho mỗi cổng
    # Ví dụ:
    # proxy_command="proxy -6 -n -a -ocUSE_TCP_FASTOPEN -p$port -i$IPV4 -e$IPV6"
    # $proxy_command
done

# Hàm tạo địa chỉ IPv6
gen_ipv6() {
    network=$1
    count=$2
    for i in $(seq 1 $count); do
        echo "$(gen64 $network)" >> $IPV6_FILE
    done
}

# Hàm tạo iptables rules
gen_iptables() {
    cat <<EOF
$(awk -v start_port="$START_PORT" -v num_ports="$NUM_PORTS" 'BEGIN {for (port=start_port; port<start_port+num_ports; port++) print "iptables -I INPUT -p tcp --dport " port "  -m state --state NEW -j ACCEPT"}')
EOF
}

# Hàm tạo cấu hình ifconfig
gen_ifconfig() {
    cat <<EOF
$(awk -v iface="eth0" '{print "ifconfig " iface " inet6 add " $1 "/64"}' ${IPV6_FILE})
EOF
}

# Hàm tải xuống proxy
download_proxy() {
    cd $WORKDIR || exit 1
    curl -F "proxy=@proxy.txt" https://transfer.sh
}

# Hàm tạo tệp proxy cho người dùng chỉ với IPv4:port mới
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Hàm xoay địa chỉ IPv6
rotate_ipv6() {
    echo "Rotating IPv6 addresses..."
    mv "$IPV6_FILE" "$IPV6_FILE.temp"
    tail -n +2 "$IPV6_FILE.temp" > "$IPV6_FILE"
    head -n 1 "$IPV6_FILE.temp" >> "$IPV6_FILE"
    rm "$IPV6_FILE.temp"
    gen_ifconfig > $WORKDIR/boot_ifconfig.sh
    bash $WORKDIR/boot_ifconfig.sh
    service network restart
}

# Cài đặt 3proxy và cấu hình
echo "Working folder = /home/vlt"
WORKDIR="/home/vlt"
IPV6_FILE="${WORKDIR}/ipv6.txt"
START_PORT=30000
NUM_PORTS=1000

install_3proxy

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg
gen_iptables > $WORKDIR/boot_iptables.sh
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod +x /etc/rc.local
bash /etc/rc.local

gen_proxy_file_for_user

echo "Starting Proxy"
echo "So Luong IPv6 Hien Tai:"
ip -6 addr | grep inet6 | wc -l

# Menu loop
while true; do
    echo "1. Thiết Lập Lại 3proxy"
    echo "2. Xoay IPv6"
    echo "3. Download proxy"
    echo "4. Tạo ipv6.txt với 10000 địa chỉ IPv6"
    echo "5. Exit"
    echo -n "Enter your choice: "
    read -r choice
    case $choice in
        1)
            install_3proxy
            gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg
            gen_iptables > $WORKDIR/boot_iptables.sh
            gen_ifconfig > $WORKDIR/boot_ifconfig.sh
            bash /etc/rc.local
            ;;
        2)
            rotate_ipv6
            ;;
        3)
            download_proxy
            ;;
        4)
            echo -n "Enter IPv6 network prefix (e.g., 2001:db8::): "
            read -r network
            gen_ipv6 $network 10000
            echo "Generated 10000 IPv6 addresses in $IPV6_FILE"
            ;;
        5)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
done
