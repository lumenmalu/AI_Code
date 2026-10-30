# Codex 多主机远程开发管理工具

通过 SSHFS 将多台远程电脑的不同目录挂载到本地,在本地运行 Codex 编辑远程代码。
远程电脑不需要安装 Codex,只需要开启 SSH 服务。

## 方案原理

```text
本地电脑
┌──────────────────────────────────────────────────┐
│  remote-codex.sh (多主机管理器)                   │
│                                                   │
│  hosts.d/nvidia8_180.conf ──> SSHFS ──> Nvidia (8.180) │
│  hosts.d/robot31_105.conf ──> SSHFS ──> 机器人 (31.105) │
│  hosts.d/gpu-box.conf ─> SSHFS ──> GPU 服务器      │
│                                                   │
│  Codex CLI ──> 本地挂载点 ──> 编辑远程文件         │
│            └─> ssh 别名  ──> 执行远程命令          │
└──────────────────────────────────────────────────┘
```

- 文件编辑: Codex 通过 SSHFS 直接读写远程文件
- 命令执行: Codex 通过 SSH 在远程执行编译、测试等命令(通过 AGENTS.md 配置)
- 多主机: 每台远程电脑一个独立配置文件,互不干扰

## 目录结构

```text
codex-ssh/
├── remote-codex.sh        # 主脚本(多主机管理入口)
├── AGENTS-template.md     # AGENTS.md 模板(自动填充)
├── README.md              # 本文档
└── hosts.d/               # 主机配置目录
    ├── README.md          # 配置说明
    ├── nvidia8_180.conf   # 10.17.8.180(复用别名 Nvidia-105-wlan)
    └── ...                # 每台主机一个 .conf 文件
```

## 快速开始

### 第一步: 安装 sshfs

```bash
sudo apt update
sudo apt install sshfs
sudo modprobe fuse
```

验证:

```bash
sshfs --version
ls /dev/fuse
```

### 第二步: 添加第一台主机

```bash
cd ~/Documents/AI_Code/Codex/codex-ssh
./remote-codex.sh add robot31_105
```

`nvidia8_180` 已写好，对应 `nvidia@10.17.8.180:/home/nvidia/atom`，并复用 SSH 别名 `Nvidia-105-wlan`。新机器按提示输入用户名、IP、目录；若 `~/.ssh/config` 已有别名，在「复用的 SSH 别名」里填上即可。

也可以直接复制示例配置:

```bash
cp hosts.d/nvidia8_180.conf hosts.d/robot2.conf
# 编辑 robot2.conf 修改用户名/IP/目录/挂载点/SSH 别名
```

### 第三步: 设置 SSH 免密登录(推荐)

```bash
./remote-codex.sh setup-ssh robot31_105
```

该命令会自动:

1. 若 conf 里的 `SSH_ALIAS` 已在 `~/.ssh/config` 中，直接复用，不再生成密钥
2. 否则生成独立密钥 `~/.ssh/codex_<别名>_key`，把公钥复制到远程（需要输入一次远程密码），并写入 `~/.ssh/config`

`nvidia8_180` 已复用 `Nvidia-105-wlan`，这一步可以跳过。设置后可直接 `ssh Nvidia-105-wlan` 连接。

### 第四步: 日常使用

```bash
./remote-codex.sh mount nvidia8_180     # 挂载远程目录
./remote-codex.sh gen-agents nvidia8_180  # 生成 AGENTS.md(远程命令执行说明)
./remote-codex.sh codex nvidia8_180     # 启动 Codex 编辑远程代码
./remote-codex.sh status                # 查看所有主机状态
./remote-codex.sh status nvidia8_180
./remote-codex.sh umount nvidia8_180    # 用完后卸载
```

另一台主机同样操作，把别名换成 `robot31_105`：

```bash
./remote-codex.sh mount robot31_105
./remote-codex.sh gen-agents robot31_105
./remote-codex.sh codex robot31_105
./remote-codex.sh umount robot31_105
```



## 命令速查

| 命令 | 缩写 | 说明 |
|------|------|------|
| `list` | `ls` | 列出所有主机 |
| `add <别名>` | - | 交互式添加主机 |
| `mount <别名>` | `m` | 挂载远程目录 |
| `umount <别名>` | `u` | 卸载 |
| `codex <别名>` | `c` | 启动 Codex |
| `status [别名]` | `st` | 查看状态 |
| `gen-agents <别名>` | - | 生成 AGENTS.md |
| `remove <别名>` | `rm` | 删除主机配置 |
| `setup-ssh <别名>` | - | SSH 免密登录 |
| `mount-all` | - | 挂载全部 |
| `umount-all` | - | 卸载全部 |
| `help` | - | 帮助 |

## 多主机典型场景

三台远程电脑,三个不同项目目录:

