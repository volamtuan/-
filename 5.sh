#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

setup_ipv6() {
    echo "Thiết lập IPv6..."
    sudo service 3proxy stop
    ip -6 addr flush dev eth0
    sudo systemctl stop firewalld
    sudo systemctl disable firewalld
    bash <(curl -s "https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh") 
}
setup_ipv6

random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Hàm sinh IPv6 ngẫu nhiên
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Cài đặt 3proxy

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

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
    echo "Installing 3proxy..."
    URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf- >/dev/null 2>&1
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux >/dev/null 2>&1
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat} >/dev/null 2>&1
    cp src/3proxy /usr/local/etc/3proxy/bin/ >/dev/null 2>&1
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 10048
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
authcache user 86400
auth none cache
auth iponly cache
allow 14.224.163.75
deny *

$(awk -F "/" '{print "\n" \
"allow *" $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Sinh file proxy cho người dùng
gen_proxy_file_for_user() {
    awk -F "/" '{print $3 ":" $4}' ${WORKDATA} > proxy.txt
}

# Định nghĩa hàm gen_ifconfig để sinh lệnh ifconfig
gen_ifconfig() {
    awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA}
}

cat << EOF > /etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
EOF

echo "Đang cài đặt các ứng dụng cần thiết..."
yum -y install wget gcc net-tools bsdtar zip >/dev/null 2>&1

install_3proxy

# Thiết lập biến làm việc
WORKDIR="/home/vlt"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $_

# Lấy địa chỉ IPv4 và IPv6
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Địa chỉ IP nội bộ = ${IP4}. Địa chỉ IP6 ngoài mạng = ${IP6}"

# Thiết lập cổng proxy và số lượng proxy
FIRST_PORT=11111
LAST_PORT=14444

echo "Cổng proxy đầu tiên: $FIRST_PORT"
echo "Số lượng proxy được tạo: $(($LAST_PORT - $FIRST_PORT + 1))"

# Sinh dữ liệu và cấu hình
echo "Đang sinh dữ liệu..."
gen_data > $WORKDIR/data.txt
echo "Đang sinh lệnh ifconfig..."
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

# Sinh cấu hình 3proxy
echo "Đang sinh cấu hình 3proxy..."
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod +x /etc/rc.local
bash /etc/rc.local

# Xóa thư mục tạm của 3proxy
echo "Đang xóa thư mục tạm của 3proxy..."
rm -rf /root/3proxy-3proxy-0.8.6
rm -rf 5.sh
# Sinh file proxy cho người dùng
echo "Đang sinh file proxy cho người dùng..."
gen_proxy_file_for_user

echo "Khởi động Proxy..."

echo "Tổng số IPv6 hiện tại:"
ip -6 addr | grep inet6 | wc -l
