#!/bin/bash
# scripts/quick-start.sh
# GitOps快速开始向导

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
    clear
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║              Flux GitOps快速开始向导               ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
}

# 检查环境
check_environment() {
    echo_step "检查环境..."
    
    # 检查是否在Git仓库中
    if ! git rev-parse --git-dir &> /dev/null; then
        echo_error "当前目录不是Git仓库"
        echo "请先运行: ./scripts/init.sh"
        exit 1
    fi
    
    # 检查目录结构
    if [[ ! -d "scripts/kubeconfigs" ]]; then
        echo_warn "scripts/kubeconfigs目录不存在"
        echo "请确保已运行初始化脚本: ./scripts/init.sh"
    fi
    
    # 检查引导脚本
    if [[ ! -f "scripts/bootstrap.sh" ]]; then
        echo_error "引导脚本不存在: scripts/bootstrap.sh"
        echo "请从模板复制引导脚本"
        exit 1
    fi
    
    # 检查依赖
    if ! command -v flux &> /dev/null; then
        echo_error "Flux CLI未安装"
        echo "安装命令: curl -s https://fluxcd.io/install.sh | sudo bash"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl未安装"
        echo "请参考: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    echo ""
}

# 检查集群配置
check_cluster_configs() {
    echo_step "检查集群配置..."
    
    if [[ ! -d "scripts/kubeconfigs" ]]; then
        echo_error "scripts/kubeconfigs目录不存在"
        echo "请创建目录: mkdir -p scripts/kubeconfigs"
        exit 1
    fi
    
    local config_files=$(find scripts/kubeconfigs -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)
    
    if [[ $config_files -eq 0 ]]; then
        echo_warn "没有找到集群配置文件"
        echo ""
        echo "请将集群的kubeconfig文件放入scripts/kubeconfigs/"
        echo "例如:"
        echo "  cp ~/.kube/config scripts/kubeconfigs/aws-prod.yaml"
        echo ""
        read -p "按Enter键继续..."
    else
        echo "找到 $config_files 个集群配置文件"
    fi
}

# 选择认证方式
select_auth_method() {
    echo_step "选择认证方式"
    echo ""
    
    echo "请选择Git认证方式:"
    echo "1) Token认证 (推荐)"
    echo "2) SSH密钥认证"
    echo "3) 用户名/密码认证"
    echo ""
    
    read -p "选择 (1-3): " auth_choice
    
    case $auth_choice in
        1)
            configure_token_auth
            ;;
        2)
            configure_ssh_auth
            ;;
        3)
            configure_basic_auth
            ;;
        *)
            echo_error "无效选择"
            exit 1
            ;;
    esac
}

# 配置Token认证
configure_token_auth() {
    echo ""
    echo "Token认证 (推荐)"
    echo "----------------"
    read -p "Git仓库URL (例如: https://github.com/my-org/repo.git): " GIT_URL
    echo ""
    echo "GIT_URL: $GIT_URL"
    
    if [[ -z "$GIT_URL" ]]; then
        echo_error "Git URL不能为空"
        exit 1
    fi
    
    if [[ ! "$GIT_URL" =~ ^https?:// ]]; then
        echo_error "Git URL必须以http://或https://开头"
        exit 1
    fi
    
    echo ""
    echo "需要Git Personal Access Token (PAT)"
    echo "权限要求: repo (读写仓库权限)"
    echo ""
    echo "创建地址:"
    echo "  GitHub: https://github.com/settings/tokens/new"
    echo "  GitLab: https://gitlab.com/-/profile/personal_access_tokens"
    echo "  Bitbucket: https://bitbucket.org/account/settings/app-passwords/"
    echo ""
    
    read -sp "请输入Git Token: " GIT_TOKEN
    echo ""
    echo "GIT_TOKEN: $GIT_TOKEN"
    
    if [[ -z "$GIT_TOKEN" ]]; then
        echo_error "Git Token不能为空"
        exit 1
    fi
    
    AUTH_METHOD="token"
    export GIT_URL
    export GIT_TOKEN
}

# 配置SSH认证
configure_ssh_auth() {
    echo ""
    echo "SSH密钥认证"
    echo "-----------"
    read -p "Git仓库URL (例如: git@github.com:my-org/repo.git): " GIT_URL
    
    if [[ -z "$GIT_URL" ]]; then
        echo_error "Git URL不能为空"
        exit 1
    fi
    
    echo ""
    echo "SSH密钥路径:"
    echo "  1) 使用默认密钥 (~/.ssh/id_rsa)"
    echo "  2) 指定其他密钥"
    echo ""
    
    read -p "选择 (1-2): " key_choice
    
    case $key_choice in
        1)
            if [[ -f "$HOME/.ssh/id_rsa" ]]; then
                SSH_KEY_PATH="$HOME/.ssh/id_rsa"
                echo_info "使用默认密钥: $SSH_KEY_PATH"
            elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
                SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
                echo_info "使用默认密钥: $SSH_KEY_PATH"
            else
                echo_error "未找到默认SSH密钥"
                exit 1
            fi
            ;;
        2)
            read -p "请输入SSH私钥路径: " SSH_KEY_PATH
            if [[ -z "$SSH_KEY_PATH" ]] || [[ ! -f "$SSH_KEY_PATH" ]]; then
                echo_error "SSH私钥文件不存在"
                exit 1
            fi
            ;;
        *)
            echo_error "无效选择"
            exit 1
            ;;
    esac
    
    # 检查公钥是否存在
    local pub_key="${SSH_KEY_PATH}.pub"
    if [[ ! -f "$pub_key" ]]; then
        echo_error "SSH公钥文件不存在: $pub_key"
        exit 1
    fi
    
    echo ""
    echo "请将以下SSH公钥添加到Git仓库的部署密钥:"
    echo "=============================================="
    cat "$pub_key"
    echo "=============================================="
    echo ""
    
    read -p "按Enter键继续，确认已添加SSH公钥到Git仓库..."
    
    AUTH_METHOD="ssh"
    export GIT_URL
    export SSH_KEY_PATH
}

