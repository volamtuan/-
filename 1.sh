#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

setup_ipv6() {
    echo "Thiết lập IPv6..."
    ip -6 addr flush dev eth0
    ip -6 addr flush dev ens33
    bash <(curl -s "https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh")
}
setup_ipv6

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
    echo "Installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf- >/dev/null 2>&1
    cd /root/3proxy-3proxy-0.8.6 || exit 1
    make -f Makefile.Linux >/dev/null 2>&1
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat} >/dev/null 2>&1
    cp src/3proxy /usr/local/etc/3proxy/bin/ >/dev/null 2>&1
    cd /root || exit 1
}

gen_3proxy() {
    cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 10000
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

gen_proxy_file_for_user() {
    awk -F "/" '{print $3 ":" $4}' ${WORKDATA} > proxy.txt
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read -r port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA}
}

gen_ifconfig() {
    awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA}
}

echo "Installing apps"
sudo yum -y install curl wget gcc net-tools bsdtar zip >/dev/null 2>&1

install_3proxy

WORKDIR="/home/proxy"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR || exit 1

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "IPv4 = ${IP4}"
echo "IPv6 = ${IP6}"

FIRST_PORT=10000
LAST_PORT=22222

echo "Cổng proxy: $FIRST_PORT"
echo "Số lượng: $(($LAST_PORT - $FIRST_PORT + 1))"

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

gen_3proxy

cat <<EOF >>/etc/rc.local
#!/bin/bash
systemctl start NetworkManager.service
killall 3proxy
service 3proxy start
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
EOF

# Tăng giới hạn file descriptor
echo "* hard nofile 999999" | sudo tee -a /etc/security/limits.conf
echo "* soft nofile 999999" | sudo tee -a /etc/security/limits.conf

# Cấu hình sysctl để hỗ trợ IPv6
sudo tee -a /etc/sysctl.conf <<EOF
net.ipv6.conf.ens3.proxy_ndp=1
net.ipv6.conf.all.proxy_ndp=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
net.ipv6.ip_nonlocal_bind = 1
EOF

# Thiết lập mô tả cho 3proxy
sudo sed -i "/Description=/c\Description=3 Proxy optimized by VLT PRO" /etc/systemd/system/3proxy.service

# Thiết lập giới hạn file descriptor và process
sudo tee -a /etc/systemd/system/3proxy.service <<EOF
LimitNOFILE=9999999
LimitNPROC=9999999
EOF

# Áp dụng các thay đổi sysctl
sudo sysctl -p
chmod +x /etc/rc.local
bash /etc/rc.local

gen_proxy_file_for_user
rm -rf /root/3proxy-3proxy-0.8.6

echo "Starting Proxy"

echo "Tổng số IPv6 hiện tại:"
ip -6 addr | grep inet6 | wc -l

