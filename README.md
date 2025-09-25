# N8N Produção - Docker Compose

Este projeto fornece uma configuração completa do N8N para ambiente de produção usando Docker Compose, com todos os serviços necessários e configurações otimizadas para performance, segurança e monitoramento.

## 🏗️ Arquitetura

```
┌─────────────────┐    ┌──────────────────┐
│   Cloudflared   │────│   Internet       │
│   (Túnel)       │    │                  │
└─────────────────┘    └──────────────────┘
         │
         ▼
┌─────────────────┐    ┌──────────────────┐
│      N8N        │────│   N8N Worker     │
│   (Principal)   │    │  (Processamento) │
└─────────────────┘    └──────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌──────────────────┐
│   PostgreSQL    │    │      Redis       │
│  (Banco dados)  │    │     (Cache)      │
└─────────────────┘    └──────────────────┘
         │
         ▼
┌─────────────────┐
│     Qdrant      │
│ (Banco vetorial)│
└─────────────────┘
```

## 🚀 Serviços Incluídos

- **N8N**: Plataforma de automação principal
- **PostgreSQL**: Banco de dados para persistência
- **Redis**: Cache e gerenciamento de filas
- **Qdrant**: Banco de dados vetorial para AI/ML
- **Cloudflared**: Túnel seguro para acesso externo
- **N8N Worker**: Processamento em paralelo de workflows

## ✨ Recursos

- ✅ **Configuração de Produção**: Otimizada para ambiente produtivo
- ✅ **Alta Disponibilidade**: Healthchecks e políticas de restart
- ✅ **Segurança**: Senhas seguras, redes isoladas, configurações hardened
- ✅ **Performance**: Limites de recursos e configurações otimizadas
- ✅ **Monitoramento**: Scripts de monitoramento e alertas
- ✅ **Backup Automático**: Sistema completo de backup e restore
- ✅ **Logs Centralizados**: Logging estruturado para todos os serviços
- ✅ **Conteúdo da Comunidade**: Templates e pacotes da comunidade N8N habilitados

## 🛠️ Pré-requisitos

- Docker 20.10+
- Docker Compose 2.0+
- 4GB RAM mínimo (8GB recomendado)
- 20GB espaço em disco mínimo
- Sistema operacional Linux (Ubuntu 20.04+ recomendado)

## 📦 Instalação Rápida

```bash
# 1. Clone o projeto
git clone https://github.com/seu-usuario/n8n-production.git
cd n8n-production

# 2. Configure as variáveis de ambiente
cp .env.example .env
nano .env  # Configure suas variáveis

# 3. Execute o script de setup
chmod +x scripts/setup.sh
./scripts/setup.sh

# 4. Inicie os serviços
# Detecta automaticamente docker-compose ou docker compose
chmod +x scripts/*.sh
./scripts/setup.sh

# 5. Verifique o status
./scripts/monitor.sh --status
```

## ⚙️ Configuração Detalhada

### 1. Variáveis de Ambiente Críticas

Edite o arquivo `.env` e configure:

```bash
# Domínio principal
N8N_HOST=n8n.giacomo.dev.br

# Chaves de segurança (gere chaves únicas!)
N8N_ENCRYPTION_KEY=sua-chave-32-chars
N8N_JWT_SECRET=sua-chave-64-chars

# Token do Cloudflare Tunnel
CLOUDFLARE_TUNNEL_TOKEN=seu-token-aqui

# Credenciais do banco
POSTGRES_PASSWORD=senha-super-segura
```

### 2. Gerar Chaves de Segurança

```bash
# Chave de criptografia do N8N (32 chars hex)
openssl rand -hex 32

# JWT Secret (64 chars hex)  
openssl rand -hex 64
```

### 3. Configurar Cloudflare Tunnel

