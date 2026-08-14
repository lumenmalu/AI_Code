# hosts.d 配置目录说明

每个远程主机对应一个 `.conf` 文件，文件名(去掉后缀)即主机别名。

## 快速新增一台主机

方式一(推荐): 用脚本交互式添加

```bash
./remote-claude.sh add robot2
```

方式二: 复制现有配置后手动修改

```bash
cp robot31_94.conf robot2.conf
# 编辑 robot2.conf,修改用户名、IP、目录、挂载点
```

## 配置字段

| 字段 | 必填 | 说明 |
|------|------|------|
| `REMOTE_USER`      | 是 | SSH 用户名 |
| `REMOTE_HOST`      | 是 | IP 地址或域名 |
| `REMOTE_DIR`       | 是 | 远程项目目录(绝对路径) |
| `LOCAL_MOUNT`      | 是 | 本地挂载点,每台主机应不同 |
| `SSH_PORT`         | 否 | SSH 端口,默认 22 |
| `SSH_ALIAS`        | 否 | 复用已有的 SSH 别名(如 codex 配置的 robot31_94),留空则本工具生成 claude_\<别名\> |
| `SKIP_PERMISSIONS` | 否 | `no`(默认,询问权限) 或 `yes`(跳过权限,用 --dangerously-skip-permissions) |

## 复用已有免密配置(推荐)

如果某台机器已经用 codex-ssh 或其他方式配过 SSH 免密，直接在 conf 里设：

```bash
SSH_ALIAS="robot31_94"   # 指向 ~/.ssh/config 中已有的别名
```

这样无需再运行 setup-ssh，开机即可挂载。

## 典型场景

多台机器人/服务器，每台对应一个项目：

```text
hosts.d/
├── robot31_94.conf     # 192.168.31.94 机器人主控(复用 codex 免密)
├── robot31_105.conf    # 192.168.31.105 机器人从机
├── gpu-box.conf        # 192.168.1.50  GPU 训练服务器
└── dev-server.conf     # dev.example.com 开发服务器
```

使用：

```bash
./remote-claude.sh mount robot31_94      # 挂载机器人1
./remote-claude.sh gen-claude-md robot31_94  # 生成 CLAUDE.md
./remote-claude.sh claude robot31_94     # 编辑机器人1代码
./remote-claude.sh mount-all             # 一次挂载全部
./remote-claude.sh status                # 查看全部状态
```
