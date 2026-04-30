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
