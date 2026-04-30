#!/bin/bash
# scripts/bootstrap.sh
# Flux GitOps 多集群引导脚本 (支持多种认证方式)
# 用法: scripts/bootstrap.sh --git-url=<git-url> [认证选项] [--cluster=<cluster-name>]

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
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 固定配置（根据需要修改这些值）
DEFAULT_BRANCH="main"           # Git分支
DEFAULT_NAMESPACE="prod"        # 应用命名空间
DEFAULT_INTERVAL="5m"           # Flux同步间隔
DEFAULT_COMPONENTS="source-controller,kustomize-controller,helm-controller,notification-controller"  # Flux组件
DEFAULT_USERNAME="git"          # 默认Git用户名
DEFAULT_AUTH_TYPE="auto"        # 默认认证类型: auto, token, ssh, basic
DEFAULT_ASSOCIATE_MODE="false"  # 默认使用官方 Bootstrap 模式

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --git-url=*)
                GIT_URL="${1#*=}"
                shift
                ;;
            --git-url)
                GIT_URL="$2"
                shift 2
                ;;
            --token=*)
                GIT_TOKEN="${1#*=}"
                AUTH_TYPE="token"
                shift
                ;;
            --token)
                GIT_TOKEN="$2"
                AUTH_TYPE="token"
                shift 2
                ;;
            --ssh-key=*)
                SSH_KEY_PATH="${1#*=}"
                AUTH_TYPE="ssh"
                shift
                ;;
            --ssh-key)
                SSH_KEY_PATH="$2"
                AUTH_TYPE="ssh"
                shift 2
                ;;
            --username=*)
                GIT_USERNAME="${1#*=}"
                shift
                ;;
            --username)
                GIT_USERNAME="$2"
                shift 2
                ;;
            --password=*)
                GIT_PASSWORD="${1#*=}"
                AUTH_TYPE="basic"
                shift
                ;;
            --password)
                GIT_PASSWORD="$2"
                AUTH_TYPE="basic"
                shift 2
                ;;
            --cluster=*)
                TARGET_CLUSTER="${1#*=}"
                shift
                ;;
            --cluster)
                TARGET_CLUSTER="$2"
                shift 2
                ;;
            --branch=*)
                GIT_BRANCH="${1#*=}"
                shift
                ;;
            --branch)
                GIT_BRANCH="$2"
                shift 2
                ;;
            --ns=*)
                NAMESPACE="${1#*=}"
                shift
                ;;
            --ns)
                NAMESPACE="$2"
                shift 2
                ;;
            --interval=*)
                FLUX_INTERVAL="${1#*=}"
                shift
                ;;
            --interval)
                FLUX_INTERVAL="$2"
                shift 2
                ;;
            --components=*)
                FLUX_COMPONENTS="${1#*=}"
                shift
                ;;
            --components)
                FLUX_COMPONENTS="$2"
                shift 2
                ;;
            --auth-type=*)
                AUTH_TYPE="${1#*=}"
                shift
                ;;
            --auth-type)
                AUTH_TYPE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --associate)
                ASSOCIATE_MODE="true"
                shift
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 显示帮助
show_help() {
    cat << EOF
Flux GitOps 引导脚本 (支持多种认证方式)

用法: $0 --git-url=<git-url> [认证选项] [其他选项]

必需参数:
  --git-url=<url>      Git仓库URL (必需)

认证选项 (至少选择一个):
  --token=<token>      使用Token认证 (推荐)
  --ssh-key=<path>     使用SSH密钥认证
  --username=<name>    用户名 (用于基本认证)
  --password=<pass>    密码 (用于基本认证)
  --auth-type=<type>   显式指定认证类型: auto, token, ssh, basic

可选参数:
  --cluster=<name>     集群名称 (可选，不指定则引导所有集群)
  --branch=<branch>    Git分支 (默认: "$DEFAULT_BRANCH")
  --ns=<namespace>     应用命名空间 (默认: "$DEFAULT_NAMESPACE")
  --interval=<interval> Flux同步间隔 (默认: "$DEFAULT_INTERVAL")
  --components=<list>  Flux组件列表 (默认: "$DEFAULT_COMPONENTS")
  --private            使用私有仓库 (默认)
  --public             使用公共仓库
  --dry-run            只显示将要执行的命令，不实际执行
  --debug              启用调试输出
  -h, --help          显示帮助信息

示例:
  # 使用Token认证 (GitHub/GitLab)
  $0 --git-url=https://github.com/my-org/repo.git --token=ghp_xxx --cluster=aws-prod
  
  # 使用SSH密钥认证
  $0 --git-url=git@github.com:my-org/repo.git --ssh-key=~/.ssh/id_rsa --cluster=aws-prod
  
  # 使用基本认证 (用户名/密码)
  $0 --git-url=https://git.example.com/repo.git --username=deploy --password=secret --cluster=onprem
  
  # 自动检测认证类型
  $0 --git-url=https://gitlab.com/my-group/repo.git --auth-type=auto --cluster=staging
  
  # 引导所有集群
  $0 --git-url=https://github.com/my-org/repo.git --token=ghp_xxx

认证类型说明:
  token:  使用Personal Access Token (GitHub, GitLab, Bitbucket等)
  ssh:    使用SSH密钥认证
  basic:  使用用户名/密码基本认证
  auto:   自动检测认证类型 (默认)
EOF
}

