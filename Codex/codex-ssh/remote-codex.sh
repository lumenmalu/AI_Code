#!/usr/bin/env bash
#
# remote-codex.sh - 多主机远程 Codex 开发管理工具
#
# 通过 SSHFS 将多台远程电脑的目录挂载到本地,在本地运行 Codex 编辑远程代码。
# 每台远程电脑使用独立的配置文件管理,支持不同目录、不同用户、不同端口。
#
# 用法见 ./remote-codex.sh help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="${SCRIPT_DIR}/hosts.d"
AGENTS_TEMPLATE="${SCRIPT_DIR}/AGENTS-template.md"
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
    REMOTE_USER="" REMOTE_HOST="" REMOTE_DIR="" LOCAL_MOUNT=""
    SANDBOX_MODE="workspace-write" SSH_PORT="22"
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
        REMOTE_USER="" REMOTE_HOST="" REMOTE_DIR="" LOCAL_MOUNT="" SANDBOX_MODE="workspace-write" SSH_PORT="22"
        # shellcheck disable=SC1090
        source "$f" 2>/dev/null || true
        if [[ -n "$LOCAL_MOUNT" ]] && is_mounted "$LOCAL_MOUNT"; then
            status_icon="${GREEN}已挂载${NC}"
        else
            status_icon="${RED}未挂载${NC}"
        fi
        printf "  ${CYAN}%-14s${NC}  %s@%s:%s  [%b]\n" \
            "$alias" "${REMOTE_USER:-?}" "${REMOTE_HOST:-?}" "${REMOTE_DIR:-?}" "$status_icon"
    done
    if [[ $found -eq 0 ]]; then
        echo "  (暂无主机配置)"
        echo ""
        echo "  添加第一台主机: ./remote-codex.sh add <别名>"
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
    local remote_user remote_host remote_dir local_mount sandbox_mode ssh_port
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
    echo "沙箱模式:"
    echo "  1) workspace-write     只允许写入工作目录(推荐)"
    echo "  2) danger-full-access  完全访问(需要 SSH 执行远程命令时用)"
    read -rp "选择 [1]: " sandbox_choice
    case "${sandbox_choice:-1}" in
        2) sandbox_mode="danger-full-access" ;;
        *) sandbox_mode="workspace-write" ;;
    esac

    cat > "$conf" <<EOF
# 主机配置: ${alias}
# 由 remote-codex.sh add 生成,可手动编辑

REMOTE_USER="${remote_user}"
REMOTE_HOST="${remote_host}"
SSH_PORT="${ssh_port}"
REMOTE_DIR="${remote_dir}"
LOCAL_MOUNT="${local_mount}"
SANDBOX_MODE="${sandbox_mode}"
EOF

    echo ""
    msg_ok "配置已保存: $conf"
    echo ""
    read -rp "是否现在设置 SSH 免密登录? (y/N): " setup_ssh
    if [[ "$setup_ssh" =~ ^[Yy]$ ]]; then
        setup_ssh_key "$alias"
    fi
    echo ""
    echo "下一步:"
    echo "  挂载:   ./remote-codex.sh mount ${alias}"
    echo "  启动:   ./remote-codex.sh codex ${alias}"
    echo "  状态:   ./remote-codex.sh status ${alias}"
}

