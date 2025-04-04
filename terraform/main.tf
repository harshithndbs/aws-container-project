provider "aws" {
  region = "us-east-1"
}

# Use existing default VPC
data "aws_vpc" "main" {
  default = true
}

# Fetch default subnets in the VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

# Fetch existing Internet Gateway if one exists for the default VPC
data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

# Public Route Table (using existing or creating a new one)
resource "aws_route_table" "public_rt" {
  vpc_id = data.aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.default.id
  }
  
  tags = {
    Name = "public-route-table"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  
  tags = {
    Name = "nat-eip"
  }
}

# NAT Gateway (using one of the default subnets)
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = data.aws_subnets.default.ids[0]
  
  tags = {
    Name = "main-nat-gw"
  }
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = data.aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  
  tags = {
    Name = "private-route-table"
  }
}

# Security Group
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web and SSH traffic"
  vpc_id      = data.aws_vpc.main.id
  
  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }
  
  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }
  
  # Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "web-security-group"
  }
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                    = "ami-0440d3b780d96b29d" # Amazon Linux 2023 AMI
  instance_type          = "t2.micro"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = "eventify-key" # Make sure to create this key pair
  
  user_data = <<-EOF
    #!/bin/bash
    # Update packages
    dnf update -y
    
    # Install Docker
    dnf install -y docker
    
    # Start Docker service
    systemctl start docker
    systemctl enable docker
    
    # Add ec2-user to docker group
    usermod -a -G docker ec2-user
    
    # Create app directory
    mkdir -p /app/html
    
    # Create a test HTML file
    cat > /app/html/index.html << 'HTMLEND'
    <!DOCTYPE html>
    <html>
    <head>
      <title>AWS Container Deployment</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        h1 { color: #0066cc; }
        .container { border: 1px solid #ddd; padding: 20px; border-radius: 5px; }
        .success { color: green; font-weight: bold; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>AWS Container Deployment Success!</h1>
        <p class="success"> Docker container is running successfully</p>
        <p>This page is being served from a Docker container running on AWS EC2.</p>
        <p>Server Time: <span id="server-time"></span></p>
        <p>Deployment Information:</p>
        <ul>
          <li>EC2 Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</li>
          <li>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</li>
          <li>Deployment Time: $(date)</li>
        </ul>
      </div>
      <script>
        function updateTime() {
          document.getElementById('server-time').textContent = new Date().toLocaleString();
        }
        updateTime();
        setInterval(updateTime, 1000);
      </script>
    </body>
    </html>
    HTMLEND
    
    # Create Dockerfile
    cat > /app/Dockerfile << 'DOCKEREND'
    FROM nginx:alpine
    COPY html/index.html /usr/share/nginx/html/index.html
    EXPOSE 80
    CMD ["nginx", "-g", "daemon off;"]
    DOCKEREND
    
    # Build and run container
    cd /app
    docker build -t webapp .
    docker run -d -p 80:80 --name webapp webapp
  EOF
  
  tags = {
    Name = "Web-Server"
  }
}

# Output the public IP
output "web_ip" {
  value = aws_instance.web.public_ip
}
