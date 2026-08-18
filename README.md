# AI 多主机远程开发工具集

通过 **SSHFS** 将多台远程电脑的目录挂载到本地，在本地运行 **Claude Code** / **Codex** 编辑远程代码，命令则通过 **SSH** 在远程执行。

> 远程电脑**无需安装任何 AI 工具**，只需要开启 SSH 服务。

本仓库包含两套对称工具，可单独使用，也可对同一台远程机器**同时使用**：

| 工具 | 路径 | 本地 AI 工具 | 指令文件 |
|------|------|-------------|---------|
| claude-ssh | [`Claude/claude-ssh/`](Claude/claude-ssh/) | Claude Code | `CLAUDE.local.md` |
| codex-ssh | [`Codex/codex-ssh/`](Codex/codex-ssh/) | Codex CLI | `AGENTS.md` |

---

## 方案原理

```text
本地电脑
┌──────────────────────────────────────────────────────────┐
│  remote-claude.sh / remote-codex.sh (多主机管理器)        │
│                                                           │
│  hosts.d/robot31_94.conf  ──> SSHFS ──> 机器人1 (31.94)  │
│  hosts.d/robot31_105.conf ──> SSHFS ──> 机器人2 (31.105) │
│  hosts.d/gpu-box.conf     ──> SSHFS ──> GPU 服务器        │
│                                                           │
│  Claude Code / Codex ──> 本地挂载点 ──> 编辑远程文件       │
│                      └─> ssh 别名   ──> 执行远程命令       │
└──────────────────────────────────────────────────────────┘
```

- **文件编辑**：AI 工具通过 SSHFS 直接读写远程文件（透明同步）
- **命令执行**：AI 工具通过 SSH 在远程执行编译、测试等命令（由指令文件告知）
- **多主机**：每台远程电脑一个独立 `.conf` 配置文件，互不干扰
- **远程零安装**：远程电脑只需 SSH 服务

---

## 目录结构

```text
AI_Code/
├── README.md                     # 本文档（项目总览）
├── Claude/
│   └── claude-ssh/
│       ├── remote-claude.sh      # Claude Code 多主机管理入口
│       ├── CLAUDE-template.md    # CLAUDE.local.md 模板
│       ├── README.md             # claude-ssh 详细文档
│       └── hosts.d/              # 主机配置目录（每台一个 .conf）
├── Codex/
│   └── codex-ssh/
│       ├── remote-codex.sh       # Codex 多主机管理入口
│       ├── AGENTS-template.md    # AGENTS.md 模板
│       ├── README.md             # codex-ssh 详细文档
│       └── hosts.d/              # 主机配置目录（每台一个 .conf）
└── (远程项目实际挂在 ~/remote/<别名>/ 下)
```

---

## 前置条件

本地电脑需要安装 **sshfs**：

```bash
sudo apt update
sudo apt install sshfs
sudo modprobe fuse          # 若 /dev/fuse 不存在
```

验证：

```bash
sshfs --version
ls /dev/fuse
claude --version            # 用 claude-ssh 时需要
codex --version             # 用 codex-ssh 时需要
```

远程电脑只需要开启 SSH 服务：

```bash
sudo apt install openssh-server && systemctl enable --now ssh
```

---

## 快速开始

### 用 Claude Code（claude-ssh）

```bash
cd ~/Documents/AI_Code/Claude/claude-ssh

./remote-claude.sh add robot31_94          # 1. 交互式添加主机
./remote-claude.sh setup-ssh robot31_94    # 2. 配置 SSH 免密（首次，需输一次远程密码）
./remote-claude.sh mount robot31_94        # 3. 挂载远程目录
./remote-claude.sh gen-claude-md robot31_94 # 4. 生成 CLAUDE.local.md（告知远程命令执行方式）
./remote-claude.sh claude robot31_94       # 5. 启动 Claude Code 编辑远程代码
./remote-claude.sh umount robot31_94       # 用完卸载
```

### 用 Codex（codex-ssh）

```bash
cd ~/Documents/AI_Code/Codex/codex-ssh

./remote-codex.sh add robot31_94           # 1. 交互式添加主机
./remote-codex.sh setup-ssh robot31_94     # 2. 配置 SSH 免密（首次，需输一次远程密码）
./remote-codex.sh mount robot31_94         # 3. 挂载远程目录
./remote-codex.sh gen-agents robot31_94    # 4. 生成 AGENTS.md（告知远程命令执行方式）
./remote-codex.sh codex robot31_94         # 5. 启动 Codex 编辑远程代码
./remote-codex.sh umount robot31_94        # 用完卸载
```

---

## 核心特性：双工具共享同一挂载点

两套工具对同一台机器**共享同一个本地挂载点** `~/remote/<别名>/`，因此可对同一远程目录同时使用 Claude 和 Codex，互不干扰。

