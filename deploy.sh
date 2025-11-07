#!/bin/bash
# deploy.sh - Complete AWS CLI Deployment Script for Qwen3-VL Demo

set -e  # Exit on any error

# Configuration
PROJECT_NAME="qwen3-vl-demo"
AWS_REGION="us-west-2"
KEY_PAIR_NAME="qwen3-vl-key"
SECURITY_GROUP_NAME="qwen3-vl-sg"
VPC_NAME="qwen3-vl-vpc"
SUBNET_NAME="qwen3-vl-subnet"
INSTANCE_TYPE="t3.medium"
AMI_ID="ami-0abcdef1234567890"  # Update with current Amazon Linux 2 AMI
BUCKET_NAME="qwen3-vl-app-bucket-$(date +%s)"  # Unique bucket name
S3_PREFIX="qwen3-vl"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if AWS CLI is configured
check_aws_config() {
    log "Checking AWS CLI configuration..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured. Please run 'aws configure' first."
    fi
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $ACCOUNT_ID"
}

# Create VPC and networking
create_network() {
    log "Creating VPC and networking infrastructure..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
        --query 'Vpc.VpcId' --output text)
    log "Created VPC: $VPC_ID"
    
    # Enable DNS hostnames
    aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
    
    # Create public subnet
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME}]" \
        --query 'Subnet.SubnetId' --output text)
    log "Created subnet: $SUBNET_ID"
    
    # Create and configure route table
    ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-rt}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
    aws ec2 associate-route-table --subnet-id $SUBNET_ID --route-table-id $ROUTE_TABLE_ID
    
    # Create Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
    
    # Create Elastic IP for NAT Gateway
    ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
    
    # Create NAT Gateway
    NAT_GW_ID=$(aws ec2 create-nat-gateway \
        --subnet-id $SUBNET_ID \
        --allocation-id $ALLOCATION_ID \
        --query 'NatGateway.NatGatewayId' --output text)
    
    log "Created NAT Gateway: $NAT_GW_ID"
    log "Waiting for NAT Gateway to be available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID
}

# Create security groups
create_security_groups() {
    log "Creating security groups..."
    
    # Main security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name $SECURITY_GROUP_NAME \
        --description "Security group for Qwen3-VL application" \
        --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SECURITY_GROUP_NAME}]" \
        --query 'GroupId' --output text)
    
    log "Created security group: $SG_ID"
    
    # Add inbound rules
    log "Adding inbound security rules..."
    
    # SSH access (restrict to your IP)
    MY_IP=$(curl -s https://checkip.amazonaws.com/)
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 22 \
        --cidr ${MY_IP}/32
    
    # HTTP access
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    # HTTPS access
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    # Application port
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 8080 \
        --cidr 0.0.0.0/0
    
    # Add outbound rules (CRITICAL for external access)
    log "Adding outbound security rules..."
    
    # HTTP/HTTPS for external API calls
    aws ec2 authorize-security-group-egress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-egress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    # Full access for other ports (OSS, APIs, etc.)
    aws ec2 authorize-security-group-egress \
        --group-id $SG_ID \
        --protocol tcp \
        --port -1 \
        --cidr 0.0.0.0/0
    
    # UDP for streaming services
    aws ec2 authorize-security-group-egress \
        --group-id $SG_ID \
        --protocol udp \
        --port -1 \
        --cidr 0.0.0.0/0
    
    log "Security group configured with full external access"
}

# Create S3 bucket for application storage
create_s3_bucket() {
    log "Creating S3 bucket for application storage..."
    
    # Create bucket (with region-specific command for us-west-2)
    aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION
    
    # Set bucket policy for public read access (if needed)
    cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://bucket-policy.json
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket $BUCKET_NAME \
        --versioning-configuration Status=Enabled
    
    log "S3 bucket created: s3://$BUCKET_NAME"
}

# Create key pair for EC2 access
create_key_pair() {
    log "Creating key pair for EC2 access..."
    
    if [ ! -f "${KEY_PAIR_NAME}.pem" ]; then
        aws ec2 create-key-pair \
            --key-name $KEY_PAIR_NAME \
            --query 'KeyMaterial' \
            --output text > ${KEY_PAIR_NAME}.pem
        
        chmod 400 ${KEY_PAIR_NAME}.pem
        log "Key pair created: ${KEY_PAIR_NAME}.pem"
    else
        warn "Key pair file already exists: ${KEY_PAIR_NAME}.pem"
    fi
}

