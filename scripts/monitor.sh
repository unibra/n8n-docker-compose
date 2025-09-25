#!/bin/bash

# ==============================================
# SCRIPT DE MONITORAMENTO - N8N PRODUÇÃO
# ==============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[STATUS]${NC} $1"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar status dos containers
check_containers() {
    print_status "Verificando status dos containers..."
    echo
    
    local containers=("n8n-postgres" "n8n-redis" "n8n-qdrant" "n8n-app" "n8n-cloudflared" "n8n-worker")
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container"; then
            local status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | awk '{print $2}')
            if [[ $status == "Up" ]]; then
                print_ok "$container: Rodando"
            else
                print_warning "$container: $status"
            fi
        else
            print_error "$container: Não encontrado"
        fi
    done
    echo
}

# Verificar uso de recursos
check_resources() {
    print_status "Verificando uso de recursos..."
    echo
    
    # CPU e Memória do sistema
    echo "🖥️  Sistema:"
    echo "   CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')"
    echo "   RAM: $(free -h | grep '^Mem:' | awk '{printf "Usado: %s / Total: %s (%.1f%%)\n", $3, $2, ($3/$2)*100}')"
    echo "   Disco: $(df -h . | tail -1 | awk '{printf "Usado: %s / Total: %s (%s)\n", $3, $2, $5}')"
    echo
    
    # Recursos dos containers
    echo "🐳 Containers:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
    echo
}

# Verificar conectividade
check_connectivity() {
    print_status "Verificando conectividade..."
    echo
    
    # PostgreSQL
    if $DOCKER_COMPOSE_CMD exec -T postgres pg_isready -U $POSTGRES_USER -d $POSTGRES_DB &>/dev/null; then
        print_ok "PostgreSQL: Conectividade OK"
    else
        print_error "PostgreSQL: Falha na conectividade"
    fi
    
    # Redis
    if $DOCKER_COMPOSE_CMD exec -T redis redis-cli ping | grep -q "PONG"; then
        print_ok "Redis: Conectividade OK"
    else
        print_error "Redis: Falha na conectividade"
    fi
    
    # Qdrant
    if curl -s -f http://localhost:6333/health &>/dev/null; then
        print_ok "Qdrant: API OK"
    else
        print_error "Qdrant: API não responde"
    fi
    
    # N8N
    if curl -s -f http://localhost:5678/healthz &>/dev/null; then
        print_ok "N8N: API OK"
    else
        print_error "N8N: API não responde"
    fi
    
    # Conectividade externa (se configurado)
    if [[ -n "$N8N_HOST" ]]; then
        if curl -s -f "https://$N8N_HOST" &>/dev/null; then
            print_ok "Acesso externo: OK (https://$N8N_HOST)"
        else
            print_warning "Acesso externo: Falha (https://$N8N_HOST)"
        fi
    fi
    echo
}

# Verificar logs de erro
check_error_logs() {
    print_status "Verificando logs de erro (últimas 24h)..."
    echo
    
    local containers=("n8n-app" "n8n-postgres" "n8n-redis" "n8n-qdrant")
    
    for container in "${containers[@]}"; do
        local errors=$(docker logs --since 24h "$container" 2>&1 | grep -i "error\|critical\|fatal" | wc -l)
        if [[ $errors -gt 0 ]]; then
            print_warning "$container: $errors erros encontrados"
            docker logs --since 24h --tail 5 "$container" 2>&1 | grep -i "error\|critical\|fatal" | head -3
        else
            print_ok "$container: Nenhum erro crítico"
        fi
    done
    echo
}

