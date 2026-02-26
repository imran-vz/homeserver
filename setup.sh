#!/bin/bash

set -e

# ===========================================
# Homeserver Setup Script
# ===========================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
INTERNAL_DATA_DIR="${SCRIPT_DIR}/data"
EXTERNAL_SSD_PATH="/Volumes/Backup"
EXTERNAL_DATA_DIR="${EXTERNAL_SSD_PATH}/homeserver-data"
CONFIG_DIR="${SCRIPT_DIR}/config"

# Network names
FRONTEND_NETWORK="homelab_frontend"
BACKEND_NETWORK="homelab_backend"

# ===========================================
# Helper Functions
# ===========================================

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# ===========================================
# Pre-flight Checks
# ===========================================

preflight_checks() {
    print_header "Running Pre-flight Checks"

    local errors=0

    # Check for Docker
    if ! check_command "docker"; then
        print_error "Please install Docker/OrbStack first"
        ((errors++))
    else
        # Check if Docker is running
        if docker info &> /dev/null; then
            print_success "Docker daemon is running"
        else
            print_error "Docker daemon is not running. Please start OrbStack."
            ((errors++))
        fi
    fi

    # Check for docker compose
    if docker compose version &> /dev/null; then
        print_success "docker compose is available"
    else
        print_error "docker compose is not available"
        ((errors++))
    fi

    # Check external SSD
    if [[ -d "$EXTERNAL_SSD_PATH" ]]; then
        print_success "External SSD mounted at $EXTERNAL_SSD_PATH"
    else
        print_error "External SSD not found at $EXTERNAL_SSD_PATH"
        print_info "Please mount your SSD or update EXTERNAL_SSD_PATH in this script"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        print_error "Pre-flight checks failed with $errors error(s)"
        exit 1
    fi

    print_success "All pre-flight checks passed"
}

# ===========================================
# Network Setup
# ===========================================

setup_networks() {
    print_header "Setting Up Docker Networks"

    for network in "$FRONTEND_NETWORK" "$BACKEND_NETWORK"; do
        if docker network inspect "$network" &> /dev/null; then
            print_success "Network '$network' already exists"
        else
            print_info "Creating network '$network'..."
            docker network create "$network"
            print_success "Network '$network' created"
        fi
    done
}

# ===========================================
# Directory Setup
# ===========================================

setup_directories() {
    print_header "Setting Up Directories"

    # Internal SSD directories (configs, databases, caches)
    local internal_dirs=(
        "${INTERNAL_DATA_DIR}/postgres"
        "${INTERNAL_DATA_DIR}/redis"
        "${INTERNAL_DATA_DIR}/immich-ml-cache"
        "${INTERNAL_DATA_DIR}/tailscale/immich"
        "${INTERNAL_DATA_DIR}/tailscale/beszel"
        "${INTERNAL_DATA_DIR}/tailscale/adguard"
        "${INTERNAL_DATA_DIR}/tailscale/audiobookshelf"
        "${INTERNAL_DATA_DIR}/beszel"
        "${INTERNAL_DATA_DIR}/beszel-socket"
        "${INTERNAL_DATA_DIR}/beszel-agent"
        "${INTERNAL_DATA_DIR}/adguard/work"
        "${INTERNAL_DATA_DIR}/adguard/conf"
        "${INTERNAL_DATA_DIR}/audiobookshelf/config"
        "${INTERNAL_DATA_DIR}/audiobookshelf/metadata"
        "${INTERNAL_DATA_DIR}/jellyfin/config"
        "${INTERNAL_DATA_DIR}/jellyfin/cache"
    )

    # External SSD directories (media storage)
    local external_dirs=(
        "${EXTERNAL_DATA_DIR}/immich"
    )

    print_info "Creating internal SSD directories..."
    for dir in "${internal_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            print_success "Directory exists: $dir"
        else
            mkdir -p "$dir"
            print_success "Created: $dir"
        fi
    done

    print_info "Creating external SSD directories..."
    for dir in "${external_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            print_success "Directory exists: $dir"
        else
            mkdir -p "$dir"
            print_success "Created: $dir"
        fi
    done

    # Create config directory
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        print_success "Created config directory: $CONFIG_DIR"
    fi
}