# 检查依赖
check_dependencies() {
    for cmd in flux kubectl; do
        if ! command -v $cmd &> /dev/null; then
            log_error "必需工具 '$cmd' 未安装"
            exit 1
        fi
    done
}

# 自动检测认证类型
detect_auth_type() {
    # 如果用户已指定，则使用用户指定的类型
    if [[ -n "$AUTH_TYPE" ]]; then
        return
    fi
    
    # 根据URL格式检测
    if [[ "$GIT_URL" =~ ^git@ ]]; then
        AUTH_TYPE="ssh"
        log_info "检测到SSH URL，自动使用SSH认证"
    elif [[ -n "$GIT_TOKEN" ]]; then
        AUTH_TYPE="token"
        log_info "检测到Token参数，自动使用Token认证"
    elif [[ -n "$GIT_USERNAME" ]] && [[ -n "$GIT_PASSWORD" ]]; then
        AUTH_TYPE="basic"
        log_info "检测到用户名/密码，自动使用基本认证"
    else
        AUTH_TYPE="auto"
    fi
}

# 验证参数
validate_parameters() {
    # 必需参数
    if [[ -z "$GIT_URL" ]]; then
        log_error "必须提供Git仓库URL (使用--git-url参数)"
        show_help
        exit 1
    fi
    
    # 设置默认值
    GIT_BRANCH="${GIT_BRANCH:-$DEFAULT_BRANCH}"
    NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"
    FLUX_INTERVAL="${FLUX_INTERVAL:-$DEFAULT_INTERVAL}"
    FLUX_COMPONENTS="${FLUX_COMPONENTS:-$DEFAULT_COMPONENTS}"
    AUTH_TYPE="${AUTH_TYPE:-$DEFAULT_AUTH_TYPE}"
    
    # 自动检测认证类型
    detect_auth_type
    
    # 根据认证类型验证参数
    case "$AUTH_TYPE" in
        token)
            if [[ -z "$GIT_TOKEN" ]]; then
                read -sp "请输入Git Token: " GIT_TOKEN
                echo
                if [[ -z "$GIT_TOKEN" ]]; then
                    log_error "Token认证需要提供--token参数"
                    exit 1
                fi
            fi
            ;;
        ssh)
            if [[ -z "$SSH_KEY_PATH" ]]; then
                # 尝试使用默认SSH密钥
                if [[ -f "$HOME/.ssh/id_rsa" ]]; then
                    SSH_KEY_PATH="$HOME/.ssh/id_rsa"
                    log_info "使用默认SSH密钥: $SSH_KEY_PATH"
                elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
                    SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
                    log_info "使用默认SSH密钥: $SSH_KEY_PATH"
                else
                    read -p "请输入SSH私钥路径: " SSH_KEY_PATH
                    if [[ -z "$SSH_KEY_PATH" ]] || [[ ! -f "$SSH_KEY_PATH" ]]; then
                        log_error "SSH认证需要有效的私钥文件"
                        exit 1
                    fi
                fi
            fi
            
            if [[ ! -f "$SSH_KEY_PATH" ]]; then
                log_error "SSH私钥文件不存在: $SSH_KEY_PATH"
                exit 1
            fi
            ;;
        basic)
            if [[ -z "$GIT_USERNAME" ]]; then
                read -p "请输入Git用户名: " GIT_USERNAME
            fi
            if [[ -z "$GIT_PASSWORD" ]]; then
                read -sp "请输入Git密码: " GIT_PASSWORD
                echo
            fi
            
            if [[ -z "$GIT_USERNAME" ]] || [[ -z "$GIT_PASSWORD" ]]; then
                log_error "基本认证需要用户名和密码"
                exit 1
            fi
            ;;
        auto)
            # 自动检测逻辑
            if [[ "$GIT_URL" =~ ^git@ ]]; then
                AUTH_TYPE="ssh"
                validate_parameters  # 重新验证
            else
                # 尝试使用Token
                if [[ -z "$GIT_TOKEN" ]]; then
                    read -sp "请选择认证方式 (回车使用Token，或输入'ssh'使用SSH): " auth_choice
                    echo
                    if [[ "$auth_choice" == "ssh" ]]; then
                        AUTH_TYPE="ssh"
                        validate_parameters
                    else
                        read -sp "请输入Git Token: " GIT_TOKEN
                        echo
                        if [[ -z "$GIT_TOKEN" ]]; then
                            log_error "需要提供认证信息"
                            exit 1
                        fi
                        AUTH_TYPE="token"
                    fi
                else
                    AUTH_TYPE="token"
                fi
            fi
            ;;
        *)
            log_error "不支持的认证类型: $AUTH_TYPE"
            exit 1
            ;;
    esac
    
    # 验证Git URL格式
    if [[ "$AUTH_TYPE" == "ssh" ]]; then
        if [[ ! "$GIT_URL" =~ ^git@ ]]; then
            log_warn "SSH认证通常使用git@格式的URL"
        fi
    else
        if [[ ! "$GIT_URL" =~ ^https?:// ]]; then
            log_error "HTTPS URL必须以http://或https://开头"
            exit 1
        fi
    fi
}

# 获取集群列表
get_cluster_list() {
    if [[ -n "$TARGET_CLUSTER" ]]; then
        echo "$TARGET_CLUSTER"
    else
        if [[ -d "scripts/kubeconfigs" ]]; then
            find scripts/kubeconfigs -maxdepth 1 \
                -name "*.yaml" -o -name "*.yml" | \
                xargs -I {} basename {} | \
                sed 's/\.yaml$//;s/\.yml$//' | sort
        else
            log_error "scripts/kubeconfigs目录不存在"
            exit 1
        fi
    fi
}

# 验证kubeconfig文件
validate_kubeconfig() {
    local cluster_name="$1"
    local kubeconfig="scripts/kubeconfigs/$cluster_name.yaml"
    
    if [[ ! -f "$kubeconfig" ]]; then
        log_error "kubeconfig文件不存在: $kubeconfig"
        return 1
    fi
    
    if ! head -1 "$kubeconfig" | grep -q "apiVersion:"; then
        log_error "kubeconfig文件格式不正确: $kubeconfig"
        return 1
    fi
    
    return 0
}

# 测试集群连接
test_cluster_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        return 1
    fi
    return 0
}

