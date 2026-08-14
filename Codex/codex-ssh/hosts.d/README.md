# hosts.d 配置目录说明

每个远程主机对应一个 `.conf` 文件,文件名(去掉后缀)即主机别名。

## 快速新增一台主机

方式一(推荐): 用脚本交互式添加

```bash
./remote-codex.sh add robot2
```

方式二: 复制现有配置后手动修改

```bash
cp robot1.conf robot2.conf
# 编辑 robot2.conf,修改用户名、IP、目录、挂载点
```

## 配置字段

| 字段 | 必填 | 说明 |
|------|------|------|
| `REMOTE_USER`  | 是 | SSH 用户名 |
| `REMOTE_HOST`  | 是 | IP 地址或域名 |
| `REMOTE_DIR`   | 是 | 远程项目目录(绝对路径) |
| `LOCAL_MOUNT`  | 是 | 本地挂载点,每台主机应不同 |
| `SSH_PORT`     | 否 | SSH 端口,默认 22 |
| `SANDBOX_MODE` | 否 | `workspace-write`(默认) 或 `danger-full-access` |

## 典型场景

多台机器人/服务器,每台对应一个项目:

```text
hosts.d/
├── robot1.conf     # 192.168.31.94 机器人主控
├── robot2.conf     # 192.168.31.95 机器人从机
├── gpu-box.conf    # 192.168.1.50  GPU 训练服务器
└── dev-server.conf # dev.example.com 开发服务器
```

使用:

```bash
./remote-codex.sh mount robot1      # 挂载机器人1
./remote-codex.sh mount gpu-box     # 挂载 GPU 服务器
./remote-codex.sh codex robot1      # 编辑机器人1代码
./remote-codex.sh mount-all         # 一次挂载全部
./remote-codex.sh status            # 查看全部状态
```
