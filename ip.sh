#!/bin/bash

# Kiểm tra và cài đặt curl trên CentOS 7
if ! yum list installed curl &>/dev/null; then
    yum install -y curl
fi

# Kiểm tra và cài đặt curl trên Ubuntu
if ! dpkg -s curl &>/dev/null; then
    apt-get update
    apt-get install -y curl
fi

# Cài đặt IPv6 cho CentOS 7
if [ -f /etc/redhat-release ]; then
    echo > /etc/sysctl.conf
    cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
EOF
    sysctl -p

    INTERFACE=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
    IP=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    IPV6_PREFIX="2403:6a40:0:40"
    IPV6_ADDRESS="$IP::1/64"
    IPV6_GATEWAY="$IPV6_PREFIX::1"

    cat <<EOF >> /etc/sysconfig/network-scripts/ifcfg-$INTERFACE
IPV6INIT=yes
IPV6_AUTOCONF=no
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
IPV6ADDR=$IPV6_ADDRESS
IPV6_DEFAULTGW=$IPV6_GATEWAY
EOF

    service network restart
fi

# Cài đặt IPv6 cho Ubuntu
if [ -f /etc/lsb-release ]; then
    IPV4=$(curl -4 -s icanhazip.com)
    INTERFACE=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
    IPC=$(echo $IPV4 | cut -d"." -f3)
    IPD=$(echo $IPV4 | cut -d"." -f4)

    if [ "$IPC" = "4" ]; then
        IPV6_ADDRESS="2403:6a40:0:40::$IPD:0000/64"
        GATEWAY="2403:6a40:0:40::1"
    elif [ "$IPC" = "5" ]; then
        IPV6_ADDRESS="2403:6a40:0:41::$IPD:0000/64"
        GATEWAY="2403:6a40:0:41::1"
    elif [ "$IPC" = "244" ]; then
        IPV6_ADDRESS="2403:6a40:2000:244::$IPD:0000/64"
        GATEWAY="2403:6a40:2000:244::1"
    else
        IPV6_ADDRESS="2403:6a40:0:$IPC::$IPD:0000/64"
        GATEWAY="2403:6a40:0:$IPC::1"
    fi

    cat <<EOF >> /etc/netplan/99-netcfg-vmware.yaml
  - $IPV6_ADDRESS
  gateway6: $GATEWAY
EOF
    netplan apply
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
# Cài đặt proxy
echo "installing 3proxy"
URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
wget -qO- $URL | bsdtar -xvf-
cd 3proxy-3proxy-0.8.6
make -f Makefile.Linux
mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
cp src/3proxy /usr/local/etc/3proxy/bin/
install_3proxy() {
    echo "Installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | tar -xzf-
    cd 3proxy-3proxy-0.8.6
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
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
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

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1}' ${WORKDATA})
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

rotate_proxy() {
    echo "Rotating proxy"
    gen_data >$WORKDIR/data.txt
    gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg
    systemctl restart 3proxy
}

echo "Installing required packages"
yum -y install gcc net-tools bsdtar zip >/dev/null

install_3proxy

echo "Setting working directory = /home/proxy"
WORKDIR="/home/proxy"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External sub for IP6 = ${IP6}"

FIRST_PORT=22000
LAST_PORT=22700

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

bash /etc/rc.local

gen_proxy_file_for_user
rm -rf /root/setup.sh
rm -rf /root/3proxy-3proxy-0.8.6

echo "Starting Proxy"

# Setup cron job for rotating proxy every 10 minutes
(crontab -l 2>/dev/null; echo "*/10 * * * * /home/bkns/rotate_proxy.sh") | crontab -
echo "Proxy rotation setup complete"
