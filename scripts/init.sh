#!/bin/bash
# scripts/init.sh
# GitOps仓库初始化工具

# ========== 进入工程根目录 ==========
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")"
SCRIPTS_DIR="$(dirname "$SCRIPT_PATH")"
PROJECT_ROOT="$(dirname "$SCRIPTS_DIR")"
cd "$PROJECT_ROOT"
# ==========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 显示标题
show_title() {
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║              GitOps仓库初始化工具                  ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
}

# 初始化Git仓库
init_git_repo() {
    if git rev-parse --git-dir &> /dev/null; then
        echo_info "已经是Git仓库"
    else
        echo_step "初始化Git仓库..."
        git init
        echo_info "Git仓库初始化完成"
    fi
}

# 创建目录结构
create_directory_structure() {
    echo_step "创建目录结构..."
    
    # 基础目录
    mkdir -p scripts/kubeconfigs
    mkdir -p {base,overlays,clusters}
    
    # 子目录
    mkdir -p base/{apps,infrastructure,monitoring}
    mkdir -p base/apps/{frontend,backend,database}
    mkdir -p base/infrastructure/{ingress,cert-manager,secrets}
    mkdir -p base/monitoring/{prometheus,grafana,alertmanager}
    
    # 示例覆盖目录
    mkdir -p overlays/{aws-prod,azure-staging,gcp-dev}
    mkdir -p overlays/aws-prod/{apps,infrastructure}
    mkdir -p overlays/azure-staging/{apps,infrastructure}
    mkdir -p overlays/gcp-dev/{apps,infrastructure}
    
    # 创建 frontend 子目录
    mkdir -p overlays/aws-prod/apps/frontend
    mkdir -p overlays/azure-staging/apps/frontend
    mkdir -p overlays/gcp-dev/apps/frontend
    
    echo_info "目录结构创建完成"
}

# 创建示例文件
create_example_files() {
    echo_step "创建示例文件..."
    
    # 基础示例
    if [[ ! -f "base/apps/frontend/deployment.yaml" ]]; then
        cat > base/apps/frontend/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
EOF
    fi
    
    if [[ ! -f "base/apps/frontend/service.yaml" ]]; then
        cat > base/apps/frontend/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
EOF
    fi
    
    if [[ ! -f "base/apps/frontend/kustomization.yaml" ]]; then
        cat > base/apps/frontend/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF
    fi
    
    # 覆盖示例
    if [[ ! -f "overlays/aws-prod/apps/frontend/kustomization.yaml" ]]; then
        cat > overlays/aws-prod/apps/frontend/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources:
  - ../../../../base/apps/frontend
patchesStrategicMerge:
  - replicas-patch.yaml
EOF
        
        cat > overlays/aws-prod/apps/frontend/replicas-patch.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 1
EOF
    fi
    
    echo_info "示例文件创建完成"
}

