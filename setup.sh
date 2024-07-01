#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

auto_detect_interface() {
    IFCFG=$(ip -o link show | awk -F': ' '$3 !~ /lo|vir|^[^0-9]/ {print $2; exit}')
}
auto_detect_interface

setup_ipv6() {
    echo "Setting up IPv6..."
    ip -6 addr flush dev eth0
    ip -6 addr flush dev ens33
    curl -s "https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh" | bash
}

# Function to generate a random string
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Function to generate a random IPv6 address block
gen64() {
    ip64() {
        array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Function to install 3proxy from source
install_3proxy() {
    echo "Installing 3proxy..."
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz"
    wget -qO- $URL | tar -xz -C /tmp
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR  # Ensure this is set correctly before usage
    systemctl link /usr/lib/systemd/system/3proxy.service
    systemctl daemon-reload
    systemctl enable 3proxy

    # Increase system limits
    echo "* hard nofile 999999" >> /etc/security/limits.conf
    echo "* soft nofile 999999" >> /etc/security/limits.conf
    echo "fs.file-max = 1000000" >> /etc/sysctl.conf
    echo "net.ipv4.ip_local_port_range = 1024 65000" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_fin_timeout = 30" >> /etc/sysctl.conf
    echo "net.core.somaxconn = 4096" >> /etc/sysctl.conf
    echo "net.core.netdev_max_backlog = 4096" >> /etc/sysctl.conf
    echo "net.ipv6.conf.${IFCFG}.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.proxy_ndp=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv6.ip_nonlocal_bind = 1" >> /etc/sysctl.conf

    # Stop and disable firewalld
    systemctl stop firewalld
    systemctl disable firewalld

    # Apply sysctl settings
    sysctl -p
}

# Function to generate 3proxy configuration file
gen_3proxy_cfg() {
    cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
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
allow 14.224.163.75
allow 127.0.0.1

$(awk -F "/" '{print "proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\nflush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >$WORKDIR/proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4}' ${WORKDATA})
EOF
}

# Function to generate data.txt containing proxy configurations
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
        echo "$IP4:$port" >> "$WORKDIR/ipv4.txt"
        new_ipv6=$(gen64 $IP6)
        echo "$new_ipv6" >> "$WORKDIR/ipv6.txt"
    done
}

# Function to generate iptables rules in boot_iptables.sh
gen_iptables() {
    cat <<EOF > $WORKDIR/boot_iptables.sh
#!/bin/bash
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
    chmod +x $WORKDIR/boot_iptables.sh
}

# Function to generate ifconfig commands in boot_ifconfig.sh
gen_ifconfig() {
    cat <<EOF > $WORKDIR/boot_ifconfig.sh
#!/bin/bash
$(awk -F "/" '{print "ifconfig '${IFCFG}' inet6 add " $5 "/64"}' ${WORKDATA})
EOF
    chmod +x $WORKDIR/boot_ifconfig.sh
}

# Function to download proxy.txt file
download_proxy() {
    curl -F "file=$WORKDIR/proxy.txt" https://file.io
}

cat << EOF > /etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
EOF

install_3proxy

# Install necessary packages
echo "Installing necessary packages..."
yum -y install wget gcc net-tools bsdtar zip

rotate_ipv6() {
    gen_data > $WORKDIR/data.txt
    gen_iptables
    gen_ifconfig
    gen_3proxy_cfg
    bash $WORKDIR/boot_iptables.sh
    bash $WORKDIR/boot_ifconfig.sh
    echo "Restarting Proxy .."
    systemctl restart 3proxy
    restart_result=$?

    if [ $restart_result -eq 0 ]; then
        echo "IPv6 IPv6 Xoay rotated successfully."
        echo "[OK]: Thành công"
    else
        echo "Failed to Xoay IPv6 new..!"
        echo "[ERROR]: Thất bại!"
        exit 1
    fi
}
}

# Install and configure 3proxy
WORKDIR="/home/proxy"
mkdir -p $WORKDIR && cd $WORKDIR

# Get external IPv4 and IPv6 addresses
IP4=$(curl -4 -s icanhazip.com)
IP6=$(ip addr show $IFCFG | grep 'inet6 ' | awk '{print $2}' | cut -f1-4 -d':' | grep '^2')

echo "IPv4 = ${IP4}"
echo "IPv6 = ${IP6}"

# Set proxy ports range and generate data.txt
FIRST_PORT=40000
LAST_PORT=40044

echo "Proxy ports range: $FIRST_PORT - $LAST_PORT"
echo "Number of proxies: $(($LAST_PORT - $FIRST_PORT + 1))"

gen_data > $WORKDIR/data.txt
gen_iptables > $WORKDIR/boot_iptables.sh
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh

# Cập nhật tập tin rc.local để khởi động các dịch vụ và cấu hình khi hệ thống khởi động
cat >>/etc/rc.local <<EOF
systemctl start NetworkManager.service
killall 3proxy
service 3proxy start
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
EOF

# Create systemd service file for 3proxy
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

# Create systemd service file for rc.local if not exists
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
systemctl disable --now firewalld
service iptables stop

chmod +x /etc/rc.d/rc.local
bash /etc/rc.d/rc.local

# Generate proxy.txt file for user
gen_proxy_file_for_user
rm -rf /root/3proxy-0.9.4

echo “Starting Proxy”

echo “Total current IPv6 addresses:”
ip -6 addr | grep inet6 | wc -l
download_proxy

Rotate IPv6 addresses every hour (3600 seconds)

while true; do
rotate_ipv6
sleep 3600
done