# setup-ssh - 为指定主机配置 SSH 密钥认证
setup_ssh_key() {
    local alias="$1"
    load_host_config "$alias" || return 1
    local key_file="$HOME/.ssh/codex_${alias}_key"
    if [[ ! -f "$key_file" ]]; then
        msg_info "生成 SSH 密钥: $key_file"
        ssh-keygen -t ed25519 -f "$key_file" -N "" -q
        msg_ok "密钥已生成"
    else
        msg_info "密钥已存在: $key_file"
    fi
    echo ""
    msg_info "复制公钥到 ${REMOTE_USER}@${REMOTE_HOST} (需要输入远程密码)"
    ssh-copy-id -i "${key_file}.pub" -p "${SSH_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" || {
        msg_warn "ssh-copy-id 失败,请手动执行:"
        echo "  ssh-copy-id -i ${key_file}.pub -p ${SSH_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
    }

    local ssh_config="$HOME/.ssh/config"
    local marker="# >>> codex-${alias} >>>"
    local marker_end="# <<< codex-${alias} <<<"
    mkdir -p "$HOME/.ssh"
    touch "$ssh_config"
    if ! grep -qF "$marker" "$ssh_config" 2>/dev/null; then
        msg_info "更新 ~/.ssh/config"
        cat >> "$ssh_config" <<EOF

${marker}
Host ${alias}
    HostName ${REMOTE_HOST}
    User ${REMOTE_USER}
    Port ${SSH_PORT}
    IdentityFile ${key_file}
    StrictHostKeyChecking no
${marker_end}
EOF
        msg_ok "SSH 配置已更新,可直接用 'ssh ${alias}' 连接"
    else
        msg_info "SSH config 中已有 ${alias} 的配置"
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

    msg_info "正在挂载 ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR} -> $LOCAL_MOUNT"
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
    local ssh_target
    if grep -q "Host ${alias}$" "$HOME/.ssh/config" 2>/dev/null; then
        ssh_target="${alias}:${REMOTE_DIR}"
        msg_info "使用 SSH 配置别名 '${alias}' 连接"
    else
        ssh_target="${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
        [[ "$SSH_PORT" != "22" ]] && mount_opts+=(-o "ssh_command=ssh -p ${SSH_PORT}")
        echo "  (未检测到 SSH 密钥配置,可能需要输入密码)"
    fi

    sshfs "$ssh_target" "$LOCAL_MOUNT" "${mount_opts[@]}" 2>&1 | sed 's/^/  /' || true

    if is_mounted "$LOCAL_MOUNT"; then
        echo ""
        msg_ok "挂载成功: ${alias}"
        echo "  远程: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
        echo "  本地: $LOCAL_MOUNT"
        echo ""
        echo "  启动 Codex: ./remote-codex.sh codex ${alias}"
    else
        msg_err "挂载失败,请检查:"
        echo "  1. 远程电脑是否开机且 SSH 服务正常"
        echo "  2. 用户名、IP、端口是否正确"
        echo "  3. 远程目录 ${REMOTE_DIR} 是否存在"
        echo "  4. 是否已设置免密登录(./remote-codex.sh setup-ssh ${alias})"
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

# codex - 在挂载目录启动 Codex
cmd_codex() {
    local alias="$1"
    load_host_config "$alias" || exit 1
    check_sshfs
    if ! is_mounted "$LOCAL_MOUNT"; then
        msg_err "${alias} 未挂载,先运行: ./remote-codex.sh mount ${alias}"
        exit 1
    fi
    echo -e "${BOLD}在 $LOCAL_MOUNT 启动 Codex${NC} (沙箱: $SANDBOX_MODE)"
    echo ""
    cd "$LOCAL_MOUNT"
    codex --sandbox "$SANDBOX_MODE"
}

# status - 查看状态(单个或全部)
cmd_status() {
    ensure_conf_dir
    local alias="${1:-}"
    if [[ -n "$alias" ]]; then
        load_host_config "$alias" || exit 1
        echo -e "${BOLD}=== ${alias} ===${NC}"
        echo "  远程: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR} (端口 ${SSH_PORT})"
        echo "  本地: $LOCAL_MOUNT"
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

# gen-agents - 生成远程开发说明(标记段写入 AGENTS.md,保留用户原有内容)
cmd_gen_agents() {
    local alias="$1"
    load_host_config "$alias" || exit 1
    if ! is_mounted "$LOCAL_MOUNT"; then
        msg_err "${alias} 未挂载,请先挂载: ./remote-codex.sh mount ${alias}"
        exit 1
    fi

    # 渲染模板到临时文件
    local rendered
    rendered=$(mktemp)
    if [[ -f "$AGENTS_TEMPLATE" ]]; then
        sed \
            -e "s|{{ALIAS}}|${alias}|g" \
            -e "s|{{REMOTE_HOST}}|${REMOTE_HOST}|g" \
            -e "s|{{REMOTE_USER}}|${REMOTE_USER}|g" \
            -e "s|{{REMOTE_DIR}}|${REMOTE_DIR}|g" \
            "$AGENTS_TEMPLATE" > "$rendered"
    else
        printf '# AGENTS.md - 远程开发配置\n\n当前工作目录通过 SSHFS 挂载到远程服务器。\n\n- 主机别名: %s\n- 远程主机: %s\n- SSH 用户: %s\n- 远程目录: %s\n\n命令执行必须通过 SSH:\n\n    ssh %s "cd %s && <你的命令>"\n' \
            "$alias" "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_DIR" "$alias" "$REMOTE_DIR" > "$rendered"
    fi

    # 标记段写入 AGENTS.md,保留你在文件中的其他内容(不覆盖)
    local target="${LOCAL_MOUNT}/AGENTS.md"
    local ms="<!-- >>> remote-codex-ssh >>>"
    local me="<!-- <<< remote-codex-ssh <<<"
    update_marked_section "$target" "$ms" "$me" "$rendered"
    rm -f "$rendered"

    msg_ok "已更新: $target"
    echo "  -> 标记段方式,保留你在 AGENTS.md 中的其他内容(不覆盖)"
    echo "  -> Codex 自动读取 AGENTS.md"
    echo "  -> 重复运行只更新标记段,安全幂等"
    echo "  -> 提示:若不想把本段提交到项目 git,可将 AGENTS.md 加入 .gitignore"
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
多主机远程 Codex 开发管理工具

用法: $0 <命令> [参数]

命令:
  list                    列出所有已配置主机
  add <别名>              交互式添加新主机
  mount <别名>            挂载指定主机的远程目录
  umount <别名>           卸载指定主机
  codex <别名>            在挂载目录启动 Codex
  status [别名]           查看状态(不指定则查看全部)
  gen-agents <别名>       为挂载目录生成 AGENTS.md
  remove <别名>           删除主机配置
  setup-ssh <别名>        设置 SSH 密钥免密登录
  mount-all               挂载所有主机
  umount-all              卸载所有主机
  help                    显示本帮助

缩写: list=ls, mount=m, umount=u, codex=c, status=st, remove=rm

配置文件目录: ${CONF_DIR}
每个主机一个 .conf 文件,文件名即主机别名。

示例:
  $0 add robot1                    # 添加主机 robot1
  $0 mount robot1                  # 挂载 robot1
  $0 codex robot1                  # 编辑 robot1 的代码
  $0 status                        # 查看所有主机状态
EOF
}

# 主入口
case "${1:-}" in
    list|ls)              cmd_list ;;
    add)                  cmd_add "${2:-}" ;;
    mount|m)              cmd_mount "${2:-}" ;;
    umount|u)             cmd_umount "${2:-}" ;;
    codex|c)              cmd_codex "${2:-}" ;;
    status|st)            cmd_status "${2:-}" ;;
    gen-agents)           cmd_gen_agents "${2:-}" ;;
    remove|rm)            cmd_remove "${2:-}" ;;
    setup-ssh)            setup_ssh_key "${2:-}" ;;
    mount-all)            cmd_mount_all ;;
    umount-all)           cmd_umount_all ;;
    help|--help|-h|"")    cmd_help ;;
    *)                    msg_err "未知命令: ${1}"; echo ""; cmd_help; exit 1 ;;
esac