```bash
# 添加三台主机
./remote-codex.sh add robot1      # 10.17.8.180 主控
./remote-codex.sh add robot2      # 192.168.31.95 从机
./remote-codex.sh add gpu-box     # 192.168.1.50  GPU 服务器

# 查看所有主机状态
./remote-codex.sh list

# 一次挂载全部
./remote-codex.sh mount-all

# 分别编辑不同主机的代码
./remote-codex.sh codex robot1
./remote-codex.sh codex gpu-box

# 用完后一次卸载
./remote-codex.sh umount-all
```

## 配置字段说明

每个 `hosts.d/<别名>.conf` 文件包含:

```bash
REMOTE_USER="用户名"              # SSH 用户名(必填)
REMOTE_HOST="IP或域名"            # 远程地址(必填)
SSH_PORT="22"                     # SSH 端口(可选,默认22)
REMOTE_DIR="/远程/项目/路径"      # 远程项目目录(必填,绝对路径)
LOCAL_MOUNT="$HOME/remote/别名"  # 本地挂载点(必填,每台不同;与 claude-ssh 共享)
SSH_ALIAS="Nvidia-105-wlan"      # 复用已有 SSH 别名(可选,留空则使用文件名别名)
SANDBOX_MODE="danger-full-access" # 沙箱模式(可选;远程 ssh 需要完全访问)
```

沙箱模式:

- `workspace-write`: 只允许写入工作目录(推荐)
- `danger-full-access`: 完全访问(需要 SSH 执行远程命令时用)

## 远程命令执行

Codex 在远程执行编译、测试等命令前,需要生成 AGENTS.md:

```bash
./remote-codex.sh mount robot1
./remote-codex.sh gen-agents robot1
```

生成后,Codex 会知道通过 `ssh robot1 "cd <远程目录> && <命令>"` 执行远程命令。

> `gen-agents` 采用**标记段**写入 AGENTS.md（`<!-- >>> remote-codex-ssh >>>` … `<!-- <<< remote-codex-ssh <<<`），重复运行只更新标记段，**保留你在 AGENTS.md 中写的其他内容**（含项目自定义规则），不会覆盖。

如果 Codex 沙箱阻止了 SSH 网络访问,将配置文件中的沙箱模式改为:

```bash
SANDBOX_MODE="danger-full-access"
```

## 与 claude-ssh 共享挂载点（同时使用 Codex 和 Claude）

本方案与 `claude-ssh` **共享同一个本地挂载点** `~/remote/<别名>/`，可同时对同一远程目录使用 Codex 和 Claude。

- **挂载一次共用**：两者 `LOCAL_MOUNT` 都指向 `~/remote/<别名>/`，SSHFS 一个挂载点只能挂一次，用任一工具 `mount` 即可，另一工具自动复用。
- **指令文件共存**：Codex 读 `AGENTS.md`、Claude 读 `CLAUDE.md`，共存互不干扰。详见 `claude-ssh/README.md`。

同时使用：

```bash
./remote-codex.sh  mount nvidia8_180          # 挂载一次(claude 也可挂,共用)
./remote-codex.sh  gen-agents     nvidia8_180 # AGENTS.md(给 Codex)
./remote-claude.sh gen-claude-md nvidia8_180  # CLAUDE.local.md(给 Claude)
./remote-codex.sh  codex  nvidia8_180         # 终端 A: Codex
./remote-claude.sh claude nvidia8_180         # 终端 B: Claude Code
```

> ⚠️ 卸载需协调：任一方 `umount` 后两者都不可访问。同时编辑同一文件可能冲突。

## 常见问题

### /dev/fuse: No such file or directory

```bash
sudo modprobe fuse
sudo apt install fuse3
```

### fusermount: failed to open mountpoint

```bash
sudo usermod -aG fuse $USER
# 然后重新登录
```

### 挂载后文件操作很慢

SSHFS 适合编辑代码,不适合大量文件操作。搜索文件建议用 `rg` 直接搜索本地挂载点。

### SSHFS 断连后无法操作

```bash
./remote-codex.sh umount robot1   # 先强制卸载
./remote-codex.sh mount robot1    # 重新挂载
```

### 挂载失败排查

```bash
# 1. 测试 SSH 连接
ssh Nvidia-105-wlan

# 2. 测试远程目录是否存在
ssh Nvidia-105-wlan "ls -d /home/nvidia/atom"

# 3. 查看状态
./remote-codex.sh status nvidia8_180
```

## 与 VS Code Remote 的区别

| 特性 | VS Code Remote SSH | 本方案(SSHFS + Codex) |
|------|-------------------|----------------------|
| 远程安装 | 需要 VS Code Server | 不需要(仅 SSH) |
| 文件编辑 | 远程 | 通过 SSHFS 本地透传 |
| 命令执行 | 远程 | 通过 SSH(需 AGENTS.md) |
| 多主机管理 | 配置较繁琐 | hosts.d 一键管理 |
| 延迟 | 低 | 稍高(网络文件系统) |
