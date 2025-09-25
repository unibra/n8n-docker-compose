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
# SCRIPT DE BACKUP AUTOMÁTICO - N8N PRODUÇÃO
# ==============================================

set -e

# Configurações
BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="n8n_backup_${DATE}"
RETENTION_DAYS=30

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[BACKUP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Criar diretório de backup
mkdir -p "$BACKUP_DIR"

# Detectar Docker Compose e carregar variáveis
detect_docker_compose
source .env 2>/dev/null || { print_error "Arquivo .env não encontrado!"; exit 1; }

print_message "Iniciando backup do N8N - $DATE"

# Backup do banco PostgreSQL
print_message "Fazendo backup do PostgreSQL..."
$DOCKER_COMPOSE_CMD exec -T postgres pg_dump -U $POSTGRES_USER -d $POSTGRES_DB > "$BACKUP_DIR/${BACKUP_NAME}_postgres.sql"

# Backup dos dados do N8N
print_message "Fazendo backup dos dados do N8N..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}_n8n_data.tar.gz" -C ./data n8n

# Backup dos arquivos do N8N
print_message "Fazendo backup dos arquivos do N8N..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}_n8n_files.tar.gz" -C ./data n8n-files

# Backup do Qdrant
print_message "Fazendo backup do Qdrant..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}_qdrant.tar.gz" -C ./data qdrant

# Backup das configurações
print_message "Fazendo backup das configurações..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}_configs.tar.gz" .env docker-compose.yml config/

# Criar arquivo de informações do backup
cat > "$BACKUP_DIR/${BACKUP_NAME}_info.txt" << EOF
Backup N8N - Informações
========================
Data: $DATE
Versão: $(docker-compose exec -T n8n n8n --version 2>/dev/null || echo "N/A")
Host: $(hostname)
Arquivos incluídos:
- ${BACKUP_NAME}_postgres.sql
- ${BACKUP_NAME}_n8n_data.tar.gz
- ${BACKUP_NAME}_n8n_files.tar.gz
- ${BACKUP_NAME}_qdrant.tar.gz
- ${BACKUP_NAME}_configs.tar.gz
EOF

print_message "✅ Backup completo criado: $BACKUP_NAME"

# Limpeza de backups antigos
print_message "Removendo backups antigos (>${RETENTION_DAYS} dias)..."
find "$BACKUP_DIR" -name "n8n_backup_*" -type f -mtime +$RETENTION_DAYS -delete

print_message "✅ Backup concluído com sucesso!"

# Upload para S3 (se configurado)
if [[ -n "$BACKUP_S3_BUCKET" ]]; then
    print_message "Enviando backup para S3..."
    
    if command -v aws &> /dev/null; then
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}_postgres.sql" "s3://$BACKUP_S3_BUCKET/n8n-backups/"
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}_n8n_data.tar.gz" "s3://$BACKUP_S3_BUCKET/n8n-backups/"
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}_n8n_files.tar.gz" "s3://$BACKUP_S3_BUCKET/n8n-backups/"
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}_qdrant.tar.gz" "s3://$BACKUP_S3_BUCKET/n8n-backups/"
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}_configs.tar.gz" "s3://$BACKUP_S3_BUCKET/n8n-backups/"
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}_info.txt" "s3://$BACKUP_S3_BUCKET/n8n-backups/"
        
        print_message "✅ Backup enviado para S3"
    else
        print_warning "AWS CLI não encontrado, backup local apenas"
    fi
fi