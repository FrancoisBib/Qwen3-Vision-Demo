# Guide de Déploiement AWS - Qwen3-VL Demo 🚀

## Table des Matières
1. [Vue d'ensemble](#vue-densemble)
2. [Prérequis](#prérequis)
3. [Options de Déploiement AWS](#options-de-déploiement-aws)
4. [Préparation de l'Application](#préparation-de-lapplication)
5. [Déploiement sur EC2](#déploiement-sur-ec2-recommandé)
6. [Déploiement sur ECS](#déploiement-sur-ecs)
7. [Configuration du Domaine et SSL](#configuration-du-domaine-et-ssl)
8. [Monitoring et Logging](#monitoring-et-logging)
9. [Troubleshooting](#troubleshooting)
10. [Sécurité et Optimisation](#sécurité-et-optimisation)

## Vue d'ensemble

Cette application Qwen3-VL est une interface web sophistiquée basée sur Gradio avec :
- Support multimodal (texte, images, vidéos)
- Intégration OpenRouter API
- Upload de fichiers avec stockage OSS
- Interface en temps réel avec streaming

**Stratégie de déploiement recommandée :** EC2 avec Application Load Balancer pour un déploiement simple et efficace.

## Prérequis

### Comptes et Services AWS
- Compte AWS avec facturation activée
- AWS CLI configuré
- Domain name (optionnel mais recommandé)
- Certificat SSL (AWS Certificate Manager)

### Variables d'Environnement Nécessaires
```bash
API_KEY=your-openrouter-api-key

```

## Options de Déploiement AWS

### 🔹 Option 1: EC2 + Application Load Balancer (RECOMMANDÉ)
- **Avantages** : Simple, contrôle total, économique
- **Inconvénients** : Gestion manuelle des updates
- **Usage** : Applications web, prototypes, production simple

### 🔹 Option 2: ECS Fargate
- **Avantages** : Serverless, scaling automatique
- **Inconvénients** : Plus complexe, coût variable
- **Usage** : Applications à trafic variable, microservices

### 🔹 Option 3: Elastic Beanstalk
- **Avantages** : Déploiement simple, gestion automatisée
- **Inconvénients** : Moins flexible, dépendance AWS
- **Usage** : Déploiement rapide d'applications Python

### 🔹 Option 4: Lambda + API Gateway
- **Avantages** : Serverless pur, coût basé sur l'usage
- **Inconvénients** : Limites de taille, complexité Gradio
- **Usage** : Fonctions simples, APIs REST

## Préparation de l'Application

### 1. Fichier de production déjà créé

Le fichier `app_prod.py` a été créé avec des optimisations spécifiques pour AWS et une configuration complète des ports :

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

### 2. Fichier requirements optimisé

Créez `requirements-prod.txt` :

```
gradio>=5.0.0
modelscope_studio>=0.3.0
openai>=1.0.0
oss2>=2.18.0
gunicorn>=21.2.0
psycopg2-binary>=2.9.0
redis>=4.5.0
```

### 3. Configuration de l'environnement

Créez `.env.production` :

```env
# API Configuration
API_KEY=your-openrouter-api-key
MODELSCOPE_ENVIRONMENT=production

# OSS Configuration (optionnel)
OSS_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com
OSS_REGION=cn-hangzhou
OSS_BUCKET_NAME=your-bucket

# Application Configuration
PORT=8080
LOG_LEVEL=INFO

# Security
ALLOWED_ORIGINS=https://yourdomain.com
```

## Déploiement sur EC2 (RECOMMANDÉ)

### Étape 1: Création de l'instance EC2

1. **Créer un Security Group avec accès complet** :
   ```bash
   # Créer un security group qui permet l'accès à tous les ports nécessaires
   aws ec2 create-security-group \
     --group-name qwen3-vl-sg \
     --description "Security group for Qwen3-VL application with full external access" \
     --vpc-id vpc-12345678
   ```

2. **Configurer les règles de sécurité (SG-12345678)** :
   ```bash
   # Ports entrants (inbound)
   aws ec2 authorize-security-group-ingress \
     --group-id sg-12345678 \
     --protocol tcp \
     --port 22 \
     --cidr YOUR_IP_ADDRESS/32
   
   aws ec2 authorize-security-group-ingress \
     --group-id sg-12345678 \
     --protocol tcp \
     --port 80 \
     --cidr 0.0.0.0/0
   
   aws ec2 authorize-security-group-ingress \
     --group-id sg-12345678 \
     --protocol tcp \
     --port 443 \
     --cidr 0.0.0.0/0
   
   aws ec2 authorize-security-group-ingress \
     --group-id sg-12345678 \
     --protocol tcp \
     --port 8080 \
     --cidr 0.0.0.0/0

   # PORTS SORTANTS (OUTBOUND) - CRITIQUE pour l'accès aux services externes
   aws ec2 authorize-security-group-egress \
     --group-id sg-12345678 \
     --protocol tcp \
     --port 80 \
     --cidr 0.0.0.0/0
   
   aws ec2 authorize-security-group-egress \
     --group-id sg-12345678 \
     --protocol tcp \
     --port 443 \
     --cidr 0.0.0.0/0
   
   # Accès complet pour tous les autres ports (nécessaire pour OSS, APIs diverses)
   aws ec2 authorize-security-group-egress \
     --group-id sg-12345678 \
     --protocol tcp \
     --port -1 \
     --cidr 0.0.0.0/0
   
   # Accès UDP pour services audio/vidéo
   aws ec2 authorize-security-group-egress \
     --group-id sg-12345678 \
     --protocol udp \
     --port -1 \
     --cidr 0.0.0.0/0
   ```

3. **Créer l'instance EC2** :
   ```bash
   aws ec2 run-instances \
     --image-id ami-0abcdef1234567890 \
     --count 1 \
     --instance-type t3.medium \
     --key-name your-key-pair \
     --security-group-ids sg-12345678 \
     --subnet-id subnet-12345678 \
     --user-data file://user-data.sh
   ```

**⚠️ CONFIGURATION CRITIQUE - PORTS SORTANTS :**
- **Port 80/443** : Accès HTTP/HTTPS pour OpenRouter API, services OSS, et APIs externes
- **Port -1 (tous ports)** : Nécessaire pour la connectivité complète avec services tiers
- **UDP** : Support pour streaming audio/vidéo et WebRTC

### Étape 2: Script d'initialisation avec configuration réseau complète (user-data.sh)

```bash
#!/bin/bash
set -e

echo "🚀 Initialisation de Qwen3-VL Demo - Configuration réseau"

# Mise à jour du système
yum update -y
yum install -y python3 python3-pip nginx curl wget netcat-openbsd

# Désactivation du firewall (pour permettre l'accès aux ports)
systemctl stop firewalld
systemctl disable firewalld

# Configuration réseau pour l'accès aux ports externes
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p

# Installation des dépendances Python
pip3 install --upgrade pip
pip3 install -r https://your-s3-bucket/requirements-prod.txt

# Configuration de l'application
mkdir -p /opt/qwen3-vl-demo
cd /opt/qwen3-vl-demo

# Télécharger le code de l'application
aws s3 cp s3://your-s3-bucket/app/ . --recursive

# Test de connectivité réseau
echo "🌐 Test de connectivité réseau..."
ping -c 3 8.8.8.8 || echo "⚠️ Problème de connectivité Internet"

# Test d'accès aux services externes (OpenRouter)
echo "🔍 Test d'accès à OpenRouter API..."
curl -s -I https://openrouter.ai/api/v1/models || echo "⚠️ Problème d'accès à OpenRouter"

# Configuration systemd avec variables d'environnement
cat > /etc/systemd/system/qwen3-vl-demo.service << 'EOF'
[Unit]
Description=Qwen3-VL Demo Application
After=network.target
Wants=network.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/opt/qwen3-vl-demo
Environment=API_KEY=your-openrouter-api-key
Environment=MODELSCOPE_ENVIRONMENT=production
Environment=OSS_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com
Environment=OSS_REGION=cn-hangzhou
Environment=OSS_BUCKET_NAME=your-bucket
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:8080 --workers 4 --timeout 300 --max-requests 1000 --max-requests-jitter 100 --access-logfile - --error-logfile - app_prod:demo
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Configuration Nginx optimisée pour la connectivité
cat > /etc/nginx/conf.d/qwen3-vl.conf << 'EOF'
# Configuration Nginx pour Qwen3-VL Demo
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    
    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
    # Support WebSocket
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    server {
        listen 80;
        server_name _;
        
        # Timeouts étendus pour Gradio
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        client_body_timeout 300s;
        client_header_timeout 300s;
        
        # Headers pour la connectivité
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Support WebSocket essentiel pour Gradio
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        
        # Headers de sécurité
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        
        # Configuration pour l'application Gradio
        location / {
            proxy_pass http://127.0.0.1:8080;
            proxy_buffering off;
            proxy_cache off;
            proxy_redirect off;
            
            # WebSocket support
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
        
        # Health check endpoint
        location /health {
            proxy_pass http://127.0.0.1:8080/health;
            access_log off;
        }
    }
}
EOF

# Script de test de connectivité
cat > /opt/qwen3-vl-demo/test_connectivity.py << 'EOF'
#!/usr/bin/env python3
import requests
import sys
import time

def test_external_connectivity():
    """Test de la connectivité vers les services externes"""
    tests = [
        ("OpenRouter API", "https://openrouter.ai/api/v1/models"),
        ("GitHub", "https://api.github.com"),
        ("Google DNS", "https://8.8.8.8"),
    ]
    
    print("🔍 Test de connectivité vers les services externes...")
    all_passed = True
    
    for service_name, url in tests:
        try:
            response = requests.get(url, timeout=10)
            if response.status_code in [200, 401, 403]:  # 401/403 = API key required but connectivity works
                print(f"✅ {service_name}: Connexion réussie")
            else:
                print(f"⚠️ {service_name}: Status {response.status_code}")
        except requests.exceptions.RequestException as e:
            print(f"❌ {service_name}: Échec de connexion - {str(e)}")
            all_passed = False
    
    return all_passed

if __name__ == "__main__":
    test_external_connectivity()
EOF

chmod +x /opt/qwen3-vl-demo/test_connectivity.py

# Test initial de connectivité
python3 /opt/qwen3-vl-demo/test_connectivity.py

# Démarrage des services
systemctl daemon-reload
systemctl enable qwen3-vl-demo
systemctl start qwen3-vl-demo

systemctl enable nginx
systemctl restart nginx

# Attendre que l'application démarre
sleep 30

# Test final
echo "🧪 Test final de l'application..."
curl -f http://localhost:8080/health || echo "⚠️ Application non démarrée"

echo "✅ Initialisation terminée"
```

### Étape 3: Upload de l'application

1. **Créer un bucket S3** pour stocker l'application :
   ```bash
   aws s3 mb s3://your-app-bucket
   ```

2. **Préparer les fichiers** :
   ```bash
   # Créer un dossier de déploiement
   mkdir deployment
   cp app.py config.py requirements-prod.txt deployment/
   cp -r assets ui_components deployment/
   ```

3. **Upload vers S3** :
   ```bash
   aws s3 sync deployment/ s3://your-app-bucket/app/
   ```

### Étape 4: Configuration de l'Application Load Balancer

1. **Créer l'ALB** :
   ```bash
   aws elbv2 create-load-balancer \
     --name qwen3-vl-alb \
     --subnets subnet-12345678 subnet-87654321 \
     --security-groups sg-12345678
   ```

2. **Créer le target group** :
   ```bash
   aws elbv2 create-target-group \
     --name qwen3-vl-tg \
     --protocol HTTP \
     --port 80 \
     --vpc-id vpc-12345678 \
     --target-type instance \
     --health-check-path /api/predict
   ```

3. **Créer le listener** :
   ```bash
   aws elbv2 create-listener \
     --load-balancer-arn arn:aws:elasticloadbalancing:region:account:loadbalancer/app/qwen3-vl-alb/123456789 \
     --protocol HTTP \
     --port 80 \
     --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:region:account:targetgroup/qwen3-vl-tg/123456789
   ```

### Étape 5: Auto Scaling (optionnel)

```bash
# Créer un launch template
aws ec2 create-launch-template \
  --launch-template-name qwen3-vl-template \
  --launch-template-data '{
    "ImageId": "ami-0abcdef1234567890",
    "InstanceType": "t3.medium",
    "UserData": "'$(base64 -w 0 user-data.sh)'",
    "SecurityGroupIds": ["sg-12345678"]
  }'

# Créer un Auto Scaling Group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name qwen3-vl-asg \
  --launch-template LaunchTemplateName=qwen3-vl-template,Version=1 \
  --min-size 1 \
  --max-size 3 \
  --desired-capacity 1 \
  --vpc-zone-identifier "subnet-12345678,subnet-87654321"
```

## Déploiement sur ECS

### Dockerfile

```dockerfile
FROM python:3.9-slim

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Configuration de l'application
WORKDIR /app
COPY requirements-prod.txt .
RUN pip install --no-cache-dir -r requirements-prod.txt

COPY . .

# Variables d'environnement
ENV PYTHONPATH=/app
ENV PORT=8080

EXPOSE 8080

# Commande de démarrage
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "--timeout", "120", "app_prod:demo"]
```

### docker-compose.yml avec Configuration Réseau

```yaml
version: '3.8'
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - API_KEY=${API_KEY}
      - MODELSCOPE_ENVIRONMENT=production
      - OSS_ENDPOINT=${OSS_ENDPOINT}
      - OSS_REGION=${OSS_REGION}
      - OSS_BUCKET_NAME=${OSS_BUCKET_NAME}
      - PYTHONUNBUFFERED=1
      - PYTHONDONTWRITEBYTECODE=1
    volumes:
      - ./logs:/app/logs
      - ./test_connectivity.py:/app/test_connectivity.py
    networks:
      - qwen3-vl-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - app
    networks:
      - qwen3-vl-network
    restart: unless-stopped
    
  network-monitor:
    build: 
      context: .
      dockerfile: Dockerfile.monitor
    environment:
      - MONITOR_INTERVAL=300
      - LOG_LEVEL=INFO
    networks:
      - qwen3-vl-network
    depends_on:
      - app
    restart: unless-stopped

networks:
  qwen3-vl-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "true"
      com.docker.network.bridge.enable_ip_masquerade: "true"
      com.docker.network.bridge.host_binding_ipv4: "0.0.0.0"
      com.docker.network.driver.mtu: "1500"
```

### Dockerfile pour le Monitor Réseau

```dockerfile
# Dockerfile.monitor
FROM python:3.9-slim

RUN pip install requests psutil

COPY network_monitor.py /app/network_monitor.py

WORKDIR /app

CMD ["python3", "network_monitor.py"]
```

### ECS Task Definition avec Accès Port Complet

```json
{
  "family": "qwen3-vl-demo",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "2048",
  "memory": "4096",
  "executionRoleArn": "arn:aws:iam::account:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::account:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "qwen3-vl-app",
      "image": "your-account.dkr.ecr.region.amazonaws.com/qwen3-vl-demo:latest",
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp",
          "hostPort": 8080
        }
      ],
      "environment": [
        {
          "name": "API_KEY",
          "value": "your-openrouter-api-key"
        },
        {
          "name": "MODELSCOPE_ENVIRONMENT",
          "value": "production"
        },
        {
          "name": "PYTHONUNBUFFERED",
          "value": "1"
        },
        {
          "name": "PYTHONDONTWRITEBYTECODE",
          "value": "1"
        }
      ],
      "secrets": [
        {
          "name": "API_KEY",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:openrouter-api-key"
        }
      ],
      "ulimits": [
        {
          "name": "nofile",
          "softLimit": 65536,
          "hardLimit": 65536
        }
      ],
      "memory": 3584,
      "memoryReservation": 2048,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/qwen3-vl-demo",
          "awslogs-region": "us-west-2",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:8080/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ],
  "proxyConfiguration": {
    "type": "APPMESH",
    "containerName": "envoy",
    "containerPort": 8080,
    "properties": [
      {
        "key": "ProxyIngressPort",
        "value": "15000"
      },
      {
        "key": "ProxyEgressPort", 
        "value": "15001"
      },
      {
        "key": "AppPorts",
        "value": "8080"
      }
    ]
  }
}
```

### ECS Service avec Configuration Réseau

```bash
# Créer le service ECS
aws ecs create-service \
  --cluster qwen3-vl-cluster \
  --service-name qwen3-vl-service \
  --task-definition qwen3-vl-demo:1 \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-12345678,subnet-87654321],securityGroups=[sg-12345678],assignPublicIp=ENABLED}" \
  --load-balancers targetGroupArn=arn:aws:elasticloadbalancing:region:account:targetgroup/qwen3-vl-tg/123456789,containerName=qwen3-vl-app,containerPort=8080

# Configuration pour accès complet aux ports
aws ecs update-service \
  --cluster qwen3-vl-cluster \
  --service qwen3-vl-service \
  --service-connect-configuration "namespace=qwen3-vl-ns,enabled=true,services=[{portName=qwen3-vl-app,discoveryName=qwen3-vl-app}]"
```

### Security Group pour ECS (Ports Externes)

```bash
# Créer un security group pour ECS avec accès complet
aws ec2 create-security-group \
  --group-name qwen3-vl-ecs-sg \
  --description "Security group for Qwen3-VL ECS tasks with full external access" \
  --vpc-id vpc-12345678

# Règles entrantes
aws ec2 authorize-security-group-ingress \
  --group-id sg-87654321 \
  --protocol tcp \
  --port 8080 \
  --source-group sg-12345678

# Règles sortantes (CRUCIAL - accès à tous les ports externes)
aws ec2 authorize-security-group-egress \
  --group-id sg-87654321 \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-egress \
  --group-id sg-87654321 \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Accès complet pour les autres ports (OSS, APIs diverses)
aws ec2 authorize-security-group-egress \
  --group-id sg-87654321 \
  --protocol tcp \
  --port -1 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-egress \
  --group-id sg-87654321 \
  --protocol udp \
  --port -1 \
  --cidr 0.0.0.0/0
```

## Configuration du Domaine et SSL

### 1. Route 53 - Configuration DNS

```bash
# Créer une hosted zone
aws route53 create-hosted-zone \
  --name yourdomain.com \
  --caller-reference $(date +%s)

# Créer un record A pour l'ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789 \
  --change-batch file://dns-record.json
```

### 2. AWS Certificate Manager

```bash
# Demander un certificat SSL
aws acm request-certificate \
  --domain-name yourdomain.com \
  --subject-alternative-names www.yourdomain.com \
  --validation-method DNS \
  --region us-east-1
```

### 3. Configuration HTTPS sur l'ALB

```json
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "yourdomain.com",
      "Type": "A",
      "AliasTarget": {
        "DNSName": "dualstack.your-alb-123456.us-west-2.elb.amazonaws.com",
        "EvaluateTargetHealth": false
      }
    }
  }]
}
```

## Monitoring et Logging

### 1. CloudWatch Logs

```bash
# Créer un log group
aws logs create-log-group --log-group-name /ecs/qwen3-vl-demo

# Configuration dans l'application
import logging
import boto3
from logging.handlers import CloudWatchLogHandler

# Configuration CloudWatch
cloudwatch_handler = CloudWatchLogHandler(
    log_group_name='/ecs/qwen3-vl-demo',
    boto3_session=boto3.Session(region_name='us-west-2')
)

logging.getLogger().addHandler(cloudwatch_handler)
```

### 2. CloudWatch Metrics

```python
# Métriques personnalisées
import boto3

cloudwatch = boto3.client('cloudwatch')

def put_custom_metrics(metric_name, value, unit='Count'):
    cloudwatch.put_metric_data(
        Namespace='Qwen3VL',
        MetricData=[
            {
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit,
                'Timestamp': datetime.utcnow()
            }
        ]
    )

# Utilisation dans l'application
@app.route('/api/predict')
def predict():
    start_time = time.time()
    try:
        result = process_request()
        put_custom_metrics('SuccessfulRequests', 1)
        return result
    except Exception as e:
        put_custom_metrics('FailedRequests', 1)
        raise e
    finally:
        duration = time.time() - start_time
        put_custom_metrics('RequestDuration', duration, 'Seconds')
```

### 3. AWS X-Ray pour le tracing

```python
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Instrumenter l'application
patch_all()

@xray_recorder.capture('qwen3_vl_request')
def process_request():
    # Votre logique d'application
    pass
```

### 4. Monitor de Connectivité Réseau

```python
# network_monitor.py - Surveillance continue de la connectivité
import requests
import time
import logging
import json
from datetime import datetime
import subprocess
import psutil

class NetworkMonitor:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.external_services = {
            'openrouter': 'https://openrouter.ai/api/v1/models',
            'github': 'https://api.github.com',
            'oss_endpoint': 'https://oss-cn-hangzhou.aliyuncs.com'
        }
    
    def check_port_connectivity(self, host, port, timeout=10):
        """Test de connectivité sur un port spécifique"""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(timeout)
                result = sock.connect_ex((host, port))
                return result == 0
        except Exception as e:
            self.logger.error(f"Erreur test port {host}:{port} - {e}")
            return False
    
    def test_external_services(self):
        """Test des services externes"""
        results = {}
        for service, url in self.external_services.items():
            try:
                response = requests.get(url, timeout=15)
                results[service] = {
                    'status': 'OK',
                    'status_code': response.status_code,
                    'response_time': response.elapsed.total_seconds()
                }
            except requests.exceptions.RequestException as e:
                results[service] = {
                    'status': 'ERROR',
                    'error': str(e),
                    'timestamp': datetime.now().isoformat()
                }
                self.logger.warning(f"Service {service} inaccessible: {e}")
        return results
    
    def check_network_interfaces(self):
        """Vérification des interfaces réseau"""
        interfaces = psutil.net_if_stats()
        return {
            interface: {
                'is_up': stats.isup,
                'speed': stats.speed,
                'mtu': stats.mtu
            }
            for interface, stats in interfaces.items()
        }
    
    def get_network_connections(self):
        """Connexions réseau actives"""
        connections = psutil.net_connections()
        return [
            {
                'local_address': f"{conn.laddr.ip}:{conn.laddr.port}" if conn.laddr else None,
                'remote_address': f"{conn.raddr.ip}:{conn.raddr.port}" if conn.raddr else None,
                'status': conn.status,
                'pid': conn.pid
            }
            for conn in connections 
            if conn.status in ['ESTABLISHED', 'SYN_SENT', 'SYN_RECV']
        ]
    
    def continuous_monitoring(self, interval=300):  # 5 minutes
        """Monitoring continu en arrière-plan"""
        self.logger.info("Démarrage du monitoring réseau continu")
        while True:
            try:
                # Test des services externes
                results = self.test_external_services()
                
                # Vérification des interfaces
                interfaces = self.check_network_interfaces()
                
                # Connexions actives
                connections = self.get_network_connections()
                
                # Log des résultats
                self.logger.info(f"Network status: {json.dumps(results, indent=2)}")
                
                # Alertes en cas de problème
                for service, result in results.items():
                    if result['status'] == 'ERROR':
                        self.logger.error(f"ALERTE: Service {service} inaccessible")
                
                time.sleep(interval)
                
            except Exception as e:
                self.logger.error(f"Erreur monitoring réseau: {e}")
                time.sleep(60)  # Attendre 1 minute avant de réessayer

# Utilisation dans l'application
if __name__ == "__main__":
    monitor = NetworkMonitor()
    # monitor.continuous_monitoring()  # Décommenter pour activer
```

## Troubleshooting

### Problèmes Courants et Solutions

#### 1. **Application ne démarre pas**

```bash
# Vérifier les logs
sudo journalctl -u qwen3-vl-demo -f

# Vérifier les variables d'environnement
sudo systemctl status qwen3-vl-demo
env | grep API_KEY

# Tester manuellement
cd /opt/qwen3-vl-demo
python3 app_prod.py
```

#### 2. **Problèmes de mémoire**

```bash
# Surveiller l'utilisation mémoire
htop
free -h

# Optimiser Gunicorn
# Dans le service systemd
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:8080 --workers 2 --max-requests 1000 --max-requests-jitter 100 app_prod:demo
```

#### 3. **Timeouts des requêtes**

```python
# Augmenter les timeouts dans app_prod.py
demo.queue(
    default_concurrency_limit=10,
    max_size=50,
    timeout=300  # 5 minutes
).launch(
    # ... autres configurations
)
```

#### 4. **Problèmes d'upload de fichiers**

```python
# Configuration des limites dans config.py
def upload_config():
    return MultimodalInputUploadConfig(
        accept="image/*,video/*",
        max_file_size=100 * 1024 * 1024,  # 100MB
        # ... autres configurations
    )
```

#### 5. **Erreurs d'API OpenRouter**

```python
# Gestion robuste des erreurs
try:
    response = client.chat.completions.create(...)
except openai.RateLimitError:
    # Gestion des limites de taux
    time.sleep(60)
    retry_request()
except openai.AuthenticationError:
    # Problème d'authentification
    log.error("API key invalid")
    raise
except Exception as e:
    # Autres erreurs
    log.error(f"API error: {str(e)}")
    raise
```

### Outils de Diagnostic

#### 1. Script de health check

```bash
#!/bin/bash
# health-check.sh

APP_URL="http://localhost:8080"

# Test de connectivité
if curl -f -s $APP_URL > /dev/null; then
    echo "✅ Application is healthy"
    exit 0
else
    echo "❌ Application is down"
    exit 1
fi
```

#### 2. Monitoring de performance

```python
# performance_monitor.py
import psutil
import time
import json

def get_system_metrics():
    return {
        'cpu_percent': psutil.cpu_percent(),
        'memory_percent': psutil.virtual_memory().percent,
        'disk_usage': psutil.disk_usage('/').percent,
        'timestamp': time.time()
    }

# Utilisation dans l'application
@app.route('/health')
def health_check():
    return jsonify(get_system_metrics())
```

## Configuration des Ports Externes

### 🔥 Règles de Sécurité - Accès Complet aux Ports

Pour garantir que votre application Qwen3-VL peut communiquer avec tous les services externes nécessaires, configurez les **ports sortants (egress)** :

#### Services Externes Nécessitant des Accès Port

| Service | Port | Usage |
|---------|------|-------|
| **OpenRouter API** | 443, 80 | Connexions HTTPS vers l'API des modèles |
| **GitHub** | 443, 80 | Téléchargement de modèles et dépendances |
| **Alibaba Cloud OSS** | 443, 80 | Stockage des fichiers uploadés |
| **CDN de modèles** | 443, 80 | Téléchargement de poids de modèles |
| **WebSocket services** | 443, 80 | Communication temps réel |
| **DNS servers** | 53 | Résolution de noms |
| **NTP servers** | 123 | Synchronisation temporelle |

#### Configuration VPC et Subnet

```bash
# Créer un VPC avec NAT Gateway pour l'accès aux ports externes
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=qwen3-vl-vpc}]'

# Créer des subnets publics et privés
aws ec2 create-subnet --vpc-id vpc-12345678 --cidr-block 10.0.1.0/24 --availability-zone us-west-2a
aws ec2 create-subnet --vpc-id vpc-12345678 --cidr-block 10.0.2.0/24 --availability-zone us-west-2b

# Créer une NAT Gateway (optionnel mais recommandé)
aws ec2 create-nat-gateway --subnet-id subnet-12345678 --allocation-id eipalloc-12345678

# Internet Gateway
aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=qwen3-vl-igw}]'

# Route tables
aws ec2 create-route-table --vpc-id vpc-12345678
aws ec2 create-route --route-table-id rtb-12345678 --destination-cidr-block 0.0.0.0/0 --gateway-id igw-12345678
aws ec2 associate-route-table --subnet-id subnet-12345678 --route-table-id rtb-12345678
```

### 🔍 Tests de Connectivité Avancés

```bash
#!/bin/bash
# test_ports_connectivity.sh

echo "🧪 Test de connectivité sur tous les ports nécessaires"

# Test de base réseau
ping -c 3 8.8.8.8
ping -c 3 1.1.1.1

# Test DNS
nslookup openrouter.ai
nslookup api.github.com

# Test ports spécifiques
nc -zv openrouter.ai 443
nc -zv api.github.com 443
nc -zv github.com 443

# Test avec curl (HTTP/HTTPS)
curl -I https://openrouter.ai/api/v1/models
curl -I https://api.github.com
curl -I https://raw.githubusercontent.com

echo "✅ Tests de connectivité terminés"
```

### 🌐 Configuration DNS et Réseaux

```bash
# Configuration DNS dans /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 208.67.222.222" >> /etc/resolv.conf

# Test de résolution
dig openrouter.ai
nslookup api.github.com
```

## Sécurité et Optimisation

### 1. Sécurité

#### Variables d'environnement sécurisées

```bash
# Utiliser AWS Secrets Manager
aws secretsmanager create-secret \
  --name openrouter-api-key \
  --secret-string '{"api_key":"your-actual-api-key"}'

# Dans l'application
import boto3

secrets = boto3.client('secretsmanager')
secret = secrets.get_secret_value(SecretId='openrouter-api-key')
api_key = json.loads(secret['SecretString'])['api_key']
```

#### Configuration Nginx sécurisée

```nginx
# /etc/nginx/conf.d/qwen3-vl-secure.conf
server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate /etc/ssl/certs/your-cert.pem;
    ssl_certificate_key /etc/ssl/private/your-key.pem;
    
    # Sécurité
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/m;
    
    location / {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://127.0.0.1:8080;
        # ... autres configurations
    }
}
```

### 2. Optimisation des performances

#### Cache Redis

```python
# redis_cache.py
import redis
import json
import hashlib

redis_client = redis.Redis(host='your-redis-endpoint', port=6379, decode_responses=True)

def cache_response(prompt, response):
    cache_key = hashlib.md5(prompt.encode()).hexdigest()
    redis_client.setex(cache_key, 3600, json.dumps(response))  # 1 heure

def get_cached_response(prompt):
    cache_key = hashlib.md5(prompt.encode()).hexdigest()
    cached = redis_client.get(cache_key)
    return json.loads(cached) if cached else None
```

#### Optimisation Gradio

```python
# Optimisations dans app_prod.py
demo.queue(
    default_concurrency_limit=20,  # Réduire si problèmes mémoire
    max_size=100,
    api_name="/api/predict"
).launch(
    server_name="0.0.0.0",
    server_port=8080,
    share=False,
    show_error=True,
    quiet=True,  # Réduire les logs en production
    ssr_mode=False,
    max_threads=50,  # Limiter les threads
    enable_queue=True
)
```

### 3. Backup et Disaster Recovery

#### Script de backup

```bash
#!/bin/bash
# backup.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/backups"

# Backup de l'application
tar -czf $BACKUP_DIR/app_backup_$DATE.tar.gz /opt/qwen3-vl-demo

# Backup de la configuration
aws s3 cp $BACKUP_DIR/app_backup_$DATE.tar.gz s3://your-backup-bucket/

# Nettoyer les anciens backups (garder 7 jours)
find $BACKUP_DIR -name "app_backup_*.tar.gz" -mtime +7 -delete
```

## Commandes Utiles

### Déploiement rapide

```bash
#!/bin/bash
# deploy.sh

echo "🚀 Déploiement Qwen3-VL Demo"

# 1. Mise à jour de l'application
cd /opt/qwen3-vl-demo
git pull origin main

# 2. Installation des dépendances
pip3 install -r requirements-prod.txt

# 3. Redémarrage du service
sudo systemctl restart qwen3-vl-demo
sudo systemctl status qwen3-vl-demo

# 4. Test de santé
sleep 10
curl -f http://localhost:8080 || echo "❌ Échec du déploiement"

echo "✅ Déploiement terminé"
```

### Surveillance

```bash
# Surveillance en temps réel
watch -n 5 'curl -s http://localhost:8080/health | python3 -m json.tool'

# Logs en temps réel
tail -f /var/log/qwen3-vl-demo.log

# Métriques système
watch -n 10 'free -h && echo "---" && df -h'
```

## Support et Maintenance

### Check-list de maintenance régulière

- [ ] Mise à jour des dépendances Python
- [ ] Vérification de la sécurité (certificats SSL)
- [ ] Backup des données et configurations
- [ ] Surveillance des coûts AWS
- [ ] Test de restauration
- [ ] Mise à jour de l'AMI (si EC2)
- [ ] Nettoyage des logs anciens

### Contacts et ressources

- **AWS Support** : Console AWS → Support
- **Documentation AWS** : https://docs.aws.amazon.com
- **Community Gradio** : https://github.com/gradio-app/gradio
- **OpenRouter API** : https://openrouter.ai/docs

---

## 📞 Support

Si vous rencontrez des problèmes lors du déploiement, vérifiez :

1. **Les logs** : `sudo journalctl -u qwen3-vl-demo -f`
2. **Les métriques** : CloudWatch Console
3. **La connectivité** : Network tab du navigateur
4. **Les variables d'environnement** : Configuration AWS SSM

Pour un support personnalisé, contactez l'équipe de développement.

---

*Guide créé le : 2025-11-06*  
*Version : 1.0*  
*Compatible : AWS EC2, ECS, Elastic Beanstalk*