- **挂载一次共用**：SSHFS 一个挂载点只能挂一次，用任一工具 `mount` 即可，另一工具检测到已挂载会自动复用。
- **指令文件共存**：Claude 读 `CLAUDE.local.md`、Codex 读 `AGENTS.md`，两个文件共存于挂载点，互不影响。
- **远程命令共用同一 SSH 别名**：均通过 `ssh <别名> "cd <远程目录> && <命令>"` 执行。
- **复用免密**：claude-ssh 支持 `SSH_ALIAS` 字段直接复用 codex-ssh 已配好的免密别名，免密只需在 codex 配一次。

同时使用流程：

```bash
# 1. 挂载一次（任一工具即可，二者挂载点相同）
./remote-claude.sh mount robot31_94

# 2. 生成两个指令文件（各自生成，共存于同一挂载点）
./remote-claude.sh gen-claude-md robot31_94    # CLAUDE.local.md（给 Claude）
./remote-codex.sh  gen-agents     robot31_94   # AGENTS.md（给 Codex）

# 3. 不同终端分别启动，可同时运行
./remote-claude.sh claude robot31_94           # 终端 A: Claude Code
./remote-codex.sh  codex  robot31_94           # 终端 B: Codex
```

> ⚠️ **卸载需协调**：任一方 `umount` 后，两个工具都不可访问该目录，需重新 `mount`。
> ⚠️ 同时编辑同一文件可能冲突，建议两个工具分工不同文件，或先后编辑。

---

## 命令速查

两套工具命令几乎一一对应（仅「启动」与「生成指令文件」命令名不同）：

| 操作 | claude-ssh | codex-ssh |
|------|-----------|-----------|
| 列出所有主机 | `list` / `ls` | `list` / `ls` |
| 添加主机 | `add <别名>` | `add <别名>` |
| 挂载远程目录 | `mount <别名>` / `m` | `mount <别名>` / `m` |
| 卸载 | `umount <别名>` / `u` | `umount <别名>` / `u` |
| 启动 AI 工具 | `claude <别名> [-y]` / `c` | `codex <别名>` / `c` |
| 查看状态 | `status [别名]` / `st` | `status [别名]` / `st` |
| 生成指令文件 | `gen-claude-md <别名>` | `gen-agents <别名>` |
| 删除主机配置 | `remove <别名>` / `rm` | `remove <别名>` / `rm` |
| SSH 免密登录 | `setup-ssh <别名>` | `setup-ssh <别名>` |
| 挂载全部 | `mount-all` | `mount-all` |
| 卸载全部 | `umount-all` | `umount-all` |
| 帮助 | `help` | `help` |

---

## 配置字段说明

每台主机对应 `hosts.d/<别名>.conf` 一个文件（文件名即别名）。两套工具字段基本一致，仅权限相关字段不同：

| 字段 | claude-ssh | codex-ssh | 说明 |
|------|-----------|-----------|------|
| `REMOTE_USER` | ✅ | ✅ | SSH 用户名（必填） |
| `REMOTE_HOST` | ✅ | ✅ | IP 或域名（必填） |
| `REMOTE_DIR` | ✅ | ✅ | 远程项目目录，绝对路径（必填） |
| `LOCAL_MOUNT` | ✅ | ✅ | 本地挂载点，每台不同，两工具共享（必填） |
| `SSH_PORT` | ✅ | ✅ | SSH 端口，默认 22 |
| `SSH_ALIAS` | ✅ | — | 复用已有 SSH 免密别名 |
| `SKIP_PERMISSIONS` | ✅ | — | `no` 询问权限 / `yes` 跳过权限 |
| `SANDBOX_MODE` | — | ✅ | `workspace-write` / `danger-full-access` |

---

## 与 VS Code Remote 的对比

| 特性 | VS Code Remote SSH | 本工具集 |
|------|-------------------|---------|
| 远程安装 | 需要 VS Code Server | 不需要（仅 SSH） |
| 本地 AI 工具 | — | Claude Code / Codex |
| 文件编辑 | 远程 | SSHFS 本地透传 |
| 命令执行 | 远程 | SSH（需指令文件告知） |
| 多主机管理 | 配置较繁琐 | hosts.d 一键管理 |
| 双 AI 工具共用 | — | ✅ 共享挂载点、复用免密 |
| 延迟 | 低 | 稍高（网络文件系统） |

---

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
./remote-claude.sh umount robot31_94   # 先强制卸载（codex 同理）
./remote-claude.sh mount robot31_94    # 重新挂载
```

### AI 工具执行命令时报错或卡住

- 确认已运行 `gen-claude-md` / `gen-agents` 生成指令文件
- 确认 SSH 免密可用：`ssh <别名> echo ok` 应无需密码即返回
- Claude 若权限询问频繁，用 `-y` 或设 `SKIP_PERMISSIONS="yes"`；Codex 若沙箱阻止 SSH，将 `SANDBOX_MODE` 改为 `danger-full-access`

---

## 详细文档

- [claude-ssh 使用文档](Claude/claude-ssh/README.md)
- [codex-ssh 使用文档](Codex/codex-ssh/README.md)
- [claude-ssh 主机配置说明](Claude/claude-ssh/hosts.d/README.md)
- [codex-ssh 主机配置说明](Codex/codex-ssh/hosts.d/README.md)
