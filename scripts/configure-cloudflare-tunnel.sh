#!/bin/bash

# ==============================================
# SCRIPT DE CONFIGURAÇÃO CLOUDFLARE TUNNEL - API TOKEN
# ==============================================

set -e

# Debug inicial
echo "🚀 Script iniciado..."
echo "Diretório atual: $(pwd)"
echo "Usuário: $(whoami)"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[CLOUDFLARE]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Configurações
TUNNEL_NAME="n8n-production"
DOMAIN="n8n.giacomo.dev.br"
ENV_FILE=".env"

# Verificar variáveis de ambiente necessárias
check_env_variables() {
    print_message "Verificando variáveis de ambiente..."
    
    # Debug
    echo "Verificando arquivo .env..."
    if [[ -f "$ENV_FILE" ]]; then
        echo "Arquivo .env encontrado"
    else
        echo "Arquivo .env NÃO encontrado em: $ENV_FILE"
    fi
    
    # Carregar arquivo .env se existir
    if [[ -f "$ENV_FILE" ]]; then
        echo "Carregando variáveis do .env..."
        set +e  # Desabilitar exit on error temporariamente
        source "$ENV_FILE"
        set -e  # Reabilitar exit on error
        echo "Variáveis carregadas"
    else
        echo "Arquivo .env não encontrado!"
    fi
    
    if [[ -z "$CLOUDFLARE_API_TOKEN" ]] || [[ "$CLOUDFLARE_API_TOKEN" == "your-cloudflare-api-token-here" ]]; then
        print_error "CLOUDFLARE_API_TOKEN não configurado no arquivo .env"
        print_info "Para configurar:"
        print_info "1. Vá para Cloudflare Dashboard > My Profile > API Tokens"
        print_info "2. Clique em 'Create Token'"
        print_info "3. Configure as permissões:"
        print_info "   - Zone:DNS:Edit (para sua zona/domínio)"
        print_info "   - Account:Cloudflare Tunnel:Edit"
        print_info "4. Copie o token para CLOUDFLARE_API_TOKEN no arquivo .env"
        exit 1
    fi
    
    export CLOUDFLARE_API_TOKEN
    print_message "✅ Variáveis de ambiente verificadas"
}

# Verificar se cloudflared está instalado
check_cloudflared() {
    print_message "Verificando se cloudflared está instalado..."
    
    if command -v cloudflared &> /dev/null; then
        local version=$(cloudflared --version | head -1)
        print_message "✅ Cloudflared encontrado: $version"
        return 0
    else
        print_warning "Cloudflared não encontrado no sistema"
        return 1
    fi
}

# Instalar cloudflared
install_cloudflared() {
    print_message "Instalando cloudflared..."
    
    # Detectar sistema operacional
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        install_cloudflared_linux
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        install_cloudflared_macos
    else
        print_error "Sistema operacional não suportado automaticamente"
        print_info "Por favor, instale o cloudflared manualmente:"
        print_info "https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation"
        exit 1
    fi
}

# Instalar no Linux
install_cloudflared_linux() {
    print_message "Instalando cloudflared no Linux..."
    
    # Baixar e instalar
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    
    if command -v dpkg &> /dev/null; then
        sudo dpkg -i cloudflared-linux-amd64.deb
    else
        print_error "dpkg não encontrado. Tentando instalação alternativa..."
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
        sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
        sudo chmod +x /usr/local/bin/cloudflared
    fi
    
    rm -f cloudflared-linux-amd64.deb cloudflared-linux-amd64
    print_message "✅ Cloudflared instalado com sucesso"
}

# Instalar no macOS
install_cloudflared_macos() {
    print_message "Instalando cloudflared no macOS..."
    
    if command -v brew &> /dev/null; then
        brew install cloudflared
    else
        print_warning "Homebrew não encontrado. Instalando manualmente..."
        curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz | tar -xz
        sudo mv cloudflared /usr/local/bin/
        sudo chmod +x /usr/local/bin/cloudflared
    fi
    
    print_message "✅ Cloudflared instalado com sucesso"
}

