#!/bin/bash
# diagnostic.sh - AWS CLI Diagnostic Tool for Qwen3-VL Demo

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_NAME="qwen3-vl-demo"
AWS_REGION="us-west-2"

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; }

# Get instance ID from tag
get_instance_id() {
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$PROJECT_NAME" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
        error "No running instance found with tag Name=$PROJECT_NAME"
        return 1
    fi
}

# Test network connectivity
test_network_connectivity() {
    log "Testing network connectivity..."
    
    # Test basic internet connectivity
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        log "✅ Internet connectivity: OK"
    else
        error "❌ Internet connectivity: FAILED"
    fi
    
    # Test external APIs
    local apis=("openrouter.ai" "api.github.com" "raw.githubusercontent.com")
    for api in "${apis[@]}"; do
        if curl -s --max-time 10 "https://$api" >/dev/null 2>&1; then
            log "✅ $api: Reachable"
        else
            warn "❌ $api: Not reachable"
        fi
    done
}

# Test security group rules
test_security_groups() {
    log "Checking security group configuration..."
    
    SG_ID=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text)
    
    log "Security Group: $SG_ID"
    
    # Check inbound rules
    INBOUND_RULES=$(aws ec2 describe-security-groups \
        --group-ids $SG_ID \
        --query 'SecurityGroups[0].IpPermissions[]' \
        --output json)
    
    # Check for port 80
    if echo "$INBOUND_RULES" | jq -e '.[] | select(.FromPort == 80)' >/dev/null 2>&1; then
        log "✅ Port 80 (HTTP) allowed"
    else
        warn "❌ Port 80 (HTTP) not allowed"
    fi
    
    # Check for port 443
    if echo "$INBOUND_RULES" | jq -e '.[] | select(.FromPort == 443)' >/dev/null 2>&1; then
        log "✅ Port 443 (HTTPS) allowed"
    else
        warn "❌ Port 443 (HTTPS) not allowed"
    fi
    
    # Check for port 8080
    if echo "$INBOUND_RULES" | jq -e '.[] | select(.FromPort == 8080)' >/dev/null 2>&1; then
        log "✅ Port 8080 (App) allowed"
    else
        warn "❌ Port 8080 (App) not allowed"
    fi
    
    # Check outbound rules
    EGRESS_RULES=$(aws ec2 describe-security-groups \
        --group-ids $SG_ID \
        --query 'SecurityGroups[0].IpPermissionsEgress[]' \
        --output json)
    
    if echo "$EGRESS_RULES" | jq -e '.[] | select(.IpProtocol == "-1")' >/dev/null 2>&1; then
        log "✅ Full outbound access allowed"
    else
        warn "❌ Limited outbound access - may cause issues with external APIs"
    fi
}

# Test application health
test_application_health() {
    log "Testing application health..."
    
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    # Test HTTP endpoint
    if curl -s --max-time 30 "http://$PUBLIC_IP:8080" >/dev/null 2>&1; then
        log "✅ Application HTTP endpoint: OK"
    else
        error "❌ Application HTTP endpoint: FAILED"
    fi
    
    # Test health endpoint
    if curl -s --max-time 10 "http://$PUBLIC_IP:8080/health" >/dev/null 2>&1; then
        log "✅ Health endpoint: OK"
    else
        warn "❌ Health endpoint: Not available or failed"
    fi
    
    # Test with detailed response
    log "Testing detailed application response..."
    RESPONSE=$(curl -s --max-time 30 "http://$PUBLIC_IP:8080" 2>/dev/null)
    if echo "$RESPONSE" | grep -q "gradio"; then
        log "✅ Gradio interface detected in response"
    else
        warn "⚠️ Gradio interface not detected in response"
        log "Response preview: $(echo "$RESPONSE" | head -c 200)..."
    fi
}

# Check instance status
check_instance_status() {
    log "Checking instance status..."
    
    # Get instance details
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    
    STATUS=$(aws ec2 describe-instance-status \
        --instance-ids $INSTANCE_ID \
        --query 'InstanceStatuses[0].InstanceStatus.Status' \
        --output text)
    
    SYSTEM_STATUS=$(aws ec2 describe-instance-status \
        --instance-ids $INSTANCE_ID \
        --query 'InstanceStatuses[0].SystemStatus.Status' \
        --output text)
    
    log "Instance State: $INSTANCE_STATE"
    log "Instance Status: $STATUS"
    log "System Status: $SYSTEM_STATUS"
    
    if [ "$STATUS" = "ok" ] && [ "$SYSTEM_STATUS" = "ok" ]; then
        log "✅ Instance status: HEALTHY"
    else
        warn "❌ Instance status: ISSUES DETECTED"
    fi
    
    # Check system logs (if available)
    log "Checking recent system events..."
    EVENTS=$(aws ec2 describe-instance-status \
        --instance-ids $INSTANCE_ID \
        --query 'InstanceStatuses[0].Events[*].Description' \
        --output text)
    
    if [ -n "$EVENTS" ] && [ "$EVENTS" != "None" ]; then
        warn "System events: $EVENTS"
    else
        log "✅ No system events"
    fi
}

# Check CloudWatch metrics
check_cloudwatch_metrics() {
    log "Checking CloudWatch metrics..."
    
    # Check if instance has CloudWatch agent
    CW_AGENT=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [ "$CW_AGENT" != "None" ] && [ -n "$CW_AGENT" ]; then
        log "✅ CloudWatch Agent: INSTALLED"
        
        # Get recent CPU utilization
        CPU_METRIC=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/EC2 \
            --metric-name CPUUtilization \
            --dimensions Name=InstanceId,Value=$INSTANCE_ID \
            --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
            --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
            --period 300 \
            --statistics Average \
            --query 'Datapoints[0].Average' \
            --output text 2>/dev/null)
        
        if [ -n "$CPU_METRIC" ] && [ "$CPU_METRIC" != "None" ]; then
            log "CPU Utilization: ${CPU_METRIC}%"
        fi
        
    else
        warn "⚠️ CloudWatch Agent: NOT INSTALLED"
        log "Install with: aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-ConfigureAWSPackage --parameters action=Install,package=AmazonCloudWatch"
    fi
}

