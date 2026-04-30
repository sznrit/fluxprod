#!/bin/bash
# scripts/utils.sh
# GitOps管理辅助工具 (增强版)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 设置集群上下文
set_cluster_context() {
    local cluster_name="$1"
    local kubeconfig="scripts/kubeconfigs/$cluster_name.yaml"
    
    if [[ ! -f "$kubeconfig" ]]; then
        log_error "kubeconfig文件不存在: $kubeconfig"
        return 1
    fi
    
    export KUBECONFIG="$kubeconfig"
    return 0
}

# 检查集群状态
check_cluster() {
    local cluster_name="$1"
    
    log_step "检查集群: $cluster_name"
    echo "------------------------"
    
    if ! set_cluster_context "$cluster_name"; then
        return 1
    fi
    
    # 集群连接
    if kubectl cluster-info &> /dev/null; then
        echo -e "✓ 集群连接正常"
    else
        echo -e "✗ 无法连接到集群"
        return 1
    fi
    
    # 集群版本
    local version=$(kubectl version --short 2>/dev/null | head -1 | sed 's/.*: v//' || echo "unknown")
    echo -e "Kubernetes版本: v$version"
    
    # 节点状态
    echo -e "\n节点状态:"
    kubectl get nodes 2>/dev/null | head -6
    
    # 命名空间
    local ns_count=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l)
    echo -e "\n命名空间数量: $ns_count"
    
    # Flux状态
    if kubectl get namespace flux-system &> /dev/null; then
        echo -e "\nFlux状态:"
        echo "------------------------"
        kubectl get pods -n flux-system
        
        echo -e "\nFlux Git仓库:"
        flux get sources git -A 2>/dev/null || echo "  无"
        
        echo -e "\nFlux Kustomizations:"
        flux get kustomizations -A 2>/dev/null || echo "  无"
    else
        echo -e "\nFlux: 未安装"
    fi
    
    return 0
}

# 检查所有集群
check_all_clusters() {
    if [[ ! -d "scripts/kubeconfigs" ]]; then
        log_error "scripts/kubeconfigs目录不存在"
        return 1
    fi
    
    local clusters=$(find scripts/kubeconfigs -name "*.yaml" -o -name "*.yml" | \
        xargs -I {} basename {} | sed 's/\.yaml$//;s/\.yml$//')
    
    for cluster in $clusters; do
        check_cluster "$cluster"
        echo -e "\n========================================\n"
    done
}

# 获取应用状态
get_app_status() {
    local cluster_name="$1"
    local namespace="${2:-}"
    
    if ! set_cluster_context "$cluster_name"; then
        return 1
    fi
    
    log_step "应用状态 (集群: $cluster_name)"
    echo "------------------------"
    
    if [[ -z "$namespace" ]]; then
        # 所有命名空间
        echo "所有命名空间的资源:"
        echo "-----------------"
        kubectl get deployments,statefulsets,daemonsets,services,configmaps,secrets --all-namespaces 2>/dev/null | head -20
    else
        # 特定命名空间
        echo "命名空间 $namespace 的资源:"
        echo "-------------------------"
        kubectl get all -n "$namespace" 2>/dev/null
    fi
}

# 查看Flux日志
view_flux_logs() {
    local cluster_name="$1"
    local tail_lines="${2:-20}"
    
    if ! set_cluster_context "$cluster_name"; then
        return 1
    fi
    
    if ! kubectl get namespace flux-system &> /dev/null; then
        log_error "Flux未安装"
        return 1
    fi
    
    log_step "Flux日志 (集群: $cluster_name, 最近 ${tail_lines} 行)"
    echo "------------------------"
    
    flux logs --tail="$tail_lines"
}

# 强制同步
force_sync() {
    local cluster_name="$1"
    
    if ! set_cluster_context "$cluster_name"; then
        return 1
    fi
    
    if ! kubectl get namespace flux-system &> /dev/null; then
        log_error "Flux未安装"
        return 1
    fi
    
    log_step "强制同步 (集群: $cluster_name)"
    echo "------------------------"
    
    # 获取所有Kustomization
    local kustomizations=$(flux get kustomizations -A --no-headers 2>/dev/null | awk '{print $2}' 2>/dev/null || echo "")
    
    if [[ -z "$kustomizations" ]]; then
        echo "没有找到Kustomization资源"
        return 0
    fi
    
    for kustomization in $kustomizations; do
        local namespace=$(flux get kustomizations -A --no-headers 2>/dev/null | grep "$kustomization" | awk '{print $1}' 2>/dev/null || echo "flux-system")
        
        echo -n "同步 $namespace/$kustomization... "
        if flux reconcile kustomization "$kustomization" -n "$namespace" &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
        fi
    done
}

