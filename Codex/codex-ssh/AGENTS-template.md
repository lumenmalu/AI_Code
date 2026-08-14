# AGENTS.md - 远程开发配置

## 远程开发环境说明

当前工作目录通过 SSHFS 挂载到远程服务器。

- 主机别名: {{ALIAS}}
- 远程主机: {{REMOTE_HOST}}
- SSH 用户: {{REMOTE_USER}}
- 远程目录: {{REMOTE_DIR}}
- 文件编辑: 直接编辑,通过 SSHFS 透明同步到远程
- 命令执行: 必须通过 SSH 在远程执行

## 命令执行规则

所有需要运行的命令(编译、测试、安装依赖等)必须通过 SSH 在远程执行:

```
ssh {{ALIAS}} "cd {{REMOTE_DIR}} && <你的命令>"
```

示例:
- 查看文件: `ssh {{ALIAS}} "ls -la {{REMOTE_DIR}}"`
- 安装依赖: `ssh {{ALIAS}} "cd {{REMOTE_DIR}} && npm install"`
- 运行测试: `ssh {{ALIAS}} "cd {{REMOTE_DIR}} && npm test"`
- 编译项目: `ssh {{ALIAS}} "cd {{REMOTE_DIR}} && make"`

注意:
1. 文件读取和编辑可以直接进行(通过 SSHFS 挂载)
2. 只有命令执行需要通过 SSH
3. 使用 rg 搜索文件时直接搜索本地挂载点,速度更快
