#!/bin/bash

# MTProxy Docker Installation Script (Fixed for Python 3.12+ / Docker Compose V2)
# Uses official telegrammessenger/proxy:latest Docker image

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}MTProxy Docker Installation (Fixed Version)${NC}\n"

# Configuration
INSTALL_DIR="/opt/MTProxy"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$INSTALL_DIR/.env"
INFO_FILE="$INSTALL_DIR/info.txt"

# Require root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This installer must be run as root (use sudo).${NC}"
    exit 1
fi

# Function to detect docker compose command
get_compose_cmd() {
    if docker compose version &> /dev/null; then
        echo "docker compose"
    elif docker-compose version &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose" # Fallback
    fi
}

DOCKER_COMPOSE=$(get_compose_cmd)

# Function to generate random hex secret
generate_secret() {
    head -c 16 /dev/urandom | xxd -ps -c 16
}

# Function to update TAG
update_tag() {
    echo -e "${YELLOW}🏷️  Update TAG from @MTProxybot${NC}\n"
    
    if [[ ! -f "$ENV_FILE" ]]; then
        echo -e "${RED}MTProxy not installed. Please install first.${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}To get your TAG:${NC}"
    echo -e "1. Open Telegram and find @MTProxybot"
    echo -e "2. Send /newproxy command"
    echo -e "3. Register your proxy with the bot"
    echo -e "4. Bot will provide you with a TAG (32 hex characters)"
    echo ""
    
    read -p "Enter TAG from @MTProxybot (leave empty to remove TAG): " NEW_TAG
    
    if [[ -n "$NEW_TAG" ]]; then
        if [[ ! "$NEW_TAG" =~ ^[0-9a-fA-F]{32}$ ]]; then
            echo -e "${RED}Invalid TAG format. TAG should be 32 hexadecimal characters.${NC}"
            exit 1
        fi
        
        if grep -q "^TAG=" "$ENV_FILE"; then
            sed -i "s/^TAG=.*/TAG=$NEW_TAG/" "$ENV_FILE"
        else
            echo "TAG=$NEW_TAG" >> "$ENV_FILE"
        fi
        echo -e "${GREEN}✅ TAG updated successfully!${NC}"
    else
        sed -i '/^TAG=/d' "$ENV_FILE"
        echo -e "${YELLOW}TAG removed. No channel will be promoted.${NC}"
    fi
    
    echo -e "${YELLOW}Restarting MTProxy container...${NC}"
    cd "$INSTALL_DIR" || exit 1
    $DOCKER_COMPOSE down
    $DOCKER_COMPOSE up -d
    
    echo -e "${GREEN}✅ MTProxy restarted with new configuration!${NC}"
}

# Check for uninstall option
if [[ "$1" == "uninstall" ]]; then
    echo -e "${YELLOW}🗑️  MTProxy Uninstallation${NC}\n"
    read -p "Are you sure you want to continue? (type 'YES' to confirm): " CONFIRM
    if [[ "$CONFIRM" != "YES" ]]; then
        echo -e "${GREEN}Uninstallation cancelled.${NC}"
        exit 0
    fi
    
    if [[ -f "$COMPOSE_FILE" ]]; then
        cd "$INSTALL_DIR" || exit 1
        $DOCKER_COMPOSE down -v 2>/dev/null || true
    fi
    docker rmi telegrammessenger/proxy:latest 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    rm -f "/usr/local/bin/mtproxy"
    echo -e "\n${GREEN}✅ MTProxy has been removed!${NC}"
    exit 0
fi

if [[ "$1" == "update-tag" ]]; then
    update_tag
    exit 0
fi

# Get user input
DEFAULT_PORT=443
read -p "Enter proxy port (default: $DEFAULT_PORT): " USER_PORT
PORT=${USER_PORT:-$DEFAULT_PORT}

echo -e "\n${YELLOW}Installing MTProxy with Docker...${NC}"

# Check and Install Docker & Compose V2
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker and Docker Compose Plugin...${NC}"
    apt update -qq
    apt install -y docker.io docker-compose-plugin
    systemctl start docker
    systemctl enable docker
fi

# Ensure docker-compose-plugin is installed if missing
if ! docker compose version &> /dev/null; then
    apt update && apt install -y docker-compose-plugin
fi

# Update variable after installation
DOCKER_COMPOSE=$(get_compose_cmd)

# Check if xxd is available
if ! command -v xxd &> /dev/null; then
    apt install -y xxd || apt install -y vim-common
fi

SECRET=$(generate_secret)
EXTERNAL_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)

read -p "Enter TAG from @MTProxybot (leave empty to skip): " USER_TAG

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# Create .env file
cat > "$ENV_FILE" << EOL
SECRET=$SECRET
PORT=$PORT
EOL

if [[ -n "$USER_TAG" && "$USER_TAG" =~ ^[0-9a-fA-F]{32}$ ]]; then
    echo "TAG=$USER_TAG" >> "$ENV_FILE"
fi

# Create docker-compose.yml
cat > "$COMPOSE_FILE" << 'EOL'
version: '3.8'
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    restart: always
    ports:
      - "${PORT}:443"
    environment:
      SECRET: "${SECRET}"
      TAG: "${TAG}"
    volumes:
      - proxy-config:/data
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
volumes:
  proxy-config:
EOL

# Firewall
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    ufw allow $PORT/tcp
fi

# Start
$DOCKER_COMPOSE up -d

# Create management utility
cat > "/usr/local/bin/mtproxy" << UTILITY_EOF
#!/bin/bash
DOCKER_COMPOSE="$DOCKER_COMPOSE"
INSTALL_DIR="$INSTALL_DIR"
case "\${1:-status}" in
    "start") cd \$INSTALL_DIR && \$DOCKER_COMPOSE up -d ;;
    "stop") cd \$INSTALL_DIR && \$DOCKER_COMPOSE down ;;
    "restart") cd \$INSTALL_DIR && \$DOCKER_COMPOSE restart ;;
    "logs") cd \$INSTALL_DIR && \$DOCKER_COMPOSE logs -f ;;
    "status") docker ps | grep mtproto-proxy ;;
    *) echo "Usage: mtproxy {start|stop|restart|logs|status}" ;;
esac
UTILITY_EOF

chmod +x "/usr/local/bin/mtproxy"

echo -e "\n${GREEN}✅ Installation Complete!${NC}"
echo -e "${YELLOW}Link:${NC} tg://proxy?server=$EXTERNAL_IP&port=$PORT&secret=$SECRET"