**Opção 1: Configuração Automática (Recomendada)**
```bash
# 1. Configure o API Token no arquivo .env
# Vá para: Cloudflare Dashboard > My Profile > API Tokens
# Crie um token com permissões:
# - Zone:DNS:Edit (para seu domínio)  
# - Account:Cloudflare Tunnel:Edit

# Execute o script de configuração automática
./scripts/configure-cloudflare-tunnel.sh
```

**Opção 2: Configuração Manual**
1. Acesse o [Cloudflare Dashboard](https://dash.cloudflare.com)

## 🔧 Comandos Úteis

### Gerenciamento dos Serviços

```bash
# Iniciar todos os serviços
docker compose up -d  # ou docker-compose up -d (auto-detectado pelos scripts)

# Parar todos os serviços  
docker compose down

# Reiniciar um serviço específico
docker compose restart n8n

# Ver logs de um serviço
docker compose logs -f n8n

# Status de todos os containers
docker compose ps
```

### Scripts de Administração

```bash
# Configurar túnel Cloudflare automaticamente
./scripts/configure-cloudflare-tunnel.sh

# Monitoramento completo
./scripts/monitor.sh

# Monitoramento contínuo  
./scripts/monitor.sh --continuous

# Backup manual
./scripts/backup.sh

# Restaurar backup
./scripts/restore.sh n8n_backup_20241201_120000

# Verificar configuração
./scripts/setup.sh
```

## 🔐 Configurações de Segurança

### PostgreSQL
- Autenticação MD5
- Conexões limitadas à rede interna
- Logs de conexão habilitados
- Configurações hardened de produção

### Redis
- Modo protegido habilitado
- Persistência RDB + AOF
- Limites de memória configurados
- Acesso restrito à rede interna

### N8N
- Chave de criptografia única
- JWT secrets seguros
- HTTPS forçado via Cloudflare
- Variáveis sensíveis via environment

### Qdrant
- API externa desabilitada em produção
- Telemetria desabilitada
- Configurações de performance otimizadas

## 📊 Monitoramento

### Métricas Disponíveis

```bash
# Status geral do sistema
./scripts/monitor.sh --status

# Uso de recursos
./scripts/monitor.sh --resources  

# Conectividade dos serviços
./scripts/monitor.sh --connectivity

# Logs de erro
./scripts/monitor.sh --errors

# Relatório completo
./scripts/monitor.sh --full
```

### Healthchecks Configurados

- **PostgreSQL**: `pg_isready` check
- **Redis**: `redis-cli ping`
- **Qdrant**: HTTP health endpoint
- **N8N**: `/healthz` endpoint

## 💾 Sistema de Backup

### Backup Automático

O backup roda automaticamente via cron:

```bash
# Adicionar ao crontab do sistema
0 2 * * * /path/to/project/scripts/backup.sh

# Configurar retenção (padrão: 30 dias)
BACKUP_RETENTION_DAYS=30
```

### Backup Manual

```bash
# Fazer backup completo
./scripts/backup.sh

# Listar backups disponíveis
ls -la backups/

# Restaurar backup específico  
./scripts/restore.sh nome_do_backup
```

### O que é incluído no Backup

- ✅ Banco PostgreSQL (dump completo)
- ✅ Dados do N8N (/home/node/.n8n)
- ✅ Arquivos de upload (/files)  
- ✅ Dados do Qdrant
- ✅ Configurações (docker-compose.yml, .env)

## 🚀 Deployment

### Primeira Instalação

```bash
# 1. Configurar servidor
sudo apt update && sudo apt upgrade -y
sudo apt install docker.io docker-compose git -y
sudo systemctl enable docker
sudo usermod -aG docker $USER

# 2. Deploy do projeto
git clone <repo> n8n-production
cd n8n-production
./scripts/setup.sh
docker-compose up -d

# 3. Configurar backup automático
(crontab -l 2>/dev/null; echo "0 2 * * * $(pwd)/scripts/backup.sh") | crontab -
```

### Atualizações

```bash
# Fazer backup antes da atualização
./scripts/backup.sh

# Atualizar imagens
docker-compose pull

# Reiniciar com novas imagens
docker-compose up -d

# Verificar se tudo está funcionando
./scripts/monitor.sh --full
```

## 🔍 Troubleshooting

### Problemas Comuns

#### N8N não inicia
```bash
# Verificar logs
docker-compose logs n8n

# Verificar se banco está pronto
docker-compose logs postgres

# Reiniciar serviços
docker-compose restart postgres redis n8n
```

#### Erro de conexão com banco
```bash
# Verificar conectividade
docker-compose exec n8n ping postgres

# Verificar credenciais no .env
grep POSTGRES .env

# Teste manual de conexão
docker-compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB
```

#### Cloudflare Tunnel não conecta
```bash
# Verificar token
grep CLOUDFLARE_TUNNEL_TOKEN .env

# Verificar logs do cloudflared  
docker-compose logs cloudflared

# Testar conectividade local
curl -I http://localhost:5678
```

### Logs Importantes

```bash
# N8N aplicação
docker-compose logs -f n8n

# Base de dados
docker-compose logs -f postgres  

# Cache/Filas
docker-compose logs -f redis

# Túnel externo
docker-compose logs -f cloudflared
```

## 🔧 Configurações Avançadas

### Escalabilidade Horizontal

Para adicionar mais workers do N8N:

```bash
# No docker-compose.yml, adicionar:
docker-compose up --scale n8n-worker=3 -d
```

### Configurações de Performance

#### PostgreSQL (config/postgres/postgresql.conf):
- `shared_buffers`: Ajustar conforme RAM disponível
- `effective_cache_size`: ~75% da RAM total
- `work_mem`: Para queries complexas
- `max_connections`: Conforme necessidade

#### Redis (config/redis/redis.conf):
- `maxmemory`: Limite de RAM para cache
- `maxmemory-policy`: Estratégia de eviction
- `save`: Configurações de persistência

### Integrações Externas

#### Templates da Comunidade
O N8N está configurado para acessar:
- Templates oficiais da comunidade
- Pacotes de nós da comunidade
- API pública do N8N para templates

#### Webhook URLs
```
https://n8n.giacomo.dev.br/webhook/seu-webhook-id
https://n8n.giacomo.dev.br/webhook-test/seu-webhook-id
```

#### API Endpoints
```
https://n8n.giacomo.dev.br/api/v1/
https://n8n.giacomo.dev.br/rest/
```

## 📋 Maintenance

### Tasks Regulares

#### Diário
- Verificar status dos serviços
- Revisar logs de erro
- Monitorar uso de recursos

#### Semanal  
- Verificar backups
- Limpar logs antigos
- Atualizar estatísticas do banco

#### Mensal
- Atualizar imagens Docker
- Revisar configurações de segurança
- Testar procedimentos de restore

### Scripts de Manutenção

```bash
# Limpeza de logs Docker
docker system prune -a

# Otimizar banco PostgreSQL
docker-compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "VACUUM ANALYZE;"

# Verificar integridade dos dados
./scripts/monitor.sh --database
```

## 📞 Suporte

### Logs de Debug

Para ativar logs detalhados:

```bash
# No .env, alterar:
N8N_LOG_LEVEL=debug

# Reiniciar N8N
docker-compose restart n8n
```

### Informações do Sistema

```bash
# Versões instaladas
docker --version
docker-compose --version

# Status do sistema
./scripts/monitor.sh --full

# Configuração ativa
docker-compose config
```

---

## 📄 Licença

Este projeto é distribuído sob a licença MIT. Veja o arquivo `LICENSE` para mais detalhes.

## 🤝 Contribuições

Contribuições são bem-vindas! Por favor:

1. Faça um fork do projeto
2. Crie uma branch para sua feature
3. Commit suas mudanças  
4. Push para a branch
5. Abra um Pull Request

---

**Desenvolvido com ❤️ para ambientes de produção seguros e confiáveis.**