# 创建命名空间
create_namespace() {
    local namespace="$1"
    
    if kubectl get namespace "$namespace" &> /dev/null; then
        log_info "命名空间 $namespace 已存在"
    else
        kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
        log_info "命名空间 $namespace 创建完成"
    fi
}

# 准备SSH认证
prepare_ssh_auth() {
    local cluster_name="$1"
    
    log_step "准备SSH认证..."
    
    # 检查SSH密钥是否存在
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH私钥文件不存在: $SSH_KEY_PATH"
        return 1
    fi
    
    # 检查公钥是否存在
    local pub_key="${SSH_KEY_PATH}.pub"
    if [[ ! -f "$pub_key" ]]; then
        log_error "SSH公钥文件不存在: $pub_key"
        return 1
    fi
    
    # 显示公钥，让用户添加到Git仓库
    echo ""
    echo "请将以下SSH公钥添加到Git仓库的部署密钥:"
    echo "=============================================="
    cat "$pub_key"
    echo "=============================================="
    echo ""
    
    read -p "按Enter键继续，确认已添加SSH公钥到Git仓库..."
    
    return 0
}

# ==========================================
# 模式 A：官方引导模式 (Run Boot Logic)
# ==========================================
run_boot_logic() {
    local cluster_name=$1
    local kubeconfig=$2
    local flux_path=$3

    log_step "执行官方引导模式: 强制覆盖现有配置..."

    local final_user="${GIT_USERNAME:-git}"

    # 增加 --timeout 以应对不稳定的网络
    local args=(
        bootstrap git
        --url="$GIT_URL"
        --branch="$GIT_BRANCH"
        --path="$flux_path"
        --interval="$FLUX_INTERVAL"
        --timeout="10m"
        --kubeconfig="$kubeconfig"
        --username="$final_user"
        --password="$GIT_TOKEN"
        --token-auth=true
        --silent
    )

    # Flux Bootstrap 内部会自动执行类似 apply 的逻辑覆盖旧密钥
    if flux "${args[@]}"; then
        log_success "集群 $cluster_name 引导成功"
    else
        log_error "集群 $cluster_name 引导失败，建议改用 --associate 模式"
        return 1
    fi
}

