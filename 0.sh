#!/bin/bash

if [ "$(id -u)" != '0' ]; then
    echo 'Error: this script can only be executed by root'
    exit 1
fi

# Lấy địa chỉ IP4 từ hệ thống
IP4=$(curl -4 -s icanhazip.com)
if [ -z "$IP4" ]; then
    echo 'Error: could not retrieve IPv4 address'
    exit 1
fi

echo "Địa chỉ IPv4 của bạn: $IP4"

# Lấy địa chỉ IP6 từ hệ thống và cắt chỉ giữ lại phần prefix
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
if [ -z "$IP6" ]; then
    echo 'Error: could not retrieve IP6 address'
    exit 1
fi

echo "Địa chỉ IPv6 của bạn: $IP6"
DEFAULT_PREFIX="${IP6}"
read -r -p "Nhập IPv6 của bạn (mặc định: $DEFAULT_PREFIX): " vPrefix
vPrefix=${vPrefix:-$DEFAULT_PREFIX}  # Sử dụng giá trị mặc định nếu không nhập

read -r -p "Số lượng Proxy: " vCount
read -r -p "IP có quyền truy cập vào Proxy này: " vIp2

# Kiểm tra các giá trị đầu vào
if [ -z "$vCount" ] || [ -z "$vIp2" ]; then
    echo 'Error: bạn phải nhập tất cả các thông tin cần thiết'
    exit 1
fi

# Cài đặt các gói cần thiết
yum -y groupinstall "Development Tools"
yum -y install gcc zlib-devel openssl-devel readline-devel ncurses-devel wget tar dnsmasq net-tools iptables-services nano

# Tải về và biên dịch 3proxy
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy
make -f Makefile.Linux
ulimit -u unlimited -n 999999 -s 16384

# Tải các tập tin cấu hình
wget https://github.com/avcvv/ipv6proxies/raw/master/3proxycfg.sh
wget https://github.com/avcvv/ipv6proxies/raw/master/Genips.sh
chmod 0755 Genips.sh
chmod 0755 3proxycfg.sh

# Cập nhật tập tin cấu hình 3proxy
sed -i "s/1.4.8.8/$vIp2/g" /root/3proxy/3proxycfg.sh
sed -i "s/i127.0.0.1/i$IP4/g" /root/3proxy/3proxycfg.sh

# Mở rộng giới hạn file
echo '* hard nofile 999999' >> /etc/security/limits.conf
echo '* soft nofile 999999' >> /etc/security/limits.conf

echo $vPrefix > v_prefix.txt
echo $vCount > v_count.txt

echo ====================================
echo      Stop 3proxy:  OK!
echo ====================================

kill -9 $(pidof 3proxy) 2>/dev/null

echo ====================================
echo  Remove old ip.list
echo ====================================

rm -rf ip.list

echo ====================================
echo      Generate IPs: OK!
echo ====================================

network=$vPrefix
MAXCOUNT=$vCount

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
count=1

rnd_ip_block () {
    a=${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}
    b=${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}
    c=${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}
    d=${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}
    echo $network:$a:$b:$c:$d >> ip.list
}

while [ "$count" -le $MAXCOUNT ]; do
    rnd_ip_block
    count=$((count + 1))
done

echo ====================================
echo      Restarting Network: OK!
echo ====================================

service network restart

echo ====================================
echo      Adding IPs to interface: OK!
echo ====================================

for i in $(cat ip.list); do
    echo "ifconfig eth0 inet6 add $i/64"
    ifconfig eth0 inet6 add $i/64
done

echo ====================================
echo      Generate 3proxy.cfg: OK!
echo ====================================

/root/3proxy/3proxycfg.sh > /root/3proxy/3proxy.cfg

echo ====================================
echo      Start 3proxy: OK!
echo ====================================

/root/3proxy/bin/3proxy /root/3proxy/3proxy.cfg

echo ====================================
echo      Stop Firewall: OK!
echo ====================================

systemctl stop firewalld
systemctl disable firewalld
