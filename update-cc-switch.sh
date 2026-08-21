#!/usr/bin/env bash
#
# update-cc-switch.sh - 手动升级 cc-switch(绕过应用内失败的自动升级)
#
# 背景: cc-switch 内建自动升级(Linux)在下载完 deb 后因缺少 root 权限而静默失败,
#       表现为日志只有"开始安装应用更新"却没有下文。本脚本直接下载官方 deb
#       包并用 sudo 安装,可重复执行、幂等(已是最新则跳过)。
#
# 用法:
#   ./update-cc-switch.sh            检查并升级(需要时)
#   ./update-cc-switch.sh --check    仅检查版本,不安装
#   ./update-cc-switch.sh --force    强制重新安装当前最新版

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

msg_ok()   { echo -e "${GREEN}[OK]${NC}     $*"; }
msg_err()  { echo -e "${RED}[ERROR]${NC}  $*"; }
msg_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
msg_info() { echo -e "${BLUE}[INFO]${NC}   $*"; }

REPO="farion1231/cc-switch"
API="https://api.github.com/repos/${REPO}/releases/latest"

# 语义化版本比较: 若 v1 > v2 返回 0,否则返回 1
ver_gt() {
    [[ "$1" == "$2" ]] && return 1
    local IFS=.
    local a=($1) b=($2)
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        local ai="${a[$i]:-0}" bi="${b[$i]:-0}"
        if ((10#$ai > 10#$bi)); then return 0; fi
        if ((10#$ai < 10#$bi)); then return 1; fi
    done
    return 1
}

# 当前已安装版本(去掉 deb 版本号中的 -N 后缀)
get_current_version() {
    dpkg-query -W -f='${Version}' cc-switch 2>/dev/null | cut -d- -f1 || echo ""
}

# 架构: uname 输出 -> release 资产名中的架构
detect_arch() {
    case "$(uname -m)" in
        x86_64)                 echo "x86_64" ;;
        aarch64 | arm64)        echo "arm64" ;;
        *) msg_err "不支持的架构: $(uname -m)"; exit 1 ;;
    esac
}

# 获取最新版本信息,设置全局变量: LATEST_VERSION, LATEST_DEB_URL
fetch_latest() {
    local arch
    arch="$(detect_arch)"
    local tmp
    tmp=$(mktemp)
    if ! curl -sfL --max-time 20 "$API" -o "$tmp"; then
        rm -f "$tmp"
        msg_err "无法访问 GitHub API($API)"
        echo "  请检查网络后重试,或到 https://github.com/farion1231/cc-switch/releases 手动下载 deb 安装"
        exit 1
    fi
    LATEST_VERSION="$(python3 -c "
import json,sys
d=json.load(open('$tmp'))
print(d['tag_name'].lstrip('v'))
" 2>/dev/null || true)"
    LATEST_DEB_URL="$(python3 -c "
import json,sys
d=json.load(open('$tmp'))
for a in d.get('assets',[]):
    n=a['name']
    if n.endswith('.deb') and '-Linux-$arch.' in n:
        print(a['browser_download_url']); break
" 2>/dev/null || true)"
    rm -f "$tmp"
    if [[ -z "$LATEST_VERSION" || -z "$LATEST_DEB_URL" ]]; then
        msg_err "解析最新版本信息失败(GitHub API 返回异常)"
        exit 1
    fi
}

# 安装前确保 cc-switch 已退出(deb 会覆盖 /usr/bin/cc-switch)
close_app_if_running() {
    local pid
    pid="$(pgrep -x cc-switch 2>/dev/null || true)"
    [[ -z "$pid" ]] && return 0
    msg_warn "检测到 cc-switch 正在运行(PID: $pid)"
    if [[ "${FORCE:-}" == "1" ]]; then
        msg_info "(--force) 自动关闭 cc-switch ..."
        pkill -x cc-switch || true
        sleep 1
        return 0
    fi
    read -rp "是否自动关闭后继续安装? (y/N): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        pkill -x cc-switch || true
        sleep 1
    else
        msg_info "已取消,请手动退出 cc-switch 后重试"
        exit 0
    fi
}

install_deb() {
    local deb="$1" target="$2"
    local cmd=""
    if [[ "$(id -u)" -eq 0 ]]; then
        cmd=(dpkg -i)
    else
        cmd=(sudo dpkg -i)
    fi
    msg_info "正在安装(需要 sudo 权限): $target"
    if "${cmd[@]}" "$deb"; then
        msg_ok "升级成功: 已安装 cc-switch ${LATEST_VERSION}"
    else
        msg_warn "dpkg 安装未完全成功,尝试修复依赖 ..."
        if [[ "$(id -u)" -eq 0 ]]; then
            apt-get install -f -y
        else
            sudo apt-get install -f -y
        fi
        msg_ok "依赖修复完成,请确认: dpkg -l | grep cc-switch"
    fi
}

usage() {
    cat <<EOF
cc-switch 升级辅助脚本(绕过应用内失败的自动升级)

用法: $0 [选项]

选项:
  --check    仅检查最新版本并对比当前版本,不安装
  --force    强制重新安装当前最新版(即使已是最新)
  -h, --help 显示本帮助

无参数时: 检测到新版本则下载 deb 并用 sudo 安装。
EOF
}

FORCE=""
CHECK=""
case "${1:-}" in
    --check)  CHECK=1 ;;
    --force)  FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    "")       ;;
    *)        msg_err "未知选项: ${1}"; usage; exit 1 ;;
esac

# 1. 当前版本
local_ver="$(get_current_version)"
if [[ -z "$local_ver" ]]; then
    msg_warn "未检测到已安装的 cc-switch(未通过 deb 安装?)"
    msg_info "本脚本仅支持 deb 安装方式的升级(dpkg)"
fi

# 2. 最新版本
msg_info "正在检查最新版本 ..."
fetch_latest
echo -e "  当前版本:  ${BOLD}${local_ver:-未安装}${NC}"
echo -e "  最新版本:  ${BOLD}${LATEST_VERSION}${NC}"

if [[ -z "$local_ver" ]]; then
    msg_err "未安装 deb 版 cc-switch,无法通过本脚本升级"
    exit 1
fi

# 3. 版本对比(--check 只检查到此为止)
if [[ -n "$CHECK" ]]; then
    exit 0
fi
if [[ -z "$FORCE" ]] && ! ver_gt "$LATEST_VERSION" "$local_ver"; then
    msg_ok "已是最新版本(${LATEST_VERSION}),无需升级"
    exit 0
fi
if [[ "$LATEST_VERSION" == "$local_ver" ]]; then
    msg_info "(--force) 强制重新安装相同版本"
fi

# 4. 下载 deb
local_arch="$(detect_arch)"
deb="$(mktemp --suffix=-cc-switch.deb)"
msg_info "下载: $LATEST_DEB_URL"
if ! curl -fL --max-time 600 --progress-bar "$LATEST_DEB_URL" -o "$deb"; then
    rm -f "$deb"
    msg_err "下载失败,请检查网络"
    exit 1
fi
echo ""

# 5. 安装
close_app_if_running
install_deb "$deb" "$LATEST_DEB_URL"
rm -f "$deb"

# 6. 验证
final="$(get_current_version)"
msg_ok "当前安装版本: ${final}"
if [[ "$final" == "$LATEST_VERSION" ]]; then
    msg_ok "升级完成"
else
    msg_warn "版本未如预期(当前 ${final}),请检查上方安装日志"
fi
