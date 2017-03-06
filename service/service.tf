variable "ami_id" {
  default     = "ami-6f587e1c"
  description = "AMI id. Defaults to Ubuntu 16.04 HVM"
}

variable "availability_zones" {
  default     = ["eu-west-1a", "eu-west-1b"]
  type        = "list"
  description = "List of Availability Zones"
}

variable "cname" {
  description = "CNAME of the instance"
}

variable "environment" {
  description = "Environment"
}

variable "instance_profile" {
  description = "IAM instance profile"
}

variable "instance_type" {
  default     = "t2.small"
  description = "Instance type"
}

variable "role" {
  description = "Name of the whole stack"
}

variable "region" {
  default     = "eu-west-1"
  description = "Region where EC2 instance is running"
}

variable "root_volume_size" {
  default     = 8
  description = "A size of HA instance"
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
  description = "Subnet IDs"
}

variable "user_data" {
  description = "User data script used in launch configuration"
}

variable "zone_id" {
  description = "Zone ID for public DNS"
}

# --------------- AUTOSCALING --------------- #

resource "aws_launch_configuration" "main" {
  name_prefix                 = "${var.environment}-${var.role}-"
  image_id                    = "${var.ami_id}"
  instance_type               = "${var.instance_type}"
  iam_instance_profile        = "${var.instance_profile}"
  ebs_optimized               = false
  key_name                    = "${var.ssh_key_name}"
  security_groups             = ["${var.security_groups}"]
  user_data                   = "${var.user_data}"
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.root_volume_size}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "main" {
  name                 = "${var.environment}-${var.role}"
  availability_zones   = "${var.availability_zones}"
  vpc_zone_identifier  = "${var.subnet_ids}"
  launch_configuration = "${aws_launch_configuration.main.id}"
  min_size             = 1
  max_size             = 1
  desired_capacity     = 1
  termination_policies = ["OldestLaunchConfiguration", "Default"]

  tag {
    key                 = "Name"
    value               = "${var.environment}-${var.role}"
    propagate_at_launch = true
  }

  tag {
    key                 = "CNAME"
    value               = "vpn"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "${var.environment}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "${var.role}"
    propagate_at_launch = true
  }

  depends_on = ["aws_launch_configuration.main", "aws_cloudwatch_event_target.lambda"]

  lifecycle {
    create_before_destroy = true
  }
}

# --------------- IAM Role for Lambda --------------- #

resource "aws_iam_role" "lambda_ha_role" {
  name = "${var.environment}-${var.role}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com"
        ]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_ha_role_policy" {
  name = "${var.environment}-${var.role}"
  role = "${aws_iam_role.lambda_ha_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaReadAccess",
      "Action": [
        "ec2:DescribeInstances",
        "route53:GetHostedZone"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Sid": "LambdaWriteAccess",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/${var.zone_id}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# --------------- CLOUDWATCH --------------- #

resource "aws_cloudwatch_event_rule" "asg_scale_event" {
  name        = "${var.environment}-${var.role}"
  description = "An AWS Cloudwatch event for updating public entires"

  event_pattern = <<PATTERN
{
  "source": [ "aws.autoscaling" ],
  "detail-type": [ "EC2 Instance Launch Successful" ],
  "detail": {
    "AutoScalingGroupName": [ "${var.environment}-${var.role}" ]
  }
}
PATTERN
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = "${aws_cloudwatch_event_rule.asg_scale_event.name}"
  target_id = "${var.environment}-${var.role}"
  arn       = "${aws_lambda_function.attach_lambda_function.arn}"
}

# --------------- LAMBDA --------------- #

data "template_file" "info_file" {
  template = "${file("${path.module}/templates/settings.yml.tpl")}"

  vars {
    region   = "${var.region}"
    zone_id  = "${var.zone_id}"
  }
}

resource "null_resource" "prepare-lambda" {
  triggers {
    main         = "${base64sha256(file("${path.module}/files/update_public_info.py"))}"
    lib          = "${base64sha256(file("${path.module}/files/aws.py"))}"
    requirements = "${base64sha256(file("${path.module}/files/requirements.txt"))}"
    temmplate    = "${base64sha256(data.template_file.info_file.rendered)}"
  }

  provisioner "local-exec" {
    command = "rm -rf ${path.module}/output || true"
  }

  provisioner "local-exec" {
    command = "mkdir ${path.module}/output || true"
  }

  provisioner "local-exec" {
    command = "echo $\"${data.template_file.info_file.rendered}\" > ${path.module}/output/settings.yml"
  }

  provisioner "local-exec" {
    command = "pip install -r ${path.module}/files/requirements.txt -t ${path.module}/output"
  }

  provisioner "local-exec" {
    command = "cp ${path.module}/files/* ${path.module}/output"
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/output && zip -r lambda.zip ."
  }
}

resource "aws_lambda_function" "attach_lambda_function" {
  filename      = "${path.module}/output/lambda.zip"
  function_name = "${var.environment}-${var.role}"
  role          = "${aws_iam_role.lambda_ha_role.arn}"
  description   = "An AWS Lambda function for ${var.environment}-${var.role}"
  handler       = "update_public_info.handler"
  timeout       = "10"
  runtime       = "python2.7"

  depends_on = ["null_resource.prepare-lambda"]
}

resource "aws_lambda_alias" "attach_lambda_alias" {
  name             = "${var.environment}-${var.role}"
  description      = "An AWS Lambda function for EC2 HA"
  function_name    = "${aws_lambda_function.attach_lambda_function.arn}"
  function_version = "$LATEST"
}

resource "aws_lambda_permission" "attach_lambda_permission" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.attach_lambda_function.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.asg_scale_event.arn}"
}