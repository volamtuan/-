#!/bin/sh
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
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
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

rotate_count=0

rotate_ipv6() {
    echo "Dang Xoay IPv6"
    gen_data >$WORKDIR/data.txt
    gen_ifconfig >$WORKDIR/boot_ifconfig.sh
    bash $WORKDIR/boot_ifconfig.sh
    echo "IPv6 Xoay Rotated successfully."
    rotate_count=$((rotate_count + 1))
    echo "Xoay IP Tu Dong: $rotate_count"
    sleep 3600
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

# Function to monitor and alert rotation process
monitor_rotation() {
    while true; do
        # Check if the rotation script is running
        if pgrep -x "rotate_ipv6.sh" > /dev/null; then
            # If running, sleep for a while and check again
            sleep 300 # Sleep for 5 minutes
        else
            # If not running, send alert
            echo "ALERT: IPv6 rotation script is not running!"
            # You can add more actions here, like sending an email notification
            break
        fi
    done
}

echo "working folder = /home/vlt"
WORKDIR="/home/vlt"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

FIRST_PORT=20000
LAST_PORT=22222

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
#!/bin/sh
$(declare -f rotate_ipv6)
rotate_ipv6
EOF
chmod +x $WORKDIR/rotate_ipv6.sh

# Setup cron job for rotating IPv6 every 10 minutes
setup_cron_job

echo "Starting Proxy"
echo "Current IPv6 Address Count:"
ip -6 addr | grep inet6 | wc -l

# Start monitoring rotation process
monitor_rotation &

# Menu loop
while true; do
    echo "1. Reset 3proxy Setup"
    echo "2. Rotate IPv6"
    echo "3. Download proxy"
    echo "4. Exit"
    echo -n "Enter your choice: "
    read choice
    case $choice in
        1)
            install_3proxy
            ;;
        2)
            rotate_ipv6
            ;;
        3)
            download_proxy
            ;;
        4)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
done