# Test load balancer health
test_load_balancer() {
    log "Checking for Application Load Balancer..."
    
    # Find ALB associated with the project
    ALB_ARN=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?contains(LoadBalancerName, '$PROJECT_NAME')].LoadBalancerArn" \
        --output text 2>/dev/null)
    
    if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
        log "✅ Load Balancer found: $ALB_ARN"
        
        ALB_DNS=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns $ALB_ARN \
            --query 'LoadBalancers[0].DNSName' \
            --output text)
        
        log "ALB DNS: $ALB_DNS"
        
        # Test ALB endpoint
        if curl -s --max-time 30 "http://$ALB_DNS" >/dev/null 2>&1; then
            log "✅ Load Balancer: REACHABLE"
        else
            warn "❌ Load Balancer: NOT REACHABLE"
        fi
        
        # Check target health
        TARGET_HEALTH=$(aws elbv2 describe-target-health \
            --load-balancer-arn $ALB_ARN \
            --query 'TargetHealthDescriptions[0].TargetHealth.State' \
            --output text 2>/dev/null)
        
        if [ -n "$TARGET_HEALTH" ] && [ "$TARGET_HEALTH" != "None" ]; then
            log "Target Health: $TARGET_HEALTH"
        fi
        
    else
        log "ℹ️ No Load Balancer found"
    fi
}

# Generate diagnostic report
generate_report() {
    log "Generating diagnostic report..."
    
    REPORT_FILE="qwen3-vl-diagnostic-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Qwen3-VL Demo Diagnostic Report"
        echo "Generated: $(date)"
        echo "================================"
        echo ""
        echo "INSTANCE INFORMATION"
        echo "-------------------"
        echo "Instance ID: $INSTANCE_ID"
        echo "Region: $AWS_REGION"
        echo "Project: $PROJECT_NAME"
        echo ""
        echo "NETWORK CONNECTIVITY"
        echo "-------------------"
        ping -c 3 8.8.8.8
        echo ""
        echo "API ENDPOINTS"
        echo "-------------"
        for api in "openrouter.ai" "api.github.com"; do
            echo "Testing $api..."
            curl -I "https://$api" --max-time 10 2>/dev/null | head -1
        done
        echo ""
        echo "APPLICATION STATUS"
        echo "------------------"
        PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        echo "Public IP: $PUBLIC_IP"
        echo "HTTP Test: $(curl -s -o /dev/null -w "%{http_code}" http://$PUBLIC_IP:8080 --max-time 30)"
        echo ""
        echo "SECURITY GROUPS"
        echo "---------------"
        aws ec2 describe-security-groups --group-ids $SG_ID --query 'SecurityGroups[0].IpPermissions[]' --output json
        echo ""
        echo "CLOUDWATCH METRICS (Last 5 minutes)"
        echo "----------------------------------"
        aws cloudwatch get-metric-statistics \
            --namespace AWS/EC2 \
            --metric-name CPUUtilization \
            --dimensions Name=InstanceId,Value=$INSTANCE_ID \
            --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
            --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
            --period 300 \
            --statistics Average \
            --query 'Datapoints[*].{Time:Timestamp,Value:Average}' \
            --output table 2>/dev/null || echo "No metrics available"
    } > $REPORT_FILE
    
    log "Diagnostic report saved: $REPORT_FILE"
}

# Main execution
main() {
    log "Starting diagnostic for $PROJECT_NAME"
    
    if ! get_instance_id; then
        error "Cannot proceed without instance ID"
        exit 1
    fi
    
    log "Instance ID: $INSTANCE_ID"
    
    # Run all tests
    test_network_connectivity
    test_security_groups
    check_instance_status
    test_application_health
    test_load_balancer
    check_cloudwatch_metrics
    
    # Generate report
    generate_report
    
    log "Diagnostic complete!"
    log ""
    log "If issues were found:"
    log "1. Check instance logs: ssh -i key.pem ec2-user@<public-ip>"
    log "2. Check system logs: sudo journalctl -u qwen3-vl-demo -f"
    log "3. Review security group rules"
    log "4. Verify API key configuration"
}

# Help function
show_help() {
    cat << EOF
AWS CLI Diagnostic Tool for Qwen3-VL Demo

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -r, --region REGION AWS region (default: us-west-2)
    -n, --name NAME     Instance tag name (default: qwen3-vl-demo)
    -i, --id ID         Instance ID (override auto-detection)

Commands:
    network             Test network connectivity only
    security            Test security groups only
    health              Test application health only
    metrics             Check CloudWatch metrics only
    report              Generate diagnostic report only

Examples:
    $0                  # Full diagnostic
    $0 network          # Network connectivity test only
    $0 -i i-123456789   # Test specific instance

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
            shift 2
            ;;
        -i|--id)
            INSTANCE_ID="$2"
            shift 2
            ;;
        network|security|health|metrics|report)
            COMMAND="$1"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Run specific command or full diagnostic
case $COMMAND in
    network)
        get_instance_id
        test_network_connectivity
        ;;
    security)
        get_instance_id
        test_security_groups
        ;;
    health)
        get_instance_id
        test_application_health
        ;;
    metrics)
        get_instance_id
        check_cloudwatch_metrics
        ;;
    report)
        get_instance_id
        generate_report
        ;;
    *)
        main
        ;;
esac