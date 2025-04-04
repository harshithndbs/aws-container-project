provider "aws" {
  region = "us-east-1"
}

# Use existing default VPC
data "aws_vpc" "main" {
  default = true
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "main-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "public-subnet-2"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  
  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  
  tags = {
    Name = "private-subnet-2"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  
  tags = {
    Name = "nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id
  
  tags = {
    Name = "main-nat-gw"
  }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "public-route-table"
  }
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  
  tags = {
    Name = "private-route-table"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Group
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web and SSH traffic"
  vpc_id      = aws_vpc.main.id
  
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
  subnet_id              = aws_subnet.public_subnet_1.id
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
