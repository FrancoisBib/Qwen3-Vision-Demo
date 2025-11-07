#!/bin/bash
# monitoring-setup.sh - CLI-based CloudWatch Monitoring Setup for Qwen3-VL Demo

set -e

# Configuration
PROJECT_NAME="qwen3-vl-demo"
AWS_REGION="us-west-2"
LOG_GROUP_NAME="/aws/ec2/$PROJECT_NAME"
METRIC_NAMESPACE="Qwen3VL/Application"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; }

# Check if AWS CLI is configured
check_aws_config() {
    log "Checking AWS CLI configuration..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured. Please run 'aws configure' first."
    fi
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $ACCOUNT_ID"
}

# Find EC2 instances for the project
find_instances() {
    log "Finding EC2 instances for $PROJECT_NAME..."
    
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$PROJECT_NAME" \
        --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' \
        --output text)
    
    if [ -z "$INSTANCE_IDS" ] || [ "$INSTANCE_IDS" = "None" ]; then
        error "No running instances found for project $PROJECT_NAME"
        return 1
    fi
    
    log "Found instances: $INSTANCE_IDS"
    return 0
}

# Install CloudWatch Agent on instances
install_cloudwatch_agent() {
    log "Installing CloudWatch Agent on instances..."
    
    # Create SSM command document
    cat > cloudwatch-install.json << 'EOF'
{
    "schemaVersion": "2.2",
    "description": "Install and configure CloudWatch Agent",
    "parameters": {},
    "mainSteps": [
        {
            "action": "aws:downloadContent",
            "name": "downloadCloudWatchAgentContent",
            "inputs": {
                "source": "https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm",
                "destination": "/tmp/amazon-cloudwatch-agent.rpm"
            }
        },
        {
            "action": "aws:runShellScript",
            "name": "installCloudWatchAgent",
            "inputs": {
                "runCommand": "rpm -U /tmp/amazon-cloudwatch-agent.rpm"
            }
        },
        {
            "action": "aws:runShellScript",
            "name": "createCloudWatchConfig",
            "inputs": {
                "runCommand": "mkdir -p /opt/aws/amazon-cloudwatch-agent/etc"
            }
        }
    ]
}
EOF
    
    # Send command to all instances
    for INSTANCE_ID in $INSTANCE_IDS; do
        log "Installing CloudWatch Agent on $INSTANCE_ID..."
        
        COMMAND_ID=$(aws ssm send-command \
            --instance-ids $INSTANCE_ID \
            --document-name "AWS-RunShellScript" \
            --parameters commands="rpm -U https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm" \
            --query 'Command.CommandId' --output text)
        
        log "Command sent to $INSTANCE_ID. Command ID: $COMMAND_ID"
        
        # Wait for command to complete
        aws ssm wait command-executed --command-id $COMMAND_ID --instance-id $INSTANCE_ID
        log "CloudWatch Agent installation completed for $INSTANCE_ID"
    done
    
    rm -f cloudwatch-install.json
}

# Create CloudWatch configuration
create_cloudwatch_config() {
    log "Creating CloudWatch configuration..."
    
    cat > cloudwatch-config.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/qwen3-vl-demo.log",
                        "log_group_name": "$LOG_GROUP_NAME/app",
                        "log_stream_name": "{instance_id}/app",
                        "timestamp_format": "%Y-%m-%d %H:%M:%S"
                    },
                    {
                        "file_path": "/var/log/nginx/access.log",
                        "log_group_name": "$LOG_GROUP_NAME/nginx-access",
                        "log_stream_name": "{instance_id}/access",
                        "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
                    },
                    {
                        "file_path": "/var/log/nginx/error.log",
                        "log_group_name": "$LOG_GROUP_NAME/nginx-error",
                        "log_stream_name": "{instance_id}/error",
                        "timestamp_format": "%Y/%m/%d %H:%M:%S"
                    },
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "$LOG_GROUP_NAME/system",
                        "log_stream_name": "{instance_id}/system"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "$METRIC_NAMESPACE",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF
    
    log "CloudWatch configuration created: cloudwatch-config.json"
}

