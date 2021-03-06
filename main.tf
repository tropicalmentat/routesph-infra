# https://coffay.haus/pages/terraform+ansible
# https://alex.dzyoba.com/blog/terraform-ansible/

terraform {
	backend "s3" {
    	endpoint = "sgp1.digitaloceanspaces.com"
	region="ap-southeast-1"
	key="terraform.tf.state"
	skip_requesting_account_id=true
	skip_credentials_validation=true
	skip_get_ec2_platforms=true
	skip_metadata_api_check=true
	}	
}

provider digitalocean {
    token = var.do_token
    version = "2.7.0"
}

variable do_token {
   type=string
}

variable "pubkey_path" {
   type=string
}

variable "pvtkey_path" {
  type=string
}

resource "digitalocean_project" "sandbox" {
   name="rowt-sandbox"
   resources=[digitalocean_domain.routes.urn,
              digitalocean_droplet.bastion.urn,
              digitalocean_droplet.api.urn,
              digitalocean_droplet.gh.urn,
              digitalocean_droplet.db.urn,
	      digitalocean_droplet.rp.urn
	      ]
}

resource "digitalocean_vpc" "sandbox" {
   name="rowt-dev-vpc"
   region="sgp1"
}

resource "digitalocean_ssh_key" "admin" {
   name="rowt_admin"
   public_key=file(var.pubkey_path)
}

resource "digitalocean_droplet" "bastion" {
   name="rowt-dev-gw"
   image="ubuntu-20-04-x64"
   region="sgp1"
   size="s-1vcpu-1gb"
   vpc_uuid=digitalocean_vpc.sandbox.id
   ssh_keys=[digitalocean_ssh_key.admin.fingerprint]
}
/*
resource "digitalocean_loadbalancer" "api_loadbalancer" {
   name="rowt-dev-api-loadbalancer"
   region="sgp1"
   vpc_uuid=digitalocean_vpc.sandbox.id
	
	forwarding_rule {
	   entry_port=80
	   entry_protocol="http"

	   target_port=5000
	   target_protocol="http"
	}

	healthcheck {
	   port=80
	   protocol="http"
	   path="/route"
	}

	droplet_ids=[digitalocean_droplet.api.id]
}
*/
resource "digitalocean_droplet" "rp" {
	name="rowt-dev-rp"
	image="ubuntu-20-04-x64"
	region="sgp1"
	size="s-1vcpu-1gb"
	vpc_uuid=digitalocean_vpc.sandbox.id
	ssh_keys=[digitalocean_ssh_key.admin.fingerprint]

}

resource "digitalocean_droplet" "api" {
   name="rowt-dev-api"
   image="ubuntu-20-04-x64"
   region="sgp1"
   size="s-1vcpu-1gb"
   vpc_uuid=digitalocean_vpc.sandbox.id
   ssh_keys=[digitalocean_ssh_key.admin.fingerprint]
}

resource "digitalocean_droplet" "gh" {
   name="rowt-dev-gh"
   image="ubuntu-20-04-x64"
   region="sgp1"
   size="s-2vcpu-4gb"
   vpc_uuid=digitalocean_vpc.sandbox.id
   ssh_keys=[digitalocean_ssh_key.admin.fingerprint]
}

resource "digitalocean_droplet" "db" {
   name="rowt-dev-db"
   image="ubuntu-20-04-x64"
   region="sgp1"
   size="s-2vcpu-4gb"
   vpc_uuid=digitalocean_vpc.sandbox.id
   ssh_keys=[digitalocean_ssh_key.admin.fingerprint]
}

resource "local_file" "inventory" {
   filename="hosts"
   content=<<EOT
[bastion]	
bastion ansible_host=${digitalocean_droplet.bastion.ipv4_address}

[api]
api ansible_host=${digitalocean_droplet.api.ipv4_address} 

[route_engine] 
re ansible_host=${digitalocean_droplet.gh.ipv4_address}

[database] 
db ansible_host=${digitalocean_droplet.db.ipv4_address}

[reverse_proxy]
rp ansible_host=${digitalocean_droplet.rp.ipv4_address}

 EOT
}

resource "local_file" "host_script" {
   filename="./add_hosts.sh"
   content=<<EOT
   echo "Setting SSH Key"
	eval "$(ssh-agent)"
   ssh-add /home/ctrlr/.ssh/id_rsa
   echo "Adding IPs"

   ssh-keyscan -H ${digitalocean_droplet.bastion.ipv4_address} >> ~/.ssh/known_hosts
   ssh-keyscan -H ${digitalocean_droplet.api.ipv4_address} >> ~/.ssh/known_hosts
   ssh-keyscan -H ${digitalocean_droplet.gh.ipv4_address} >> ~/.ssh/known_hosts 
   ssh-keyscan -H ${digitalocean_droplet.db.ipv4_address} >> ~/.ssh/known_hosts
	ssh-keyscan -H ${digitalocean_droplet.rp.ipv4_address} >> ~/.ssh/known_hosts

   EOT
}

resource "digitalocean_domain" "routes" {
	name="routes.ph"
}

resource "digitalocean_record" "dev" {
	domain = digitalocean_domain.routes.name
	type = "A"
	name = "dev"
	value = digitalocean_droplet.rp.ipv4_address
}

output "ssh_public_key" {
   value=digitalocean_ssh_key.admin.public_key
   sensitive=true
}
