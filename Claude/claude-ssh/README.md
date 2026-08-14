# Claude Code 多主机远程开发管理工具

通过 SSHFS 将多台远程电脑的不同目录挂载到本地，在本地运行 Claude Code 编辑远程代码。
**远程电脑不需要安装 Claude，只需要开启 SSH 服务。**

本方案仿照 `codex-ssh` 实现，并针对 Claude Code 做了适配（用 `CLAUDE.md` 替代 `AGENTS.md`，支持复用已有 SSH 免密别名）。

## 方案原理

```text
本地电脑
┌──────────────────────────────────────────────────┐
│  remote-claude.sh (多主机管理器)                  │
│                                                   │
│  hosts.d/robot31_94.conf ─> SSHFS ─> 机器人1      │
│  hosts.d/robot31_105.conf > SSHFS ─> 机器人2      │
│  hosts.d/gpu-box.conf ────> SSHFS ─> GPU 服务器    │
│                                                   │
│  Claude Code ─> 本地挂载点 ─> 编辑远程文件         │
│             └─> ssh 别名   ─> 执行远程命令          │
└──────────────────────────────────────────────────┘
```

- **文件编辑**：Claude 通过 SSHFS 直接读写远程文件（透明同步）
- **命令执行**：Claude 通过 SSH 在远程执行编译、测试等命令（通过 `CLAUDE.md` 告知）
- **多主机**：每台远程电脑一个独立配置文件，互不干扰
- **远程零安装**：远程电脑只需 SSH 服务

## 目录结构

```text
claude-ssh/
├── remote-claude.sh        # 主脚本(多主机管理入口)
├── CLAUDE-template.md      # CLAUDE.md 模板(自动填充)
├── README.md               # 本文档
└── hosts.d/                # 主机配置目录
    ├── README.md           # 配置说明
    ├── robot31_94.conf     # 示例: 192.168.31.94(复用 codex 免密)
    └── ...                 # 每台主机一个 .conf 文件
```

## 前置条件

本地电脑需要：

```bash
sudo apt update
sudo apt install sshfs
sudo modprobe fuse          # 若 /dev/fuse 不存在
```

验证：

```bash
sshfs --version
ls /dev/fuse
claude --version            # Claude Code 已安装
```

远程电脑只需要：开启 SSH 服务（`sudo apt install openssh-server && systemctl enable --now ssh`）。

## 快速开始

### 第一步: 添加主机

交互式添加（推荐）：

```bash
cd ~/Documents/AI_Code/Claude/claude-ssh
./remote-claude.sh add robot31_105
```

按提示输入：

```text
SSH 用户名: pnd-humanoid
IP 地址或域名: 192.168.31.105
SSH 端口 [22]: (回车默认)
远程项目目录(绝对路径): /home/pnd-humanoid/Documents/test/luchuang/test_lu
本地挂载点 [~/remote/robot31_105]: (回车默认)
复用的 SSH 别名(留空跳过): (若有 codex 配的别名可填,否则留空)
权限模式选择 [1]: (回车默认询问模式)
```

也可以直接复制示例配置：

```bash
cp hosts.d/robot31_94.conf hosts.d/robot31_105.conf
# 编辑 robot31_105.conf 修改 IP/目录/挂载点
```

### 第二步: 设置 SSH 免密登录(新机器需要)

```bash
./remote-claude.sh setup-ssh robot31_105
```

该命令会自动：

1. 生成独立密钥 `~/.ssh/claude_robot31_105_key`
2. 将公钥复制到远程（需要输入一次远程密码）
3. 在 `~/.ssh/config` 中添加别名 `claude_robot31_105`

> **复用 codex 免密（免配置）**：如果该机器已用 codex-ssh 配过免密，只需在 conf 里设 `SSH_ALIAS="robot31_94"`（对应的别名），即可跳过本步。本仓库自带的 `robot31_94.conf` 已这样配置。

### 第三步: 日常使用

```bash
cd ~/Documents/AI_Code/Claude/claude-ssh
./remote-claude.sh mount robot31_94            # 挂载远程目录
./remote-claude.sh gen-claude-md robot31_94    # 生成 CLAUDE.md(让 Claude 知道如何远程执行命令)
./remote-claude.sh claude robot31_94           # 启动 Claude Code 编辑远程代码
./remote-claude.sh claude robot31_94 -y        # 同上,但跳过权限询问(更流畅)
./remote-claude.sh status                      # 查看所有主机状态
./remote-claude.sh umount robot31_94           # 用完后卸载
```