# Deploy CloudWatch configuration to instances
deploy_config() {
    log "Deploying CloudWatch configuration to instances..."
    
    # Create log groups
    log "Creating CloudWatch log groups..."
    aws logs create-log-group --log-group-name "$LOG_GROUP_NAME/app" || true
    aws logs create-log-group --log-group-name "$LOG_GROUP_NAME/nginx-access" || true
    aws logs create-log-group --log-group-name "$LOG_GROUP_NAME/nginx-error" || true
    aws logs create-log-group --log-group-name "$LOG_GROUP_NAME/system" || true
    
    # Set retention policies
    log "Setting log retention policies..."
    aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME/app" --retention-in-days 7
    aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME/nginx-access" --retention-in-days 3
    aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME/nginx-error" --retention-in-days 7
    aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME/system" --retention-in-days 3
    
    # Deploy configuration to each instance
    for INSTANCE_ID in $INSTANCE_IDS; do
        log "Deploying config to $INSTANCE_ID..."
        
        # Copy config file to instance
        aws s3 cp cloudwatch-config.json s3://aws-ssm-${ACCOUNT_ID}-${AWS_REGION}/cloudwatch-config.json
        
        # Download and apply config
        COMMAND_ID=$(aws ssm send-command \
            --instance-ids $INSTANCE_ID \
            --document-name "AWS-RunShellScript" \
            --parameters commands="
                aws s3 cp s3://aws-ssm-${ACCOUNT_ID}-${AWS_REGION}/cloudwatch-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
                systemctl restart amazon-cloudwatch-agent
                systemctl enable amazon-cloudwatch-agent
            " \
            --query 'Command.CommandId' --output text)
        
        log "Config deployment command sent. Command ID: $COMMAND_ID"
        aws ssm wait command-executed --command-id $COMMAND_ID --instance-id $INSTANCE_ID
        log "Configuration deployed successfully to $INSTANCE_ID"
    done
}

# Create CloudWatch alarms
create_alarms() {
    log "Creating CloudWatch alarms..."
    
    # CPU Utilization Alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-High-CPU" \
        --alarm-description "Alarm when CPU exceeds 80%" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts \
        --dimensions Name=InstanceId,Value=${INSTANCE_IDS%% *} \
        --ok-actions arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts
    
    # Memory Utilization Alarm (using custom metric)
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-High-Memory" \
        --alarm-description "Alarm when memory exceeds 85%" \
        --metric-name mem_used_percent \
        --namespace $METRIC_NAMESPACE \
        --statistic Average \
        --period 300 \
        --threshold 85 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts \
        --dimensions Name=InstanceId,Value=${INSTANCE_IDS%% *} \
        --ok-actions arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts
    
    # Disk Space Alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-High-Disk-Usage" \
        --alarm-description "Alarm when disk usage exceeds 90%" \
        --metric-name used_percent \
        --namespace $METRIC_NAMESPACE \
        --statistic Average \
        --period 300 \
        --threshold 90 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts \
        --dimensions Name=InstanceId,Value=${INSTANCE_IDS%% *} \
        --ok-actions arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts
    
    # Application Health Alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-Application-Down" \
        --alarm-description "Alarm when application is not responding" \
        --metric-name HealthCheck \
        --namespace $METRIC_NAMESPACE \
        --statistic Average \
        --period 60 \
        --threshold 0 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts \
        --dimensions Name=InstanceId,Value=${INSTANCE_IDS%% *} \
        --ok-actions arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts
    
    log "CloudWatch alarms created"
}

# Create SNS topic for alerts
create_sns_topic() {
    log "Creating SNS topic for alerts..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic --name ${PROJECT_NAME}-alerts --query 'TopicArn' --output text)
    echo $SNS_TOPIC_ARN
    
    # Create email subscription
    read -p "Enter email address for alert notifications: " EMAIL
    if [ -n "$EMAIL" ]; then
        aws sns subscribe \
            --topic-arn $SNS_TOPIC_ARN \
            --protocol email \
            --notification-endpoint $EMAIL
        
        log "SNS topic created: $SNS_TOPIC_ARN"
        log "Please check your email and confirm the subscription"
    fi
}

# Create custom application metrics
create_application_metrics() {
    log "Creating application metrics collection script..."
    
    cat > collect-metrics.py << 'EOF'
#!/usr/bin/env python3
import boto3
import requests
import json
import time
from datetime import datetime
import subprocess
import psutil

def get_system_metrics():
    """Collect system metrics"""
    return {
        'cpu_percent': psutil.cpu_percent(interval=1),
        'memory_percent': psutil.virtual_memory().percent,
        'disk_percent': psutil.disk_usage('/').percent,
        'network_bytes_sent': psutil.net_io_counters().bytes_sent,
        'network_bytes_recv': psutil.net_io_counters().bytes_recv,
        'timestamp': datetime.utcnow().isoformat()
    }

def check_application_health():
    """Check application health"""
    try:
        response = requests.get('http://localhost:8080/health', timeout=5)
        return {
            'status': 1 if response.status_code == 200 else 0,
            'response_time': response.elapsed.total_seconds(),
            'status_code': response.status_code
        }
    except:
        return {
            'status': 0,
            'response_time': 999,
            'status_code': 0
        }

def put_cloudwatch_metrics(metrics, namespace):
    """Put metrics to CloudWatch"""
    cloudwatch = boto3.client('cloudwatch')
    
    metric_data = []
    for metric_name, value in metrics.items():
        if isinstance(value, (int, float)):
            metric_data.append({
                'MetricName': metric_name,
                'Value': value,
                'Unit': 'Count' if metric_name in ['status'] else 'Percent',
                'Timestamp': datetime.utcnow()
            })
    
    if metric_data:
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=metric_data
        )

def main():
    namespace = 'Qwen3VL/Application'
    
    # Collect metrics
    system_metrics = get_system_metrics()
    health_metrics = check_application_health()
    
    # Combine metrics
    all_metrics = {**system_metrics, **health_metrics}
    
    # Send to CloudWatch
    put_cloudwatch_metrics(all_metrics, namespace)
    
    print(f"Metrics collected: {all_metrics}")

if __name__ == "__main__":
    main()
EOF
    
    chmod +x collect-metrics.py
    
    # Deploy metrics collection script to instances
    for INSTANCE_ID in $INSTANCE_IDS; do
        log "Deploying metrics collection script to $INSTANCE_ID..."
        
        aws ssm send-command \
            --instance-ids $INSTANCE_ID \
            --document-name "AWS-RunShellScript" \
            --parameters commands="
                aws s3 cp collect-metrics.py /opt/qwen3-vl-demo/
                chmod +x /opt/qwen3-vl-demo/collect-metrics.py
                echo '*/5 * * * * /usr/bin/python3 /opt/qwen3-vl-demo/collect-metrics.py >> /var/log/qwen3-metrics.log 2>&1' | crontab -
            " \
            --query 'Command.CommandId' --output text
    done
}