# ===========================================
# Configuration Files Setup
# ===========================================

setup_env_file() {
    print_header "Setting Up Environment File"

    local env_file="${SCRIPT_DIR}/.env"
    local env_example="${SCRIPT_DIR}/.env.example"

    if [[ -f "$env_file" ]]; then
        print_success ".env file already exists"

        # Check for required variables
        local missing_vars=()

        if ! grep -q "^DB_PASSWORD=" "$env_file" || grep -q "^DB_PASSWORD=$" "$env_file"; then
            missing_vars+=("DB_PASSWORD")
        fi

        if ! grep -q "^TS_AUTHKEY=" "$env_file" || grep -q "^TS_AUTHKEY=$" "$env_file" || grep -q "^TS_AUTHKEY=tskey-auth-xxxxxxxxxxxxx" "$env_file"; then
            missing_vars+=("TS_AUTHKEY")
        fi

        # Note: BESZEL_AGENT_TOKEN and BESZEL_AGENT_KEY are optional - configured after first run

        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            print_warning "The following variables need to be set in .env:"
            for var in "${missing_vars[@]}"; do
                echo "  - $var"
            done
        fi
    else
        if [[ -f "$env_example" ]]; then
            cp "$env_example" "$env_file"
            print_success "Created .env from .env.example"
        else
            # Create .env file from scratch
            cat > "$env_file" << 'EOF'
# ===========================================
# IMMICH Configuration
# ===========================================

# Immich version - use 'release' for latest stable
IMMICH_VERSION=release

# Database credentials
DB_USERNAME=immich
DB_PASSWORD=
DB_DATABASE_NAME=immich

# Timezone
TZ=Asia/Kolkata

# ===========================================
# TAILSCALE Configuration
# ===========================================

# Generate an auth key at: https://login.tailscale.com/admin/settings/keys
# Use a reusable key for easier container recreation
# Tags must be defined in your Tailscale ACL policy
TS_AUTHKEY=

# Your Tailscale tailnet domain (found in Tailscale admin console)
# Format: your-tailnet-name.ts.net
TS_DOMAIN=

# ===========================================
# BESZEL Configuration
# ===========================================

# These are generated after first run - add system in Beszel web UI
# then copy the TOKEN and KEY values here
BESZEL_AGENT_TOKEN=
BESZEL_AGENT_KEY=
EOF
            print_success "Created .env file"
        fi

        print_warning "Please edit .env and set the following:"
        echo "  - DB_PASSWORD (generate a strong password)"
        echo "  - TS_AUTHKEY (from https://login.tailscale.com/admin/settings/keys)"
        echo "  - TS_DOMAIN (your Tailscale tailnet domain, e.g., myname.ts.net)"
    fi
}

setup_tailscale_config() {
    print_header "Setting Up Tailscale Configuration"

    # Immich Tailscale config
    local ts_immich_config="${CONFIG_DIR}/tailscale-immich-serve.json"

    if [[ -f "$ts_immich_config" ]]; then
        print_success "Tailscale Immich serve config already exists"
    else
        cat > "$ts_immich_config" << 'EOF'
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://immich-server:2283"
        }
      }
    }
  },
  "AllowFunnel": {
    "${TS_CERT_DOMAIN}:443": false
  }
}
EOF
        print_success "Created Tailscale Immich serve config"
    fi

    # Beszel Tailscale config
    local ts_beszel_config="${CONFIG_DIR}/tailscale-beszel-serve.json"

    if [[ -f "$ts_beszel_config" ]]; then
        print_success "Tailscale Beszel serve config already exists"
    else
        cat > "$ts_beszel_config" << 'EOF'
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://beszel:8090"
        }
      }
    }
  },
  "AllowFunnel": {
    "${TS_CERT_DOMAIN}:443": false
  }
}
EOF
        print_success "Created Tailscale Beszel serve config"
    fi

    # Audiobookshelf Tailscale config
    local ts_audiobookshelf_config="${CONFIG_DIR}/tailscale-audiobookshelf-serve.json"

    if [[ -f "$ts_audiobookshelf_config" ]]; then
        print_success "Tailscale Audiobookshelf serve config already exists"
    else
        cat > "$ts_audiobookshelf_config" << 'EOF'
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://audiobookshelf:80"
        }
      }
    }
  },
  "AllowFunnel": {
    "${TS_CERT_DOMAIN}:443": false
  }
}
EOF
        print_success "Created Tailscale Audiobookshelf serve config"
    fi
}

