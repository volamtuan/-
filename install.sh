#!/bin/bash

setup_ipv6() {
    echo "Thiết lập IPv6..."
    bash <(curl -s "https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh") 
}

install_3proxy_without_pass() {
    echo "Bắt đầu cài đặt 3proxy không có mật khẩu..."
    bash <(curl -s "https://raw.githubusercontent.com/volamtuan/proxy/main/lan.sh")
}

install_3proxy_with_pass() {
    echo "Bắt đầu cài đặt 3proxy có mật khẩu..."
    bash <(curl -s "https://raw.githubusercontent.com/volamtuan/-/main/3proxy") 
}

# Menu
while true; do
    echo "Menu:"
    echo "1. Thiết lập IPv6 Cho Máy Ảo"
    echo "2. Cài đặt 3proxy không có mật khẩu"
    echo "3. Cài đặt 3proxy có mật khẩu"
    echo "0. Thoát"

    read -p "Chọn một tùy chọn: " choice
    case $choice in
        1) setup_ipv6 ;;
        2) install_3proxy_without_pass ;;
        3) install_3proxy_with_pass ;;
        0) echo "Thoát..."; exit ;;
        *) echo "Tùy chọn không hợp lệ. Vui lòng thử lại." ;;
    esac
done
