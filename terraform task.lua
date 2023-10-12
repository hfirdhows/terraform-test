# Variables
variable "aws_region" {
  default = "us-east-1"
}

variable "availability_zones" {
  default = ["us-east-1a", "us-east-1b"]
}

variable "app_port" {
  default = 80
}

variable "asg_min_size" {
  default = 2
}

variable "asg_max_size" {
  default = 4
}

variable "asg_desired_capacity" {
  default = 2
}

#
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

}

# Create two subnets in different availability zones
resource "aws_subnet" "subnet_a" {
  count = 2
  vpc_id     = aws_vpc.vpc.id
  cidr_block = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true
}

# Create a custom route table
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id
}

# Define your custom routes
resource "aws_route" "custom_route" {
  route_table_id         = aws_route_table.route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}
resource "aws_route_table_association" "subnet_association" {
  for_each        = { for idx, subnet in aws_subnet.subnet_a : idx => subnet }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_autoscaling_group" "asg" {
  name_prefix                 = "asg-group"
  launch_configuration        = aws_launch_configuration.lc.name
  vpc_zone_identifier         = aws_subnet.subnet_a[*].id
  min_size                    = var.asg_min_size
  max_size                    = var.asg_max_size
  desired_capacity            = var.asg_desired_capacity
  health_check_grace_period                    = 300 
}

resource "aws_launch_configuration""lc" {
  name_prefix                 = "lc"
  image_id                    = "ami-041feb57c611358bd" 
  instance_type               = "t2.micro"      
  security_groups             = [aws_security_group.sg.id]
  key_name                    = "task"
  associate_public_ip_address = true
}

resource "aws_security_group" "sg" {
  name        = "sg"
  description = "Security Group"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_instance" "instances" {
  count         = var.asg_desired_capacity
  ami           = aws_launch_configuration.lc.image_id
  instance_type = aws_launch_configuration.lc.instance_type
  subnet_id     = element(aws_subnet.subnet_a[*].id, count.index)
  key_name      = aws_launch_configuration.lc.key_name
  security_groups = [aws_security_group.sg.id]
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

}

resource "aws_lb" "alb" {
  name               = "alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.subnet_a[*].id
  enable_deletion_protection = false

  enable_http2 = true
}

resource "aws_lb_target_group" "target_group" {
  name     = "target-group"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port             = var.app_port
  protocol         = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
        content_type = "text/plain"
        status_code  = "200"
    }
  }

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"  
      status_code  = "502"

    }
  }
}
resource "aws_iam_role" "ec2_role" {
  name = "EC2Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "ec2_policy" {
  name        = "EC2Policy"
  description = "Policy for EC2 instances"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "ec2:*",
        Effect   = "Allow",
        Resource = "*",
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ec2_role_attachment" {
  name       = "EC2RoleAttachment"
  roles      = [aws_iam_role.ec2_role.name]
  policy_arn = aws_iam_policy.ec2_policy.arn
}

resource "aws_iam_instance_profile" "instance_profile" {
    name = "instance-profile"
    role = aws_iam_role.ec2-rolerole.name
  }