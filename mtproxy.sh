#!/bin/bash

# MTProxy Docker Installation Script (Ultra-Fixed Version)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="/opt/MTProxy"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$INSTALL_DIR/.env"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Запустите скрипт от имени root (sudo).${NC}"
    exit 1
fi

# 1. Проверка Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Установка Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl start docker && systemctl enable docker
    rm get-docker.sh
fi

# 2. Определение команды compose
if docker compose version &> /dev/null; then
    DOCKER_CMD="docker compose"
else
    DOCKER_CMD="docker-compose"
fi

# 3. Настройка параметров
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

read -p "Введите порт (по умолчанию 443): " USER_PORT
PORT=${USER_PORT:-443}

if ! command -v xxd &> /dev/null; then apt update && apt install -y xxd; fi
SECRET=$(head -c 16 /dev/urandom | xxd -ps -c 16)
IP=$(curl -4 -s ifconfig.me)

read -p "Введите TAG из @MTProxybot (если нет, жми Enter): " TAG

# 4. Создание файлов без лишних ворнингов
cat > "$ENV_FILE" << EOL
SECRET=$SECRET
PORT=$PORT
TAG=$TAG
EOL

cat > "$COMPOSE_FILE" << EOL
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    restart: always
    ports:
      - "\${PORT}:443"
    environment:
      SECRET: "\${SECRET}"
      TAG: "\${TAG}"
    volumes:
      - proxy-config:/data
volumes:
  proxy-config:
EOL

# 5. Запуск
$DOCKER_CMD down &> /dev/null
$DOCKER_CMD up -d

# 6. Создание команды управления (Упрощенный метод)
cat > /usr/local/bin/mtproxy << 'EOF'
#!/bin/bash
INSTALL_DIR="/opt/MTProxy"
cd $INSTALL_DIR
if docker compose version &> /dev/null; then CMD="docker compose"; else CMD="docker-compose"; fi

case "$1" in
    status) $CMD ps ;;
    stop) $CMD down ;;
    start) $CMD up -d ;;
    restart) $CMD restart ;;
    logs) $CMD logs -f ;;
    *) echo "Используйте: mtproxy {status|start|stop|restart|logs}" ;;
esac
EOF
chmod +x /usr/local/bin/mtproxy

echo -e "\n${GREEN}✅ Установка завершена!${NC}"
echo -e "${CYAN}Ссылка для подключения:${NC}"
echo -e "${YELLOW}tg://proxy?server=$IP&port=$PORT&secret=$SECRET${NC}"
echo -e "\nИспользуйте команду ${GREEN}mtproxy status${NC} для проверки."
