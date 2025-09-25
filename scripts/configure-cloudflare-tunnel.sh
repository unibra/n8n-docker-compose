#!/bin/bash

# ==============================================
# SCRIPT DE CONFIGURAÇÃO CLOUDFLARE TUNNEL
# ==============================================

set -e

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

# Fazer login no Cloudflare
cloudflare_login() {
    print_message "Iniciando processo de autenticação com Cloudflare..."
    print_info "Uma janela do navegador será aberta para autenticação"
    print_info "Pressione Enter quando estiver pronto para continuar"
    read -p ""
    
    if cloudflared tunnel login; then
        print_message "✅ Autenticação realizada com sucesso"
    else
        print_error "Falha na autenticação com Cloudflare"
        exit 1
    fi
}

# Verificar se o túnel já existe
check_existing_tunnel() {
    print_message "Verificando se o túnel '$TUNNEL_NAME' já existe..."
    
    if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
        print_warning "Túnel '$TUNNEL_NAME' já existe"
        print_info "Opções:"
        echo "1. Usar túnel existente"
        echo "2. Deletar e criar novo"
        echo "3. Cancelar"
        
        read -p "Escolha uma opção (1-3): " choice
        
        case $choice in
            1)
                print_message "Usando túnel existente"
                return 0
                ;;
            2)
                print_warning "Deletando túnel existente..."
                cloudflared tunnel delete "$TUNNEL_NAME" --force
                print_message "Túnel deletado"
                return 1
                ;;
            3)
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

# Criar novo túnel
create_tunnel() {
    print_message "Criando túnel '$TUNNEL_NAME'..."
    
    if cloudflared tunnel create "$TUNNEL_NAME"; then
        print_message "✅ Túnel criado com sucesso"
    else
        print_error "Falha ao criar túnel"
        exit 1
    fi
}

# Configurar DNS
configure_dns() {
    print_message "Configurando DNS para '$DOMAIN'..."
    
    if cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"; then
        print_message "✅ DNS configurado com sucesso"
    else
        print_error "Falha ao configurar DNS"
        print_warning "Você pode configurar manualmente no Cloudflare Dashboard:"
        print_warning "Tipo: CNAME"
        print_warning "Nome: n8n"
        print_warning "Destino: $TUNNEL_NAME.cfargotunnel.com"
        exit 1
    fi
}

# Obter token do túnel
get_tunnel_token() {
    print_message "Obtendo token do túnel..."
    
    # Obter ID do túnel
    local tunnel_id=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [[ -z "$tunnel_id" ]]; then
        print_error "Não foi possível obter o ID do túnel"
        exit 1
    fi
    
    print_info "ID do túnel: $tunnel_id"
    
    # Criar arquivo de configuração temporário
    local config_file="/tmp/cloudflared_config.yml"
    cat > "$config_file" << EOF
tunnel: $tunnel_id
credentials-file: $HOME/.cloudflared/$tunnel_id.json

ingress:
  - hostname: $DOMAIN
    service: http://n8n:5678
  - service: http_status:404
EOF
    
    # Gerar token
    local token=$(cloudflared tunnel token --cred-file "$HOME/.cloudflared/$tunnel_id.json" "$tunnel_id")
    
    if [[ -z "$token" ]]; then
        print_error "Não foi possível gerar o token do túnel"
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
        sed -i.bak "s/^CLOUDFLARE_TUNNEL_TOKEN=.*/CLOUDFLARE_TUNNEL_TOKEN=$token/" "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
    else
        echo "CLOUDFLARE_TUNNEL_TOKEN=$token" >> "$ENV_FILE"
    fi
    
    print_message "✅ Token adicionado ao arquivo .env"
}

# Teste de conectividade
test_tunnel() {
    print_message "Testando configuração do túnel..."
    
    # Criar configuração de teste
    local config_file="/tmp/cloudflared_test.yml"
    local tunnel_id=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    cat > "$config_file" << EOF
tunnel: $tunnel_id
credentials-file: $HOME/.cloudflared/$tunnel_id.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:5678
  - service: http_status:404
EOF
    
    print_info "Iniciando teste do túnel (pressione Ctrl+C após alguns segundos)..."
    timeout 10 cloudflared tunnel --config "$config_file" run "$TUNNEL_NAME" || true
    
    rm -f "$config_file"
    print_message "✅ Teste concluído"
}

# Exibir informações finais
show_final_info() {
    print_message "=== CONFIGURAÇÃO CONCLUÍDA ==="
    echo
    print_info "🌐 Domínio configurado: https://$DOMAIN"
    print_info "🔧 Túnel criado: $TUNNEL_NAME"
    print_info "📁 Token salvo em: $ENV_FILE"
    echo
    print_message "Próximos passos:"
    print_message "1. Execute: docker-compose up -d"
    print_message "2. Aguarde os serviços iniciarem"
    print_message "3. Acesse: https://$DOMAIN"
    echo
    print_warning "IMPORTANTE:"
    print_warning "• Mantenha os arquivos de credencial em ~/.cloudflared/ seguros"
    print_warning "• Faça backup do arquivo .env regularmente"
    print_warning "• O túnel será iniciado automaticamente com o docker-compose"
}

# Função principal
main() {
    print_message "=== CONFIGURAÇÃO CLOUDFLARE TUNNEL ==="
    echo
    
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
    
    # Fazer login no Cloudflare
    if [[ ! -f "$HOME/.cloudflared/cert.pem" ]]; then
        cloudflare_login
    else
        print_message "Certificado Cloudflare já existe, pulando autenticação"
    fi
    
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
    main "$@"
fi