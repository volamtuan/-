#!/bin/bash

# Kiểm tra sự tồn tại của gói quản lý gói yum
YUM=$(which yum)

# Kiểm tra xem hệ thống có sử dụng yum không
if [ "$YUM" ]; then
    # Cài đặt gói cấu hình sysctl để cấu hình IPv6
    echo > /etc/sysctl.conf
    tee -a /etc/sysctl.conf <<EOF
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
EOF
    sysctl -p

    # Lấy phần cuối của địa chỉ IP
    IPC=$(curl -4 -s icanhazip.com | cut -d"." -f3)
    IPD=$(curl -4 -s icanhazip.com | cut -d"." -f4)

    # Thiết lập cấu hình cho card mạng eth0 dựa trên địa chỉ IP cuối cùng
    tee -a /etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
IPV6ADDR=2403:6a40:0:$IPC::$IPD:0000/64
IPV6_DEFAULTGW=2403:6a40:0:$IPC::1
EOF
    # Khởi động lại dịch vụ mạng
    service network restart
fi

# Cài đặt gói cần thiết
echo "Cài đặt các ứng dụng cần thiết"
yum -y install gcc net-tools bsdtar zip >/dev/null

# Hàm cài đặt 3proxy
install_3proxy() {
    echo "Cài đặt 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

# Hàm sinh dữ liệu người dùng
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "user$port/$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# Hàm tạo file proxy.txt để tải proxy
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Hàm sinh chuỗi ngẫu nhiên
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Mảng các ký tự hex để sinh địa chỉ IPv6
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Hàm sinh địa chỉ IPv6
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Hàm tạo cấu hình 3proxy
gen_3proxy() {
    cat <<EOF
daemon
maxconn 4000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2403:4860:4860::8888
nserver 2403:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
authcache ip 999999
auth iponly
allow 14.224.163.75
deny *

$(awk -F "/" '{print "auth iponly\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush"}' ${WORKDATA})
EOF
}

# Hàm cấu hình tường lửa
gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

# Hàm thêm địa chỉ IPv6 vào card mạng
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Thực hiện cài đặt 3proxy
install_3proxy

# Khởi tạo thư mục làm việc
WORKDIR="/home/proxy"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

# Lấy địa chỉ IPv4 và IPv6
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External sub for IP6 = ${IP6}"

# Sinh dữ liệu người dùng và cấu hình tường lửa
FIRST_PORT=20000
LAST_PORT=22000

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

# Tạo cấu hình cho 3proxy
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Thêm vào file rc.local để tự động khởi động
cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

# Khởi động lại dịch vụ
bash /etc/rc.local

# Xóa các file không cần thiết
gen_proxy_file_for_user
rm -rf /root/setup.sh
rm -rf /root/3proxy-3proxy-0.8.6

# Khởi động proxy
echo "Khởi động proxy"

# Setup cron job for rotating proxy every 10 minutes
(crontab -l 2>/dev/null; echo "*/10 * * * * /home/bkns/rotate_proxy.sh") | crontab -
echo "Proxy rotation setup complete"
