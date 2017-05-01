### Introduction
A simple Terraform module and Python lambda function to automatically update Route53 records for instances created by 
AutoScaling.

### Requirements
* Terraform (tested on version 0.8)
* Python 2.7
* zip

### Usage

```hcl-terraform
data "template_file" "user_data" {
    template = <<-EOF
#!/bin/bash

echo "Hello World!"

    EOF
}

module "service" {
  source             = "github.com/gruzewski/terraform"
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
```

### Troubleshooting

```bash
error: must supply either home or prefix/exec-prefix -- not both
```

There is a known bug in pip with python installed via Homebrew. Workaround is to run below (but please remove it afterwards):

```bash
echo -e '[install]\nprefix=' > ~/.pydistutils.cfg
```