⁪⁬⁮File Chạy Setup 3 Chức Năng 
1. Thiết lập IPv6 Cho Máy Ảo
2. Cài đặt 3proxy không có mật khẩu
3. Cài đặt 3proxy có mật khẩu

bash <(curl -s "https://raw.githubusercontent.com/volamtuan/-/main/iíntall.sh") 

Bước 1: Gán IPv6 cho vps

Tìm hiểu cách thêm IPv6 đối với dịch vụ VPS của BKNS
Lệnh thêm IPv6 tự động:
curl -sO https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh && bash ipv6.sh

Bước 2: Cài đặt 3Proxy

Các bạn chạy lệnh sau để cài đặt trong trường hợp proxy cần user và pass:
wget https://raw.githubusercontent.com/quanglinh0208/3proxy/main/setup.sh && chmod +x setup.sh && bash setup.sh  

 

Bước 3: Lấy thông tin tài khoản

Lấy thông tin tài khoản tại đường dẫn /home/bkns. Mở file proxy.txt để lấy các thông tin đăng nhập.

cat /home/proxy/proxy.txt

