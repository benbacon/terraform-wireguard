terraform {
    required_providers {
        linode = {
            source = "linode/linode"
            version = "1.26.0"
        }
        cloudflare = {
            source = "cloudflare/cloudflare"
            version = "3.10.1"
        }
    }
}

provider "linode" {
    token = var.linode_api_token
}

provider "cloudflare" {
    api_token = var.cloudflare_api_token
}

resource "linode_sshkey" "wireguard" {
    label = "wireguard"
    ssh_key = chomp(file("${var.ssh_path}.pub"))
}

resource "linode_firewall" "wireguard" {
    label = "wireguard"

    inbound {
        label    = "SSH"
        action   = "ACCEPT"
        protocol = "TCP"
        ports    = "22"
        ipv4     = [var.ssh_ingress_ip]
    }

    inbound {
        label = "wireguard"
        action = "ACCEPT"
        protocol  = "UDP"
        ports     = "51820"
        ipv4 = ["0.0.0.0/0"]
    }

    inbound {
        label = "wireguard"
        action = "ACCEPT"
        protocol  = "UDP"
        ports     = "1194"
        ipv4 = ["0.0.0.0/0"]
    }

    inbound {
        label = "wireguard"
        action = "ACCEPT"
        protocol  = "ICMP"
        ipv4 = ["0.0.0.0/0"]
    }

    inbound_policy = "DROP"
    outbound_policy = "ACCEPT"

    linodes = [linode_instance.wireguard.id]

}

resource "linode_stackscript" "wireguard" {
    label = "wireguard"
    description = "Install Wireguard"
    script = <<EOF
#!/bin/bash
# <UDF name="domain" label="Publically resolvable FQDN">
# <UDF name="wireguard_private_key" label="Wireguard private key">
# <UDF name="wireguard_public_key" label="Wireguard public key">

set -e
export DEBIAN_FRONTEND=noninteractive

# Harden SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g; s/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
systemctl reload ssh

# Set hostname
hostnamectl set-hostname $DOMAIN
echo -e "127.0.0.1 localhost $DOMAIN" >> /etc/hosts

apt-get -y update
apt-get -y install iptables wireguard
apt-get -y upgrade -o Dpkg::Options::="--force-confold"

echo -e "[Interface]\nAddress = 10.9.0.1/32\nMTU = 1420\nListenPort = 51820\nPrivateKey = $WIREGUARD_PRIVATE_KEY\nPostUp = iptables -t nat -A PREROUTING -p udp -i eth0 --dport 1194 -j DNAT --to-destination 10.9.0.2; iptables -I INPUT -p udp --dport 51820 -j ACCEPT;  iptables -A FORWARD -p udp -i eth0 -o wg0 --dport 1194 -d 10.9.0.2 -j ACCEPT; iptables -A FORWARD -p udp -i wg0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.9.0.1\nPostDown = iptables -t nat -D PREROUTING -p udp -i eth0 --dport 1194 -j DNAT --to-destination 10.9.0.2; iptables -D INPUT -p udp --dport 51820 -j ACCEPT; iptables -D FORWARD -p udp -i eth0 -o wg0 --dport 1194 -d 10.9.0.2 -j ACCEPT; iptables -D FORWARD -p udp -i wg0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -D POSTROUTING -o wg0 -j SNAT --to-source 10.9.0.1\n\n[Peer]\nPublicKey = $WIREGUARD_PUBLIC_KEY\nAllowedIPs = 10.9.0.2/32" > /etc/wireguard/wg0.conf

sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

systemctl enable wg-quick@wg0

reboot
EOF
    images = [var.linode_image]
}

resource "linode_instance" "wireguard" {
        image = var.linode_image
        region = var.linode_region
        type = var.linode_type
        authorized_keys = [ linode_sshkey.wireguard.ssh_key ]
        stackscript_id = linode_stackscript.wireguard.id
        stackscript_data = {
            "domain" = var.domain
            "wireguard_private_key" = var.wireguard_private_key
            "wireguard_public_key" = var.wireguard_public_key
        }
}

resource "cloudflare_record" "wireguard" {
    zone_id = var.cloudflare_zone_id
    name = var.domain
    value = linode_instance.wireguard.ip_address
    type = "A"
    proxied = false
    ttl = 1
}