# 创建配置文件
create_config_files() {
    echo_step "创建配置文件..."
    
    # .gitignore
    if [[ ! -f ".gitignore" ]]; then
        cat > .gitignore << 'EOF'
# Flux
flux-system/

# Kubernetes
kubeconfig*
*.kubeconfig
scripts/kubeconfigs/*

# Secrets
secrets/
*.secret.yaml
*.enc.yaml
*.key
*.pem

# IDE
.vscode/
.idea/
*.swp
*.swo
*.code-workspace

# OS
.DS_Store
Thumbs.db
Desktop.ini

# 临时文件
tmp/
temp/
*.tmp
*.temp

# 日志
*.log
logs/
EOF
    fi
    
    # README.md
    if [[ ! -f "README.md" ]]; then
        cat > README.md << 'EOF'
# GitOps多集群管理

使用Flux和Kustomize管理多集群Kubernetes应用。

## 目录结构
```plaintext
├── scripts/ # 管理脚本
│ ├── bootstrap.sh # 引导脚本 (支持多种认证方式)
│ ├── kubeconfigs/ # 集群配置文件
│ ├── utils.sh # 工具函数
│ └── init.sh # 初始化脚本
├── base/ # 基础配置
├── overlays/ # 环境差异配置
└── clusters/ # Flux配置目录
```
## 快速开始

### 1. 初始化仓库
```bash
./scripts/init.sh
```
### 2. 配置集群连接
将集群的kubeconfig文件放入`scripts/kubeconfigs/`目录。

### 3. 引导集群
```bash
#使用Token认证 (推荐)
./scripts/bootstrap.sh --git-url=<git-url> --token=<token> --cluster=<cluster-name>
#使用SSH认证
./scripts/bootstrap.sh --git-url=git@github.com:owner/repo.git --ssh-key=~/.ssh/id_rsa --cluster=<cluster-name>
#引导所有集群
./scripts/bootstrap.sh --git-url=<git-url> --token=<token>
```
### 4. 管理集群
```bash
#查看帮助
./scripts/utils.sh help
#检查集群状态
./scripts/utils.sh check <cluster-name>
#查看所有集群
./scripts/utils.sh list
```
## 支持的认证方式

1. **Token认证** (推荐)
   - GitHub: Personal Access Token (以ghp_开头)
   - GitLab: Personal Access Token (以glpat_开头)
   - 其他Git服务: Access Token

2. **SSH认证**
   - 使用SSH密钥对
   - 需要将公钥添加到Git仓库的部署密钥

3. **基本认证**
   - 用户名/密码认证
   - 适用于自建Git服务器

## 工作流程

1. **基础配置** (`base/`): 定义应用的通用配置
2. **环境覆盖** (`overlays/`): 为不同环境定制配置
3. **Git提交**: 将更改推送到Git仓库
4. **自动同步**: Flux自动同步到集群

## 开发流程

1. 在`base/`中修改基础配置
2. 在`overlays/<env>/`中调整环境特定配置
3. 提交并推送代码
4. 监控同步状态: `flux get kustomizations -A`

## 故障排除

1. 检查Flux状态: `kubectl get pods -n flux-system`
2. 查看Flux日志: `flux logs --tail=50`
3. 强制同步: `flux reconcile kustomization <name> -n flux-system`
EOF
    fi
    
    echo_info "配置文件创建完成"
}

# 检查脚本文件
check_script_files() {
    echo_step "检查脚本文件..."
    
    if [[ ! -f "scripts/bootstrap.sh" ]]; then
        echo_warn "引导脚本不存在: scripts/bootstrap.sh"
        echo "请从模板复制引导脚本到此位置"
    fi
    
    if [[ ! -f "scripts/utils.sh" ]]; then
        echo_warn "工具脚本不存在: scripts/utils.sh"
        echo "请从模板复制工具脚本到此位置"
    fi
    
    if [[ ! -f "scripts/init.sh" ]]; then
        echo_warn "初始化脚本不存在: scripts/init.sh"
        echo "请从模板复制初始化脚本到此位置"
    fi
}

# 设置脚本权限
set_script_permissions() {
    echo_step "设置脚本权限..."
    
    for script in init.sh bootstrap.sh utils.sh; do
        if [[ -f "scripts/$script" ]]; then
            chmod +x "scripts/$script"
            echo_info "设置 scripts/$script 可执行"
        fi
    done
}

# 显示完成信息
show_completion() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                    初始化完成                        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "✅ GitOps仓库已初始化"
    echo ""
    echo "📁 创建的目录结构:"
    echo "  base/                 # 基础配置"
    echo "  overlays/             # 环境差异配置"
    echo "  clusters/             # Flux配置"
    echo "  scripts/              # 管理脚本"
    echo "  scripts/kubeconfigs/  # 集群配置文件"
    echo ""
    echo "🚀 下一步:"
    echo "  1. 将集群的kubeconfig放入scripts/kubeconfigs/"
    echo "  2. 运行引导脚本引导集群"
    echo ""
    echo "🔧 可用脚本:"
    echo "  ./scripts/bootstrap.sh  # 引导集群 (支持多种认证)"
    echo "  ./scripts/utils.sh      # 管理工具"
    echo ""
    echo "📖 文档: 查看README.md获取更多信息"
}

# 主函数
main() {
    show_title
    
    init_git_repo
    echo ""
    
    create_directory_structure
    echo ""
    
    create_example_files
    echo ""
    
    create_config_files
    echo ""
    
    check_script_files
    echo ""
    
    set_script_permissions
    echo ""
    
    show_completion
}

# 执行
main "$@"