# ==========================================
# 模式 B：关联模式 (Run Associate Logic)
# ==========================================
run_associate_logic() {
    local cluster_name=$1
    local kubeconfig=$2
    local flux_path=$3
    local secret_name="flux-git-auth"

    log_step "执行关联模式: 强制更新凭据并建立同步..."

    # 1. 动态确定用户名 (兼容所有 Git 服务商)
    local final_user="${GIT_USERNAME:-git}"
    local final_pass="${GIT_TOKEN:-$GIT_PASSWORD}"

    # 2. 强制覆盖 Secret
    log_info "覆盖 Git 凭据: 用户名=$final_user"
    kubectl create secret generic "$secret_name" \
        --namespace="flux-system" \
        --from-literal=username="$final_user" \
        --from-literal=password="$final_pass" \
        --kubeconfig="$kubeconfig" \
        --dry-run=client -o yaml | kubectl apply -f -

    # 3. 强制覆盖 Source (GitRepository)
    log_info "同步 GitRepository 配置..."
    flux create source git "${cluster_name}-repo" \
        --url="$GIT_URL" \
        --branch="$GIT_BRANCH" \
        --secret-ref="$secret_name" \
        --interval="$FLUX_INTERVAL" \
        --kubeconfig="$kubeconfig" \
        --export | kubectl apply -f -

    # 4. 强制覆盖 Kustomization
    log_info "同步 Kustomization 配置..."
    flux create kustomization "${cluster_name}-sync" \
        --source="GitRepository/${cluster_name}-repo" \
        --path="$flux_path" \
        --prune=true \
        --interval="$FLUX_INTERVAL" \
        --kubeconfig="$kubeconfig" \
        --export | kubectl apply -f -
    
    log_success "关联指令已发送。请稍后使用 'flux get sources git' 查看集群拉取状态。"
}

# ==========================================
# 主入口分流 (Bootstrap Single Cluster)
# ==========================================
bootstrap_single_cluster() {
    local cluster_name="$1"
    local kubeconfig="scripts/kubeconfigs/$cluster_name.yaml"
    local flux_path="${FLUX_PATH:-clusters/$cluster_name}"
    
    # 基础校验
    if ! validate_kubeconfig "$cluster_name"; then return 1; fi

    # 模式选择
    local result=0
    set +e
    if [[ "$ASSOCIATE_MODE" == "true" ]]; then
        run_associate_logic "$cluster_name" "$kubeconfig" "$flux_path"
        result=$?
    else
        run_boot_logic "$cluster_name" "$kubeconfig" "$flux_path"
        result=$?
    fi
    set -e

    if [[ $result -eq 0 ]]; then
        log_success "集群 $cluster_name 配置处理完成"
    else
        log_error "集群 $cluster_name 配置处理失败"
    fi

    return $result
}