# 列出所有集群
list_clusters() {
    if [[ ! -d "scripts/kubeconfigs" ]]; then
        log_error "scripts/kubeconfigs目录不存在"
        return 1
    fi
    
    log_step "可用集群列表"
    echo "------------------------"
    
    local count=0
    for config in scripts/kubeconfigs/*.yaml scripts/kubeconfigs/*.yml; do
        if [[ -f "$config" ]]; then
            local cluster_name=$(basename "$config" .yaml)
            cluster_name=$(basename "$cluster_name" .yml)
            
            # 检查集群状态
            export KUBECONFIG="$config"
            if kubectl cluster-info &> /dev/null; then
                local context=$(kubectl config current-context 2>/dev/null || echo "unknown")
                echo -e "  ${GREEN}✓${NC} $cluster_name ($context)"
            else
                echo -e "  ${RED}✗${NC} $cluster_name (无法连接)"
            fi
            
            ((count++))
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        echo "  没有找到集群配置"
    else
        echo -e "\n总计: $count 个集群"
    fi
}

# 验证Git仓库连接
verify_git_connection() {
    local cluster_name="$1"
    
    if ! set_cluster_context "$cluster_name"; then
        return 1
    fi
    
    if ! kubectl get namespace flux-system &> /dev/null; then
        log_error "Flux未安装"
        return 1
    fi
    
    log_step "验证Git仓库连接 (集群: $cluster_name)"
    echo "------------------------"
    
    echo "Git仓库状态:"
    flux get sources git -A
    
    echo ""
    echo "尝试拉取最新状态..."
    flux reconcile source git flux-system -n flux-system
    
    echo ""
    echo "查看详细状态:"
    kubectl get gitrepositories -n flux-system -o wide
    echo ""
    
    kubectl describe gitrepositories flux-system -n flux-system | grep -A5 -B5 "Status"
}

# 清理集群
clean_cluster() {
    local cluster_name="$1"
    
    if ! set_cluster_context "$cluster_name"; then
        return 1
    fi
    
    read -p "确认要清理集群 $cluster_name 吗? 这将删除Flux和其管理的资源 (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作取消"
        return
    fi
    
    log_step "清理集群: $cluster_name"
    echo "------------------------"
    
    # 暂停所有同步
    echo "暂停所有同步..."
    flux suspend kustomization --all -A 2>/dev/null || true
    flux suspend helmrelease --all -A 2>/dev/null || true
    
    # 卸载Flux
    echo "卸载Flux..."
    flux uninstall --silent 2>/dev/null || true
    
    # 删除flux-system命名空间
    echo "删除flux-system命名空间..."
    kubectl delete namespace flux-system --ignore-not-found --wait=false
    
    log_info "清理完成"
}

# 显示帮助
show_help() {
    cat << EOF
GitOps管理工具 (增强版)

使用: ./scripts/utils.sh <命令> [参数]

命令:
  check <cluster>         检查集群状态
  check-all               检查所有集群状态
  apps <cluster> [ns]     查看应用状态
  logs <cluster> [lines]  查看Flux日志
  sync <cluster>          强制同步
  list                    列出所有集群
  verify-git <cluster>    验证Git仓库连接
  clean <cluster>         清理集群
  help                    显示帮助

示例:
  ./scripts/utils.sh check aws-prod
  ./scripts/utils.sh check-all
  ./scripts/utils.sh apps aws-prod
  ./scripts/utils.sh logs aws-prod 50
  ./scripts/utils.sh sync aws-prod
  ./scripts/utils.sh list
  ./scripts/utils.sh verify-git aws-prod
EOF
}

# 主函数
main() {
    local command="$1"
    
    case "$command" in
        check)
            if [[ -z "$2" ]]; then
                log_error "请指定集群名"
                show_help
                exit 1
            fi
            check_cluster "$2"
            ;;
        check-all)
            check_all_clusters
            ;;
        apps)
            if [[ -z "$2" ]]; then
                log_error "请指定集群名"
                show_help
                exit 1
            fi
            get_app_status "$2" "$3"
            ;;
        logs)
            if [[ -z "$2" ]]; then
                log_error "请指定集群名"
                show_help
                exit 1
            fi
            view_flux_logs "$2" "$3"
            ;;
        sync)
            if [[ -z "$2" ]]; then
                log_error "请指定集群名"
                show_help
                exit 1
            fi
            force_sync "$2"
            ;;
        list)
            list_clusters
            ;;
        verify-git)
            if [[ -z "$2" ]]; then
                log_error "请指定集群名"
                show_help
                exit 1
            fi
            verify_git_connection "$2"
            ;;
        clean)
            if [[ -z "$2" ]]; then
                log_error "请指定集群名"
                show_help
                exit 1
            fi
            clean_cluster "$2"
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi