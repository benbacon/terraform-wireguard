#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export HOSTNAME="${domain}"

# Harden SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g; s/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
systemctl reload ssh

# Set hostname
hostnamectl set-hostname $HOSTNAME
echo -e "127.0.0.1 localhost $HOSTNAME" >> /etc/hosts

apt-get -y update
apt-get -y install apt-transport-https linux-image-amd64 wireguard
apt-get -y upgrade -o Dpkg::Options::="--force-confold"
dpkg-reconfigure wireguard-dkms

echo -e "[Interface]\nAddress = 10.9.0.1/32\nMTU = 1420\nListenPort = 51820\nPrivateKey = ${wireguard_private_key}\nPostUp = iptables -t nat -A PREROUTING -p udp -i eth0 --dport 1194 -j DNAT --to-destination 10.9.0.2; iptables -I INPUT -p udp --dport 51820 -j ACCEPT;  iptables -A FORWARD -p udp -i eth0 -o wg0 --dport 1194 -d 10.9.0.2 -j ACCEPT; iptables -A FORWARD -p udp -i wg0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.9.0.1\nPostDown = iptables -t nat -D PREROUTING -p udp -i eth0 --dport 1194 -j DNAT --to-destination 10.9.0.2; iptables -D INPUT -p udp --dport 51820 -j ACCEPT; iptables -D FORWARD -p udp -i eth0 -o wg0 --dport 1194 -d 10.9.0.2 -j ACCEPT; iptables -D FORWARD -p udp -i wg0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -D POSTROUTING -o wg0 -j SNAT --to-source 10.9.0.1\n\n[Peer]\nPublicKey = ${wireguard_public_key}\nAllowedIPs = 10.9.0.2/32" > /etc/wireguard/wg0.conf

sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

systemctl enable wg-quick@wg0

reboot