# 显示Flux状态
show_flux_status() {
    local cluster_name="$1"
    
    log_step "Flux状态 ($cluster_name):"
    
    echo -e "\nFlux组件:"
    kubectl get pods -n flux-system 2>/dev/null | head -10
    
    echo -e "\nGit仓库:"
    flux get sources git -A 2>/dev/null | head -10
    
    echo -e "\nKustomizations:"
    flux get kustomizations -A 2>/dev/null | head -10
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"
    
    # 验证参数
    validate_parameters
    
    # 检查依赖
    check_dependencies
    
    # 获取集群列表
    local cluster_list
    cluster_list=$(get_cluster_list)

    if [[ -z "$cluster_list" ]]; then
        log_error "没有找到可用的集群配置"
        echo "请在scripts/kubeconfigs/目录下添加集群的kubeconfig文件"
        exit 1
    fi
    
    # 显示配置信息
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║         Flux GitOps引导配置           ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    log_info "配置信息:"
    echo "  Git仓库:  $GIT_URL"
    echo "  认证类型:  $AUTH_TYPE"
    echo "  分支:      $GIT_BRANCH"
    echo "  命名空间:  $NAMESPACE"
    echo "  同步间隔:  $FLUX_INTERVAL"
    
    if [[ "$AUTH_TYPE" == "ssh" ]] && [[ -n "$SSH_KEY_PATH" ]]; then
        echo "  SSH密钥:  $SSH_KEY_PATH"
    fi
    
    # 显示集群
    log_info "目标集群:"
    while IFS= read -r cluster; do
        [[ -n "$cluster" ]] && echo "  - $cluster"
    done <<< "$cluster_list"

    echo ""
    
    # 1. 转换并清理数组
    mapfile -t cluster_array < <(get_cluster_list | grep -v '^$')
    local total_count=${#cluster_array[@]}

    if [[ $total_count -eq 0 ]]; then
        log_error "未检测到有效的集群配置，退出。"
        exit 1
    fi

    # 2. 交互确认
    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ $total_count -gt 1 ]]; then
            log_warn "即将对 $total_count 个集群执行引导操作。"
            echo -n "确定继续吗? (y/N): "
            read -r confirm < /dev/tty
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_info "操作已取消。"
                exit 0
            fi
        fi
    fi
    
    # 3. 迭代执行
    local success_count=0
    for cluster in "${cluster_array[@]}"; do
        [[ -z "$cluster" ]] && continue  # 再次防御空行
        
        log_step "准备引导集群: ${cluster}"
        if bootstrap_single_cluster "$cluster"; then
            ((success_count++))
        else
            log_error "集群 ${cluster} 引导失败，继续下一个..."
        fi
    done
    
    # 输出总结
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║              引导完成                 ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [[ $success_count -eq $total_count ]]; then
        log_info "✅ 所有集群引导完成 ($success_count/$total_count)"
    elif [[ $success_count -gt 0 ]]; then
        log_warn "⚠️  部分集群引导完成 ($success_count/$total_count)"
    else
        log_error "❌ 所有集群引导失败"
        exit 1
    fi
    
    if [[ $success_count -gt 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo "🎉 GitOps配置已就绪！"
        echo ""
        echo "下一步操作:"
        echo "  1. 在Git仓库中创建基础目录结构"
        echo "  2. 在base/目录下添加基础应用配置"
        echo "  3. 在overlays/<集群名>/目录下添加集群特定配置"
        echo "  4. 提交并推送更改到Git仓库"
        echo "  5. Flux会自动同步配置到集群"
    fi
}

# 捕获Ctrl+C
trap 'echo -e "\n\n操作被用户中断"; exit 130' INT

# 执行主函数
main "$@"