# Prepare application files
prepare_application() {
    log "Preparing application files for S3 upload..."
    
    # Create deployment directory
    DEPLOY_DIR="deployment"
    mkdir -p $DEPLOY_DIR
    
    # Copy application files
    cp app_prod.py $DEPLOY_DIR/
    cp config.py $DEPLOY_DIR/
    cp requirements.txt $DEPLOY_DIR/
    cp -r assets $DEPLOY_DIR/ 2>/dev/null || true
    cp -r ui_components $DEPLOY_DIR/ 2>/dev/null || true
    
    # Create production requirements
    cat > $DEPLOY_DIR/requirements-prod.txt << EOF
gradio>=5.0.0
modelscope_studio>=0.3.0
openai>=1.0.0
oss2>=2.18.0
gunicorn>=21.2.0
boto3>=1.26.0
requests>=2.28.0
EOF
    
    # Create optimized user data script
    create_user_data_script
}

# Create EC2 user data script
create_user_data_script() {
    log "Creating EC2 user data script..."
    
    cat > user-data.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Initializing Qwen3-VL Demo Application"

# Update system
yum update -y
yum install -y python3 python3-pip nginx curl wget netcat-openbsd

# Disable firewall
systemctl stop firewalld
systemctl disable firewalld

# Configure network
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# Install Python dependencies
pip3 install --upgrade pip
pip3 install -r /opt/app/requirements-prod.txt

# Create application directory
mkdir -p /opt/qwen3-vl-demo
cd /opt/qwen3-vl-demo

# Download application from S3
aws s3 sync s3://BUCKET_PLACEHOLDER/ /opt/qwen3-vl-demo/

# Test network connectivity
echo "🌐 Testing network connectivity..."
ping -c 3 8.8.8.8 || echo "⚠️ Network connectivity issue"

# Test external API access
echo "🔍 Testing external API access..."
curl -s -I https://openrouter.ai/api/v1/models || echo "⚠️ OpenRouter API access issue"

# Create systemd service
cat > /etc/systemd/system/qwen3-vl-demo.service << 'SERVICEEOF'
[Unit]
Description=Qwen3-VL Demo Application
After=network.target
Wants=network.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/opt/qwen3-vl-demo
Environment=API_KEY=API_KEY_PLACEHOLDER
Environment=MODELSCOPE_ENVIRONMENT=production
Environment=PORT=8080
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:8080 --workers 2 --timeout 300 app_prod:demo
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Configure Nginx
create_nginx_config

# Start services
systemctl daemon-reload
systemctl enable qwen3-vl-demo
systemctl start qwen3-vl-demo

systemctl enable nginx
systemctl restart nginx

# Wait for application to start
sleep 30

# Health check
echo "🧪 Performing health check..."
curl -f http://localhost:8080 || echo "⚠️ Application health check failed"

echo "✅ Qwen3-VL Demo initialization complete"

create_nginx_config() {
    cat > /etc/nginx/conf.d/qwen3-vl.conf << 'NGINXEOF'
server {
    listen 80;
    server_name _;
    
    # Extended timeouts for Gradio
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
    client_body_timeout 300s;
    client_header_timeout 300s;
    
    # Headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_buffering off;
        proxy_cache off;
        proxy_redirect off;
    }
    
    location /health {
        proxy_pass http://127.0.0.1:8080/health;
        access_log off;
    }
}
NGINXEOF
}
EOF
    
    # Replace placeholders
    sed -i "s/BUCKET_PLACEHOLDER/$BUCKET_NAME/g" user-data.sh
    sed -i "s/API_KEY_PLACEHOLDER/${API_KEY}/g" user-data.sh
    
    log "User data script created"
}

# Upload application to S3
upload_application() {
    log "Uploading application to S3..."
    
    aws s3 sync deployment/ s3://$BUCKET_NAME/$S3_PREFIX/ --delete
    
    log "Application uploaded to s3://$BUCKET_NAME/$S3_PREFIX/"
}

