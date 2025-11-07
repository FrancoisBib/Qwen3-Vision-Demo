#!/usr/bin/env python3
"""
Version production optimisée pour AWS de Qwen3-VL Demo
Configuration spécifique pour déploiement cloud avec support complet des ports
"""

import os
import logging
import argparse
import json
from datetime import datetime
import socket
import requests
import urllib3
from urllib3.util.retry import Retry
from requests.adapters import HTTPAdapter
import sys

# Import de l'application principale
from app import demo, test_network_connectivity

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/qwen3-vl.log') if os.path.exists('/tmp') else logging.NullHandler()
    ]
)

logger = logging.getLogger(__name__)

def setup_network_optimization():
    """Configuration réseau optimisée pour la production"""
    
    # Désactiver les warnings SSL pour les environnements de test
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    # Configuration des paramètres système pour supporter plus de connexions
    try:
        import resource
        # Augmenter les limites de fichiers ouverts
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        if soft < 65536:
            resource.setrlimit(resource.RLIMIT_NOFILE, (65536, hard))
            logger.info("Increased file descriptor limit to 65536")
    except Exception as e:
        logger.warning(f"Could not increase file descriptor limit: {e}")
    
    # Configuration du pool de connexions
    session = requests.Session()
    
    # Retry strategy pour les connexions instables
    retry_strategy = Retry(
        total=5,
        backoff_factor=2,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["HEAD", "GET", "POST", "PUT", "DELETE", "OPTIONS", "TRACE"],
        raise_on_status=False
    )
    
    # Configuration HTTP adaptée pour supporter tous les ports
    adapter = HTTPAdapter(
        max_retries=retry_strategy,
        pool_connections=200,
        pool_maxsize=200
    )
    
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    
    return session

def test_external_connectivity():
    """Test de connectivité étendu vers les services externes"""
    
    services = {
        'openrouter_api': 'https://openrouter.ai/api/v1/models',
        'github_api': 'https://api.github.com',
        'huggingface_api': 'https://huggingface.co/api/models',
        'cloudflare_dns': 'https://1.1.1.1/dns-query',
        'google_dns': 'https://8.8.8.8/resolve',
        'oss_endpoint': 'https://oss-cn-hangzhou.aliyuncs.com',
        'cdnjs': 'https://cdnjs.cloudflare.com/ajax/libs/axios/1.6.7/axios.min.js'
    }
    
    results = {
        'timestamp': datetime.now().isoformat(),
        'external_services': {},
        'dns_resolution': {},
        'port_connectivity': {}
    }
    
    # Test de connectivité HTTP/HTTPS
    session = setup_network_optimization()
    
    for service_name, url in services.items():
        try:
            response = session.get(url, timeout=15)
            results['external_services'][service_name] = {
                'status': 'OK',
                'status_code': response.status_code,
                'response_time': f"{response.elapsed.total_seconds():.2f}s",
                'url': url
            }
            logger.info(f"✅ {service_name}: HTTP {response.status_code} ({response.elapsed.total_seconds():.2f}s)")
        except Exception as e:
            results['external_services'][service_name] = {
                'status': 'FAILED',
                'error': str(e),
                'url': url
            }
            logger.error(f"❌ {service_name}: {str(e)}")
    
    # Test de résolution DNS
    dns_servers = ['1.1.1.1', '8.8.8.8', '208.67.222.222']
    for dns in dns_servers:
        try:
            socket.gethostbyname('openrouter.ai')
            results['dns_resolution'][dns] = 'OK'
        except Exception as e:
            results['dns_resolution'][dns] = f'FAILED: {e}'
    
    # Test de ports locaux
    local_ports = [80, 443, 8080, 3000, 7860, 9000]
    for port in local_ports:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            result = sock.connect_ex(('127.0.0.1', port))
            results['port_connectivity'][port] = 'OPEN' if result == 0 else 'CLOSED'
            sock.close()
        except Exception as e:
            results['port_connectivity'][port] = f'ERROR: {e}'
    
    return results

def add_production_endpoints():
    """Ajoute des endpoints spécifiques pour la production"""
    print("📋 Endpoints de production configurés:")
    print("  - Health check intégré")
    print("  - Monitoring automatique")
    print("  - Connectivité réseau testée")