# ===========================================
# Validation
# ===========================================

validate_setup() {
    print_header "Validating Setup"

    local errors=0

    # Check compose file syntax
    print_info "Validating docker compose configuration..."
    if docker compose -f "${SCRIPT_DIR}/compose.yml" config --quiet 2>/dev/null; then
        print_success "Docker compose configuration is valid"
    else
        print_error "Docker compose configuration has errors"
        docker compose -f "${SCRIPT_DIR}/compose.yml" config 2>&1 | head -20
        ((errors++))
    fi

    # Check .env file
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        # Check DB_PASSWORD is set
        if grep -q "^DB_PASSWORD=.\+" "$env_file" && ! grep -q "^DB_PASSWORD=changeme" "$env_file"; then
            print_success "DB_PASSWORD is configured"
        else
            print_warning "DB_PASSWORD is not set or using default value"
            ((errors++))
        fi

        # Check TS_AUTHKEY
        if grep -q "^TS_AUTHKEY=tskey-" "$env_file" && ! grep -q "^TS_AUTHKEY=tskey-auth-xxxxxxxxxxxxx" "$env_file"; then
            print_success "TS_AUTHKEY is configured"
        else
            print_warning "TS_AUTHKEY is not set (Tailscale won't auto-authenticate)"
        fi
    else
        print_error ".env file not found"
        ((errors++))
    fi

    # Check external library path exists (optional)
    if [[ -d "${EXTERNAL_SSD_PATH}/Photos" ]]; then
        print_success "External Photos library found at ${EXTERNAL_SSD_PATH}/Photos"
    else
        print_warning "External Photos library not found at ${EXTERNAL_SSD_PATH}/Photos"
        print_info "Create this directory or update the compose.yml if your photos are elsewhere"
    fi

    # Check audiobooks library path exists (optional)
    if [[ -d "${EXTERNAL_SSD_PATH}/Books" ]]; then
        print_success "External Books library found at ${EXTERNAL_SSD_PATH}/Books"
    else
        print_warning "External Books library not found at ${EXTERNAL_SSD_PATH}/Books"
        print_info "Create this directory or update the compose.yml if your audiobooks are elsewhere"
    fi

    return $errors
}

# ===========================================
# Generate Password
# ===========================================

