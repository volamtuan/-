#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

WORKDIR="/proxy"
WORKDATA="${WORKDIR}/data.txt"
IFACE="enp1s0"
API_URL="http://localhost:5000/get_ipv6"  # Flask API for getting IPv6

# Install system dependencies
echo "Installing system dependencies..."
sudo apt update -y
sudo apt install -y python3 python3-pip curl jq wget gcc make socat

# Install Flask
echo "Installing Flask..."
pip3 install Flask

# Create Flask app
echo "Creating Flask app..."
cat <<EOF > app.py
from flask import Flask, jsonify
import random

app = Flask(__name__)

# Array of characters to create IPv6 addresses
array = '0123456789abcdef'

# Function to generate a random IPv6 address
def gen_ipv6():
    ip64 = lambda: ''.join(random.choice(array) for _ in range(4))
    ipv6 = "2401:c080:2000:22bf:{}:{}:{}:{}:{}:{}:{}:{}".format(
        ip64(), ip64(), ip64(), ip64(), ip64(), ip64(), ip64(), ip64()
    )
    return ipv6

@app.route('/get_ipv6', methods=['GET'])
def get_ipv6():
    ipv6 = gen_ipv6()
    return jsonify({'ipv6': ipv6})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Run Flask app in the background
echo "Starting Flask app..."
nohup python3 app.py > flask.log 2>&1 &

# Create proxy setup script
echo "Creating proxy setup script..."
cat <<'EOF' > /usr/local/bin/setup_proxy.sh
#!/bin/bash
WORKDIR="/proxy"
WORKDATA="${WORKDIR}/data.txt"
API_URL="http://localhost:5000/get_ipv6"
IFACE="enp1s0"

fetch_ipv6() {
    curl -s $API_URL | jq -r '.ipv6'
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        IPV6=$(fetch_ipv6)
        echo "//$IP4/$port/$IPV6"
    done
}

gen_ifconfig() {
    awk -F "/" '{print "ifconfig " ENVIRON["IFACE"] " inet6 add " $5 "/64"}' ${WORKDATA}
}

create_proxy() {
    while IFS= read -r line; do
        PORT=$(echo $line | cut -d '/' -f 3)
        IP6=$(echo $line | cut -d '/' -f 4)

        cat <<EOF > /etc/systemd/system/proxy-${PORT}.service
[Unit]
Description=Proxy on port ${PORT}
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP4-LISTEN:${PORT},fork TCP6:[${IP6}]:${PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable proxy-${PORT}.service
        systemctl start proxy-${PORT}.service
    done < $WORKDATA
}

update_proxy() {
    echo "Updating proxy configuration..."
    gen_data >$WORKDATA
    gen_ifconfig >$WORKDIR/boot_ifconfig.sh
    chmod +x $WORKDIR/boot_ifconfig.sh

    bash $WORKDIR/boot_ifconfig.sh
    create_proxy
}

echo "Setting up proxy..."
mkdir -p $WORKDIR
IP4=$(curl -4 -s icanhazip.com)

FIRST_PORT=10000
LAST_PORT=10010

update_proxy

# Schedule updates every hour
echo "Scheduling IPv6 updates..."
(crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/setup_proxy.sh") | crontab -

EOF

# Make the proxy setup script executable
chmod +x /usr/local/bin/setup_proxy.sh

# Run the proxy setup script
echo "Running proxy setup script..."
sudo /usr/local/bin/setup_proxy.sh

echo "Setup completed."