```bash
./remote-claude.sh add robot31_105             # 交互式添加
./remote-claude.sh setup-ssh robot31_105       # 输入一次该机器的远程密码(配免密)
./remote-claude.sh mount robot31_105 && ./remote-claude.sh gen-claude-md robot31_105
./remote-claude.sh claude robot31_105

# robot31_105 双工具使用(挂载一次,两个指令文件,分别启动)
./remote-claude.sh mount robot31_105
./remote-claude.sh gen-claude-md robot31_105   # CLAUDE.md
./remote-codex.sh  gen-agents     robot31_105   # AGENTS.md
./remote-claude.sh claude robot31_105           # 终端 A
./remote-codex.sh  codex  robot31_105           # 终端 B
```



## 命令速查

| 命令 | 缩写 | 说明 |
|------|------|------|
| `list` | `ls` | 列出所有主机 |
| `add <别名>` | - | 交互式添加主机 |
| `mount <别名>` | `m` | 挂载远程目录 |
| `umount <别名>` | `u` | 卸载 |
| `claude <别名> [-y]` | `c` | 启动 Claude Code（-y 跳过权限） |
| `status [别名]` | `st` | 查看状态 |
| `gen-claude-md <别名>` | - | 生成 CLAUDE.local.md（不覆盖项目 CLAUDE.md） |
| `remove <别名>` | `rm` | 删除主机配置 |
| `setup-ssh <别名>` | - | SSH 免密登录 |
| `mount-all` | - | 挂载全部 |
| `umount-all` | - | 卸载全部 |
| `help` | - | 帮助 |

## 多主机典型场景

三台远程电脑，三个不同项目目录：

```bash
# 添加三台主机
./remote-claude.sh add robot1      # 192.168.31.94 主控
./remote-claude.sh add robot2      # 192.168.31.95 从机
./remote-claude.sh add gpu-box     # 192.168.1.50  GPU 服务器

# 查看所有主机状态
./remote-claude.sh list

# 一次挂载全部
./remote-claude.sh mount-all

# 分别编辑不同主机的代码
./remote-claude.sh claude robot1
./remote-claude.sh claude gpu-box

# 用完后一次卸载
./remote-claude.sh umount-all
```

## 配置字段说明

每个 `hosts.d/<别名>.conf` 文件包含：

```bash
REMOTE_USER="用户名"                  # SSH 用户名(必填)
REMOTE_HOST="IP或域名"                # 远程地址(必填)
SSH_PORT="22"                         # SSH 端口(可选,默认22)
REMOTE_DIR="/远程/项目/路径"          # 远程项目目录(必填,绝对路径)
LOCAL_MOUNT="$HOME/remote/别名" # 本地挂载点(必填,每台不同;与 codex-ssh 共享)
SSH_ALIAS="robot31_94"                # 复用已有 SSH 别名(可选,留空则生成 claude_别名)
SKIP_PERMISSIONS="no"                 # 权限模式(可选,no=询问/yes=跳过)
```

### SSH 别名策略（关键）

| 场景 | 配置 | 效果 |
|------|------|------|
| 复用 codex 已配免密 | `SSH_ALIAS="robot31_94"` | 直接用，无需 setup-ssh |
| 本工具独立免密 | `SSH_ALIAS=""` + `setup-ssh` | 生成 `claude_<别名>` 别名与密钥 |
| 用密码登录 | `SSH_ALIAS=""`，不 setup-ssh | 挂载时输密码（不推荐，SSHFS 体验差） |

### 权限模式

- `SKIP_PERMISSIONS="no"`（默认）：Claude 执行每条命令前询问，更安全
- `SKIP_PERMISSIONS="yes"`：跳过所有权限检查（`--dangerously-skip-permissions`），适合受信任的局域网机器，体验更流畅
- 也可启动时临时加 `-y`：`./remote-claude.sh claude robot1 -y`

## 远程命令执行原理

Claude Code 启动时会自动加载工作目录下的 `CLAUDE.md` 与 `CLAUDE.local.md`。`gen-claude-md` 把远程开发说明写入 **`CLAUDE.local.md`**（而非 `CLAUDE.md`），明确告诉 Claude：

1. 文件操作直接在本地进行（通过 SSHFS 同步）
2. 所有命令必须用 `ssh <别名> "cd <远程目录> && <命令>"` 包裹
3. 远程路径与本地路径的区分

### 为什么不覆盖 CLAUDE.md

