# Guide de Déploiement AWS CLI - Qwen3-VL Demo 🚀

## Table des Matières
1. [Vue d'ensemble](#vue-densemble)
2. [Déploiement Automatisé CLI](#déploiement-automatisé-cli)
3. [Infrastructure as Code](#infrastructure-as-code)
4. [Monitoring et Diagnostics](#monitoring-et-diagnostics)
5. [Configuration du Domaine et SSL](#configuration-du-domaine-et-ssl)
6. [Déploiement Manuel (Optionnel)](#déploiement-manuel-optionnel)
7. [Troubleshooting CLI](#troubleshooting-cli)
8. [Sécurité et Optimisation](#sécurité-et-optimisation)

## Vue d'ensemble

Cette application Qwen3-VL est une interface web sophistiquée basée sur Gradio avec :
- Support multimodal (texte, images, vidéos)
- Intégration OpenRouter API
- Upload de fichiers avec stockage OSS
- Interface en temps réel avec streaming

**🚀 NOUVEAU : Déploiement entièrement automatisé avec AWS CLI**

**Stratégie de déploiement recommandée :** Déploiement automatisé CLI avec EC2 et Application Load Balancer.

## Déploiement Automatisé CLI

### 🚀 Script de Déploiement One-Click

Le déploiement le plus simple utilise le script `deploy.sh` :

```bash
# Rendre le script exécutable
chmod +x deploy.sh

# Déploiement interactif (recommandé)
./deploy.sh

# Déploiement avec paramètres
API_KEY=your-openrouter-key ./deploy.sh -r us-west-2 -t t3.medium

# Aide du script
./deploy.sh --help
```

**Ce script automatise :**
- ✅ Création complète de l'infrastructure VPC
- ✅ Configuration des security groups avec accès complet aux ports
- ✅ Déploiement de l'instance EC2 optimisée
- ✅ Configuration automatique de l'application
- ✅ Setup du Load Balancer (optionnel)
- ✅ Configuration du monitoring CloudWatch

### 📋 Prérequis Automatisés

Le script vérifie automatiquement :
```bash
# Configuration AWS CLI
aws configure

# Vérification
aws sts get-caller-identity
```

**Variables d'environnement :**
- `API_KEY` : Clé API OpenRouter (requise)
- `AWS_REGION` : Région AWS (par défaut: us-west-2)
- `INSTANCE_TYPE` : Type d'instance (par défaut: t3.medium)

### 🔧 Options de Déploiement

```bash
# Déploiement standard avec ALB
API_KEY=sk-or-v1-... ./deploy.sh

# Déploiement rapide sans Load Balancer
API_KEY=sk-or-v1-... ./deploy.sh

# Déploiement personnalisé
API_KEY=sk-or-v1-... ./deploy.sh -r eu-west-1 -t t3.large -k my-keypair
```

## Infrastructure as Code

### 🌐 CloudFormation Template

Infrastructure complète avec un seul fichier JSON :

```bash
# Déploiement avec CloudFormation
aws cloudformation create-stack \
  --stack-name qwen3-vl-demo \
  --template-body file://cloudformation-template.json \
  --parameters ParameterKey=KeyName,ParameterValue=qwen3-vl-key \
               ParameterKey=APIToken,ParameterValue=sk-or-v1-... \
               ParameterKey=InstanceType,ParameterValue=t3.medium \
               ParameterKey=CreateLoadBalancer,ParameterValue=true \
  --capabilities CAPABILITY_IAM

# Vérification du déploiement
aws cloudformation describe-stacks --stack-name qwen3-vl-demo

# Mise à jour
aws cloudformation update-stack \
  --stack-name qwen3-vl-demo \
  --template-body file://cloudformation-template.json \
  --parameters ParameterKey=InstanceType,ParameterValue=t3.large \
  --capabilities CAPABILITY_IAM
```

**Template CloudFormation inclut :**
- ✅ VPC complet avec subnets publics/privés
- ✅ Security Groups avec règles optimisées
- ✅ Instance EC2 avec user data automatisé
- ✅ Application Load Balancer (optionnel)
- ✅ S3 bucket pour le stockage
- ✅ IAM roles et instance profiles
- ✅ CloudWatch logging
- ✅ NAT Gateway pour accès externe

### 🚀 Avantages du CloudFormation

- **Reproductibilité** : Déploiement identique à chaque fois
- **Versioning** : Infrastructure versionnée avec le code
- **Rollback** : Retour en arrière facile en cas de problème
- **Multi-région** : Déploiement dans plusieurs régions simultanément
- **Automation** : Intégration CI/CD complète

### 📊 Exemple de Déploiement avec Outputs

```bash
# Après déploiement, récupérer les informations
INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name qwen3-vl-demo \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text)

PUBLIC_IP=$(aws cloudformation describe-stacks \
  --stack-name qwen3-vl-demo \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicIP`].OutputValue' \
  --output text)

PUBLIC_DNS=$(aws cloudformation describe-stacks \
  --stack-name qwen3-vl-demo \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicDNS`].OutputValue' \
  --output text)

echo "Application disponible sur: http://$PUBLIC_DNS:8080"
```

## Monitoring et Diagnostics

### 📊 Setup de Monitoring Automatisé

Configuration CloudWatch complète avec le script `monitoring-setup.sh` :

```bash
# Setup complet de monitoring
./monitoring-setup.sh

# Installation seulement de l'agent CloudWatch
./monitoring-setup.sh install

# Création des alarmes seulement
./monitoring-setup.sh alarms

# Création du dashboard seulement
./monitoring-setup.sh dashboard
```

**Le script configure automatiquement :**
- ✅ Installation de l'agent CloudWatch sur toutes les instances
- ✅ Configuration des logs (application, nginx, système)
- ✅ Métriques personnalisées (CPU, mémoire, réseau, santé de l'app)
- ✅ Alertes CloudWatch (CPU > 80%, mémoire > 85%, disk > 90%)
- ✅ Dashboard CloudWatch avec métriques en temps réel
- ✅ Configuration SNS pour les alertes email

### 🔍 Script de Diagnostic Complet

Outil de diagnostic `diagnostic.sh` pour troubleshooting rapide :

```bash
# Diagnostic complet
./diagnostic.sh

# Tests spécifiques
./diagnostic.sh network    # Test de connectivité réseau
./diagnostic.sh security   # Test des security groups
./diagnostic.sh health     # Test de santé de l'application
./diagnostic.sh metrics    # Vérification des métriques CloudWatch
./diagnostic.sh report     # Génération d'un rapport complet

# Diagnostic d'une instance spécifique
./diagnostic.sh -i i-123456789
```

**Tests automatisés :**
- ✅ Connectivité Internet et APIs externes
- ✅ Configuration des security groups (ports inbound/outbound)
- ✅ Statut des instances EC2
- ✅ Santé de l'application (endpoints HTTP)
- ✅ Load Balancer et target groups
- ✅ Métriques CloudWatch
- ✅ Génération de rapport de diagnostic

### 📈 Monitoring des Coûts

```bash
# Configuration des alertes de coût
aws ce create-anomaly-monitor \
  --monitor-name "Qwen3VL-High-Cost" \
  --monitor-type COST_ANOMALY \
  --monitor-specification file://cost-monitor.json

# Vérification des coûts
aws ce get-cost-and-usage \
  --time-period Start=2025-11-01,End=2025-11-30 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Configuration du Domaine et SSL

### 🌐 Configuration DNS avec CLI

```bash
# Créer une hosted zone
ZONE_ID=$(aws route53 create-hosted-zone \
  --name yourdomain.com \
  --caller-reference $(date +%s) \
  --query 'HostedZone.Id' --output text | cut -d'/' -f3)

# Créer un record A pour l'ALB
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns arn:aws:elasticloadbalancing:region:account:loadbalancer/app/qwen3-vl-alb/123456789 \
  --query 'LoadBalancers[0].DNSName' --output text)

cat > dns-record.json << EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "yourdomain.com",
      "Type": "A",
      "AliasTarget": {
        "DNSName": "dualstack.${ALB_DNS}",
        "EvaluateTargetHealth": false
      }
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch file://dns-record.json
```

### 🔒 Configuration SSL Automatisée

```bash
# Demander un certificat SSL
CERT_ARN=$(aws acm request-certificate \
  --domain-name yourdomain.com \
  --subject-alternative-names www.yourdomain.com \
  --validation-method DNS \
  --region us-east-1 \
  --query 'CertificateArn' --output text)

# Configuration du listener HTTPS sur l'ALB
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:region:account:loadbalancer/app/qwen3-vl-alb/123456789 \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=$CERT_ARN \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:region:account:targetgroup/qwen3-vl-tg/123456789
```

## Déploiement Manuel (Optionnel)

### ⚠️ Section Legacy - Utilisation du script de déploiement recommandée

Les étapes manuelles suivantes sont maintenues pour référence ou cas d'usage spéciaux.

### Configuration de l'Application

#### 1. Fichier de production optimisé

Le fichier `app_prod.py` inclut des optimisations pour AWS :

```python
import os
import logging
from app import demo

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

if __name__ == "__main__":
    # Configuration pour la production
    demo.queue(
        default_concurrency_limit=50,
        max_size=100,
        api_name="/api/predict"  # Endpoint pour les APIs
    ).launch(
        server_name="0.0.0.0",
        server_port=int(os.environ.get("PORT", 8080)),
        share=False,  # Désactiver en production
        show_error=True,
        quiet=False,
        ssr_mode=False,
        max_threads=100,
        enable_queue=True
    )
```

#### 2. Requirements optimisés

Créez `requirements-prod.txt` :
```
gradio>=5.0.0
modelscope_studio>=0.3.0
openai>=1.0.0
oss2>=2.18.0
gunicorn>=21.2.0
boto3>=1.26.0
```

#### 3. Variables d'environnement

```env
# API Configuration
API_KEY=your-openrouter-api-key
MODELSCOPE_ENVIRONMENT=production

# Application Configuration
PORT=8080
LOG_LEVEL=INFO

# Security
ALLOWED_ORIGINS=https://yourdomain.com
```

### Déploiement EC2 Manuel (Legacy)

#### 1. Configuration des Security Groups

```bash
# Créer un security group avec accès complet
SG_ID=$(aws ec2 create-security-group \
  --group-name qwen3-vl-sg \
  --description "Security group for Qwen3-VL application" \
  --vpc-id vpc-12345678 \
  --query 'GroupId' --output text)

# Configuration des ports sortants (CRITIQUE)
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

# Accès complet pour APIs externes
aws ec2 authorize-security-group-egress \
  --group-id $SG_ID \
  --protocol tcp \
  --port -1 \
  --cidr 0.0.0.0/0

# UDP pour streaming
aws ec2 authorize-security-group-egress \
  --group-id $SG_ID \
  --protocol udp \
  --port -1 \
  --cidr 0.0.0.0/0
```

#### 2. Configuration du Load Balancer

```bash
# Créer l'ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name qwen3-vl-alb \
  --subnets subnet-12345678 subnet-87654321 \
  --security-groups $SG_ID \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Créer le target group
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --name qwen3-vl-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-12345678 \
  --target-type instance \
  --health-check-path /health \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Créer le listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN
```

## Troubleshooting CLI

### 🔧 Outils de Diagnostic Automatisés

Le script `diagnostic.sh` fournit un diagnostic complet :

```bash
# Exécution du diagnostic complet
./diagnostic.sh

# Sortie d'exemple
[10:15:30] Starting diagnostic for qwen3-vl-demo
[10:15:30] Instance ID: i-0abcdef1234567890
[10:15:30] ✅ Internet connectivity: OK
[10:15:30] ✅ openrouter.ai: Reachable
[10:15:30] ✅ Security Group: sg-12345678
[10:15:30] ✅ Port 80 (HTTP) allowed
[10:15:30] ✅ Full outbound access allowed
[10:15:30] ✅ Instance status: HEALTHY
[10:15:30] ✅ Application HTTP endpoint: OK
[10:15:30] ✅ Load Balancer: REACHABLE
[10:15:30] ✅ CloudWatch Agent: INSTALLED
[10:15:30] Diagnostic report saved: qwen3-vl-diagnostic-20251107-101530.txt
```

### 🚑 Résolution Rapide des Problèmes

#### 1. Application ne démarre pas

```bash
# Diagnostic automatique
./diagnostic.sh health

# Vérification des logs
INSTANCE_ID=$(./diagnostic.sh --id-only)
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands="sudo journalctl -u qwen3-vl-demo -f --no-pager"

# Test manuel de l'application
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands="cd /opt/qwen3-vl-demo && python3 app_prod.py"
```

#### 2. Problèmes de connectivité réseau

```bash
# Test de connectivité automatique
./diagnostic.sh network

# Test manuel des APIs externes
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands="
    curl -I https://openrouter.ai/api/v1/models
    curl -I https://api.github.com
    ping -c 3 8.8.8.8
  "
```

#### 3. Problèmes de ressources

```bash
# Vérification des métriques
./diagnostic.sh metrics

# Surveillance en temps réel
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --query 'Datapoints[*].{Time:Timestamp,CPU:Average}' \
  --output table
```

#### 4. Problèmes d'API OpenRouter

```bash
# Test de l'API
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands="
    curl -H 'Authorization: Bearer \$API_KEY' https://openrouter.ai/api/v1/models
  "

# Vérification des variables d'environnement
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands="env | grep API_KEY"
```

### 📈 Monitoring en Temps Réel

```bash
# Surveillance continue
watch -n 5 './diagnostic.sh health'

# Logs en temps réel
./diagnostic.sh | tail -f

# Métriques CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace Qwen3VL/Application \
  --metric-name HealthCheck \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average \
  --query 'Datapoints[*].{Time:Timestamp,Health:Average}' \
  --output table
```

## Sécurité et Optimisation

### 🔒 Sécurité CLI

#### 1. Variables d'environnement sécurisées

```bash
# Création d'un secret dans AWS Secrets Manager
aws secretsmanager create-secret \
  --name qwen3-vl-api-key \
  --secret-string '{"api_key":"sk-or-v1-your-actual-key"}'

# Utilisation dans CloudFormation
ParameterKey=APIToken,ParameterValue=arn:aws:secretsmanager:region:account:secret:qwen3-vl-api-key
```

#### 2. Configuration sécurisée avec CLI

```bash
# Activation du chiffrement EBS
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true,"Encrypted":true,"KmsKeyId":"alias/aws/ebs"}}]' \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID

# Configuration VPC avec endpoints privés
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.region.s3 \
  --route-table-ids $ROUTE_TABLE_ID
```

### ⚡ Optimisation des Performances

#### 1. Configuration automatique des performances

```bash
# Script d'optimisation
cat > optimize.sh << 'EOF'
#!/bin/bash

# Optimisation des paramètres système
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 65536 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' >> /etc/sysctl.conf
sysctl -p

# Optimisation Nginx
cat > /etc/nginx/conf.d/optimization.conf << 'NGINXEOF'
# Worker processes
worker_processes auto;

# Connection limits
worker_connections 4096;

# Buffer sizes
client_body_buffer_size 128k;
client_max_body_size 100m;
client_header_buffer_size 1k;
large_client_header_buffers 4 4k;

# Timeouts
client_body_timeout 60;
client_header_timeout 60;
keepalive_timeout 65;
send_timeout 60;
NGINXEOF

# Redémarrage
systemctl restart nginx
EOF
```

#### 2. Mise à l'échelle automatique

```bash
# Création d'un Auto Scaling Group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name qwen3-vl-asg \
  --launch-template LaunchTemplateName=qwen3-vl-template,Version=1 \
  --min-size 1 \
  --max-size 5 \
  --desired-capacity 2 \
  --vpc-zone-identifier "subnet-12345678,subnet-87654321" \
  --target-group-arns arn:aws:elasticloadbalancing:region:account:targetgroup/qwen3-vl-tg/123456789

# Politiques de mise à l'échelle
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name qwen3-vl-asg \
  --policy-name scale-up-cpu \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    }
  }'
```

## Commandes Utiles

### 🚀 Script de Déploiement Rapide

```bash
# Mise à jour de l'application
cat > quick-deploy.sh << 'EOF'
#!/bin/bash

# Mise à jour depuis S3
aws s3 sync s3://your-app-bucket/ /opt/qwen3-vl-demo/ --delete

# Redémarrage du service
sudo systemctl restart qwen3-vl-demo
sudo systemctl status qwen3-vl-demo

# Test de santé
sleep 15
./diagnostic.sh health

echo "✅ Déploiement rapide terminé"
EOF
```

### 📊 Surveillance CLI

```bash
# Commandes de surveillance
alias qwen-health='./diagnostic.sh health'
alias qwen-logs='aws logs tail /aws/ec2/qwen3-vl-demo/app --follow'
alias qwen-metrics='aws cloudwatch get-metric-statistics --namespace Qwen3VL/Application'
alias qwen-costs='aws ce get-cost-and-usage --time-period Start=2025-11-01,End=2025-11-30 --granularity DAILY --metrics BlendedCost'
```

## Support et Maintenance

### 📋 Check-list de Maintenance

```bash
# Script de maintenance automatique
cat > maintenance.sh << 'EOF'
#!/bin/bash

echo "🔧 Maintenance Qwen3-VL Demo"

# 1. Mise à jour des dépendances
echo "📦 Mise à jour des dépendances..."
aws ssm send-command \
  --instance-ids $(aws ec2 describe-instances --filters "Name=tag:Name,Values=qwen3-vl-demo" --query 'Reservations[].Instances[].InstanceId' --output text) \
  --document-name "AWS-RunShellScript" \
  --parameters commands="pip3 install --upgrade -r /opt/qwen3-vl-demo/requirements-prod.txt"

# 2. Test de santé
echo "🩺 Test de santé..."
./diagnostic.sh

# 3. Nettoyage des logs
echo "🧹 Nettoyage des logs..."
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands="find /var/log -name '*.log' -mtime +7 -delete"

# 4. Backup de la configuration
echo "💾 Backup de la configuration..."
aws s3 cp /opt/qwen3-vl-demo/config.py s3://your-backup-bucket/config-$(date +%Y%m%d).py

echo "✅ Maintenance terminée"
EOF
```

### 🔍 Surveillance Automatisée

```bash
# Cron job pour surveillance quotidienne
(crontab -l 2>/dev/null; echo "0 6 * * * /path/to/diagnostic.sh report > /dev/null 2>&1") | crontab -

# Alertes SNS pour problèmes critiques
aws cloudwatch put-metric-alarm \
  --alarm-name "Qwen3VL-Critical-Health" \
  --alarm-description "Critical health check failure" \
  --metric-name HealthCheck \
  --namespace Qwen3VL/Application \
  --statistic Average \
  --period 300 \
  --threshold 0.1 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:region:account:qwen3-vl-alerts
```

### 📞 Support

**Outils de diagnostic automatique :**
1. `./diagnostic.sh` - Diagnostic complet avec rapport
2. `./monitoring-setup.sh` - Configuration CloudWatch
3. `./deploy.sh` - Déploiement automatisé
4. `aws cloudformation` - Infrastructure as Code

**Log commands pour debugging :**
```bash
# Logs système
aws logs tail /aws/ec2/qwen3-vl-demo/app --follow

# Métriques en temps réel
aws cloudwatch get-metric-statistics --namespace Qwen3VL/Application

# État des ressources
aws cloudformation describe-stacks --stack-name qwen3-vl-demo
```

---

*Guide créé le : 2025-11-07*  
*Version : 2.0 - CLI Focused*  
*Compatible : AWS EC2, ECS, CloudFormation*