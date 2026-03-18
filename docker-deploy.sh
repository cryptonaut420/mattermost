#!/bin/bash
# ===========================================
# Mattermost Docker Deploy Script
# ===========================================
# Usage:
#   ./docker-deploy.sh              # Deploy locally (port 8065)
#   ./docker-deploy.sh local        # Deploy locally (port 8065)
#   ./docker-deploy.sh server       # Deploy with nginx-proxy
#   ./docker-deploy.sh down         # Shut down deployment
#   ./docker-deploy.sh logs         # View logs
#   ./docker-deploy.sh status       # Check status

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ===========================================
# Setup directories and permissions
# ===========================================
setup_dirs() {
    log_info "Creating required directories..."
    mkdir -p ./volumes/app/mattermost/{config,data,logs,plugins,client/plugins,bleve-indexes}
    mkdir -p ./volumes/db/var/lib/postgresql/data
    
    log_info "Setting permissions (may require sudo)..."
    sudo chown -R 2000:2000 ./volumes/app/mattermost 2>/dev/null || {
        log_warn "Could not set permissions with sudo. Trying without..."
        chown -R 2000:2000 ./volumes/app/mattermost 2>/dev/null || {
            log_warn "Could not set ownership. Container may handle this."
        }
    }
}

# ===========================================
# Deploy locally (without nginx-proxy)
# ===========================================
deploy_local() {
    log_info "Deploying Mattermost locally on port 8065..."
    
    # Update .env for local mode
    sed -i 's|MM_SERVICESETTINGS_SITEURL=.*|MM_SERVICESETTINGS_SITEURL=http://localhost:8065|' .env
    
    setup_dirs
    
    docker compose -f docker-compose.yml -f docker-compose.without-nginx.yml up -d
    
    log_info "Mattermost is starting..."
    log_info "Access at: http://localhost:8065"
    log_info ""
    log_info "Wait ~30 seconds for first-time initialization."
    log_info "Run './docker-deploy.sh logs' to watch startup."
}

# ===========================================
# Deploy with nginx-proxy (for server)
# ===========================================
deploy_server() {
    log_info "Deploying Mattermost with nginx-proxy..."
    
    # Check if nginx-proxy network exists
    if ! docker network ls | grep -q "nginx-proxy"; then
        log_error "nginx-proxy network not found!"
        log_error "Create it with: docker network create nginx-proxy"
        log_error "Or ensure your nginx-proxy container is running."
        exit 1
    fi
    
    # Load domain from .env
    source .env
    
    # Update .env for server mode
    sed -i "s|MM_SERVICESETTINGS_SITEURL=.*|MM_SERVICESETTINGS_SITEURL=https://${DOMAIN}|" .env
    
    setup_dirs
    
    docker compose -f docker-compose.yml -f docker-compose.nginx-proxy.yml up -d
    
    log_info "Mattermost is starting..."
    log_info "Access at: https://${DOMAIN}"
    log_info ""
    log_info "Ensure DNS for ${DOMAIN} points to this server."
    log_info "Run './docker-deploy.sh logs' to watch startup."
}

# ===========================================
# Shut down deployment
# ===========================================
shutdown() {
    log_info "Shutting down Mattermost..."
    
    # Try both compose file combinations
    docker compose -f docker-compose.yml -f docker-compose.without-nginx.yml down 2>/dev/null || true
    docker compose -f docker-compose.yml -f docker-compose.nginx-proxy.yml down 2>/dev/null || true
    
    log_info "Mattermost stopped."
}

# ===========================================
# View logs
# ===========================================
view_logs() {
    docker compose logs -f mattermost
}

# ===========================================
# Check status
# ===========================================
check_status() {
    echo ""
    log_info "Container Status:"
    docker compose ps
    echo ""
    log_info "Recent Logs:"
    docker compose logs --tail=20 mattermost
}

# ===========================================
# Main
# ===========================================
case "${1:-local}" in
    local)
        deploy_local
        ;;
    server)
        deploy_server
        ;;
    down|stop)
        shutdown
        ;;
    logs)
        view_logs
        ;;
    status)
        check_status
        ;;
    setup)
        setup_dirs
        log_info "Directories created."
        ;;
    *)
        echo "Usage: $0 {local|server|down|logs|status|setup}"
        echo ""
        echo "  local   - Deploy locally on port 8065 (default)"
        echo "  server  - Deploy with nginx-proxy for production"
        echo "  down    - Shut down the deployment"
        echo "  logs    - View container logs"
        echo "  status  - Check container status"
        echo "  setup   - Just create directories"
        exit 1
        ;;
esac