你的项目 `CLAUDE.md`（手写或 `/init` 生成的项目规则）**永远不会被本工具改动**，远程开发说明单独写在 `CLAUDE.local.md`：

| 文件 | 用途 | 来源 |
|------|------|------|
| `CLAUDE.md` | 项目规则（架构、构建、规范） | `/init` 生成 / 手写 / 团队共享，进 git |
| `CLAUDE.local.md` | 远程开发说明（SSHFS + SSH 命令） | 本工具 `gen-claude-md` 生成，项目本地，通常不进 git |

Claude Code 会自动合并加载两者。`gen-claude-md` 用**标记段**（`<!-- >>> remote-claude-ssh >>>` … `<!-- <<< remote-claude-ssh <<<`）管理 `CLAUDE.local.md` 中属于本工具的部分，重复运行只更新标记段，绝不覆盖标记段之外你写的内容。

## 与 codex-ssh 共享挂载点（同时使用 Claude 和 Codex）

本方案与 `codex-ssh` **共享同一个本地挂载点** `~/remote/<别名>/`，可同时对同一台远程电脑、同一远程目录使用 Claude 和 Codex，互不干扰。

- **挂载点共享**：两者 `LOCAL_MOUNT` 都指向 `~/remote/<别名>/`。SSHFS 一个挂载点只能挂一次，因此**挂载一次即可共用**——用任一工具的 `mount`，另一工具检测到已挂载会自动复用，不会重复挂载。
- **指令文件共存**：Claude 读 `CLAUDE.md`、Codex 读 `AGENTS.md`，两个文件可同时存在于挂载点，互不干扰。
- **远程命令共用同一 SSH 别名**：均通过 `ssh <别名> "cd <远程目录> && <命令>"` 执行。

同时使用流程：

```bash
# 1. 挂载一次(用 claude 或 codex 任一即可,二者挂载点相同)
./remote-claude.sh mount robot31_94

# 2. 生成两个指令文件(各自生成,共存于同一挂载点)
./remote-claude.sh gen-claude-md robot31_94    # 生成 CLAUDE.md(给 Claude)
./remote-codex.sh  gen-agents     robot31_94    # 生成 AGENTS.md(给 Codex)

# 3. 不同终端分别启动,可同时运行
./remote-claude.sh claude robot31_94            # 终端 A: Claude Code
./remote-codex.sh  codex  robot31_94            # 终端 B: Codex
```

> ⚠️ **卸载需协调**：任一方 `umount` 后，两个工具都不可访问该目录，需重新 `mount`。
> ⚠️ 同时编辑同一文件可能冲突，建议两个工具分工不同文件，或先后编辑。

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

SSHFS 适合编辑代码，不适合大量文件操作。搜索文件建议用 `rg` / Grep 直接搜索本地挂载点。

### SSHFS 断连后无法操作

```bash
./remote-claude.sh umount robot31_94   # 先强制卸载
./remote-claude.sh mount robot31_94    # 重新挂载
```

### 挂载失败排查

```bash
# 1. 测试 SSH 连接(远程需在线)
ssh robot31_94            # 或 ssh claude_robot31_94 / ssh 用户@IP

# 2. 测试远程目录是否存在
ssh robot31_94 "ls -d /远程/项目/路径"

# 3. 查看状态
./remote-claude.sh status robot31_94
```

### Claude 执行命令时报错或卡住

- 确认已运行 `gen-claude-md` 生成了 `CLAUDE.md`
- 若权限询问频繁，用 `-y` 或设 `SKIP_PERMISSIONS="yes"`
- 确认 SSH 免密可用：`ssh <别名> echo ok` 应无需密码即返回

## 与 VS Code Remote / codex-ssh 的区别

| 特性 | VS Code Remote SSH | codex-ssh | 本方案(claude-ssh) |
|------|-------------------|-----------|-------------------|
| 远程安装 | 需要 VS Code Server | 不需要(仅 SSH) | 不需要(仅 SSH) |
| 本地 AI 工具 | - | Codex CLI | Claude Code |
| 指令文件 | - | AGENTS.md | CLAUDE.md |
| 文件编辑 | 远程 | SSHFS 本地透传 | SSHFS 本地透传 |
| 命令执行 | 远程 | SSH(需 AGENTS.md) | SSH(需 CLAUDE.md) |
| 多主机管理 | 配置较繁琐 | hosts.d 一键管理 | hosts.d 一键管理 |
| 复用免密 | - | - | ✅ 支持 SSH_ALIAS 复用 |
