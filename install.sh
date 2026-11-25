#!/usr/bin/env bash
# ============================================================================
#  Linux 工具包一键安装脚本
#  自动安装: Git / Zsh / Oh My Zsh / Powerlevel10k / Vim / Tmux / Btop / Yazi / Lazygit
#  公共函数见 lib.sh，配置模板见 config/
#  已存在的配置默认保留；--force-config 用模板覆盖（先备份）
# ============================================================================

# ========================= 版本配置（集中管理）=========================
TMUX_VER="3.6a"
BTOP_VER="1.3.2"
YAZI_VER="v26.1.22"
LAZYGIT_VER="0.57.0"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$REPO_DIR/lib.sh" ]]; then
    echo "找不到 $REPO_DIR/lib.sh，请在完整的仓库目录内运行 install.sh"
    exit 1
fi
source "$REPO_DIR/lib.sh"

banner() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║         Linux 工具包  ·  一键安装脚本                ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║ zsh · oh-my-zsh · vim · tmux · btop · yazi · lazygit ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

declare -A STATUS=()
detect_system
init_workdir

# ####################################################################
#  组件选择（按需安装）
# ####################################################################
ALL_COMPONENTS=(git zsh vim tmux btop yazi lazygit rsync ssh)
declare -A SELECTED=()
SELECT_ALL=true

want()     { $SELECT_ALL && return 0; [[ -n "${SELECTED[$1]:-}" ]]; }
any_want() { local _c; for _c in "$@"; do want "$_c" && return 0; done; return 1; }

show_help() {
    banner
    echo -e "  ${BOLD}用法:${NC} ./install.sh [--force-config] [组件...]"
    echo ""
    echo -e "  不带参数 = 安装${BOLD}全部${NC}组件（默认行为）"
    echo -e "  指定组件 = ${BOLD}仅${NC}安装列出的组件，空格分隔多个"
    echo ""
    echo -e "  ${BOLD}可选组件:${NC}"
    echo -e "    ${CYAN}git${NC}      Git（旧系统自动 PPA 升级）"
    echo -e "    ${CYAN}zsh${NC}      Zsh + Oh My Zsh + Powerlevel10k + 插件 + .zshrc"
    echo -e "    ${CYAN}vim${NC}      Vim (vim-gtk3) + .vimrc"
    echo -e "    ${CYAN}tmux${NC}     Tmux（源码编译）+ TPM + .tmux.conf + 插件"
    echo -e "    ${CYAN}btop${NC}     Btop 1.3.2（源码编译，支持 GPU 监控）"
    echo -e "    ${CYAN}yazi${NC}     Yazi + keymap + transfer.sh + gv 可视化 + gy 目录工具"
    echo -e "    ${CYAN}lazygit${NC}  Lazygit"
    echo -e "    ${CYAN}rsync${NC}    Rsync"
    echo -e "    ${CYAN}ssh${NC}      生成 SSH 密钥 + ~/.ssh/config"
    echo ""
    echo -e "  ${BOLD}配置文件:${NC}"
    echo -e "    默认${BOLD}保留${NC}已存在的配置（keymap.toml 只追加缺少的键位）"
    echo -e "    ${CYAN}--force-config${NC}  用 config/ 模板覆盖已有配置（先备份为 .bak.时间戳）"
    echo ""
    echo -e "  ${BOLD}示例:${NC}"
    echo -e "    ${DIM}./install.sh${NC}                    # 全部"
    echo -e "    ${DIM}./install.sh yazi${NC}               # 只装 yazi"
    echo -e "    ${DIM}./install.sh yazi lazygit tmux${NC}  # 装多个"
    echo -e "    ${DIM}./install.sh --force-config vim${NC} # 重置 .vimrc 为模板"
    echo -e "    ${DIM}./install.sh --only zsh vim${NC}     # --only 为可选兼容写法"
    echo ""
}

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help; exit 0 ;;
        -l|--list)
            echo "可选组件: ${ALL_COMPONENTS[*]}"; exit 0 ;;
        --force-config)
            FORCE_CONFIG=true ;;
        --only|--option|--components)
            continue ;;   # 可选兼容写法，本身不代表组件
        git|zsh|vim|tmux|btop|yazi|lazygit|rsync|ssh)
            SELECTED[$arg]=1; SELECT_ALL=false ;;
        *)
            echo -e "${RED}未知参数: $arg${NC}"
            echo -e "运行 ${CYAN}./install.sh --help${NC} 查看可用组件"
            exit 1 ;;
    esac
