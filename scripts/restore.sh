#!/bin/bash

# Detectar comando Docker Compose
DOCKER_COMPOSE_CMD=""

detect_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    elif docker compose version &> /dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    else
        echo "❌ Docker Compose não está disponível"
        exit 1
    fi
}

# ==============================================
# SCRIPT DE RESTORE - N8N PRODUÇÃO
# ==============================================

set -e

# Verificar parâmetros
if [[ $# -ne 1 ]]; then
    echo "Uso: $0 <nome_do_backup>"
    echo "Exemplo: $0 n8n_backup_20241201_120000"
    exit 1
fi

BACKUP_NAME=$1
BACKUP_DIR="./backups"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[RESTORE]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se os arquivos de backup existem
check_backup_files() {
    local missing_files=()
    
    if [[ ! -f "$BACKUP_DIR/${BACKUP_NAME}_postgres.sql" ]]; then
        missing_files+=("${BACKUP_NAME}_postgres.sql")
    fi
    
    if [[ ! -f "$BACKUP_DIR/${BACKUP_NAME}_n8n_data.tar.gz" ]]; then
        missing_files+=("${BACKUP_NAME}_n8n_data.tar.gz")
    fi
    
    if [[ ! -f "$BACKUP_DIR/${BACKUP_NAME}_n8n_files.tar.gz" ]]; then
        missing_files+=("${BACKUP_NAME}_n8n_files.tar.gz")
    fi
    
    if [[ ! -f "$BACKUP_DIR/${BACKUP_NAME}_qdrant.tar.gz" ]]; then
        missing_files+=("${BACKUP_NAME}_qdrant.tar.gz")
    fi
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "Arquivos de backup não encontrados:"
        for file in "${missing_files[@]}"; do
            print_error "  - $file"
        done
        exit 1
    fi
}

# Confirmar operação
confirm_restore() {
    print_warning "ATENÇÃO: Esta operação irá sobrescrever todos os dados atuais!"
    read -p "Deseja continuar? (digite 'yes' para confirmar): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        print_message "Operação cancelada."
        exit 0
    fi
}

# Parar serviços
stop_services() {
    print_message "Parando serviços..."
    $DOCKER_COMPOSE_CMD down
}

# Fazer backup dos dados atuais
backup_current_data() {
    local current_date=$(date +%Y%m%d_%H%M%S)
    print_message "Fazendo backup dos dados atuais antes do restore..."
    
    if [[ -d "./data" ]]; then
        tar -czf "$BACKUP_DIR/pre_restore_backup_${current_date}.tar.gz" -C . data
        print_message "✅ Backup atual salvo como: pre_restore_backup_${current_date}.tar.gz"
    fi
}

# Restaurar dados
restore_data() {
    print_message "Restaurando dados do N8N..."
    
    # Limpar dados atuais
    rm -rf ./data/n8n/*
    rm -rf ./data/n8n-files/*
    rm -rf ./data/qdrant/*
    
    # Restaurar arquivos
    tar -xzf "$BACKUP_DIR/${BACKUP_NAME}_n8n_data.tar.gz" -C ./data
    tar -xzf "$BACKUP_DIR/${BACKUP_NAME}_n8n_files.tar.gz" -C ./data
    tar -xzf "$BACKUP_DIR/${BACKUP_NAME}_qdrant.tar.gz" -C ./data
    
    print_message "✅ Dados do N8N restaurados"
}

# Restaurar banco de dados
restore_database() {
    print_message "Iniciando PostgreSQL para restore..."
    docker-compose up -d postgres
    
    # Aguardar PostgreSQL ficar pronto
    until docker-compose exec -T postgres pg_isready -U $POSTGRES_USER -d $POSTGRES_DB; do
        sleep 2
    done
    
    print_message "Restaurando banco de dados..."
    
    # Limpar banco atual
    docker-compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
    
    # Restaurar backup
    docker-compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < "$BACKUP_DIR/${BACKUP_NAME}_postgres.sql"
    
    print_message "✅ Banco de dados restaurado"
}

# Iniciar todos os serviços
start_services() {
    print_message "Iniciando todos os serviços..."
    $DOCKER_COMPOSE_CMD up -d
    
    # Aguardar serviços ficarem prontos
    sleep 30
    
    print_message "✅ Serviços iniciados"
}

# Verificar status dos serviços
check_services() {
    print_message "Verificando status dos serviços..."
    $DOCKER_COMPOSE_CMD ps
    
    # Verificar se N8N está respondendo
    if curl -f -s http://localhost:5678/healthz > /dev/null; then
        print_message "✅ N8N está respondendo corretamente"
    else
        print_warning "N8N pode não estar totalmente pronto ainda"
    fi
}

# Função principal
main() {
    print_message "=== RESTAURAÇÃO N8N - $BACKUP_NAME ==="
    
    # Detectar Docker Compose e carregar variáveis
    detect_docker_compose
    source .env 2>/dev/null || { print_error "Arquivo .env não encontrado!"; exit 1; }
    
    check_backup_files
    confirm_restore
    stop_services
    backup_current_data
    restore_data
    restore_database
    start_services
    check_services
    
    print_message "=== RESTAURAÇÃO CONCLUÍDA ==="
    print_message "N8N foi restaurado com sucesso!"
    print_message "Acesse: https://n8n.giacomo.dev.br"
}

# Executar script
main "$@"