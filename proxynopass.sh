#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Lấy địa chỉ IPv6 của eth0, bỏ qua địa chỉ fe80::
ipv6_address=$(ip addr show eth0 | awk '/inet6/{print $2}' | grep -v '^fe80' | head -n1)

# Kiểm tra xem có địa chỉ IPv6 hay không
if [ -n "$ipv6_address" ]; then
    echo "IPv6 address obtained: $ipv6_address"

    # Lấy phần IPC và IPD từ địa chỉ IPv6
    IPC=$(echo "$ipv6_address" | cut -d":" -f5)
    IPD=$(echo "$ipv6_address" | cut -d":" -f6)

    # Tạo các mảng liên kết để lưu địa chỉ IPv6 và gateway
    declare -A ipv6_addresses=(
        [4]="2001:ee0:4f9b:$IPD::/64"
        [5]="2001:ee0:4f9b:$IPD::/64"
        [244]="2001:ee0:4f9b:$IPD::/64"
        ["default"]="2001:ee0:4f9b:$IPC::$IPD::/64"
    )

    declare -A gateways=(
        [4]="2001:ee0:4f9b:$IPC::1"
        [5]="2001:ee0:4f9b:$IPC::1"
        [244]="2001:ee0:4f9b:$IPC::1"
        ["default"]="2001:ee0:4f9b:$IPC::1"
    )

    # Xác định địa chỉ IPv6 và gateway dựa trên IPC
    IPV6_ADDRESS="${ipv6_addresses[$IPC]:-${ipv6_addresses["default"]}}"
    GATEWAY="${gateways[$IPC]:-${gateways["default"]}}"

    # Kiểm tra xem giao diện mạng có khả dụng không
    INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)

    if [ -n "$INTERFACE" ]; then
        echo "Configuring interface: $INTERFACE"

        # Cấu hình các thiết lập IPv6
        echo "auto $INTERFACE" >> /etc/network/interfaces
        echo "iface $INTERFACE inet6 static" >> /etc/network/interfaces
        echo "    address $IPV6_ADDRESS" >> /etc/network/interfaces
        echo "    gateway $GATEWAY" >> /etc/network/interfaces

        # Khởi động lại dịch vụ mạng
        service networking restart
        systemctl restart NetworkManager.service

        # Hiển thị thông tin giao diện mạng
        ifconfig "$INTERFACE"
        echo "Done Tao IPV6 !"
    else
        echo "No network interface available."
    fi
else
    echo "No IPv6 address obtained."
fi

random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

install_3proxy() {
    echo "installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.3.tar.gz"
    wget -qO- $URL | tar -xz
    cd 3proxy-0.9.3
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 4000
nserver 1.1.1.1
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
flush
auth none

$(awk -F "/" '{print "allow *\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

download_proxy() {
    cd $WORKDIR || return
    curl -F "file=@proxy.txt" https://file.io
}

cat << EOF > /etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
EOF

echo "installing apps"
yum -y install wget gcc net-tools bsdtar zip >/dev/null

install_3proxy

echo "Dang Thiet Lap Thu Muc"
WORKDIR="/home/proxy"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

FIRST_PORT=30000
LAST_PORT=29000

echo "$FIRST_PORT is $LAST_PORT. Continue..."

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
#!/bin/bash
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 20048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod 0755 /etc/rc.local
sudo systemctl start rc-local
sudo systemctl enable rc-local
bash /etc/rc.local

gen_proxy_file_for_user
rm -rf /root/3proxy-0.9.3
rm -rf proxynopass.sh
echo "Starting Proxy"

Tong Proxy Hien Tai:
ip -6 addr | grep inet6 | wc -l
download_proxy