# Verificar espaço em disco
check_disk_usage() {
    print_status "Verificando uso de espaço..."
    echo
    
    echo "📁 Diretórios de dados:"
    du -sh ./data/* 2>/dev/null | sort -hr
    echo
    
    echo "📦 Volumes Docker:"
    docker system df
    echo
    
    # Verificar se está ficando sem espaço
    local disk_usage=$(df . | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 80 ]]; then
        print_warning "Uso de disco alto: ${disk_usage}%"
    else
        print_ok "Uso de disco: ${disk_usage}%"
    fi
    echo
}

# Verificar backups
check_backups() {
    print_status "Verificando backups..."
    echo
    
    if [[ -d "./backups" ]]; then
        local backup_count=$(ls -1 ./backups/n8n_backup_*.sql 2>/dev/null | wc -l)
        if [[ $backup_count -gt 0 ]]; then
            print_ok "Encontrados $backup_count backups"
            echo "Backup mais recente:"
            ls -lt ./backups/n8n_backup_*.sql 2>/dev/null | head -1
        else
            print_warning "Nenhum backup encontrado"
        fi
    else
        print_warning "Diretório de backup não existe"
    fi
    echo
}

# Verificar performance do banco
check_database_performance() {
    print_status "Verificando performance do PostgreSQL..."
    echo
    
    # Carregar variáveis de ambiente
    source .env 2>/dev/null || true
    
    # Conexões ativas
    local active_connections=$($DOCKER_COMPOSE_CMD exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT count(*) FROM pg_stat_activity;" | tr -d ' ')
    print_ok "Conexões ativas: $active_connections"
    
    # Tamanho do banco
    local db_size=$($DOCKER_COMPOSE_CMD exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));" | tr -d ' ')
    print_ok "Tamanho do banco: $db_size"
    
    # Queries lentas (se habilitadas)
    local slow_queries=$($DOCKER_COMPOSE_CMD exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT count(*) FROM pg_stat_statements WHERE mean_time > 1000;" 2>/dev/null | tr -d ' ' || echo "N/A")
    if [[ "$slow_queries" != "N/A" ]]; then
        print_ok "Queries lentas: $slow_queries"
    fi
    echo
}

# Menu interativo
show_menu() {
    echo "=== MONITOR N8N PRODUÇÃO ==="
    echo "1. Status geral"
    echo "2. Recursos do sistema"
    echo "3. Conectividade"
    echo "4. Logs de erro"
    echo "5. Uso de disco"
    echo "6. Status de backups"
    echo "7. Performance do banco"
    echo "8. Relatório completo"
    echo "9. Monitoramento contínuo"
    echo "0. Sair"
    echo
}

# Monitoramento contínuo
continuous_monitoring() {
    print_status "Iniciando monitoramento contínuo (Ctrl+C para parar)..."
    
    while true; do
        clear
        echo "=== MONITORAMENTO CONTÍNUO - $(date) ==="
        echo
        check_containers
        check_resources
        echo "Próxima atualização em 30 segundos..."
        sleep 30
    done
}

# Relatório completo
full_report() {
    echo "=== RELATÓRIO COMPLETO N8N - $(date) ==="
    echo
    check_containers
    check_resources
    check_connectivity
    check_error_logs
    check_disk_usage
    check_backups
    check_database_performance
    echo "=== FIM DO RELATÓRIO ==="
}

# Menu principal
main() {
    source .env 2>/dev/null || true
    
    # Detectar comando Docker Compose
    detect_docker_compose
    
    if [[ $# -eq 0 ]]; then
        while true; do
            show_menu
            read -p "Escolha uma opção: " choice
            
            case $choice in
                1) check_containers ;;
                2) check_resources ;;
                3) check_connectivity ;;
                4) check_error_logs ;;
                5) check_disk_usage ;;
                6) check_backups ;;
                7) check_database_performance ;;
                8) full_report ;;
                9) continuous_monitoring ;;
                0) exit 0 ;;
                *) print_error "Opção inválida" ;;
            esac
            
            if [[ $choice != "9" ]]; then
                echo
                read -p "Pressione Enter para continuar..."
                clear
            fi
        done
    else
        case $1 in
            --full) full_report ;;
            --status) check_containers ;;
            --resources) check_resources ;;
            --connectivity) check_connectivity ;;
            --errors) check_error_logs ;;
            --disk) check_disk_usage ;;
            --backups) check_backups ;;
            --database) check_database_performance ;;
            --continuous) continuous_monitoring ;;
            *) 
                echo "Uso: $0 [--full|--status|--resources|--connectivity|--errors|--disk|--backups|--database|--continuous]"
                exit 1
                ;;
        esac
    fi
}

# Executar
main "$@"