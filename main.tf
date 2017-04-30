variable "ami_id" {
  description = "AMI ID "
}

variable "availability_zones" {
  type        = "list"
  description = "List of Availability Zones"
}

variable "environment" {
  description = "Environment"
}

variable "instance_type" {
  description = "Instance type"
}

variable "region" {
  description = "Region"
}

variable "root_volume_size" {
  description = "Root volume size"
}

variable "security_groups" {
  type        = "list"
  description = "List of security groups"
}

variable "ssh_key_name" {
  description = "SSH Key name"
}

variable "subnet_ids" {
  type        = "list"
  description = "List of subnet IDs"
}

variable "zone_id" {
  description = "Public DNS Zone ID"
}

# --------------- PROVIDER --------------- #

provider "aws" {
  region  = "eu-west-1"
  profile = "private"
}

# --------------- SERVICE USER DATA --------------- #

data "template_file" "user_data" {
    template = <<-EOF
#!/bin/bash

echo "Hello World!"

    EOF
}

# --------------- SERVICE --------------- #

module "service" {
  source             = "./service"
  ami_id             = "${var.ami_id}"
  availability_zones = "${var.availability_zones}"
  cname              = "service"
  environment        = "${var.environment}"
  instance_profile   = ""
  instance_type      = "t2.small"
  role               = "service"
  region             = "${var.region}"
  root_volume_size   = 8
  security_groups    = "${var.security_groups}"
  ssh_key_name       = "${var.ssh_key_name}"
  subnet_ids         = "${var.subnet_ids}"
  user_data          = "${data.template_file.user_data.rendered}"
  zone_id            = "${var.zone_id}"
}