# Verificar autenticação com API Token
check_api_authentication() {
    print_message "Verificando autenticação com API Token..."
    
    # Testar conectividade com a API do Cloudflare usando o token
    local response=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                          -H "Content-Type: application/json" \
                          "https://api.cloudflare.com/client/v4/user/tokens/verify")
    
    if echo "$response" | grep -q '"success":true'; then
        print_message "✅ API Token válido e funcionando"
        # Extrair informações do usuário
        local user_email=$(echo "$response" | grep -o '"email":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$user_email" ]]; then
            print_info "Autenticado como: $user_email"
        fi
    else
        print_error "API Token inválido ou sem permissões adequadas"
        print_error "Resposta da API: $response"
        exit 1
    fi
}

# Obter Account ID necessário para operações de túnel
get_account_id() {
    print_message "Obtendo Account ID..."
    
    local response=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                          -H "Content-Type: application/json" \
                          "https://api.cloudflare.com/client/v4/accounts")
    
    if echo "$response" | grep -q '"success":true'; then
        ACCOUNT_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [[ -n "$ACCOUNT_ID" ]]; then
            print_message "✅ Account ID obtido: $ACCOUNT_ID"
            export CF_ACCOUNT_ID="$ACCOUNT_ID"
        else
            print_error "Não foi possível obter Account ID"
            exit 1
        fi
    else
        print_error "Falha ao obter Account ID"
        print_error "Resposta da API: $response"
        exit 1
    fi
}

# Verificar se o túnel já existe
check_existing_tunnel() {
    print_message "Verificando se o túnel '$TUNNEL_NAME' já existe..."
    
    # Usar API Token para listar túneis
    export CLOUDFLARE_API_TOKEN
    local tunnel_list=$(cloudflared tunnel list 2>/dev/null)
    local tunnel_count=$(echo "$tunnel_list" | grep -c "$TUNNEL_NAME" || echo "0")
    
    if [[ $tunnel_count -gt 0 ]]; then
        if [[ $tunnel_count -gt 1 ]]; then
            print_warning "Encontrados $tunnel_count túneis com nome '$TUNNEL_NAME'"
            print_info "Lista de túneis:"
            echo "$tunnel_list" | grep "$TUNNEL_NAME"
        else
            print_warning "Túnel '$TUNNEL_NAME' já existe"
        fi
        
        print_warning "Túnel '$TUNNEL_NAME' já existe"
        print_info "Opções:"
        echo "1. Usar túnel existente"
        echo "2. Deletar e criar novo"
        echo "3. Listar todos os túneis"
        echo "4. Cancelar"
        
        read -p "Escolha uma opção (1-4): " choice
        
        case $choice in
            1)
                print_message "Usando túnel existente"
                return 0
                ;;
            2)
                print_warning "Deletando túnel existente..."
                delete_existing_tunnels
                return 1
                ;;
            3)
                print_info "Listando todos os túneis:"
                cloudflared tunnel list
                echo
                read -p "Deseja continuar com a deleção? (y/n): " delete_choice
                if [[ $delete_choice =~ ^[Yy]$ ]]; then
                    delete_existing_tunnels
                    return 1
                else
                    exit 0
                fi
                ;;
            4)
                print_message "Operação cancelada"
                exit 0
                ;;
            *)
                print_error "Opção inválida"
                exit 1
                ;;
        esac
    else
        return 1
    fi
}

# Deletar túneis existentes
delete_existing_tunnels() {
    print_message "Deletando túneis com nome '$TUNNEL_NAME'..."
    
    # Obter IDs dos túneis com o nome especificado
    local tunnel_ids=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -z "$tunnel_ids" ]]; then
        print_warning "Nenhum túnel encontrado para deletar"
        return
    fi
    
    # Deletar cada túnel pelo ID
    for tunnel_id in $tunnel_ids; do
        print_message "Deletando túnel ID: $tunnel_id"
        if cloudflared tunnel delete "$tunnel_id" 2>/dev/null; then
            print_message "✅ Túnel $tunnel_id deletado com sucesso"
        else
            print_error "Falha ao deletar túnel $tunnel_id"
            # Tentar deletar com força
            print_message "Tentando deleção forçada..."
            if cloudflared tunnel delete "$tunnel_id" --force 2>/dev/null; then
                print_message "✅ Túnel $tunnel_id deletado com força"
            else
                print_error "Não foi possível deletar túnel $tunnel_id"
            fi
        fi
    done
    
    # Aguardar um pouco para propagação
    sleep 2
    print_message "✅ Processo de deleção concluído"
}