done

# ####################################################################
#  Phase 0 · 环境检查与用户输入
# ####################################################################
banner
phase "Phase 0 · 环境检查与配置"
$FORCE_CONFIG && warn "--force-config：已有配置将被模板覆盖（先备份）"

check_sudo
setup_proxy "127.0.0.1:17897"
any_want git zsh tmux btop yazi lazygit && check_github
want ssh && ask_ssh_key_name
choose_apt_mode
install_base_deps

# ####################################################################
#  Phase 1 · Git / Zsh / Oh My Zsh / Powerlevel10k / 插件
# ####################################################################
if any_want git zsh; then
    phase "Phase 1 · Shell 环境"
fi

if want git; then
# ---- Git ----
step "Git"
# 旧系统（< 22.04）自带 Git 太老才走 PPA；已升级过（≥ GIT_MIN_VER）则跳过，避免每次重跑都刷 PPA
GIT_MIN_VER="2.34.0"   # Ubuntu 22.04 自带版本
need_git_upgrade=false
if [[ "$UBUNTU_VER" != "unknown" ]]; then
    ubuntu_major=$(echo "$UBUNTU_VER" | cut -d. -f1)
    if (( ubuntu_major < 22 )); then
        cur_git=$(git --version 2>/dev/null | awk '{print $3}')
        if [[ -z "$cur_git" ]] ||
            [[ "$(printf '%s\n%s\n' "$GIT_MIN_VER" "$cur_git" | sort -V | head -1)" != "$GIT_MIN_VER" ]]; then
            need_git_upgrade=true
        fi
    fi
fi

if $need_git_upgrade; then
    info "Ubuntu ${UBUNTU_VER} 检测到旧版本系统，通过 PPA 升级 Git..."
    "${APT_SUDO[@]}" apt-get install -y -qq software-properties-common > /dev/null 2>&1
    # add-apt-repository 需访问 launchpad（境外），始终走代理；--no-update 避免它用错误的代理策略刷新国内源
    sudo -E add-apt-repository -y --no-update ppa:git-core/ppa > /dev/null 2>&1
    # 刷新索引：国内镜像直连，仅 launchpad 走代理（APT_PPA_PROXY 在官方源场景为空）
    run_quiet "apt update" "${APT_SUDO[@]}" apt-get "${APT_PPA_PROXY[@]}" update -qq
    run_quiet "升级 Git" "${APT_SUDO[@]}" DEBIAN_FRONTEND=noninteractive apt-get "${APT_PPA_PROXY[@]}" install -y git
else
    if cmd_exists git; then
        ok "Git $(git --version | awk '{print $3}') 已安装"
    else
        run_quiet "安装 Git" "${APT_SUDO[@]}" DEBIAN_FRONTEND=noninteractive apt-get install -y git
    fi
fi
STATUS["Git"]="$(git --version 2>/dev/null | awk '{print $3}' || echo '✘')"
fi

if want zsh; then
# ---- Zsh ----
step "Zsh"
if cmd_exists zsh; then
    ok "Zsh $(zsh --version | awk '{print $2}') 已安装"
else
    run_quiet "安装 Zsh" "${APT_SUDO[@]}" DEBIAN_FRONTEND=noninteractive apt-get install -y zsh
