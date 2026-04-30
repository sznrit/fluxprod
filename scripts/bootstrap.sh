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

set -euo pipefail  # 增加 -u 防止未定义变量，-o pipefail 增强管道错误检测

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
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }  # 修复：添加缺失的函数

# 固定配置
DEFAULT_BRANCH="main"
DEFAULT_NAMESPACE="prod"
DEFAULT_INTERVAL="5m"
DEFAULT_COMPONENTS="source-controller,kustomize-controller,helm-controller,notification-controller"
DEFAULT_USERNAME="git"
DEFAULT_AUTH_TYPE="auto"
ASSOCIATE_MODE="${ASSOCIATE_MODE:-false}"  # 默认使用官方 Bootstrap 模式
DRY_RUN="${DRY_RUN:-false}"
DEBUG="${DEBUG:-false}"

# 全局变量（由参数解析填充）
GIT_URL=""
GIT_TOKEN=""
SSH_KEY_PATH=""
GIT_USERNAME=""
GIT_PASSWORD=""
TARGET_CLUSTER=""
GIT_BRANCH="$DEFAULT_BRANCH"
NAMESPACE="$DEFAULT_NAMESPACE"
FLUX_INTERVAL="$DEFAULT_INTERVAL"
FLUX_COMPONENTS="$DEFAULT_COMPONENTS"
AUTH_TYPE="$DEFAULT_AUTH_TYPE"

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
                set -x
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
  --ssh-key=<path>     使用SSH密钥认证 (支持SSH URL格式 git@host:path 和 ssh://)
  --username=<name>    用户名 (用于基本认证)
  --password=<pass>    密码 (用于基本认证)
  --auth-type=<type>   显式指定认证类型: auto, token, ssh, basic

可选参数:
  --cluster=<name>     集群名称 (可选，不指定则引导所有集群)
  --branch=<branch>    Git分支 (默认: "$DEFAULT_BRANCH")
  --ns=<namespace>     应用命名空间 (默认: "$DEFAULT_NAMESPACE")
  --interval=<interval> Flux同步间隔 (默认: "$DEFAULT_INTERVAL")
  --components=<list>  Flux组件列表 (默认: "$DEFAULT_COMPONENTS")
  --associate          使用关联模式 (适用于已安装Flux控制器的集群)
  --dry-run            只显示将要执行的命令，不实际执行
  --debug              启用调试输出
  -h, --help          显示帮助信息

示例:
  # 使用Token认证 (GitHub/GitLab)
  $0 --git-url=https://github.com/my-org/repo.git --token=ghp_xxx --cluster=aws-prod
  
  # 使用SSH密钥认证 (自动转换 git@github.com:user/repo.git 为 ssh://格式)
  $0 --git-url=git@github.com:my-org/repo.git --ssh-key=~/.ssh/id_rsa --cluster=aws-prod
  
  # 使用基本认证
  $0 --git-url=https://git.example.com/repo.git --username=deploy --password=secret --cluster=onprem
  
  # 引导所有集群 (依赖 scripts/kubeconfigs/ 下的配置文件)
  $0 --git-url=https://github.com/my-org/repo.git --token=ghp_xxx

认证类型说明:
  token:  使用Personal Access Token (GitHub, GitLab, Bitbucket等)
  ssh:    使用SSH密钥认证，支持 SCP 风格 URL (git@host:path) 自动转换
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
    if [[ -n "$AUTH_TYPE" && "$AUTH_TYPE" != "auto" ]]; then
        return
    fi
    
    if [[ "$GIT_URL" =~ ^git@ ]] || [[ "$GIT_URL" =~ ^ssh:// ]]; then
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

# 标准化 SSH URL: git@github.com:user/repo.git -> ssh://git@github.com/user/repo.git
normalize_ssh_url() {
    local input_url="$1"
    if [[ "$input_url" =~ ^git@([^:]+):(.+)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local path="${BASH_REMATCH[2]}"
        echo "ssh://git@${host}/${path}"
    else
        echo "$input_url"
    fi
}

# 验证参数并交互式收集缺失信息
validate_parameters() {
    if [[ -z "$GIT_URL" ]]; then
        log_error "必须提供Git仓库URL (使用--git-url参数)"
        show_help
        exit 1
    fi
    
    # 设置默认值（如果未通过参数指定）
    GIT_BRANCH="${GIT_BRANCH:-$DEFAULT_BRANCH}"
    NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"
    FLUX_INTERVAL="${FLUX_INTERVAL:-$DEFAULT_INTERVAL}"
    FLUX_COMPONENTS="${FLUX_COMPONENTS:-$DEFAULT_COMPONENTS}"
    
    detect_auth_type
    
    # 根据认证类型收集缺失信息
    case "$AUTH_TYPE" in
        token)
            if [[ -z "$GIT_TOKEN" ]]; then
                read -rsp "请输入Git Token: " GIT_TOKEN < /dev/tty
                echo
                if [[ -z "$GIT_TOKEN" ]]; then
                    log_error "Token认证需要提供--token参数或交互输入"
                    exit 1
                fi
            fi
            ;;
        ssh)
            if [[ -z "$SSH_KEY_PATH" ]]; then
                if [[ -f "$HOME/.ssh/id_rsa" ]]; then
                    SSH_KEY_PATH="$HOME/.ssh/id_rsa"
                    log_info "使用默认SSH密钥: $SSH_KEY_PATH"
                elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
                    SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
                    log_info "使用默认SSH密钥: $SSH_KEY_PATH"
                else
                    read -p "请输入SSH私钥路径: " SSH_KEY_PATH < /dev/tty
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
            # 标准化 URL
            GIT_URL="$(normalize_ssh_url "$GIT_URL")"
            log_info "标准化后的 Git URL: $GIT_URL"
            ;;
        basic)
            if [[ -z "$GIT_USERNAME" ]]; then
                read -p "请输入Git用户名: " GIT_USERNAME < /dev/tty
            fi
            if [[ -z "$GIT_PASSWORD" ]]; then
                read -rsp "请输入Git密码: " GIT_PASSWORD < /dev/tty
                echo
            fi
            if [[ -z "$GIT_USERNAME" ]] || [[ -z "$GIT_PASSWORD" ]]; then
                log_error "基本认证需要用户名和密码"
                exit 1
            fi
            ;;
        auto)
            # 最后尝试交互式选择
            echo "无法自动检测认证类型，请选择:"
            echo "1) Token (推荐)"
            echo "2) SSH 密钥"
            echo "3) 用户名/密码"
            read -p "请输入选项 [1-3]: " choice < /dev/tty
            case $choice in
                1) AUTH_TYPE="token"; validate_parameters ;;
                2) AUTH_TYPE="ssh"; validate_parameters ;;
                3) AUTH_TYPE="basic"; validate_parameters ;;
                *) log_error "无效选择"; exit 1 ;;
            esac
            ;;
        *)
            log_error "不支持的认证类型: $AUTH_TYPE"
            exit 1
            ;;
    esac
}