# Launch EC2 instance
launch_instance() {
    log "Launching EC2 instance..."
    
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id $AMI_ID \
        --count 1 \
        --instance-type $INSTANCE_TYPE \
        --key-name $KEY_PAIR_NAME \
        --security-group-ids $SG_ID \
        --subnet-id $SUBNET_ID \
        --user-data file://user-data.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$PROJECT_NAME}]" \
        --query 'Instances[0].InstanceId' --output text)
    
    log "Instance launched: $INSTANCE_ID"
    log "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID
    
    # Get instance details
    PUBLIC_DNS=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicDnsName' \
        --output text)
    
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    log "Instance Details:"
    log "  - Instance ID: $INSTANCE_ID"
    log "  - Public DNS: $PUBLIC_DNS"
    log "  - Public IP: $PUBLIC_IP"
    
    # Wait for application to be ready
    log "Waiting for application to be ready..."
    sleep 60
    
    # Test application
    if curl -f http://$PUBLIC_IP:8080 >/dev/null 2>&1; then
        log "✅ Application is running successfully!"
        log "Access your application at: http://$PUBLIC_IP:8080"
    else
        warn "Application may not be ready yet. Check logs with:"
        warn "ssh -i ${KEY_PAIR_NAME}.pem ec2-user@$PUBLIC_IP"
        warn "sudo journalctl -u qwen3-vl-demo -f"
    fi
}

# Create Application Load Balancer (optional)
create_load_balancer() {
    read -p "Do you want to create an Application Load Balancer? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Creating Application Load Balancer..."
        
        # Create ALB
        ALB_ARN=$(aws elbv2 create-load-balancer \
            --name ${PROJECT_NAME}-alb \
            --subnets $SUBNET_ID \
            --security-groups $SG_ID \
            --query 'LoadBalancers[0].LoadBalancerArn' --output text)
        
        # Create target group
        TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
            --name ${PROJECT_NAME}-tg \
            --protocol HTTP \
            --port 80 \
            --vpc-id $VPC_ID \
            --target-type instance \
            --health-check-path /health \
            --query 'TargetGroups[0].TargetGroupArn' --output text)
        
        # Create listener
        LISTENER_ARN=$(aws elbv2 create-listener \
            --load-balancer-arn $ALB_ARN \
            --protocol HTTP \
            --port 80 \
            --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
            --query 'Listeners[0].ListenerArn' --output text)
        
        # Register instance with target group
        aws elbv2 register-targets \
            --target-group-arn $TARGET_GROUP_ARN \
            --targets Id=$INSTANCE_ID,Port=80
        
        ALB_DNS=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns $ALB_ARN \
            --query 'LoadBalancers[0].DNSName' --output text)
        
        log "Load Balancer created: http://$ALB_DNS"
        log "Registering instance with load balancer..."
        aws elbv2 wait target-in-service \
            --target-group-arn $TARGET_GROUP_ARN \
            --targets Id=$INSTANCE_ID,Port=80
    fi
}

# Setup monitoring
setup_monitoring() {
    log "Setting up CloudWatch monitoring..."
    
    # Create log group
    aws logs create-log-group --log-group-name "/aws/ec2/$PROJECT_NAME" || true
    
    # Create SNS topic for alerts
    SNS_TOPIC_ARN=$(aws sns create-topic --name ${PROJECT_NAME}-alerts --query 'TopicArn' --output text)
    
    log "Monitoring setup complete"
    log "SNS Topic: $SNS_TOPIC_ARN"
}

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Cleaning up resources..."
        # Add cleanup commands here
    fi
}

trap cleanup EXIT

# Main execution
main() {
    log "Starting AWS CLI deployment for $PROJECT_NAME"
    log "Region: $AWS_REGION"
    
    # Check prerequisites
    check_aws_config
    
    # Get API key from user
    if [ -z "$API_KEY" ]; then
        read -sp "Enter your OpenRouter API key: " API_KEY
        echo
    fi
    
    # Create infrastructure
    create_network
    create_security_groups
    create_s3_bucket
    create_key_pair
    prepare_application
    upload_application
    launch_instance
    create_load_balancer
    setup_monitoring
    
    log "🎉 Deployment completed successfully!"
    log "Don't forget to:"
    log "1. Update your API key in the instance if not set via environment"
    log "2. Configure your domain DNS to point to the instance or ALB"
    log "3. Set up SSL certificates for production use"
}

# Help function
show_help() {
    cat << EOF
AWS CLI Deployment Script for Qwen3-VL Demo

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -r, --region REGION AWS region (default: us-west-2)
    -t, --type TYPE     Instance type (default: t3.medium)
    -k, --key-name NAME Key pair name (default: qwen3-vl-key)

Environment Variables:
    API_KEY             OpenRouter API key (required)

Examples:
    $0                           # Interactive mode
    API_KEY=your-key $0          # Non-interactive mode
    $0 -r us-east-1 -t t3.large  # Custom region and instance type

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -t|--type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        -k|--key-name)
            KEY_PAIR_NAME="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Run main function
main