generate_password() {
    # Generate a secure random password
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

# ===========================================
# Interactive Setup
# ===========================================

interactive_setup() {
    local env_file="${SCRIPT_DIR}/.env"

    print_header "Interactive Configuration"

    # DB Password
    if grep -q "^DB_PASSWORD=$" "$env_file" 2>/dev/null || ! grep -q "^DB_PASSWORD=" "$env_file" 2>/dev/null; then
        echo ""
        read -p "Generate a random database password? [Y/n]: " gen_pass
        if [[ "$gen_pass" != "n" && "$gen_pass" != "N" ]]; then
            local new_pass=$(generate_password)
            if [[ -f "$env_file" ]]; then
                sed -i '' "s/^DB_PASSWORD=.*/DB_PASSWORD=${new_pass}/" "$env_file"
            fi
            print_success "Generated and saved database password"
        fi
    fi

    # Tailscale Auth Key
    if grep -q "^TS_AUTHKEY=$" "$env_file" 2>/dev/null || grep -q "^TS_AUTHKEY=tskey-auth-xxxxxxxxxxxxx" "$env_file" 2>/dev/null; then
        echo ""
        print_info "Tailscale auth key not configured"
        echo "Get one from: https://login.tailscale.com/admin/settings/keys"
        echo "  - Check 'Reusable' for easier container recreation"
        echo "  - Add tag 'tag:container' if using ACL tags"
        echo ""
        read -p "Enter your Tailscale auth key (or press Enter to skip): " ts_key
        if [[ -n "$ts_key" ]]; then
            sed -i '' "s/^TS_AUTHKEY=.*/TS_AUTHKEY=${ts_key}/" "$env_file"
            print_success "Saved Tailscale auth key"
        else
            print_warning "Skipped Tailscale auth key - you'll need to authenticate manually"
        fi
    fi

    # Tailscale domain
    local ts_config="${CONFIG_DIR}/tailscale-immich-serve.json"
    if grep -q "your-tailnet" "$ts_config" 2>/dev/null; then
        echo ""
        print_info "Tailscale serve config needs your tailnet domain"
        echo "Your tailnet domain looks like: your-name.ts.net"
        echo ""
        read -p "Enter your tailnet domain (e.g., myname.ts.net) or press Enter to skip: " ts_domain
        if [[ -n "$ts_domain" ]]; then
            sed -i '' "s/your-tailnet\.ts\.net/${ts_domain}/g" "$ts_config"
            print_success "Updated Tailscale serve config with domain: immich.${ts_domain}"
        fi
    fi
}

# ===========================================
# Start Services
# ===========================================

start_services() {
    print_header "Starting Services"

    read -p "Start the services now? [y/N]: " start_now
    if [[ "$start_now" == "y" || "$start_now" == "Y" ]]; then
        print_info "Pulling latest images..."
        docker compose -f "${SCRIPT_DIR}/compose.yml" pull

        print_info "Starting services..."
        docker compose -f "${SCRIPT_DIR}/compose.yml" up -d

        print_success "Services started!"
        echo ""
        print_info "Immich will be available at: http://localhost:2283"
        print_info "First startup may take a few minutes for ML models to download"
        echo ""
        print_info "Check status with: docker compose logs -f"
    else
        print_info "Skipped starting services"
        echo ""
        echo "To start manually, run:"
        echo "  cd ${SCRIPT_DIR}"
        echo "  docker compose up -d"
    fi
}

# ===========================================
# Main
# ===========================================

main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Homeserver Setup Script             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""

    # Change to script directory
    cd "$SCRIPT_DIR"

    # Run setup steps
    preflight_checks
    setup_networks
    setup_directories
    setup_env_file
    setup_tailscale_config
    interactive_setup

    # Validate
    if validate_setup; then
        print_header "Setup Complete!"
        start_services
    else
        print_header "Setup Complete (with warnings)"
        print_warning "Please address the warnings above before starting services"
        echo ""
        echo "Once fixed, start services with:"
        echo "  cd ${SCRIPT_DIR}"
        echo "  docker compose up -d"
    fi

    echo ""
    print_header "Useful Commands"
    echo "  Start services:    docker compose up -d"
    echo "  Stop services:     docker compose down"
    echo "  View logs:         docker compose logs -f"
    echo "  View status:       docker compose ps"
    echo "  Restart a service: docker compose restart <service-name>"
    echo ""

    print_header "Beszel Setup (after first start)"
    echo "  1. Open Beszel at http://localhost:8090 or https://beszel.<your-tailnet>.ts.net"
    echo "  2. Create an admin account"
    echo "  3. Click 'Add System' and use '/beszel_socket/beszel.sock' as Host/IP"
    echo "  4. Copy the TOKEN and KEY values to your .env file"
    echo "  5. Restart the agent: docker compose restart beszel-agent"
    echo ""
}

# Run main function
main "$@"
