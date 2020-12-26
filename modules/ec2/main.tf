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

resource "aws_eip" "ec2" {
  count = var.create_elastic_ip ? 1 : 0
  vpc   = true

  tags = {
    Name        = var.name == null ? var.host_name : var.name
    Terraform   = "true"
    environment = var.environment
    project     = var.aws_project
  }
}

resource "aws_eip_association" "eip_assoc" {
  count         = var.create_elastic_ip ? 1 : 0
  instance_id   = module.ec2.id[0]
  allocation_id = aws_eip.ec2.0.id
}

module "ec2" {
  source = "terraform-aws-modules/ec2-instance/aws"

  instance_count = 1

  name          = var.name == null ? var.host_name : var.name
  ami           = var.ami_id == null ? data.aws_ami.amazon_linux2.id : var.ami_id
  key_name      = var.key_name
  instance_type = var.instance_type
  cpu_credits   = var.cpu_credits
  subnet_id     = var.subnet_id
  private_ips   = var.private_ips
  # private_dns is not supported in terraform-aws-modules/ec2-instance/aws
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = var.iam_instance_profile

  # swap cannot be added in Ansible at a later time, because yum needs the memory
  # for the insallation of ansible...
  user_data = templatefile("${path.module}/template/user_data.txt",
    {
      install_option_OS = var.install_option_OS
      host_name = var.host_name
      domain_name = var.domain_name
      aws_region = var.aws_region
      http_proxy = var.http_proxy
      fail2ban_ignoreip = var.fail2ban_ignoreip
      install_option = var.install_option
      custom_RPMs = var.custom_RPMs
    }
  )

  ebs_optimized = var.ebs_optimized

  disable_api_termination = var.disable_api_termination

  root_block_device = [
    {
      volume_type = "gp3"
      volume_size = var.root_disk_size
      delete_on_termination = var.root_disk_termination
      encrypted   = var.root_disk_encryption
      kms_key_id  = var.root_kms_key_id
    },
  ]

  ebs_block_device = var.ebs_block_device

  tags = merge(local.common_tags, local.backup_tags, var.custom_tags)
}

data "aws_route53_zone" "internal" {
  zone_id      = var.route53_zone_id
}

locals {
  common_tags = {
    Terraform   = "true"
    environment = var.environment
    project     = var.aws_project
    hostname    = var.host_name == null ? var.name : var.host_name
    hostname_fqdn = format("%s.%s", var.host_name == null ? var.name : var.host_name, trimsuffix(data.aws_route53_zone.internal.name, "."))
  }

  backup_tags = {
    dlm_snapshot             = var.dlm_policy == null ? null : "true"
    dlm_policy               = var.dlm_policy == null ? null : var.dlm_policy
    "shelvery:create_backup" = var.shelvery_backup
  }
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

  records = [var.create_elastic_ip ? aws_eip.ec2.0.public_ip : module.ec2.public_ip[0]]
}