fi
STATUS["Zsh"]="$(zsh --version 2>/dev/null | awk '{print $2}' || echo '✘')"

# ---- Oh My Zsh ----
step "Oh My Zsh"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    skip "Oh My Zsh 已存在"
else
    info "正在安装 Oh My Zsh (--unattended 模式)..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=no \
        sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        ok "Oh My Zsh 安装完成"
    else
        fail "Oh My Zsh 安装失败"
    fi
fi
STATUS["Oh My Zsh"]="$([ -d "$HOME/.oh-my-zsh" ] && echo '✔' || echo '✘')"

if [[ -d "$HOME/.oh-my-zsh" ]]; then
    # ---- Powerlevel10k ----
    step "Powerlevel10k 主题"
    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$P10K_DIR" ]]; then
        skip "Powerlevel10k 已存在"
    else
        if git_proxy_clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" 2>/dev/null; then
            ok "Powerlevel10k 安装完成"
        else
            fail "Powerlevel10k 安装失败"
        fi
    fi
    STATUS["Powerlevel10k"]="$([ -d "$P10K_DIR" ] && echo '✔' || echo '✘')"

    # ---- Zsh 插件 ----
    step "Zsh 插件"
    ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    declare -A ZSH_PLUGINS=(
        ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
        ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
        ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
    )

    for name in zsh-completions zsh-autosuggestions zsh-syntax-highlighting; do
        dest="$ZSH_CUSTOM_DIR/plugins/$name"
        if [[ -d "$dest" ]]; then
            skip "$name"
        else
            if git_proxy_clone --depth=1 "${ZSH_PLUGINS[$name]}" "$dest" 2>/dev/null; then
                ok "$name"
            else
                fail "$name"
            fi
        fi
    done
else
    warn "Oh My Zsh 未就绪，跳过 Powerlevel10k 和 Zsh 插件安装"
    STATUS["Powerlevel10k"]="✘"
fi

# ---- .zshrc ----
# 只替换 Oh My Zsh 默认值（robbyrussell / plugins=(git)），用户改过的保留；--force-config 强制
step "配置 ~/.zshrc"
ZSH_PLUGIN_LINE='plugins=(git zsh-completions zsh-autosuggestions zsh-syntax-highlighting)'
if [[ ! -f "$HOME/.zshrc" ]]; then
    cp "$CONFIG_DIR/zshrc" "$HOME/.zshrc"
    ok ".zshrc 已创建"