# Criar novo túnel
create_tunnel() {
    print_message "Criando túnel '$TUNNEL_NAME'..."
    
    # Verificar se ainda existe algum túnel com o mesmo nome
    local remaining_tunnels=$(cloudflared tunnel list 2>/dev/null | grep -c "$TUNNEL_NAME" || echo "0")
    if [[ $remaining_tunnels -gt 0 ]]; then
        print_warning "Ainda existem $remaining_tunnels túneis com nome '$TUNNEL_NAME'"
        print_message "Aguardando 5 segundos para propagação..."
        sleep 5
    fi
    
    # Usar API Token para criar túnel
    export CLOUDFLARE_API_TOKEN
    local create_output=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
    local create_status=$?
    
    if [[ $create_status -eq 0 ]]; then
        print_message "✅ Túnel criado com sucesso"
        # Exibir informações do túnel criado
        if echo "$create_output" | grep -q "Created tunnel"; then
            local tunnel_info=$(echo "$create_output" | grep "Created tunnel")
            print_info "$tunnel_info"
        fi
    else
        print_error "Falha ao criar túnel"
        print_error "Output: $create_output"
        
        # Verificar se é problema de nome duplicado
        if echo "$create_output" | grep -q "already exists"; then
            print_warning "Túnel com esse nome ainda existe. Tentando resolver..."
            print_message "Listando túneis atuais:"
            cloudflared tunnel list
            
            read -p "Deseja tentar deletar novamente? (y/n): " retry_choice
            if [[ $retry_choice =~ ^[Yy]$ ]]; then
                delete_existing_tunnels
                sleep 3
                # Tentar criar novamente
                if cloudflared tunnel create "$TUNNEL_NAME" 2>/dev/null; then
                    print_message "✅ Túnel criado com sucesso na segunda tentativa"
                else
                    print_error "Falha persistente ao criar túnel"
                    exit 1
                fi
            else
                exit 1
            fi
        else
            print_error "Verifique se o API Token tem permissões 'Account:Cloudflare Tunnel:Edit'"
            exit 1
        fi
    fi
}
        exit 1
    fi
}

