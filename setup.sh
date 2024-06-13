#!/bin/bash
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
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 2000
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

$(awk -F "/" '{print "\n" \
"" $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 " }' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $FIXED_IPV6_ADDRESS)"
    done
}

gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

setup_environment() {
    echo "Installing necessary packages"
    yum -y install gcc net-tools bsdtar zip make >/dev/null
}

setup_cron_job() {
    crontab -l > mycron
    echo "*/10 * * * * /bin/bash -c '$WORKDIR/rotate_ipv6.sh'" >> mycron
    crontab mycron
    rm mycron
}

download_proxy() {
    cd $WORKDIR || exit 1
    curl -F "proxy.txt" https://transfer.sh
}

echo "Thiet Lap Thu Muc + Setup Proxy"
WORKDIR="/home/vlt"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

FIRST_PORT=20000
LAST_PORT=22222
MAXCOUNT=$((LAST_PORT - FIRST_PORT + 1))

setup_environment
install_3proxy

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

gen_proxy_file_for_user

rm -rf /root/3proxy-3proxy-0.8.6

# Create rotate_ipv6 script
cat >$WORKDIR/rotate_ipv6.sh <<EOF
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Function to generate random IPv6 addresses
gen_ipv6_64() {
    rm -f "$WORKDIR/data.txt"  # Backup File
    count_ipv6=1
    while [ "\$count_ipv6" -le "$MAXCOUNT" ]; do
        array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
        ip64() {
            echo "\${array[\$RANDOM % 16]}\${array[\$RANDOM % 16]}\${array[\$RANDOM % 16]}\${array[\$RANDOM % 16]}"
        }
        echo "$IP6:\$(ip64):\$(ip64):\$(ip64):\$(ip64)" >> "$WORKDIR/data.txt"
        ((count_ipv6 += 1))
    done
}

# Function to generate 3proxy configuration
gen_3proxy_cfg() {
    echo 'daemon'
    echo 'maxconn 3000'
    echo 'nserver 1.1.1.1'
    echo 'nserver [2001:4860:4860::8888]'
    echo 'nserver [2001:4860:4860::8844]'
    echo 'nserver [2001:4860:4860::1111]'
    echo 'nscache 65536'
    echo 'timeouts 1 5 30 60 180 1800 15 60'
    echo 'setgid 65535'
    echo 'setuid 65535'
    echo 'stacksize 6291456'
    echo 'flush'
    echo 'auth none'

    port="$START_PORT"
    while read -r ip; do
        echo "proxy -6 -n -a -p\$port -i$IP4 -e\$ip"
        ((port += 1))
    done < "$WORKDIR/data.txt"
}

# Function to generate ifconfig commands for IPv6
gen_ifconfig() {
    while read -r line; do
        echo "ifconfig $IFCFG inet6 add \$line/64"
    done < "$WORKDIR/data.txt"
}

# Function to rotate IPv6 addresses
rotate_ipv6() {
    echo "Dang Xoay IPv6"
    gen_ipv6_64
    gen_ifconfig >"$WORKDIR/boot_ifconfig.sh"
    bash "$WORKDIR/boot_ifconfig.sh"
    gen_3proxy_cfg > /usr/local/etc/3proxy/3proxy.cfg
    killall 3proxy
    /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
    echo "IPv6 Xoay Rotated successfully."
    rotate_count=$((rotate_count + 1))
    echo "Xoay IP Tu Dong: \$rotate_count"
    sleep 3600
}

# Main script starts here
if [ "\$(id -u)" -ne 0 ]; then
    echo 'Error: This script must be run as root'
    exit 1
fi

# Set variables
WORKDIR="/home/vlt"
START_PORT=20000
MAXCOUNT=22222
IFCFG="eth0"

# Rotate IPv6 addresses
rotate_ipv6
EOF

chmod +x $WORKDIR/rotate_ipv6.sh

# Set up cron job
setup_cron_job

echo 'IPv6 setup complete.'
echo "Starting Proxy"
echo "Current IPv6 Address Count:"
ip -6 addr | grep inet6 | wc -l