# 配置基本认证
configure_basic_auth() {
    echo ""
    echo "用户名/密码认证"
    echo "---------------"
    read -p "Git仓库URL (例如: https://git.example.com/repo.git): " GIT_URL
    
    if [[ -z "$GIT_URL" ]]; then
        echo_error "Git URL不能为空"
        exit 1
    fi
    
    if [[ ! "$GIT_URL" =~ ^https?:// ]]; then
        echo_error "Git URL必须以http://或https://开头"
        exit 1
    fi
    
    read -p "Git用户名: " GIT_USERNAME
    read -sp "Git密码: " GIT_PASSWORD
    echo
    
    if [[ -z "$GIT_USERNAME" ]] || [[ -z "$GIT_PASSWORD" ]]; then
        echo_error "用户名和密码不能为空"
        exit 1
    fi
    
    AUTH_METHOD="basic"
    export GIT_URL
    export GIT_USERNAME
    export GIT_PASSWORD
}

# 选择集群
select_cluster() {
    echo_step "选择集群"
    echo ""
    
    if [[ ! -d "scripts/kubeconfigs" ]] || [[ -z "$(ls -A scripts/kubeconfigs/*.yaml 2>/dev/null || true)" ]]; then
        echo_error "没有找到集群配置"
        echo "请先在scripts/kubeconfigs/目录下添加kubeconfig文件"
        exit 1
    fi
    
    # 列出可用集群
    echo "可用集群:"
    echo "------------------------"
    
    local clusters=()
    local index=1
    
    for config in scripts/kubeconfigs/*.yaml scripts/kubeconfigs/*.yml; do
        if [[ -f "$config" ]]; then
            local cluster_name=$(basename "$config" .yaml)
            cluster_name=$(basename "$cluster_name" .yml)
            clusters+=("$cluster_name")
            echo "  $index) $cluster_name"
            ((index++))
        fi
    done
    
    echo "  $index) 所有集群"
    echo ""
    
    read -p "选择集群 (1-$index): " choice
    
    if [[ "$choice" -eq "$index" ]]; then
        echo "将引导所有集群"
        CLUSTER_NAME=""
    elif [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$index" ]]; then
        local selected_index=$((choice - 1))
        CLUSTER_NAME="${clusters[$selected_index]}"
        echo "已选择集群: $CLUSTER_NAME"
    else
        echo_error "无效选择"
        exit 1
    fi
}

# 确认引导
confirm_bootstrap() {
    echo_step "确认引导"
    echo ""
    
    echo "引导配置:"
    echo "------------------------"
    echo "Git仓库: $GIT_URL"
    echo "认证方式: $AUTH_METHOD"
    echo "目标集群: ${CLUSTER_NAME:-所有集群}"
    echo ""
    
    read -p "是否开始引导? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo_info "操作取消"
        exit 0
    fi
}

# 执行引导
execute_bootstrap() {
    echo_step "执行引导"
    echo ""
    
    # 构建命令
    local cmd="./scripts/bootstrap.sh --git-url=\"$GIT_URL\""
    
    # 根据认证方式添加参数
    case "$AUTH_METHOD" in
        token)
            cmd+=" --token=\"$GIT_TOKEN\""
            ;;
        ssh)
            cmd+=" --ssh-key=\"$SSH_KEY_PATH\""
            ;;
        basic)
            cmd+=" --username=\"$GIT_USERNAME\" --password=\"$GIT_PASSWORD\""
            ;;
    esac
    
    if [[ -n "$CLUSTER_NAME" ]]; then
        cmd+=" --cluster=\"$CLUSTER_NAME\""
    fi
    
    echo "执行命令:"
    echo "  $cmd"
    echo ""
    
    # 执行命令
    eval "$cmd"
}

# 显示后续步骤
show_next_steps() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                    向导完成                         ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "🎉 GitOps引导完成！"
    echo ""
    echo "📋 下一步操作:"
    echo "  1. 在base/目录下添加基础应用配置"
    echo "  2. 在overlays/<集群名>/目录下添加集群特定配置"
    echo "  3. 提交并推送更改到Git仓库"
    echo "  4. Flux会自动同步配置到集群"
    echo ""
    echo "🔧 管理工具:"
    echo "  ./scripts/utils.sh help    # 查看帮助"
    echo "  ./scripts/utils.sh list    # 列出所有集群"
    echo "  ./scripts/utils.sh check <集群名>  # 检查集群状态"
    echo ""
    echo "📊 监控命令:"
    echo "  flux get sources git -A"
    echo "  flux get kustomizations -A"
    echo "  flux logs --tail=10"
}

# 主函数
main() {
    show_title
    
    check_environment
    echo ""
    
    check_cluster_configs
    echo ""
    
    select_auth_method
    echo ""
    
    select_cluster
    echo ""
    
    confirm_bootstrap
    echo ""
    
    execute_bootstrap
    echo ""
    
    show_next_steps
}

# 执行
main "$@"