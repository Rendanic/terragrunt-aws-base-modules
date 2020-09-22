variable "aws_region" {
  description = "The AWS region to deploy to (e.g. us-east-1)"
  type        = string
}

variable "environment" {
  description = "The name of the environment"
  type        = string
}

variable "aws_project" {
  description = "The name of the Project"
  type        = string
}

variable "vpc_id" {
  description = "vpc_id of the VPC"
  type        = string
}

variable "cidr_block" {
  description = "CIDR of the VPC"
  type        = string
}

variable "subnet_id" {
  type        = string
  description = "subnet_id of Bastion"
  default     = ""
}

variable "iam_instance_profile" {
  default = ""
}

variable "associate_public_ip_address" {
  type        = bool
  description = "associate_public_ip_address to Instance"
  default     = false
}

variable "ami_id" {
  description = "Use ami_id instead of searching the AMI2 from Amazon"
  type        = string
  default     = null
}

variable "name" {
  description = "Instance Name. Default = host_name"
  type    = string
  default = null
}

variable "host_name" {
  type    = string
  default = ""
}

variable "root_disk_size" {
  type    = number
  default = 8
}

variable "root_disk_termination" {
  description = "Deletion Protection for disk"
  type    = bool
  default = true
}

variable "root_disk_encryption" {
  description = "Encryption of root disk"
  type    = bool
  default = true
}

variable "root_kms_key_id" {
  description = "optional encryption key"
  type    = string
  default = null
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "instance_type" {
  default = "t3a.nano"
}

variable "cpu_credits" {
  description = "cpu_credits for t3. standard or unlimited"
  default     = "standard"
}

variable "key_name" {
  default = ""
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of Security-Groups"
  default     = [""]
}

variable "private_ips" {
  type        = list(string)
  description = "Private IPs of EC2-Instances"
  default     = [""]
}

variable "route53_zone_id" {
  description = "zone_id for CNAME in route53"
  type        = string
}

variable "public_zone_id" {
  description = "zone_id for public_fqdn route53"
  type        = string
  default     = null
}

variable "dlm_policy" {
  description = "dlm_policy Name"
  type        = string
  default     = null
}

variable "shelvery_backup" {
  description = "Add tag shelvery:create_backup to instance resource"
  type        = bool
  default     = null
}

variable "custom_tags" {
  description = "Add tag shelvery:create_backup to instance resource"
  type        = map
  default     = { "this_dummy_is_removed_later" = null }
}

variable "create_elastic_ip" {
  type        = bool
  description = "create elastic IP for bastion host"
  default     = false
}

variable "ebs_optimized" {
  description = "If true, the launched EC2 instance will be EBS-optimized"
  type        = bool
  default     = false
}

variable "disable_api_termination" {
  description = "If true, enables EC2 Instance Termination Protection"
  type        = bool
  default     = false
}

variable "fail2ban_ignoreip" {
  type        = string
  description = "optinal String for ignoreip in fail2ban. Be aware! Changing this value invalidates user_data!"
  default     = "127.0.0.1/8"
}

variable "custom_RPMs" {
  type        = string
  description = "install custom RPMs on Bastion"
  default     = null
}

variable "install_option" {
  type        = string
  description = "install option in user_data. Be aware: Changing this value results in destroy and add resource"
  default     = ""
}

variable "security_group_ingres" {
  type = list(object({
    rule = string
    cidr_blocks = string
    from_port = number
    to_port = number
    description = string
  }))
  default = null
}