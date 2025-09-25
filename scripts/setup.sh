#!/bin/bash

# ==============================================
# SCRIPT DE CONFIGURAÇÃO INICIAL - N8N PRODUÇÃO
# ==============================================

set -e

echo "🚀 Iniciando configuração do N8N para produção..."

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detectar qual comando Docker Compose usar
DOCKER_COMPOSE_CMD=""

detect_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    elif docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    else
        print_error "Docker Compose não está disponível"
        print_error "Instale Docker Compose ou use Docker com plugin compose"
        exit 1
    fi
    print_message "Usando comando: $DOCKER_COMPOSE_CMD"
}

# Função para exibir mensagens
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se Docker e Docker Compose estão instalados
check_dependencies() {
    print_message "Verificando dependências..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker não está instalado. Instale o Docker primeiro."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        print_error "Docker Compose não está disponível. Verifique sua instalação do Docker."
        exit 1
    fi
    
    print_message "✅ Dependências verificadas com sucesso"
}

# Criar estrutura de diretórios
create_directories() {
    print_message "Criando estrutura de diretórios..."
    
    # Diretórios de dados
    mkdir -p data/{postgres,redis,qdrant,n8n,n8n-files}
    
    # Diretórios de configuração
    mkdir -p config/{postgres,redis,qdrant}
    
    # Diretórios de backup e logs
    mkdir -p backups logs
    
    # Definir permissões
    chmod -R 755 data
    chmod -R 755 config
    chmod -R 755 backups
    chmod -R 755 logs
    
    print_message "✅ Estrutura de diretórios criada"
}

# Verificar arquivo .env
check_env_file() {
    print_message "Verificando arquivo de configuração..."
    
    if [[ ! -f .env ]]; then
        print_error "Arquivo .env não encontrado!"
        print_error "Copie o arquivo .env.example para .env e configure as variáveis necessárias."
        exit 1
    fi
    
    # Verificar variáveis críticas
    source .env
    
    if [[ -z "$N8N_ENCRYPTION_KEY" ]] || [[ "$N8N_ENCRYPTION_KEY" == "your-unique-32-char-hex-encryption-key-here" ]]; then
        print_error "N8N_ENCRYPTION_KEY não configurada!"
        print_error "Execute: openssl rand -hex 32"
        exit 1
    fi
    
    if [[ -z "$N8N_JWT_SECRET" ]] || [[ "$N8N_JWT_SECRET" == "your-unique-64-char-hex-jwt-secret-here" ]]; then
        print_error "N8N_JWT_SECRET não configurada!"
        print_error "Execute: openssl rand -hex 64"
        exit 1
    fi
    
    if [[ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]] || [[ "$CLOUDFLARE_TUNNEL_TOKEN" == "your-cloudflare-tunnel-token-here" ]]; then
        if [[ -z "$CLOUDFLARE_API_TOKEN" ]] || [[ "$CLOUDFLARE_API_TOKEN" == "your-cloudflare-api-token-here" ]]; then
            print_warning "CLOUDFLARE_API_TOKEN não configurado!"
            print_warning "Configure o API Token antes do Tunnel Token:"
            print_warning "1. Vá para Cloudflare Dashboard > My Profile > API Tokens"
            print_warning "2. Crie um token com permissões Zone:DNS:Edit e Account:Cloudflare Tunnel:Edit"
            print_warning "3. Configure CLOUDFLARE_API_TOKEN no arquivo .env"
            echo
        fi
        
        print_warning "CLOUDFLARE_TUNNEL_TOKEN não configurado!"
        print_warning "Você pode configurar automaticamente executando:"
        print_warning "./scripts/configure-cloudflare-tunnel.sh"
        echo
        read -p "Deseja configurar o Cloudflare Tunnel agora? (y/n): " configure_tunnel
        
        if [[ $configure_tunnel =~ ^[Yy]$ ]]; then
            print_message "Iniciando configuração do Cloudflare Tunnel..."
            ./scripts/configure-cloudflare-tunnel.sh
        else
            print_warning "Lembre-se de configurar o túnel antes de iniciar os serviços!"
        fi
    fi
    
    print_message "✅ Configurações verificadas"
}

# Gerar chaves de segurança se não existirem
generate_security_keys() {
    print_message "Verificando chaves de segurança..."
    
    # Backup do .env original
    cp .env .env.backup
    
    # Gerar N8N_ENCRYPTION_KEY se não existir ou for padrão
    if grep -q "your-unique-32-char-hex-encryption-key-here" .env; then
        ENCRYPTION_KEY=$(openssl rand -hex 32)
        sed -i "s/your-unique-32-char-hex-encryption-key-here/$ENCRYPTION_KEY/" .env
        print_message "✅ N8N_ENCRYPTION_KEY gerada"
    fi
    
    # Gerar N8N_JWT_SECRET se não existir ou for padrão
    if grep -q "your-unique-64-char-hex-jwt-secret-here" .env; then
        JWT_SECRET=$(openssl rand -hex 64)
        sed -i "s/your-unique-64-char-hex-jwt-secret-here/$JWT_SECRET/" .env
        print_message "✅ N8N_JWT_SECRET gerada"
    fi
}

# Inicializar banco de dados
init_database() {
    print_message "Inicializando banco de dados..."
    
    # Carregar variáveis de ambiente
    source .env
    
    # Subir apenas o PostgreSQL primeiro
    $DOCKER_COMPOSE_CMD up -d postgres
    
    # Aguardar PostgreSQL ficar pronto
    print_message "Aguardando PostgreSQL ficar pronto..."
    until $DOCKER_COMPOSE_CMD exec -T postgres pg_isready -U $POSTGRES_USER -d $POSTGRES_DB; do
        sleep 2
    done
    
    print_message "✅ PostgreSQL inicializado"
}

# Função principal de setup
main() {
    print_message "=== CONFIGURAÇÃO N8N PRODUÇÃO ==="
    
    check_dependencies
    create_directories
    check_env_file
    generate_security_keys
    init_database
    
    print_message "=== CONFIGURAÇÃO CONCLUÍDA ==="
    print_message ""
    print_message "Próximos passos:"
    print_message "1. Configure o token do Cloudflare Tunnel no arquivo .env"
    print_message "2. Execute: $DOCKER_COMPOSE_CMD up -d"
    print_message "3. Acesse: https://n8n.giacomo.dev.br"
    print_message ""
    print_warning "IMPORTANTE: Guarde as chaves geradas em local seguro!"
    print_warning "Backup do .env original salvo como .env.backup"
}

# Executar script
main "$@"