# Create monitoring dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    cat > dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/EC2", "CPUUtilization", "InstanceId", "${INSTANCE_IDS%% *}" ],
                    [ ".", "NetworkIn", ".", "." ],
                    [ ".", "NetworkOut", ".", "." ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "EC2 Instance Metrics",
                "period": 300
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "${METRIC_NAMESPACE}", "mem_used_percent", "InstanceId", "${INSTANCE_IDS%% *}" ],
                    [ ".", "disk_percent", ".", "." ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "System Resource Usage",
                "period": 300
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 12,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '${LOG_GROUP_NAME}/app' | fields @timestamp, @message | sort @timestamp desc | limit 50",
                "view": "table",
                "region": "${AWS_REGION}",
                "title": "Application Logs"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${PROJECT_NAME}-Dashboard" \
        --dashboard-body file://dashboard.json
    
    log "Dashboard created: ${PROJECT_NAME}-Dashboard"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -f cloudwatch-config.json dashboard.json collect-metrics.py
}

trap cleanup EXIT

# Main execution
main() {
    log "Setting up CloudWatch monitoring for $PROJECT_NAME"
    log "Region: $AWS_REGION"
    
    # Check prerequisites
    check_aws_config
    
    # Find instances
    if ! find_instances; then
        error "Cannot proceed without running instances"
        exit 1
    fi
    
    # Setup monitoring infrastructure
    create_sns_topic
    create_cloudwatch_config
    install_cloudwatch_agent
    deploy_config
    create_alarms
    create_application_metrics
    create_dashboard
    
    log "🎉 Monitoring setup completed successfully!"
    log ""
    log "Next steps:"
    log "1. Check the CloudWatch console for your dashboard"
    log "2. Verify SNS subscription via email confirmation"
    log "3. Monitor the first metrics collection cycle (5 minutes)"
    log "4. Check alarm configuration in CloudWatch console"
}

# Help function
show_help() {
    cat << EOF
CloudWatch Monitoring Setup for Qwen3-VL Demo

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -r, --region REGION AWS region (default: us-west-2)
    -n, --name NAME     Project name (default: qwen3-vl-demo)

Commands:
    install             Install CloudWatch Agent only
    config              Create configuration only
    alarms              Create CloudWatch alarms only
    dashboard           Create dashboard only

Examples:
    $0                  # Full monitoring setup
    $0 install          # Install CloudWatch Agent only
    $0 -r eu-west-1     # Setup in specific region

EOF
}

# Parse command line arguments
COMMAND=""
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
        -n|--name)
            PROJECT_NAME="$2"
            LOG_GROUP_NAME="/aws/ec2/$PROJECT_NAME"
            METRIC_NAMESPACE="Qwen3VL/Application"
            shift 2
            ;;
        install|config|alarms|dashboard)
            COMMAND="$1"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Run specific command or full setup
case $COMMAND in
    install)
        check_aws_config
        find_instances
        install_cloudwatch_agent
        ;;
    config)
        create_cloudwatch_config
        ;;
    alarms)
        check_aws_config
        find_instances
        create_alarms
        ;;
    dashboard)
        check_aws_config
        find_instances
        create_dashboard
        ;;
    *)
        main
        ;;
esac