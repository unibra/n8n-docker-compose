# Como enviar os arquivos para o Git

## Método 1: Usar Git localmente

Se você tem acesso local aos arquivos, execute estes comandos no terminal:

```bash
# 1. Inicializar repositório (se ainda não existir)
git init

# 2. Adicionar todos os arquivos
git add .

# 3. Fazer commit inicial
git commit -m "feat: Configuração inicial N8N produção com Cloudflare Tunnel

- Docker Compose completo com N8N, PostgreSQL, Redis, Qdrant
- Scripts de backup, restore e monitoramento
- Configuração automática do Cloudflare Tunnel  
- Configurações otimizadas para produção
- Sistema de monitoramento e healthchecks"

# 4. Adicionar remote do GitHub/GitLab
git remote add origin https://github.com/seu-usuario/n8n-production.git

# 5. Fazer push
git push -u origin main
```

## Método 2: Usar GitHub CLI (se instalado)

```bash
# Criar repositório e fazer upload
gh repo create n8n-production --public --source=. --remote=origin --push
```

## Método 3: Upload manual via interface web

1. Vá para GitHub/GitLab
2. Crie um novo repositório chamado `n8n-production`
3. Use a interface web para fazer upload dos arquivos

## Estrutura de arquivos para Git

```
n8n-production/
├── README.md
├── docker-compose.yml
├── .env.example
├── .gitignore
├── package.json
├── config/
│   ├── postgres/
│   │   └── postgresql.conf
│   ├── redis/
│   │   └── redis.conf
│   └── qdrant/
│       └── config.yaml
├── scripts/
│   ├── setup.sh
│   ├── monitor.sh
│   ├── backup.sh
│   ├── restore.sh
│   └── configure-cloudflare-tunnel.sh
└── data/ (será criado automaticamente)
```

## Arquivo .gitignore recomendado

```
# Dados sensíveis
.env
*.env.local
*.env.production

# Dados dos containers
data/
backups/
logs/

# Node modules
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Sistema
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo

# Backups
*.backup
```

## Tags recomendadas

Após o primeiro commit, adicione tags para versionamento:

```bash
git tag -a v1.0.0 -m "Versão inicial - N8N Production Ready"
git push origin v1.0.0
```