# 获取集群列表（兼容旧版 bash）
get_cluster_list() {
    if [[ -n "$TARGET_CLUSTER" ]]; then
        echo "$TARGET_CLUSTER"
    else
        if [[ -d "scripts/kubeconfigs" ]]; then
            for file in scripts/kubeconfigs/*.yaml scripts/kubeconfigs/*.yml; do
                if [[ -f "$file" ]]; then
                    basename "$file" | sed 's/\.yaml$//;s/\.yml$//'
                fi
            done
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
        kubeconfig="scripts/kubeconfigs/$cluster_name.yml"
    fi
    if [[ ! -f "$kubeconfig" ]]; then
        log_error "kubeconfig文件不存在: $kubeconfig"
        return 1
    fi
    if ! head -1 "$kubeconfig" | grep -q "apiVersion:"; then
        log_error "kubeconfig文件格式不正确: $kubeconfig"
        return 1
    fi
    export KUBECONFIG="$kubeconfig"  # 为后续命令设置
    return 0
}

# 准备 SSH 认证 (显示公钥，提示用户添加)
prepare_ssh_auth() {
    local pub_key="${SSH_KEY_PATH}.pub"
    if [[ ! -f "$pub_key" ]]; then
        log_error "SSH公钥文件不存在: $pub_key"
        return 1
    fi
    echo ""
    echo "请将以下SSH公钥添加到Git仓库的部署密钥 (Deploy Keys) 并授予写权限:"
    echo "=============================================="
    cat "$pub_key"
    echo "=============================================="
    echo ""
    read -p "按Enter键继续，确认已添加SSH公钥到Git仓库..." < /dev/tty
    return 0
}

# ==========================================
# 模式 A：官方引导模式
# ==========================================
run_boot_logic() {
    local cluster_name=$1
    local kubeconfig=$2
    local flux_path=$3

    log_step "执行官方引导模式: 强制覆盖现有配置..."

    local final_user="${GIT_USERNAME:-$DEFAULT_USERNAME}"
    local args=(
        bootstrap git
        --url="$GIT_URL"
        --branch="$GIT_BRANCH"
        --path="$flux_path"
        --interval="$FLUX_INTERVAL"
        --timeout="10m"
        --kubeconfig="$kubeconfig"
    )

    case "$AUTH_TYPE" in
        token)
            args+=(--token-auth --username="$final_user" --password="$GIT_TOKEN")
            ;;
        basic)
            args+=(--username="$GIT_USERNAME" --password="$GIT_PASSWORD")
            ;;
        ssh)
            # 使用 Flux 官方标准参数: --private-key-file
            args+=(--private-key-file="$SSH_KEY_PATH")
            ;;
        *)
            log_error "引导模式不支持的认证类型: $AUTH_TYPE"
            return 1
            ;;
    esac

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] flux ${args[*]}"
        return 0
    fi

    if flux "${args[@]}" 2>&1; then
        log_success "集群 $cluster_name 引导成功"
        return 0
    else
        log_error "集群 $cluster_name 引导失败"
        return 1
    fi
}

# ==========================================
# 模式 B：关联模式 (手动创建资源)
# ==========================================
run_associate_logic() {
    local cluster_name=$1
    local kubeconfig=$2
    local flux_path=$3
    local secret_name="flux-git-auth"

    log_step "执行关联模式: 强制更新凭据并建立同步..."

    # 确保 flux-system 命名空间存在
    if ! kubectl get namespace flux-system --kubeconfig="$kubeconfig" &>/dev/null; then
        log_info "创建 flux-system 命名空间"
        kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f - --kubeconfig="$kubeconfig"
    fi

    case "$AUTH_TYPE" in
        token)
            local final_user="${GIT_USERNAME:-git}"
            log_info "覆盖 Git Token 凭据: 用户名=$final_user"
            kubectl create secret generic "$secret_name" \
                --namespace="flux-system" \
                --from-literal=username="$final_user" \
                --from-literal=password="$GIT_TOKEN" \
                --kubeconfig="$kubeconfig" \
                --dry-run=client -o yaml | kubectl apply -f -
            ;;
        basic)
            log_info "覆盖 Git 基本认证凭据: 用户名=$GIT_USERNAME"
            kubectl create secret generic "$secret_name" \
                --namespace="flux-system" \
                --from-literal=username="$GIT_USERNAME" \
                --from-literal=password="$GIT_PASSWORD" \
                --kubeconfig="$kubeconfig" \
                --dry-run=client -o yaml | kubectl apply -f -
            ;;
        ssh)
            secret_name="flux-git-ssh"
            log_info "创建 SSH 认证 Secret"
            kubectl create secret generic "$secret_name" \
                --namespace="flux-system" \
                --from-file=identity="$SSH_KEY_PATH" \
                --from-file=identity.pub="${SSH_KEY_PATH}.pub" \
                --dry-run=client -o yaml | kubectl apply -f -
            ;;
        *)
            log_error "关联模式不支持的认证类型: $AUTH_TYPE"
            return 1
            ;;
    esac

    # 创建 GitRepository 源
    log_info "同步 GitRepository 配置..."
    flux create source git "${cluster_name}-repo" \
        --url="$GIT_URL" \
        --branch="$GIT_BRANCH" \
        --secret-ref="$secret_name" \
        --interval="$FLUX_INTERVAL" \
        --kubeconfig="$kubeconfig" \
        --export | kubectl apply -f -

    # 创建 Kustomization
    log_info "同步 Kustomization 配置..."
    flux create kustomization "${cluster_name}-sync" \
        --source="GitRepository/${cluster_name}-repo" \
        --path="$flux_path" \
        --prune=true \
        --interval="$FLUX_INTERVAL" \
        --kubeconfig="$kubeconfig" \
        --export | kubectl apply -f -

    log_success "关联指令已发送。请稍后使用 'flux get sources git' 查看集群拉取状态。"
    return 0
}

# ==========================================
# 单集群引导入口
# ==========================================
bootstrap_single_cluster() {
    local cluster_name="$1"
    local kubeconfig="scripts/kubeconfigs/$cluster_name.yaml"
    [[ -f "$kubeconfig" ]] || kubeconfig="scripts/kubeconfigs/$cluster_name.yml"
    local flux_path="clusters/$cluster_name"

    if ! validate_kubeconfig "$cluster_name"; then
        return 1
    fi

    # SSH 模式预检查公钥
    if [[ "$AUTH_TYPE" == "ssh" ]] && [[ "$DRY_RUN" != "true" ]]; then
        prepare_ssh_auth || return 1
    fi

    if [[ "$ASSOCIATE_MODE" == "true" ]]; then
        run_associate_logic "$cluster_name" "$kubeconfig" "$flux_path"
    else
        run_boot_logic "$cluster_name" "$kubeconfig" "$flux_path"
    fi
    return $?
}

# 显示Flux状态 (可选)
show_flux_status() {
    local cluster_name="$1"
    local kubeconfig="scripts/kubeconfigs/$cluster_name.yaml"
    [[ -f "$kubeconfig" ]] || kubeconfig="scripts/kubeconfigs/$cluster_name.yml"
    log_step "Flux状态 ($cluster_name):"
    echo -e "\nFlux组件:"
    kubectl get pods -n flux-system --kubeconfig="$kubeconfig" 2>/dev/null | head -10
    echo -e "\nGit仓库:"
    flux get sources git -A --kubeconfig="$kubeconfig" 2>/dev/null | head -10
    echo -e "\nKustomizations:"
    flux get kustomizations -A --kubeconfig="$kubeconfig" 2>/dev/null | head -10
}

# 主函数
main() {
    parse_args "$@"
    validate_parameters
    check_dependencies

    # 构建集群数组 (兼容旧版 bash)
    cluster_list=()
    while IFS= read -r cluster; do
        [[ -n "$cluster" ]] && cluster_list+=("$cluster")
    done < <(get_cluster_list)

    if [[ ${#cluster_list[@]} -eq 0 ]]; then
        log_error "没有找到可用的集群配置"
        echo "请在scripts/kubeconfigs/目录下添加集群的kubeconfig文件 (扩展名 .yaml 或 .yml)"
        exit 1
    fi

    # 显示配置摘要
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║         Flux GitOps引导配置           ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    log_info "配置信息:"
    echo "  Git仓库:  $GIT_URL"
    echo "  认证类型:  $AUTH_TYPE"
    echo "  分支:      $GIT_BRANCH"
    echo "  应用命名空间: $NAMESPACE"
    echo "  同步间隔:  $FLUX_INTERVAL"
    [[ "$AUTH_TYPE" == "ssh" ]] && echo "  SSH密钥:  $SSH_KEY_PATH"
    echo "  关联模式:  $ASSOCIATE_MODE"
    echo "  试运行:    $DRY_RUN"
    log_info "目标集群:"
    for cluster in "${cluster_list[@]}"; do
        echo "  - $cluster"
    done
    echo ""

    # 多集群确认
    if [[ "$DRY_RUN" != "true" ]] && [[ ${#cluster_list[@]} -gt 1 ]]; then
        log_warn "即将对 ${#cluster_list[@]} 个集群执行引导操作。"
        read -p "确定继续吗? (y/N): " confirm < /dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "操作已取消。"
            exit 0
        fi
    fi

    # 逐个引导
    local success_count=0
    for cluster in "${cluster_list[@]}"; do
        log_step "准备引导集群: ${cluster}"
        if bootstrap_single_cluster "$cluster"; then
            ((success_count++))
            if [[ "$DRY_RUN" != "true" ]]; then
                show_flux_status "$cluster"
            fi
        else
            log_error "集群 ${cluster} 引导失败，继续下一个..."
        fi
    done

    # 总结
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║              引导完成                 ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    if [[ $success_count -eq ${#cluster_list[@]} ]]; then
        log_success "✅ 所有集群引导完成 ($success_count/${#cluster_list[@]})"
    elif [[ $success_count -gt 0 ]]; then
        log_warn "⚠️  部分集群引导完成 ($success_count/${#cluster_list[@]})"
    else
        log_error "❌ 所有集群引导失败"
        exit 1
    fi

    if [[ $success_count -gt 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo "🎉 GitOps配置已就绪！"
        echo ""
        echo "下一步操作:"
        echo "  1. 在Git仓库中创建基础目录结构 (clusters/<集群名>/ 等)"
        echo "  2. 在 base/ 目录下添加基础应用配置"
        echo "  3. 在 overlays/<集群名>/ 目录下添加集群特定配置"
        echo "  4. 提交并推送更改到Git仓库"
        echo "  5. Flux会自动同步配置到集群"
    fi
}

# 捕获中断信号
trap 'echo -e "\n\n操作被用户中断"; exit 130' INT

# 运行主函数
main "$@"