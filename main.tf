provider "aws" {
  region = "us-east-1"
}
#1.vpc
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
  tags={
    Name="example-vpc"
  }
}
#2.internet gateway
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
  tags={
    Name="example-igw"
  }
}
#3. 2 subnets 
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.1.0/24"
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
    tags={
      Name="example-subnet1"
    }
}
resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.2.0/24"
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
    tags={
      Name="example-subnet2"
    }
}
#4. Public route table
resource "aws_route_table" "example" {
  vpc_id = aws_vpc.example.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }
  tags={
    Name="example-public-rt"
  }
}
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.example.id
} 
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.example.id
} 

#5.ALB Security Group
resource "aws_security_group" "alb" {
  name        = "example-alb-sg"
  description = "Allow HTTP traffic"
  vpc_id      = aws_vpc.example.id

   ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#6.EC2 Security Group
resource "aws_security_group" "web" {
  name        = "example-web-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.example.id

   ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#7.Application Load Balancer

resource "aws_alb" "example" {
  name               = "example-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets=[
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
  tags={
    Name="example-alb"
  }
 
}
#8.Target Group 
resource "aws_lb_target_group" "example" {
  name     = "example-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.example.id
  health_check {
    enabled            = true
    path                = "/"
    protocol = "HTTP"
    interval            = 30
    matcher = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}
#9.Listener
resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_alb.example.arn
  port              = "80"
  protocol          = "HTTP"  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn                    
  }
}
# 10. Aws Instance
resource "aws_instance" "example" {
  ami           = "ami-0d97d7f07b25dd693"
  instance_type = "t3.micro"


}
#11.Aws launch template
resource "aws_launch_template" "example" {
  name_prefix   = "example-launch-template"
  image_id      = "ami-0d97d7f07b25dd693"
  instance_type = "t3.micro" 
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data=base64encode(<<-EOF
  #!/bin/bash
  apt-get update -y
  apt-get install -y nginx
  systemctl enable --now nginx
  echo '<h1>Welcome to the Web Server</h1>'
  \
   > /var/www/html/index.html"
   EOF
  )

}
#12. Auto Scaling Group
resource "aws_autoscaling_group" "example" {
  name="example-asg"
  min_size = 1
  max_size=2 
  desired_capacity=1
  vpc_zone_identifier =  [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id]
  target_group_arns = [
    aws_lb_target_group.example.arn
    ]
  health_check_type = "ELB"
  health_check_grace_period = 180
  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
    
     }
}  

#13. ALB DNs
output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value = aws_alb.example.dns_name
  
}
output "public_ip" {
  description = "The public IP address of the EC2 instance"
  value = aws_instance.example.public_ip
}
