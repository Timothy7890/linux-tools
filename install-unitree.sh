#!/usr/bin/env bash
# ============================================================================
#  宇树机器人专用 · 精简工具包一键安装脚本
#  仅安装: Tmux / Yazi (含 rsync 传输支持)
#  公共函数见 lib.sh，配置模板见 config/
#  已存在的配置默认保留；--force-config 用模板覆盖（先备份）
# ============================================================================

# ========================= 版本配置（集中管理）=========================
TMUX_VER="3.6a"
YAZI_VER="v26.1.22"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$REPO_DIR/lib.sh" ]]; then
    echo "找不到 $REPO_DIR/lib.sh，请在完整的仓库目录内运行 install-unitree.sh"
    exit 1
fi
source "$REPO_DIR/lib.sh"

banner() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║      宇树机器人专用  ·  精简工具包安装脚本          ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                tmux · yazi                            ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

for arg in "$@"; do
    case "$arg" in
        --force-config) FORCE_CONFIG=true ;;
        -h|--help)
            echo "用法: ./install-unitree.sh [--force-config]"
            echo "  默认保留已存在的配置；--force-config 用 config/ 模板覆盖（先备份）"
            exit 0 ;;
        *) echo -e "${RED}未知参数: $arg${NC}"; exit 1 ;;
    esac
done

declare -A STATUS=()
detect_system
init_workdir

# ####################################################################
#  Phase 0 · 环境检查与用户输入
# ####################################################################
banner
phase "Phase 0 · 环境检查与配置"
$FORCE_CONFIG && warn "--force-config：已有配置将被模板覆盖（先备份）"

check_sudo
setup_proxy "192.168.60.181:7897"
check_github
ask_ssh_key_name
apt_use_proxy
install_base_deps

# ####################################################################
#  Phase 1 · Tmux
# ####################################################################
phase "Phase 1 · 终端复用 (Tmux)"
install_tmux

# ####################################################################
#  Phase 2 · Yazi / Rsync
# ####################################################################
phase "Phase 2 · 文件管理 (Yazi)"
install_yazi_bin
step "Yazi 快捷键配置"
deploy_yazi_keymap g-l R
deploy_transfer_script transfer-unitree.sh
install_rsync

# ####################################################################
#  Phase 3 · SSH 配置（可选）
# ####################################################################
if [[ -n "${SSH_KEY_NAME:-}" ]]; then
    phase "Phase 3 · SSH 密钥与远程传输配置"
    setup_ssh_macos
else
    phase "Phase 3 · SSH 配置（已跳过）"
fi

# ####################################################################
#  Phase 4 · 收尾
# ####################################################################
phase "Phase 4 · 安装完成"
setup_proxy_helpers

TOOL_ORDER=("Tmux" "Yazi" "Rsync")
[[ -n "${SSH_KEY_NAME:-}" ]] && TOOL_ORDER+=("SSH Key")
print_summary "${TOOL_ORDER[@]}"

# ---- 交互操作提示 ----
print_manual_header
echo -e "  ${BOLD}1.${NC} 验证 Tmux 插件是否安装成功:"
echo -e "     ${CYAN}ls ~/.tmux/plugins/${NC}"
echo -e "     ${DIM}应看到 tpm、tmux-resurrect、tmux-continuum 三个目录${NC}"
echo ""
echo -e "  ${BOLD}2.${NC} 如果 Tmux 插件未自动安装，请进入 tmux 后按 ${BOLD}Prefix + I${NC}，或运行:"
echo -e "     ${CYAN}~/.tmux/plugins/tpm/bin/install_plugins${NC}"
echo ""
echo -e "  ${BOLD}3.${NC} Yazi 用法: 进入 tmux 后运行 ${CYAN}yazi${NC}，选中文件后按 ${BOLD}R${NC} 分屏传输到 macos-yx。"
echo ""

if [[ -n "${SSH_KEY_NAME:-}" ]]; then
    echo -e "  ${BOLD}4.${NC} 将公钥添加到远程主机以启用免密登录:"
    echo -e "     ${CYAN}cat ~/.ssh/${SSH_KEY_NAME}_key.pub${NC}"
    echo -e "     ${DIM}复制输出内容，追加到远程主机的 ~/.ssh/authorized_keys${NC}"
    echo ""
fi

echo -e "  ${GREEN}${BOLD}  全部安装流程已完成！${NC}"
echo ""
