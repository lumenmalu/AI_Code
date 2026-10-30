#!/usr/bin/env bash
#
# remote-claude.sh - 多主机远程 Claude Code 开发管理工具
#
# 通过 SSHFS 将多台远程电脑的目录挂载到本地,在本地运行 Claude Code 编辑远程代码。
# 远程电脑不需要安装 Claude,只需要开启 SSH 服务。
# 每台远程电脑使用独立的配置文件管理,支持不同目录、不同用户、不同端口。
#
# 用法见 ./remote-claude.sh help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="${SCRIPT_DIR}/hosts.d"
CLAUDE_TEMPLATE="${SCRIPT_DIR}/CLAUDE-template.md"
DEFAULT_MOUNT_BASE="$HOME/remote"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

msg_ok()   { echo -e "${GREEN}[OK]${NC}     $*"; }
msg_err()  { echo -e "${RED}[ERROR]${NC}  $*"; }
msg_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
msg_info() { echo -e "${BLUE}[INFO]${NC}   $*"; }

check_sshfs() {
    if ! command -v sshfs &>/dev/null; then
        msg_err "sshfs 未安装"
        echo "  请运行: sudo apt install sshfs"
        echo "  安装后可能需要: sudo modprobe fuse"
        exit 1
    fi
}

ensure_conf_dir() { mkdir -p "$CONF_DIR"; }

# 检查 ~/.ssh/config 中是否存在某个 Host 别名
has_ssh_host() {
    local host="$1"
    [[ -z "$host" ]] && return 1
    grep -qE "^Host[[:space:]]+${host}([[:space:]]|$)" "$HOME/.ssh/config" 2>/dev/null
}

# 加载指定主机的配置,变量加载到当前 shell
load_host_config() {
    local alias="$1"
    local conf="${CONF_DIR}/${alias}.conf"
    if [[ ! -f "$conf" ]]; then
        msg_err "主机 '${alias}' 不存在"
        local avail
        avail="$(list_host_aliases)"
        [[ -n "$avail" ]] && echo "  可用主机: $avail"
        return 1
    fi
    # 先置默认值(可选字段)
    REMOTE_USER="" REMOTE_HOST="" REMOTE_DIR="" LOCAL_MOUNT=""
    SSH_PORT="22" SSH_ALIAS="" SKIP_PERMISSIONS="no"
    # shellcheck disable=SC1090
    source "$conf"
    local ok=1
    [[ -n "$REMOTE_USER" && -n "$REMOTE_HOST" && -n "$REMOTE_DIR" && -n "$LOCAL_MOUNT" ]] && ok=0
    if [[ $ok -ne 0 ]]; then
        msg_err "配置不完整: $conf (需要 REMOTE_USER/REMOTE_HOST/REMOTE_DIR/LOCAL_MOUNT)"
        return 1
    fi
    return 0
}

# 解析实际使用的 SSH 别名与挂载目标
# 优先级: SSH_ALIAS(复用已有别名) > claude_<alias>(本工具生成) > user@host(需密码)
# 设置全局变量: USE_ALIAS(可能为空), SSH_TARGET, NEED_PASSWORD(0/1)
resolve_ssh_target() {
    local alias="$1"
    USE_ALIAS=""
    NEED_PASSWORD=0
    if [[ -n "${SSH_ALIAS:-}" ]] && has_ssh_host "$SSH_ALIAS"; then
        USE_ALIAS="$SSH_ALIAS"
        SSH_TARGET="${SSH_ALIAS}:${REMOTE_DIR}"
    elif has_ssh_host "claude_${alias}"; then
        USE_ALIAS="claude_${alias}"
        SSH_TARGET="claude_${alias}:${REMOTE_DIR}"
    else
        USE_ALIAS=""
        SSH_TARGET="${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
        NEED_PASSWORD=1
    fi
}

