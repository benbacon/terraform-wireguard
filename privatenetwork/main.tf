terraform {
    required_providers {
        openstack = {
            source = "terraform-provider-openstack/openstack"
            version = "~> 1.42.0"
        }
        cloudflare = {
            source = "cloudflare/cloudflare"
            version = "~> 2.21.0"
        }
    }
}

provider "openstack" {

}

provider "cloudflare" {
    api_token = var.cloudflare_api_token
}

resource "openstack_compute_keypair_v2" "wireguard" {
    name = var.openstack_resource_name
    public_key = file("${var.ssh_path}.pub")
}

resource "openstack_networking_secgroup_v2" "wireguard" {
    name = var.openstack_resource_name
}

resource "openstack_networking_secgroup_rule_v2" "wireguard_ssh" {
    description = "Allow SSH traffic"
    direction = "ingress"
    ethertype = "IPv4"
    protocol = "tcp"
    port_range_min = 22
    port_range_max = 22
    remote_ip_prefix = var.ssh_ingress_ip
    security_group_id = openstack_networking_secgroup_v2.wireguard.id
}

resource "openstack_networking_secgroup_rule_v2" "wireguard_wireguard" {
    description = "Allow RTP UDP traffic"
    direction = "ingress"
    ethertype = "IPv4"
    protocol = "udp"
    port_range_min = 51820
    port_range_max = 51820
    security_group_id = openstack_networking_secgroup_v2.wireguard.id
}

resource "openstack_networking_secgroup_rule_v2" "wireguard_openvpn" {
    description = "Allow RTP UDP traffic"
    direction = "ingress"
    ethertype = "IPv4"
    protocol = "udp"
    port_range_min = 1194
    port_range_max = 1194
    security_group_id = openstack_networking_secgroup_v2.wireguard.id
}

resource "openstack_networking_secgroup_rule_v2" "wireguard_icmp" {
    description = "Allow ICMP traffic"
    direction = "ingress"
    ethertype = "IPv4"
    protocol = "icmp"
    port_range_min = 8
    port_range_max = 0
    security_group_id = openstack_networking_secgroup_v2.wireguard.id
}

resource "openstack_networking_network_v2" "wireguard" {
    name = var.openstack_resource_name
    admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "wireguard" {
    name = var.openstack_resource_name
    network_id = openstack_networking_network_v2.wireguard.id
    cidr = "192.168.0.0/24"
    dns_nameservers = [ "1.1.1.1","1.0.0.1" ]
    ip_version = 4
}

resource "openstack_networking_port_v2" "wireguard" {
    name = var.openstack_resource_name
    network_id = openstack_networking_network_v2.wireguard.id
    admin_state_up = "true"
    security_group_ids = [ openstack_networking_secgroup_v2.wireguard.id ]
    
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.wireguard.id
        ip_address = "192.168.0.69"
    }
}

data "openstack_networking_router_v2" "router" {
    name = var.openstack_router_name
}

resource "openstack_networking_router_interface_v2" "router_interface" {
    router_id = data.openstack_networking_router_v2.router.id
    subnet_id = openstack_networking_subnet_v2.wireguard.id
}

resource "openstack_compute_floatingip_v2" "wireguard" {
    pool = var.openstack_network
}

resource "openstack_compute_floatingip_associate_v2" "wireguard" {
    floating_ip = openstack_compute_floatingip_v2.wireguard.address
    instance_id = openstack_compute_instance_v2.wireguard.id
}

resource "openstack_compute_instance_v2" "wireguard" {
    name = var.openstack_resource_name
    image_name = var.openstack_image
    flavor_name = var.openstack_flavor
    key_pair = openstack_compute_keypair_v2.wireguard.name
    user_data = templatefile( "${path.module}/install_wireguard.tpl", { domain = var.domain, wireguard_private_key = var.wireguard_private_key, wireguard_public_key = var.wireguard_public_key } )

    network {
        port = openstack_networking_port_v2.wireguard.id
    }

}

resource "cloudflare_record" "wireguard" {
    zone_id = var.cloudflare_zone_id
    name = var.domain
    value = openstack_compute_floatingip_v2.wireguard.address
    type = "A"
    proxied = false
    ttl = 1
}