else
    zshrc_changes=()
    if ! grep -q '^ZSH_THEME="powerlevel10k/powerlevel10k"' "$HOME/.zshrc" &&
        { $FORCE_CONFIG || grep -qE '^ZSH_THEME="robbyrussell"' "$HOME/.zshrc"; }; then
        zshrc_changes+=(theme)
    fi
    if ! grep -qxF "$ZSH_PLUGIN_LINE" "$HOME/.zshrc" &&
        { $FORCE_CONFIG || grep -qE '^plugins=\(git\)$' "$HOME/.zshrc"; }; then
        zshrc_changes+=(plugins)
    fi
    if [[ ${#zshrc_changes[@]} -eq 0 ]]; then
        skip ".zshrc 主题/插件已配置或已自定义，保留"
    else
        backup_if_exists "$HOME/.zshrc"
        [[ " ${zshrc_changes[*]} " == *" theme "* ]] &&
            sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
        [[ " ${zshrc_changes[*]} " == *" plugins "* ]] &&
            sed -i "s|^plugins=(.*)|${ZSH_PLUGIN_LINE}|" "$HOME/.zshrc"
        ok ".zshrc 已更新 (${zshrc_changes[*]})"
    fi
fi
fi

# ####################################################################
#  Phase 2 · Vim / Tmux / Btop
# ####################################################################
if any_want vim tmux btop; then
    phase "Phase 2 · 编辑器与终端工具"
fi

if want vim; then
# ---- Vim ----
step "Vim (vim-gtk3，支持系统剪贴板)"
vim_has_clipboard=false
if cmd_exists vim; then
    if vim --version 2>/dev/null | grep -q '+clipboard'; then
        vim_has_clipboard=true
    fi
fi

if $vim_has_clipboard; then
    skip "Vim 已支持 +clipboard"
else
    run_quiet "安装 vim-gtk3" "${APT_SUDO[@]}" DEBIAN_FRONTEND=noninteractive apt-get install -y vim-gtk3
fi
STATUS["Vim"]="$(vim --version 2>/dev/null | head -1 | grep -oP 'Vi IMproved \K[0-9.]+' || echo '✘')"

step "配置 ~/.vimrc"
deploy_config "$CONFIG_DIR/vimrc" "$HOME/.vimrc"
fi

want tmux && install_tmux

if want btop; then
# ---- Btop 源码编译（GPU 支持）----
step "Btop ${BTOP_VER} (源码编译，GPU 支持)"

btop_need_install=true
if cmd_exists btop; then
    current_btop=$(btop --version 2>/dev/null | awk 'NR == 1 {print $NF}')
    if [[ "$current_btop" == "$BTOP_VER" ]]; then
        btop_need_install=false
        skip "Btop ${BTOP_VER} 已安装"
    else
        info "当前 Btop ${current_btop:-未知版本}，将安装 ${BTOP_VER}"
    fi
fi

if $btop_need_install; then
    info "安装 Btop 编译依赖..."
    "${APT_SUDO[@]}" apt-get install -y -qq build-essential > /dev/null 2>&1
    ok "编译依赖就绪"

    BTOP_CXX="g++"
    btop_compiler_ready=true
    btop_cxx_major=0
    if cmd_exists "$BTOP_CXX"; then
        btop_cxx_major=$("$BTOP_CXX" -dumpfullversion -dumpversion 2>/dev/null | cut -d. -f1)
    fi

    # Btop 1.3.2 需要 GCC 10.1+；Ubuntu 20.04 默认 GCC 9.4，需要新版编译器。
    if [[ ! "$btop_cxx_major" =~ ^[0-9]+$ ]] || (( btop_cxx_major < 10 )); then
        warn "当前 g++ ${btop_cxx_major:-未知} 过旧，Btop ${BTOP_VER} 需要 GCC 10.1+"

        if ! cmd_exists g++-13; then
            info "通过 ubuntu-toolchain-r/test PPA 安装 g++-13..."
            "${APT_SUDO[@]}" apt-get install -y -qq software-properties-common > /dev/null 2>&1

            if sudo -E add-apt-repository -y --no-update ppa:ubuntu-toolchain-r/test > /dev/null 2>&1; then
                run_quiet "更新 GCC PPA 索引" \
                    "${APT_SUDO[@]}" apt-get "${APT_PPA_PROXY[@]}" update -qq
                run_quiet "安装 g++-13" \
                    "${APT_SUDO[@]}" DEBIAN_FRONTEND=noninteractive \
                    apt-get "${APT_PPA_PROXY[@]}" install -y g++-13
            else
                fail "添加 ubuntu-toolchain-r/test PPA 失败"
            fi
        fi

        if cmd_exists g++-13; then
            BTOP_CXX="g++-13"
            ok "将使用 g++-13 编译，不修改系统默认编译器"
        else
            btop_compiler_ready=false
            fail "找不到满足要求的 C++ 编译器，无法编译 Btop"
        fi
    else
        ok "编译器可用: $("$BTOP_CXX" --version | head -1)"
    fi

    BTOP_GPU_SUPPORT=true
    if [[ "$ARCH_TAG" != "x86_64" ]]; then
        BTOP_GPU_SUPPORT=false
        warn "Btop ${BTOP_VER} 仅在 Linux x86_64 支持 GPU 监控，当前将编译普通版本"
    fi

    if $btop_compiler_ready && cmd_exists "$BTOP_CXX"; then
        BTOP_ARCHIVE="$WORK_DIR/btop-v${BTOP_VER}.tar.gz"
        BTOP_SRC_DIR="$WORK_DIR/btop-${BTOP_VER}"

        info "下载 Btop ${BTOP_VER} 源码..."
        if wget -q --show-progress -O "$BTOP_ARCHIVE" \
            "https://github.com/aristocratos/btop/archive/refs/tags/v${BTOP_VER}.tar.gz"; then
            if tar -xzf "$BTOP_ARCHIVE" -C "$WORK_DIR" &&
                pushd "$BTOP_SRC_DIR" > /dev/null; then
                # -ldl 兼容 Ubuntu 20.04 上启用 GPU 支持时的动态库链接。
                make CXX="$BTOP_CXX" GPU_SUPPORT="$BTOP_GPU_SUPPORT" LDFLAGS=-ldl \
                    > "$WORK_DIR/btop_make.log" 2>&1 &
                btop_make_pid=$!
                spinner "$btop_make_pid" "编译 Btop（GPU 支持）..."

                if wait "$btop_make_pid"; then
                    ok "Btop 编译完成"
                    if sudo -E make install CXX="$BTOP_CXX" \
                        GPU_SUPPORT="$BTOP_GPU_SUPPORT" LDFLAGS=-ldl \
                        > "$WORK_DIR/btop_install.log" 2>&1; then
                        ok "Btop ${BTOP_VER} 安装完成"
                    else
                        fail "Btop 安装失败，日志: $WORK_DIR/btop_install.log"
                    fi
                else
                    fail "Btop 编译失败，日志: $WORK_DIR/btop_make.log"
                    echo -e "  ${DIM}$(tail -5 "$WORK_DIR/btop_make.log" 2>/dev/null)${NC}"
                fi
                popd > /dev/null
            else
                fail "Btop 源码解压失败"
            fi
        else
            fail "Btop 源码下载失败"
        fi
    fi
fi

if cmd_exists btop; then
    STATUS["Btop"]="$(btop --version 2>/dev/null | awk 'NR == 1 {print $NF}')"
else
    STATUS["Btop"]="✘"
fi
fi

# ####################################################################
#  Phase 3 · Yazi / Lazygit / Rsync
# ####################################################################
if any_want yazi lazygit rsync; then
    phase "Phase 3 · 文件管理与 Git 工具"
fi

if want yazi; then
    install_yazi_bin
    step "Yazi 快捷键配置"
    deploy_yazi_keymap g-l g-i R g-v g-y
    deploy_transfer_script transfer.sh
    deploy_yazi_dirtool
    deploy_yazi_viz
fi

if want lazygit; then
# ---- Lazygit ----
step "Lazygit"
if cmd_exists lazygit; then
    skip "Lazygit 已安装"
else
    if [[ "$ARCH_TAG" == "x86_64" ]]; then
        LG_FILE="lazygit_${LAZYGIT_VER}_linux_x86_64.tar.gz"
    else
        LG_FILE="lazygit_${LAZYGIT_VER}_linux_arm64.tar.gz"
    fi
    LG_URL="https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VER}/${LG_FILE}"

    info "下载 Lazygit v${LAZYGIT_VER} (${ARCH_TAG})..."
    if wget -q --show-progress -P "$WORK_DIR" "$LG_URL"; then
        tar -xf "$WORK_DIR/$LG_FILE" -C "$WORK_DIR"
        if [[ -f "$WORK_DIR/lazygit" ]]; then
            sudo install "$WORK_DIR/lazygit" /usr/local/bin/
            ok "Lazygit 安装完成"
        else
            fail "Lazygit 解压异常"
        fi
    else
        fail "Lazygit 下载失败"
    fi
fi
STATUS["Lazygit"]="$(cmd_exists lazygit && echo '✔' || echo '✘')"
fi

want rsync && install_rsync

# ####################################################################
#  Phase 4 · SSH 配置（可选）
# ####################################################################
if [[ -n "${SSH_KEY_NAME:-}" ]]; then
    phase "Phase 4 · SSH 密钥与远程传输配置"
    setup_ssh_macos
elif want ssh; then
    phase "Phase 4 · SSH 配置（已跳过）"
fi

# ####################################################################
#  Phase 5 · 收尾
# ####################################################################
phase "Phase 5 · 安装完成"
setup_proxy_helpers ask_rc

TOOL_ORDER=()
want git     && TOOL_ORDER+=("Git")
want zsh     && TOOL_ORDER+=("Zsh" "Oh My Zsh" "Powerlevel10k")
want vim     && TOOL_ORDER+=("Vim")
want tmux    && TOOL_ORDER+=("Tmux")
want btop    && TOOL_ORDER+=("Btop")
want yazi    && TOOL_ORDER+=("Yazi" "Yazi 可视化")
want lazygit && TOOL_ORDER+=("Lazygit")
want rsync   && TOOL_ORDER+=("Rsync")
[[ -n "${SSH_KEY_NAME:-}" ]] && TOOL_ORDER+=("SSH Key")
print_summary "${TOOL_ORDER[@]}"

# ---- 交互操作提示 ----
if want zsh || want tmux || [[ -n "${SSH_KEY_NAME:-}" ]]; then
    print_manual_header
    tip_n=0
    if want zsh; then
        echo -e "  ${BOLD}$((++tip_n)).${NC} 将默认 Shell 切换为 Zsh（需要输入密码）:"
        echo -e "     ${CYAN}chsh -s \$(which zsh)${NC}"
        echo ""
        echo -e "  ${BOLD}$((++tip_n)).${NC} 重新登录终端，或执行以下命令立即进入 Zsh:"
        echo -e "     ${CYAN}exec zsh${NC}"
        echo ""
        echo -e "  ${BOLD}$((++tip_n)).${NC} 配置 Powerlevel10k 主题（首次进入 Zsh 会自动弹出，或手动运行）:"
        echo -e "     ${CYAN}p10k configure${NC}"
        echo ""
        echo -e "  ${BOLD}$((++tip_n)).${NC} p10k configure 完成后，修改路径显示最大长度（可选）:"
        echo -e "     ${CYAN}sed -i 's/typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=.*/typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=20/' ~/.p10k.zsh && source ~/.p10k.zsh${NC}"
        echo ""
    fi

    if want tmux; then
        echo -e "  ${BOLD}$((++tip_n)).${NC} 验证 Tmux 插件是否安装成功:"
        echo -e "     ${CYAN}ls ~/.tmux/plugins/${NC}"
        echo -e "     ${DIM}应看到 tpm、tmux-resurrect、tmux-continuum 三个目录${NC}"
        echo ""
        echo -e "  ${BOLD}$((++tip_n)).${NC} 如果 Tmux 插件未自动安装，请进入 tmux 后按 ${BOLD}Prefix + I${NC}，或运行:"
        echo -e "     ${CYAN}~/.tmux/plugins/tpm/bin/install_plugins${NC}"
        echo ""
    fi

    if [[ -n "${SSH_KEY_NAME:-}" ]]; then
        echo -e "  ${BOLD}$((++tip_n)).${NC} 将公钥添加到远程主机以启用免密登录:"
        echo -e "     ${CYAN}cat ~/.ssh/${SSH_KEY_NAME}_key.pub${NC}"
        echo -e "     ${DIM}复制输出内容，追加到远程主机的 ~/.ssh/authorized_keys${NC}"
        echo ""
    fi
fi

echo -e "  ${GREEN}${BOLD}  全部安装流程已完成！${NC}"
echo ""
