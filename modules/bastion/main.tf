terraform {
  backend "s3" {
  }
}

provider "aws" {
  version = "~> 2.18"
  region  = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0.????????-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

module "sg_to_bastion" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = "${var.host_name}_to"
  description = "SG for access to Bastion"
  vpc_id      = var.vpc_id

  egress_rules = ["all-all"]

  ingress_with_cidr_blocks = [
    {
      rule        = "all-icmp"
      cidr_blocks = var.cidr_block
      description = "Ping from VPC"
    },
    {
      rule        = "ssh-tcp"
      cidr_blocks = "${var.ssh_public_ingress}"
    },
    {
      rule        = "ssh-tcp"
      cidr_blocks = var.cidr_block
    },
    {
      rule        = "squid-proxy-tcp"
      cidr_blocks = var.cidr_block
      description = "TinyProxy"
    }
  ]
  tags = {
    Terraform   = "true"
    environment = var.environment
    project     = var.aws_project
  }
}

# module "sg_from_bastion" {
#   source  = "terraform-aws-modules/security-group/aws"
#   version = "~> 3.0"

#   name        = "${var.host_name}_from"
#   description = "SG for access from Bastion"
#   vpc_id      = var.vpc_id

#   egress_rules = ["all-all"]

#   ingress_with_cidr_blocks = [
#     {
#       rule        = "all-icmp"
#       cidr_blocks = "${module.ec2.private_ip[0]}/32"
#       description = "Ping from Bastion"
#     },
#     {
#       rule        = "ssh-tcp"
#       cidr_blocks = "${module.ec2.private_ip[0]}/32"
#       description = "SSH from Bastion"
#     }
#   ]
#   tags = {
#     Terraform   = "true"
#     environment = var.environment
#     project     = var.aws_project
#   }
# }

resource "aws_eip" "bastion" {
  count    = var.create_elastic_ip ? 1 : 0
  vpc      = true

  tags = {
    Name        = var.host_name
    Terraform   = "true"
    environment = var.environment
    project     = var.aws_project
  }
}

resource "aws_eip_association" "eip_assoc" {
  count    = var.create_elastic_ip ? 1 : 0
  instance_id   = module.ec2.id[0]
  allocation_id = aws_eip.bastion.0.id
}

module "ec2" {
  source = "terraform-aws-modules/ec2-instance/aws"

  instance_count = 1

  name                        = var.host_name
  ami                         = "${var.ami_id == null ? data.aws_ami.amazon_linux2.id : var.ami_id}"
  key_name                    = var.key_name
  instance_type               = var.instance_type
  cpu_credits                 = var.cpu_credits
  subnet_id                   = var.subnet_id
  private_ips                 = var.private_ips
  vpc_security_group_ids      = [module.sg_to_bastion.this_security_group_id]
  associate_public_ip_address = true
  iam_instance_profile        = var.iam_instance_profile

  root_block_device = [
    {
      volume_type = "gp2"
      volume_size = 15
      encrypted   = true
    },
  ]
  user_data = <<EOF
#!/bin/bash
hostnamectl set-hostname ${var.host_name}.${var.domain_name}

dd if=/dev/zero of=/var/swapfile bs=10240 count=50000
mkswap /var/swapfile ; chmod 600 /var/swapfile
echo "/var/swapfile     swap           swap    defaults  1   1" >> /etc/fstab
swapon -a

yes | amazon-linux-extras install epel | tee -a ~/cloud-init.log
sleep 5
yum install -y git ansible | tee -a ~/cloud-init.log
systemctl enable amazon-ssm-agent ; systemctl restart amazon-ssm-agent

mkdir /root/git ; cd /root/git
git clone https://github.com/Rendanic/aws_ec2_ossetup.git | tee -a ~/cloud-init.log
cd aws_ec2_ossetup/ansible
./security.sh | tee -a ~/cloud-init.log

if [ "${var.create_tinyproxy}" = "true" ] ; then
    ansible-playbook install_docker.yml | tee -a ~/cloud-init.log
    ansible-playbook docker_tinyproxy.yml | tee -a ~/cloud-init.log
fi

if [ "${var.create_internal_key}" = "true" ] ; then
    echo "${tls_private_key.internal_key.private_key_pem }" > /home/ec2-user/.ssh/pem
    chmod 600 /home/ec2-user/.ssh/pem ; openssl rsa -in /home/ec2-user/.ssh/pem -out /home/ec2-user/.ssh/id_rsa
    ssh-keygen -y -f /home/ec2-user/.ssh/pem > /home/ec2-user/.ssh/id_rsa.pub
    chown ec2-user:ec2-user -R /home/ec2-user/.ssh
    chmod 600 /home/ec2-user/.ssh/id_rsa
fi

yum update -y | tee -a ~/cloud-init.log
EOF

  tags = {
    Terraform   = "true"
    environment = var.environment
    project     = var.aws_project

    # Tags for DLM
    dlm_snapshot = "${var.dlm_policy == null ? "false" : "true"}"
    dlm_policy   = "${var.dlm_policy == null ? "" : var.dlm_policy}"
  }
}

# The handling of ssh-keys is dangrerous and only for the
# Playground environment. DON'T USE IT IN PRODUCTION!!!
resource "tls_private_key" "internal_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# created key in AWS when create_internal_key is true
resource "aws_key_pair" "generated_key" {
  count     = var.create_internal_key ? 1 : 0
  key_name   = var.internal_key_name
  public_key = tls_private_key.internal_key.public_key_openssh
}

resource "aws_route53_record" "internal" {
  zone_id = var.route53_zone_id
  name    = var.host_name
  type    = "A"
  ttl     = 60

   records = module.ec2.private_ip
}

resource "aws_route53_record" "public" {
  count   = var.public_zone_id == null ? 0 : 1
  zone_id = var.public_zone_id
  name    = var.host_name
  ttl     = 60
  type    = "A"

   records = [var.create_elastic_ip ? aws_eip.bastion.0.public_ip : module.ec2.public_ip[0]]
}