list_host_aliases() {
    ensure_conf_dir
    local a=()
    local f
    for f in "$CONF_DIR"/*.conf; do
        [[ -f "$f" ]] || continue
        a+=("$(basename "$f" .conf)")
    done
    echo "${a[*]}"
}

is_mounted() { mountpoint -q "$1" 2>/dev/null; }

# list - 列出所有主机
cmd_list() {
    ensure_conf_dir
    echo -e "${BOLD}已配置的远程主机:${NC}"
    echo ""
    local found=0
    local f
    for f in "$CONF_DIR"/*.conf; do
        [[ -f "$f" ]] || continue
        local alias status_icon
        alias="$(basename "$f" .conf)"
        found=1
        REMOTE_USER="" REMOTE_HOST="" REMOTE_DIR="" LOCAL_MOUNT=""
        SSH_PORT="22" SSH_ALIAS="" SKIP_PERMISSIONS="no"
        # shellcheck disable=SC1090
        source "$f" 2>/dev/null || true
        if [[ -n "$LOCAL_MOUNT" ]] && is_mounted "$LOCAL_MOUNT"; then
            status_icon="${GREEN}已挂载${NC}"
        else
            status_icon="${RED}未挂载${NC}"
        fi
        local ssh_info="${SSH_ALIAS:-${REMOTE_USER:-?}@${REMOTE_HOST:-?}}"
        printf "  ${CYAN}%-14s${NC}  %s:%s  [%b]\n" \
            "$alias" "$ssh_info" "${REMOTE_DIR:-?}" "$status_icon"
    done
    if [[ $found -eq 0 ]]; then
        echo "  (暂无主机配置)"
        echo ""
        echo "  添加第一台主机: ./remote-claude.sh add <别名>"
    fi
    echo ""
}

# add - 交互式添加主机
cmd_add() {
    ensure_conf_dir
    local alias="${1:-}"
    if [[ -z "$alias" ]]; then
        read -rp "输入主机别名(英文,如 robot1): " alias
    fi
    if [[ ! "$alias" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        msg_err "别名只能包含字母、数字、下划线和连字符"
        exit 1
    fi
    local conf="${CONF_DIR}/${alias}.conf"
    if [[ -f "$conf" ]]; then
        msg_warn "主机 '${alias}' 已存在"
        read -rp "是否覆盖? (y/N): " overwrite
        [[ "$overwrite" =~ ^[Yy]$ ]] || exit 0
    fi

    echo -e "${BOLD}=== 添加主机: ${alias} ===${NC}"
    echo ""
    local remote_user remote_host remote_dir local_mount ssh_port ssh_alias skip_perm
    read -rp "SSH 用户名: " remote_user
    read -rp "IP 地址或域名: " remote_host
    read -rp "SSH 端口 [22]: " ssh_port
    ssh_port="${ssh_port:-22}"
    read -rp "远程项目目录(绝对路径): " remote_dir
    read -rp "本地挂载点 [${DEFAULT_MOUNT_BASE}/${alias}]: " local_mount
    local_mount="${local_mount:-${DEFAULT_MOUNT_BASE}/${alias}}"

    if [[ -z "$remote_user" || -z "$remote_host" || -z "$remote_dir" ]]; then
        msg_err "SSH 用户名、IP/域名、远程项目目录不能为空"
        exit 1
    fi

    echo ""
    echo "复用已有 SSH 别名(可选):"
    echo "  若该机器已用 codex-ssh 或其他方式配过免密,填写其 SSH 别名可直接复用(免重新配密钥)。"
    echo "  例: ~/.ssh/config 里的 Nvidia-105-wlan 。留空则本工具会单独生成 claude_${alias} 别名。"
    read -rp "复用的 SSH 别名(留空跳过): " ssh_alias

    echo ""
    echo "启动 Claude 时的权限模式:"
    echo "  1) 询问模式(默认,Claude 执行命令前会询问,更安全)"
    echo "  2) 跳过权限(--dangerously-skip-permissions,不再询问,适合受信任的局域网机器)"
    read -rp "选择 [1]: " skip_choice
    case "${skip_choice:-1}" in
        2) skip_perm="yes" ;;
        *) skip_perm="no" ;;
    esac

    cat > "$conf" <<EOF
# 主机配置: ${alias}
# 由 remote-claude.sh add 生成,可手动编辑

REMOTE_USER="${remote_user}"
REMOTE_HOST="${remote_host}"
SSH_PORT="${ssh_port}"
REMOTE_DIR="${remote_dir}"
LOCAL_MOUNT="${local_mount}"
SSH_ALIAS="${ssh_alias}"
SKIP_PERMISSIONS="${skip_perm}"
EOF

    echo ""
    msg_ok "配置已保存: $conf"
    echo ""

    # 若复用了已有别名且该别名已存在,则无需再配密钥
    if [[ -n "$ssh_alias" ]] && has_ssh_host "$ssh_alias"; then
        msg_ok "检测到 SSH 别名 '${ssh_alias}' 已存在,直接复用,无需配置免密"
    else
        read -rp "是否现在设置 SSH 免密登录? (y/N): " setup_ssh
        if [[ "$setup_ssh" =~ ^[Yy]$ ]]; then
            setup_ssh_key "$alias"
        fi
    fi
    echo ""
    echo "下一步:"
    echo "  挂载:   ./remote-claude.sh mount ${alias}"
    echo "  生成说明: ./remote-claude.sh gen-claude-md ${alias}"
    echo "  启动:   ./remote-claude.sh claude ${alias}"
    echo "  状态:   ./remote-claude.sh status ${alias}"
}

# setup-ssh - 为指定主机配置 SSH 密钥认证
setup_ssh_key() {
    local alias="$1"
    load_host_config "$alias" || return 1

    # 情况1: 复用已有别名
    if [[ -n "$SSH_ALIAS" ]]; then
        if has_ssh_host "$SSH_ALIAS"; then
            msg_ok "SSH 别名 '${SSH_ALIAS}' 已存在,直接复用"
            return 0
        else
            msg_err "配置中 SSH_ALIAS='${SSH_ALIAS}',但 ~/.ssh/config 未找到该别名"
            echo "  请先创建该别名(二选一):"
            echo "    1) 在 ~/.ssh/config 中添加 Host ${SSH_ALIAS}(Claude 与 Codex 填同一个别名,免密只配一次)"
            echo "    2) 或清空 ${CONF_DIR}/${alias}.conf 中的 SSH_ALIAS,再运行:"
            echo "         ./remote-claude.sh setup-ssh ${alias}"
            echo "       本工具将独立生成 claude_${alias} 别名"
            return 1
        fi
    fi

    # 情况2: 本工具单独生成 claude_<alias> 别名
    local host_name="claude_${alias}"
    local key_file="$HOME/.ssh/claude_${alias}_key"
    if has_ssh_host "$host_name"; then
        msg_info "SSH 别名 '${host_name}' 已存在,跳过"
        return 0
    fi
    if [[ ! -f "$key_file" ]]; then
        msg_info "生成 SSH 密钥: $key_file"
        ssh-keygen -t ed25519 -f "$key_file" -N "" -q
        msg_ok "密钥已生成"
    else
        msg_info "密钥已存在: $key_file"
    fi
    echo ""
    msg_info "复制公钥到 ${REMOTE_USER}@${REMOTE_HOST} (需要输入一次远程密码)"
    ssh-copy-id -i "${key_file}.pub" -p "${SSH_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" || {
        msg_warn "ssh-copy-id 失败,请手动执行:"
        echo "  ssh-copy-id -i ${key_file}.pub -p ${SSH_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
    }

    local ssh_config="$HOME/.ssh/config"
    local marker="# >>> claude-${alias} >>>"
    local marker_end="# <<< claude-${alias} <<<"
    mkdir -p "$HOME/.ssh"
    touch "$ssh_config"
    if ! grep -qF "$marker" "$ssh_config" 2>/dev/null; then
        msg_info "更新 ~/.ssh/config (添加别名 ${host_name})"
        cat >> "$ssh_config" <<EOF

${marker}
Host ${host_name}
    HostName ${REMOTE_HOST}
    User ${REMOTE_USER}
    Port ${SSH_PORT}
    IdentityFile ${key_file}
    StrictHostKeyChecking no
${marker_end}
EOF
        msg_ok "SSH 配置已更新,挂载与远程命令将使用别名 '${host_name}'"
    else
        msg_info "SSH config 中已有 ${host_name} 的配置"
    fi
}

# mount - 挂载指定主机
cmd_mount() {
    local alias="$1"
    load_host_config "$alias" || exit 1
    check_sshfs
    mkdir -p "$LOCAL_MOUNT"
    if is_mounted "$LOCAL_MOUNT"; then
        msg_info "${alias} 已挂载在 $LOCAL_MOUNT"
        return 0
    fi

    resolve_ssh_target "$alias"
    msg_info "正在挂载 -> $LOCAL_MOUNT"
    msg_info "SSH 目标: $SSH_TARGET"

    local mount_opts=(
        -o reconnect
        -o ServerAliveInterval=15
        -o ServerAliveCountMax=3
        -o follow_symlinks
        -o cache=yes
        -o kernel_cache
        -o compression=yes
        -o noatime
    )
    if [[ "$NEED_PASSWORD" -eq 1 ]]; then
        [[ "$SSH_PORT" != "22" ]] && mount_opts+=(-o "ssh_command=ssh -p ${SSH_PORT}")
        echo "  (未检测到 SSH 免密别名,可能需要输入密码;建议运行: ./remote-claude.sh setup-ssh ${alias})"
    else
        msg_info "使用 SSH 别名 '${USE_ALIAS}' 免密连接"
    fi

    sshfs "$SSH_TARGET" "$LOCAL_MOUNT" "${mount_opts[@]}" 2>&1 | sed 's/^/  /' || true

    if is_mounted "$LOCAL_MOUNT"; then
        echo ""
        msg_ok "挂载成功: ${alias}"
        echo "  远程: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
        echo "  本地: $LOCAL_MOUNT"
        echo "  SSH 别名: ${USE_ALIAS:-（无,使用密码）}"
        echo ""
        echo "  生成远程命令说明: ./remote-claude.sh gen-claude-md ${alias}"
        echo "  启动 Claude:       ./remote-claude.sh claude ${alias}"
    else
        msg_err "挂载失败,请检查:"
        echo "  1. 远程电脑是否开机且 SSH 服务正常(当前可能不在线)"
        echo "  2. 用户名、IP、端口是否正确"
        echo "  3. 远程目录 ${REMOTE_DIR} 是否存在"
        echo "  4. 是否已设置免密(./remote-claude.sh setup-ssh ${alias})"
        echo "  5. 测试连接: ssh ${USE_ALIAS:-${REMOTE_USER}@${REMOTE_HOST}} "
        exit 1
    fi
}

# umount - 卸载指定主机
cmd_umount() {
    local alias="$1"
    load_host_config "$alias" || exit 1
    if ! is_mounted "$LOCAL_MOUNT"; then
        msg_info "${alias} 未挂载"
        return 0
    fi
    msg_info "正在卸载 ${alias} ($LOCAL_MOUNT) ..."
    fusermount -u "$LOCAL_MOUNT" 2>/dev/null || fusermount -uz "$LOCAL_MOUNT"
    msg_ok "已卸载 ${alias}"
}

# claude - 在挂载目录启动 Claude Code
cmd_claude() {
    local alias="$1"
    local skip="${2:-}"
    load_host_config "$alias" || exit 1
    if ! is_mounted "$LOCAL_MOUNT"; then
        msg_err "${alias} 未挂载,先运行: ./remote-claude.sh mount ${alias}"
        exit 1
    fi
    local skip_perm="$SKIP_PERMISSIONS"
    [[ "$skip" == "-y" || "$skip" == "--skip-permissions" ]] && skip_perm="yes"

    echo -e "${BOLD}在 $LOCAL_MOUNT 启动 Claude Code${NC}"
    [[ -f "${LOCAL_MOUNT}/CLAUDE.md" ]] || msg_warn "挂载点未发现 CLAUDE.md,建议先生成: ./remote-claude.sh gen-claude-md ${alias}"

    cd "$LOCAL_MOUNT"
    if [[ "$skip_perm" == "yes" ]]; then
        msg_warn "启用 --dangerously-skip-permissions,Claude 将不再询问命令执行权限"
        claude --dangerously-skip-permissions
    else
        claude
    fi
}

# status - 查看状态(单个或全部)
cmd_status() {
    ensure_conf_dir
    local alias="${1:-}"
    if [[ -n "$alias" ]]; then
        load_host_config "$alias" || exit 1
        resolve_ssh_target "$alias"
        echo -e "${BOLD}=== ${alias} ===${NC}"
        echo "  远程: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR} (端口 ${SSH_PORT})"
        echo "  本地: $LOCAL_MOUNT"
        echo "  SSH 别名: ${USE_ALIAS:-（无,将使用密码）}"
        echo "  跳过权限: ${SKIP_PERMISSIONS}"
        if is_mounted "$LOCAL_MOUNT"; then
            msg_ok "挂载状态: 已挂载"
            echo "  内容:"
            ls "$LOCAL_MOUNT" 2>/dev/null | head -20 | sed 's/^/    /'
        else
            msg_warn "挂载状态: 未挂载"
        fi
        return 0
    fi
    cmd_list
}

# 标记段管理:在 file 中幂等更新一段由 marker 包裹的内容。
# 标记段之外的用户内容原样保留,绝不覆盖。
# 用法: update_marked_section <file> <marker_start> <marker_end> <content_file>
update_marked_section() {
    local file="$1" ms="$2" me="$3" cf="$4"
    local tmp
    tmp=$(mktemp)
    if [[ -f "$file" ]]; then
        # 去掉旧标记段(含两行 marker),保留其余内容
        awk -v ms="$ms" -v me="$me" '
            BEGIN { in_sec = 0 }
            $0 == ms { in_sec = 1; next }
            $0 == me { in_sec = 0; next }
            in_sec { next }
            { print }
        ' "$file" > "$tmp"
    fi
    {
        if [[ -s "$tmp" ]]; then
            cat "$tmp"
            echo ""
        fi
        echo "$ms"
        cat "$cf"
        echo ""
        echo "$me"
    } > "$file"
    rm -f "$tmp"
}

# gen-claude-md - 生成远程开发说明(写入 CLAUDE.local.md,绝不覆盖项目 CLAUDE.md)
cmd_gen_claude_md() {
    local alias="$1"
    load_host_config "$alias" || exit 1
    if ! is_mounted "$LOCAL_MOUNT"; then
        msg_err "${alias} 未挂载,请先挂载: ./remote-claude.sh mount ${alias}"
        exit 1
    fi
    resolve_ssh_target "$alias"
    local ssh_name="${USE_ALIAS:-${REMOTE_USER}@${REMOTE_HOST}}"

    if [[ ! -f "$CLAUDE_TEMPLATE" ]]; then
        msg_err "模板文件不存在: $CLAUDE_TEMPLATE"
        exit 1
    fi

    # 渲染模板到临时文件
    local rendered
    rendered=$(mktemp)
    sed \
        -e "s|{{ALIAS}}|${ssh_name}|g" \
        -e "s|{{REMOTE_HOST}}|${REMOTE_HOST}|g" \
        -e "s|{{REMOTE_USER}}|${REMOTE_USER}|g" \
        -e "s|{{SSH_PORT}}|${SSH_PORT}|g" \
        -e "s|{{REMOTE_DIR}}|${REMOTE_DIR}|g" \
        -e "s|{{LOCAL_MOUNT}}|${LOCAL_MOUNT}|g" \
        "$CLAUDE_TEMPLATE" > "$rendered"

    # 写入 CLAUDE.local.md(项目本地,Claude Code 自动加载,通常不进 git)
    # 采用标记段,绝不覆盖你手写或 /init 生成的 CLAUDE.md
    local target="${LOCAL_MOUNT}/CLAUDE.local.md"
    local ms="<!-- >>> remote-claude-ssh >>>"
    local me="<!-- <<< remote-claude-ssh <<<"
    update_marked_section "$target" "$ms" "$me" "$rendered"
    rm -f "$rendered"

    msg_ok "已更新: $target"
    echo "  -> 标记段方式,绝不覆盖你的 CLAUDE.md(含 /init 生成的项目规则)"
    echo "  -> Claude Code 自动加载 CLAUDE.local.md(项目本地,通常不进 git)"
    echo "  -> 重复运行只更新标记段,安全幂等"
    echo "  -> SSH 别名: ${ssh_name}"

    # 检测旧版(覆盖式)生成的 CLAUDE.md,提示清理以免与项目规则混淆
    local old="${LOCAL_MOUNT}/CLAUDE.md"
    if [[ -f "$old" ]] && grep -qF "SSHFS 远程挂载环境" "$old" 2>/dev/null; then
        msg_warn "检测到 ${old} 是旧版覆盖式生成的远程开发说明"
        read -rp "  是否删除它以避免与项目规则混淆? (y/N): " del
        if [[ "$del" =~ ^[Yy]$ ]]; then
            rm -f "$old"
            msg_ok "已删除旧 ${old}"
        fi
    fi
}

# remove - 删除主机配置
cmd_remove() {
    local alias="$1"
    local conf="${CONF_DIR}/${alias}.conf"
    if [[ ! -f "$conf" ]]; then
        msg_err "主机 '${alias}' 不存在"
        return 1
    fi
    msg_warn "即将删除配置: $conf"
    read -rp "确认删除? (输入 ${alias} 确认): " confirm
    if [[ "$confirm" != "$alias" ]]; then
        msg_info "已取消"
        return 0
    fi
    rm -f "$conf"
    msg_ok "已删除 ${alias}"
    echo "  (SSH 密钥与 ~/.ssh/config 中的别名未删除,如需清理请手动处理)"
}

# mount-all - 挂载所有主机
cmd_mount_all() {
    local aliases
    aliases="$(list_host_aliases)"
    [[ -z "$aliases" ]] && { msg_warn "暂无主机配置"; return 0; }
    local ok=0 fail=0
    for a in $aliases; do
        if cmd_mount "$a"; then ok=$((ok+1)); else fail=$((fail+1)); fi
    done
    msg_info "完成: 成功 ${ok},失败 ${fail}"
}

# umount-all - 卸载所有主机
cmd_umount_all() {
    local aliases
    aliases="$(list_host_aliases)"
    [[ -z "$aliases" ]] && { msg_warn "暂无主机配置"; return 0; }
    for a in $aliases; do
        cmd_umount "$a"
    done
}

# help - 使用说明
cmd_help() {
    cat <<EOF
多主机远程 Claude Code 开发管理工具

通过 SSHFS 把多台远程电脑的目录挂载到本地,在本地运行 Claude Code 编辑远程代码。
远程电脑无需安装 Claude,只需开启 SSH 服务。

用法: $0 <命令> [参数]

命令:
  list                    列出所有已配置主机
  add <别名>              交互式添加新主机
  mount <别名>            挂载指定主机的远程目录
  umount <别名>           卸载指定主机
  claude <别名> [-y]      在挂载目录启动 Claude Code(-y 跳过权限询问)
  status [别名]           查看状态(不指定则查看全部)
  gen-claude-md <别名>    为挂载目录生成 CLAUDE.md(远程命令执行说明)
  remove <别名>           删除主机配置
  setup-ssh <别名>        设置 SSH 密钥免密登录
  mount-all               挂载所有主机
  umount-all              卸载所有主机
  help                    显示本帮助

缩写: list=ls, mount=m, umount=u, claude=c, status=st, remove=rm

配置文件目录: ${CONF_DIR}
每个主机一个 .conf 文件,文件名即主机别名。

示例:
  $0 add robot1                    # 添加主机 robot1
  $0 mount robot1                  # 挂载 robot1
  $0 gen-claude-md robot1          # 生成 CLAUDE.md
  $0 claude robot1                 # 编辑 robot1 的代码
  $0 claude robot1 -y              # 同上,但跳过权限询问
  $0 status                        # 查看所有主机状态
EOF
}

# 主入口
case "${1:-}" in
    list|ls)              cmd_list ;;
    add)                  cmd_add "${2:-}" ;;
    mount|m)              cmd_mount "${2:-}" ;;
    umount|u)             cmd_umount "${2:-}" ;;
    claude|c)             cmd_claude "${2:-}" "${3:-}" ;;
    status|st)            cmd_status "${2:-}" ;;
    gen-claude-md)        cmd_gen_claude_md "${2:-}" ;;
    remove|rm)            cmd_remove "${2:-}" ;;
    setup-ssh)            setup_ssh_key "${2:-}" ;;
    mount-all)            cmd_mount_all ;;
    umount-all)           cmd_umount_all ;;
    help|--help|-h|"")    cmd_help ;;
    *)                    msg_err "未知命令: ${1}"; echo ""; cmd_help; exit 1 ;;
esac