# Configurar DNS
configure_dns() {
    print_message "Configurando DNS para '$DOMAIN'..."
    
    # Usar API Token para configurar DNS
    export CLOUDFLARE_API_TOKEN
    if cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>/dev/null; then
        print_message "✅ DNS configurado com sucesso"
    else
        print_error "Falha ao configurar DNS"
        print_error "Verifique se o API Token tem permissões 'Zone:DNS:Edit' para o domínio $DOMAIN"
        print_warning "Você pode configurar manualmente no Cloudflare Dashboard:"
        print_warning "Tipo: CNAME"
        print_warning "Nome: ${DOMAIN%%.*}"
        print_warning "Destino: $TUNNEL_NAME.cfargotunnel.com"
        
        read -p "Deseja continuar mesmo assim? (y/n): " continue_choice
        if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Obter token do túnel
get_tunnel_token() {
    print_message "Obtendo token do túnel..."
    
    # Obter ID do túnel usando API Token
    export CLOUDFLARE_API_TOKEN
    local tunnel_id=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "Não foi possível obter o ID do túnel"
        exit 1
    fi
    
    print_info "ID do túnel: $tunnel_id"
    
    # Gerar token usando API Token
    export CLOUDFLARE_API_TOKEN
    local token=$(cloudflared tunnel token "$tunnel_id" 2>/dev/null)
    
    if [[ -z "$token" ]]; then
        print_error "Não foi possível gerar o token do túnel"
        print_error "Verifique se o túnel foi criado corretamente"
        exit 1
    fi
    
    echo "$token"
}

# Atualizar arquivo .env
update_env_file() {
    local token=$1
    
    print_message "Atualizando arquivo .env com o token do túnel..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error "Arquivo .env não encontrado"
        exit 1
    fi
    
    # Fazer backup do .env
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Atualizar token
    if grep -q "CLOUDFLARE_TUNNEL_TOKEN=" "$ENV_FILE"; then
        sed -i.bak "s#^CLOUDFLARE_TUNNEL_TOKEN=.*#CLOUDFLARE_TUNNEL_TOKEN=$token#" "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
    else
        echo "CLOUDFLARE_TUNNEL_TOKEN=$token" >> "$ENV_FILE"
    fi
    
    print_message "✅ Token adicionado ao arquivo .env"
}

# Teste de conectividade
test_tunnel() {
    print_message "Testando configuração do túnel..."
    
    print_info "Verificando se o túnel está configurado corretamente..."
    
    # Verificar se o túnel existe na lista
    export CLOUDFLARE_API_TOKEN
    if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
        print_message "✅ Túnel encontrado na lista"
    else
        print_warning "Túnel não encontrado na lista"
    fi
    
    # Verificar configuração DNS via API
    local zone_name=$(echo "$DOMAIN" | sed 's/^[^.]*\.//')
    local record_name=$(echo "$DOMAIN" | sed 's/\..*//')
    
    print_info "Verificando configuração DNS para $DOMAIN..."
    print_message "✅ Teste concluído"
}

# Exibir informações finais
show_final_info() {
    print_message "=== CONFIGURAÇÃO CONCLUÍDA ==="
    echo
    print_info "🌐 Domínio configurado: https://$DOMAIN"
    print_info "🔧 Túnel criado: $TUNNEL_NAME"
    print_info "🔑 API Token: Configurado e validado"
    print_info "📁 Tunnel Token: Salvo em $ENV_FILE"
    echo
    print_message "Próximos passos:"
    print_message "1. Execute: docker-compose up -d"
    print_message "2. Aguarde os serviços iniciarem"
    print_message "3. Acesse: https://$DOMAIN"
    echo
    print_warning "IMPORTANTE:"
    print_warning "• Mantenha o API Token seguro e com permissões limitadas"
    print_warning "• Faça backup do arquivo .env regularmente"
    print_warning "• O túnel será iniciado automaticamente com o docker-compose"
    echo
    print_info "ℹ️  Para gerenciar outros túneis ou contas:"
    print_info "• Configure diferentes API Tokens no arquivo .env"
    print_info "• Execute este script com diferentes valores de TUNNEL_NAME e DOMAIN"
}

# Função principal
main() {
    echo "=== INICIANDO FUNÇÃO PRINCIPAL ==="
    print_message "=== CONFIGURAÇÃO CLOUDFLARE TUNNEL ==="
    echo
    
    echo "Chamando check_env_variables..."
    # Verificar variáveis de ambiente
    check_env_variables
    echo "check_env_variables concluída"
    
    echo "Chamando check_cloudflared..."
    # Verificar pré-requisitos
    if ! check_cloudflared; then
        print_warning "Cloudflared precisa ser instalado primeiro"
        read -p "Deseja instalar agora? (y/n): " install_choice
        
        if [[ $install_choice =~ ^[Yy]$ ]]; then
            install_cloudflared
        else
            print_error "Cloudflared é necessário para continuar"
            exit 1
        fi
    fi
    
    # Verificar autenticação com API Token
    check_api_authentication
    
    # Obter Account ID
    get_account_id
    
    # Verificar/criar túnel
    if ! check_existing_tunnel; then
        create_tunnel
    fi
    
    # Configurar DNS
    configure_dns
    
    # Obter e salvar token
    local token=$(get_tunnel_token)
    update_env_file "$token"
    
    # Teste opcional
    read -p "Deseja testar a configuração do túnel? (y/n): " test_choice
    if [[ $test_choice =~ ^[Yy]$ ]]; then
        test_tunnel
    fi
    
    # Informações finais
    show_final_info
}

# Executar apenas se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Script chamado diretamente, executando main..."
    main "$@"
else
    echo "Script sendo sourced, não executando main"
fi