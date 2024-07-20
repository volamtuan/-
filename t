#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

WORKDIR="/proxy"
WORKDATA="${WORKDIR}/data.txt"

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

install_dependencies() {
    OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
    echo "Detected OS: $OS"
    
    if [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"AlmaLinux"* ]]; then
        yum update -y
        yum install -y wget gcc make net-tools
    elif [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]] || [[ "$OS" == *"AlmaLinux"* ]]; then
        apt-get update -y
        apt-get install -y wget gcc make net-tools
    else
        echo "Unsupported OS. Exiting."
        exit 1
    fi
}

install_3proxy() {
    echo "installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.8.13.tar.gz"
    wget -qO- $URL | tar -xzf-
    cd $WORKDIR/3proxy-0.8.13
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 65536
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

$(awk -F "/" '{print "" \
"allow * * 192.168.1.0/24 * * * *" $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"proxy -n -a -p" $4 " -i" $3 "\n" \
"bandlimout 10000000 20000000 $4\n" \  # Set bandwidth limit for each port (Example: 10MBps in and 20MBps out)
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 }' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
    done
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Cấu hình hệ thống để khởi động lại proxy khi bị tắt
setup_proxy_restart() {
    cat <<EOF > /etc/systemd/system/3proxy.service
[Unit]
Description=3Proxy Proxy Server
After=network.target

[Service]
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable 3proxy.service
    systemctl start 3proxy.service
}

echo "installing dependencies"
install_dependencies

echo "installing apps"
install_3proxy

echo "working folder = $WORKDIR"
mkdir -p $WORKDIR && cd $WORKDIR

IP4=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External sub for IP6 = ${IP6}"

FIRST_PORT=10000
LAST_PORT=65536

gen_data >$WORKDIR/data.txt
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65536
EOF

chmod +x /etc/rc.local

if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
    systemctl enable rc-local
    systemctl start rc-local
else
    systemctl enable rc.local
    systemctl start rc.local
fi

gen_proxy_file_for_user

# Thiết lập proxy tự khởi động lại nếu bị tắt
setup_proxy_restart

rm -rf /root/setup.sh
rm -rf /root/3proxy-0.8.13

echo "Starting Proxy"
