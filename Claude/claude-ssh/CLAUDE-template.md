# CLAUDE.md - 远程开发配置

## ⚠️ 重要：当前是 SSHFS 远程挂载环境

当前工作目录通过 SSHFS 挂载到远程服务器 {{REMOTE_HOST}}。
**文件操作在本地进行（自动同步到远程），但所有命令执行必须在远程通过 SSH 进行**，否则会在本地（错误的机器、没有远程环境）执行。

## 远程环境信息

- SSH 连接目标: {{ALIAS}}
- 远程主机: {{REMOTE_USER}}@{{REMOTE_HOST}}:{{SSH_PORT}}
- 远程项目目录: {{REMOTE_DIR}}
- 本地挂载点(即当前工作目录): {{LOCAL_MOUNT}}

## 核心规则

### 1. 文件操作 → 直接在本地进行（通过 SSHFS 自动同步到远程）

- 读取文件：用 Read 工具，路径用本地挂载点下的路径
- 编辑/创建文件：用 Edit/Write 工具，直接编辑（自动同步到远程）
- 搜索文件：用 Grep/Glob 工具直接搜索本地挂载点目录（速度快）

### 2. 命令执行 → 必须通过 SSH 在远程执行

本地没有远程的运行环境（依赖、编译器、Python 虚拟环境等），所有 Bash 命令都必须用 SSH 包裹：

    ssh {{ALIAS}} "cd {{REMOTE_DIR}} && <你的命令>"

示例：
- 查看目录: `ssh {{ALIAS}} "ls -la {{REMOTE_DIR}}"`
- 查看当前路径: `ssh {{ALIAS}} "pwd"`
- 查看环境: `ssh {{ALIAS}} "python3 --version && which python3"`
- 安装依赖: `ssh {{ALIAS}} "cd {{REMOTE_DIR}} && pip install -r requirements.txt"`
- 运行测试: `ssh {{ALIAS}} "cd {{REMOTE_DIR}} && python -m pytest"`
- 编译项目: `ssh {{ALIAS}} "cd {{REMOTE_DIR}} && make"`
- 查看进程: `ssh {{ALIAS}} "ps aux | grep python"`
- 查看端口: `ssh {{ALIAS}} "ss -tlnp"`

### 3. 路径规则（易错，务必区分）

| 操作类型 | 使用的路径 |
|---------|-----------|
| 文件工具（Read/Edit/Write/Grep/Glob） | 本地挂载点路径 {{LOCAL_MOUNT}} |
| 命令执行（ssh 内的命令） | 远程路径 {{REMOTE_DIR}} |

## 禁止事项

1. ❌ 不要在本地直接运行编译/测试/运行命令（本地没有远程环境与依赖）
2. ❌ 不要用本地路径作为 ssh 命令的工作目录（远程命令必须 `cd {{REMOTE_DIR}}`）
3. ❌ 不要尝试在远程电脑安装 Claude（本方案的设计就是远程只跑 SSH 服务）

## 建议工作流程

1. 先了解远程目录结构: `ssh {{ALIAS}} "ls -la {{REMOTE_DIR}}"`
2. 读取/编辑文件直接用本地工具（速度快，通过 SSHFS 透明同步）
3. 任何需要执行的命令，统一用 `ssh {{ALIAS}} "cd {{REMOTE_DIR}} && <命令>"` 包裹
4. 运行长时间任务时，可在 ssh 命令末尾加 `&` 或使用 nohup，避免阻塞
