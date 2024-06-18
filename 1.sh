#!/bin/sh

# Thiết lập thư mục làm việc và file dữ liệu
WORKDIR="/home/cloudfly"
WORKDATA="${WORKDIR}/data.txt"
rotate_count=0

# Mảng các ký tự hex để tạo IPv6 ngẫu nhiên
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Hàm tạo dải IPv6 ngẫu nhiên
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Hàm tạo dữ liệu proxy
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
    done
}

gen_proxy_file_for_user() {
    awk -F "/" '{print $3 ":" $4}' ${WORKDATA} > proxy.txt
}

# Hàm tạo cấu hình ifconfig
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

download_proxy() {
    cd $WORKDIR || exit 1
    curl -F "proxy.txt" https://transfer.sh
}

# Hàm tạo file cấu hình 3proxy
gen_3proxy_cfg() {
    cat <<EOF
daemon
maxconn 5000
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
auth none
allow 127.0.0.1
allow $IP4

$(awk -F "/" '{print "proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\nflush\n"}' ${WORKDATA})
EOF
}

# Hàm xoay IPv6
rotate_ipv6() {
    echo "Dang Xoay IPv6"
    IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
    gen_data > $WORKDIR/data.txt
    gen_ifconfig > "$WORKDIR/boot_ifconfig.sh"
    bash "$WORKDIR/boot_ifconfig.sh"
    gen_3proxy_cfg > /usr/local/etc/3proxy/3proxy.cfg
    killall 3proxy
    /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
    echo "IPv6 Xoay Rotated successfully."
    rotate_count=$((rotate_count + 1))
    echo "Xoay IP Tu Dong: $rotate_count"
    sleep 3600
}

# Hàm cài đặt 3proxy
install_3proxy() {
    echo "Cài đặt 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.3.tar.gz"
    wget -qO- $URL | tar -xz
    cd 3proxy-0.9.3
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

# Hàm cài đặt các ứng dụng cần thiết
install_dependencies() {
    echo "Cài đặt các ứng dụng cần thiết"
    yum -y install wget gcc net-tools bsdtar zip >/dev/null
}

# Hàm thiết lập cấu hình khởi động lại hệ thống
setup_rc_local() {
    cat <<EOF >/etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF
    chmod +x /etc/rc.local
}

# Thiết lập các biến ban đầu
FIRST_PORT=40000
LAST_PORT=40444
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

# Kích hoạt IPv6
echo "Kích hoạt IPv6"
sysctl -w net.ipv6.conf.all.disable_ipv6=0
sysctl -w net.ipv6.conf.default.disable_ipv6=0
sysctl -w net.ipv6.conf.lo.disable_ipv6=0

# Cập nhật sysctl.conf để duy trì sau khi khởi động lại
cat <<EOF >>/etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
EOF

# Thiết lập thư mục làm việc
mkdir -p $WORKDIR && cd $WORKDIR

# Cài đặt các ứng dụng và 3proxy
install_dependencies
install_3proxy

# Tạo dữ liệu và cấu hình ban đầu
gen_data > $WORKDIR/data.txt
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
setup_rc_local
gen_3proxy_cfg > /usr/local/etc/3proxy/3proxy.cfg

# Khởi động 3proxy lần đầu
chmod +x /etc/rc.local
bash /etc/rc.local

# Xoay IPv6 định kỳ
while true; do
    rotate_ipv6
done

gen_proxy_file_for_user

echo "Starting Proxy"
echo "So Luong IPv6 Hien Tai:"
ip -6 addr | grep inet6 | wc -l
download_proxy
