# Provider
provider "aws" {
    region = var.region
    access_key = var.access_key
    secret_key = var.secret_key
}


# Custom VPC
resource "aws_vpc" "prod-vpc" {
    cidr_block = "172.28.0.0/16"
    enable_dns_hostnames = true
    tags = {
        Name = "prod-vpc"
    }
}
resource "aws_internet_gateway" "prod-igw" {
    vpc_id = aws_vpc.prod-vpc.id
        tags = {
        Name = "prod-igw"
    }
}
resource "aws_route_table" "prod-rt" {
    vpc_id = aws_vpc.prod-vpc.id
    route {
        cidr_block = var.all_ipv4
        gateway_id = aws_internet_gateway.prod-igw.id
    }
    route {
        ipv6_cidr_block = var.all_ipv6
        gateway_id = aws_internet_gateway.prod-igw.id
    }
}
resource "aws_subnet" "prod-subnet-1" {
    vpc_id = aws_vpc.prod-vpc.id
    cidr_block = "172.28.1.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
    tags = {
        Name = "prod-subnet-1"
    }
}
resource "aws_subnet" "prod-subnet-2" {
    vpc_id = aws_vpc.prod-vpc.id
    cidr_block = "172.28.2.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1b"
    tags = {
        Name = "prod-subnet-2"
    }
}
resource "aws_route_table_association" "subnet-rt" {
    subnet_id = aws_subnet.prod-subnet-1.id
    route_table_id = aws_route_table.prod-rt.id
}
resource "aws_route_table_association" "subnet-rt-2" {
    subnet_id = aws_subnet.prod-subnet-2.id
    route_table_id = aws_route_table.prod-rt.id
}


# Security Groups
resource "aws_security_group" "web-server-sg" {
  name        = "web-server-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description      = "HTTP Traffic"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [var.all_ipv4]
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = [var.my_ip_cidr]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [var.all_ipv4]
    ipv6_cidr_blocks = [var.all_ipv6]
  }

  tags = {
    Name = "web-server-sg"
  }
}
resource "aws_security_group" "web-server-alb-sg" {
  vpc_id = aws_vpc.prod-vpc.id
  name = "web-server-alb-sg"
  
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [var.all_ipv4]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [var.all_ipv4]
  }
  
}


# Autoscaling
resource "aws_launch_template" "asg-lt" {
  name_prefix   = "asg-lt-web-server"
  image_id      = lookup(var.AMI, var.region)
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web-server-sg.id]
}
resource "aws_autoscaling_group" "web-server-asg" {
  name = "web-server-asg"
  health_check_grace_period = 300
  health_check_type = "ELB"
  vpc_zone_identifier = [aws_subnet.prod-subnet-1.id, aws_subnet.prod-subnet-2.id]
  target_group_arns = [aws_lb_target_group.web-server-alb-tg.arn]
  max_size           = 6
  min_size           = 2
  desired_capacity   = 4
  launch_template {
    id      = aws_launch_template.asg-lt.id
    version = "$Latest"
  }
  tag {
    key = "Name"
    value = "web-server-asg"
    propagate_at_launch = true
  }
}
resource "aws_autoscaling_policy" "asg-policy-cpu-scaleup" {
  name = "asg-policy-cpu-scaleup"
  autoscaling_group_name = aws_autoscaling_group.web-server-asg.name
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = 1
  cooldown = 90
  policy_type = "SimpleScaling"
  
}
resource "aws_autoscaling_policy" "asg-policy-cpu-scaledown" {
  name = "asg-policy-cpu-scaleup"
  autoscaling_group_name = aws_autoscaling_group.web-server-asg.name
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown = 90
  policy_type = "SimpleScaling"
}
resource "aws_cloudwatch_metric_alarm" "asg-cpu-alarm-increase" {
  alarm_name = "asg-cpu-alarm-increase"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = 1
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = 120
  statistic = "Average"
  threshold = 80

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web-server-asg.name
  }
  actions_enabled = true
  alarm_actions = [aws_autoscaling_policy.asg-policy-cpu-scaleup.arn] 
}
resource "aws_cloudwatch_metric_alarm" "asg-cpu-alarm-decrease" {
  alarm_name = "asg-cpu-alarm-decrease"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = 1
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = 120
  statistic = "Average"
  threshold = 10

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web-server-asg.name
  }
  actions_enabled = true
  alarm_actions = [aws_autoscaling_policy.asg-policy-cpu-scaledown.arn] 
}


# Application Load Balancer
resource "aws_lb" "web-server-alb" {
  name               = "web-server-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web-server-alb-sg.id, aws_security_group.web-server-sg.id]
  subnets            = [aws_subnet.prod-subnet-1.id, aws_subnet.prod-subnet-2.id]

  enable_deletion_protection = false
  tags = {
    Environment = "production"
  }
}
resource "aws_lb_target_group" "web-server-alb-tg" {
  name     = "web-server-alb-tg"
  port     = 80
  protocol = "HTTP"
  health_check {
    path = "/"
    interval = 10
    timeout = 5
    healthy_threshold = 5
    unhealthy_threshold = 2
  }
  vpc_id   = aws_vpc.prod-vpc.id
}
resource "aws_lb_listener" "web-server-alb-listener" {
  load_balancer_arn = aws_lb.web-server-alb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.web-server-alb-tg.arn
    type = "forward"
  }
}