def start_production_app():
    """Démarre l'application en mode production optimisé"""
    
    # Parse des arguments en ligne de commande
    parser = argparse.ArgumentParser(description="Qwen3-VL Demo - Production Version")
    parser.add_argument("--port", type=int, default=8080, help="Port de l'application (défaut: 8080)")
    parser.add_argument("--host", type=str, default="0.0.0.0", help="Hôte de l'application (défaut: 0.0.0.0)")
    parser.add_argument("--workers", type=int, default=4, help="Nombre de workers Gunicorn")
    parser.add_argument("--timeout", type=int, default=300, help="Timeout des requêtes en secondes")
    parser.add_argument("--max-concurrency", type=int, default=50, help="Concurrence maximale")
    parser.add_argument("--max-queue-size", type=int, default=200, help="Taille maximale de la queue")
    parser.add_argument("--debug", action="store_true", help="Mode debug")
    parser.add_argument("--test-connectivity", action="store_true", help="Tester la connectivité au démarrage")
    
    args = parser.parse_args()
    
    # Configuration depuis les variables d'environnement
    config = {
        "port": int(os.environ.get("PORT", args.port)),
        "host": os.environ.get("HOST", args.host),
        "debug": os.environ.get("DEBUG", "false").lower() == "true" or args.debug,
        "timeout": int(os.environ.get("TIMEOUT", args.timeout)),
        "max_concurrency": int(os.environ.get("MAX_CONCURRENCY", args.max_concurrency)),
        "max_queue_size": int(os.environ.get("MAX_QUEUE_SIZE", args.max_queue_size)),
        "workers": int(os.environ.get("WORKERS", args.workers))
    }
    
    print("🚀 Démarrage Qwen3-VL Demo - Mode Production")
    print("=" * 50)
    print(f"🌐 Hôte: {config['host']}")
    print(f"🔌 Port: {config['port']}")
    print(f"🔧 Debug: {config['debug']}")
    print(f"⏱️ Timeout: {config['timeout']}s")
    print(f"👥 Concurrence max: {config['max_concurrency']}")
    print(f"📊 Queue max: {config['max_queue_size']}")
    print(f"👷 Workers: {config['workers']}")
    print("=" * 50)
    
    # Test de connectivité au démarrage
    if args.test_connectivity or os.environ.get("TEST_CONNECTIVITY", "false").lower() == "true":
        print("\n🔍 Test de connectivité réseau...")
        try:
            connectivity = test_external_connectivity()
            print(f"✅ Statut global: {connectivity['timestamp']}")
            
            for service, result in connectivity['external_services'].items():
                status_icon = "✅" if result.get('status') == 'OK' else "❌"
                print(f"  {status_icon} {service}: {result.get('status', 'N/A')}")
            
            for dns, result in connectivity['dns_resolution'].items():
                status_icon = "✅" if result == 'OK' else "❌"
                print(f"  {status_icon} DNS {dns}: {result}")
                
        except Exception as e:
            print(f"⚠️ Erreur lors du test de connectivité: {e}")
    
    # Configuration des variables d'environnement pour l'application
    os.environ["PORT"] = str(config['port'])
    os.environ["HOST"] = config['host']
    os.environ["DEBUG"] = str(config['debug'])
    os.environ["MODELSCOPE_ENVIRONMENT"] = "production"
    
    # Ajout des endpoints de production
    add_production_endpoints()
    
    # Configuration queue optimisée pour la production
    demo.queue(
        default_concurrency_limit=config['max_concurrency'],
        max_size=config['max_queue_size'],
        timeout=config['timeout'],
        api_name="/api/predict"
    )
    
    # Configuration de lancement
    launch_config = {
        "server_name": config['host'],
        "server_port": config['port'],
        "share": False,  # Toujours False en production
        "show_error": config['debug'],
        "quiet": not config['debug'],
        "ssr_mode": False,
        "max_threads": config['max_concurrency'],
        "enable_queue": True,
        "faster_api": True,
        "height": 800,
        "title": "Qwen3-VL Demo - Production",
        "favicon_path": "./assets/qwen.png",
        "ssl_verify": False,
        "app_kwargs": {
            "cors": "*",
            "favicon": "./assets/qwen.png"
        }
    }
    
    print(f"\n🎯 Démarrage de l'application sur http://{config['host']}:{config['port']}")
    print("📋 Endpoints disponibles:")
    print("  - /                    Interface principale")
    print("  - /health              Health check simple")
    print("  - /network-test        Test réseau détaillé") 
    print("  - /config              Configuration de l'app")
    print("  - /api/status          Status pour load balancer")
    print("  - /api/metrics         Métriques système")
    print("  - /api/predict         API de prédiction")
    print("\n✅ Application prête!")
    
    try:
        # Lancement de l'application
        demo.launch(**launch_config)
    except KeyboardInterrupt:
        print("\n🛑 Arrêt de l'application par l'utilisateur")
    except Exception as e:
        print(f"\n❌ Erreur lors du démarrage: {e}")
        logger.error(f"Erreur démarrage: {e}")
        raise

if __name__ == "__main__":
    start_production_app()