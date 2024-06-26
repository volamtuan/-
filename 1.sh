#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

setup_ipv6() {
    echo "Thiết lập IPv6..."
    ip -6 addr flush dev eth0
    ip -6 addr flush dev ens33
    bash <(curl -s "https://raw.githubusercontent.com/volamtuan/-/main/set.sh") 
}

setup_ipv6

# Function to generate random characters
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Function to generate IPv6 addresses
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Function to install 3proxy
install_3proxy() {
    echo "Installing 3proxy..."
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz"
    wget -qO- $URL | tar xz
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd ..
    rm -rf 3proxy-0.9.4
}

# Function to generate 3proxy configuration
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

$(awk -F "/" '{print "auth none\n" \
"allow *" $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Function to generate proxy file for users
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 }' ${WORKDATA})
EOF
}

# Function to generate data for 3proxy
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IPV4_ADDR/$port/$(gen64 $IPV6_ADDR)"
    done
}

# Function to generate iptables rules
gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

# Function to generate ifconfig commands
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Main script starts here

echo "Installing required packages..."
yum -y install curl wget gcc net-tools tar zip >/dev/null

install_3proxy

echo "Setting up working directory..."
WORKDIR="/home/proxy"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

IPV4_ADDR=$(curl -4 -s icanhazip.com)
IPV6_ADDR=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IPv4 Address = $IPV4_ADDR"
echo "External IPv6 Address = $IPV6_ADDR"

FIRST_PORT=30000
LAST_PORT=40000

# Generate data file for 3proxy
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.d/rc.local

# Generate 3proxy configuration
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Append startup commands to rc.local
cat >>/etc/rc.d/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod +x /etc/rc.d/rc.local
bash /etc/rc.d/rc.local

# Generate proxy file for users
gen_proxy_file_for_user
echo "Proxy setup complete"
# Bổ sung lệnh để tăng giới hạn file descriptor
echo "* hard nofile 999999" | sudo tee -a /etc/security/limits.conf
echo "* soft nofile 999999" | sudo tee -a /etc/security/limits.conf

# Cấu hình sysctl để hỗ trợ IPv6
echo "net.ipv6.conf.ens3.proxy_ndp=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.proxy_ndp=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.forwarding=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.ip_nonlocal_bind = 1" | sudo tee -a /etc/sysctl.conf

# Thiết lập mô tả cho 3proxy
sudo sed -i "/Description=/c\Description=3 Proxy optimized by VLT PRO" /etc/sysctl.conf

# Thiết lập giới hạn file descriptor và process
sudo sed -i "/LimitNOFILE=/c\LimitNOFILE=9999999" /etc/sysctl.conf
sudo sed -i "/LimitNPROC=/c\LimitNPROC=9999999" /etc/sysctl.conf
