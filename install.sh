#!/usr/bin/env bash
# ============================================================================
#  Linux 工具包一键安装脚本
#  自动安装: Git / Zsh / Oh My Zsh / Powerlevel10k / Vim / Tmux / Yazi / Lazygit
# ============================================================================

# ========================= 版本配置（集中管理）=========================
TMUX_VER="3.6a"
YAZI_VER="v26.1.22"
LAZYGIT_VER="0.57.0"

# ========================= 颜色与样式 =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ========================= 输出函数 =========================
ok()    { echo -e "  ${GREEN}✔${NC} $1"; }
fail()  { echo -e "  ${RED}✘${NC} $1"; }
skip()  { echo -e "  ${YELLOW}⊘${NC} $1 ${DIM}(已跳过)${NC}"; }
info()  { echo -e "  ${BLUE}ℹ${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }

step() {
    echo -e "\n${CYAN}${BOLD}  ▸ $1${NC}"
}

phase() {
    local w=54
    echo ""
    echo -e "${MAGENTA}${BOLD}  ┌$(printf '─%.0s' $(seq 1 $w))┐${NC}"
    printf "  ${MAGENTA}${BOLD}│${NC} %-$(($w - 1))s${MAGENTA}${BOLD}│${NC}\n" "$1"
    echo -e "${MAGENTA}${BOLD}  └$(printf '─%.0s' $(seq 1 $w))┘${NC}"
}

banner() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║         Linux 工具包  ·  一键安装脚本                ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║   zsh · oh-my-zsh · vim · tmux · yazi · lazygit      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ========================= Spinner（长耗时操作） =========================
spinner() {
    local pid=$1 msg="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${NC} %s" "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    printf "\r\033[K"
    tput cnorm 2>/dev/null
}

run_quiet() {
    local msg="$1"; shift
    local log="$WORK_DIR/cmd_$$.log"
    "$@" > "$log" 2>&1 &
    local pid=$!
    spinner "$pid" "$msg"
    if wait "$pid"; then
        ok "$msg"
        return 0
    else
        fail "$msg"
        echo -e "  ${DIM}$(tail -3 "$log" 2>/dev/null)${NC}"
        return 1
    fi
}

# ========================= 工具函数 =========================
cmd_exists() { command -v "$1" &>/dev/null; }

backup_if_exists() {
    local f="$1"
    if [[ -f "$f" ]]; then
        local bak="${f}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$f" "$bak"
        info "已备份 ${f} → ${bak}"
    fi
}

git_proxy_clone() {
    git -c "http.proxy=http://127.0.0.1:${PROXY_PORT}" \
        -c "https.proxy=http://127.0.0.1:${PROXY_PORT}" \
        clone "$@"
}

# ========================= 状态追踪 =========================
declare -A STATUS=()

# ========================= 架构检测 =========================
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_TAG="x86_64" ;;
    aarch64) ARCH_TAG="aarch64" ;;
    *)
        echo -e "\n  ${RED}不支持的系统架构: $ARCH${NC}"
        exit 1
        ;;
esac

# ========================= Ubuntu 版本 =========================
UBUNTU_VER="unknown"
if [[ -f /etc/os-release ]]; then
    UBUNTU_VER=$(. /etc/os-release && echo "${VERSION_ID:-unknown}")
elif cmd_exists lsb_release; then
    UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")
fi

# ========================= 临时目录 =========================
WORK_DIR=$(mktemp -d /tmp/linux-tool-install-XXXXXX)
cleanup() {
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ####################################################################
#  Phase 0 · 环境检查与用户输入
# ####################################################################
banner
phase "Phase 0 · 环境检查与配置"

# ---- sudo ----
step "检查 sudo 权限"
if sudo -n true 2>/dev/null; then
    ok "sudo 免密可用"
else
    info "部分操作需要 sudo，请输入密码"
    if sudo true; then
        ok "sudo 验证通过"
    else
        fail "无法获取 sudo 权限，脚本终止"
        exit 1
    fi
fi

# 后台保活 sudo
( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!

info "系统架构: ${BOLD}${ARCH_TAG}${NC}"
info "Ubuntu 版本: ${BOLD}${UBUNTU_VER}${NC}"

# ---- 代理 ----
step "代理配置"
echo -ne "  输入代理端口 ${DIM}(默认 17897，回车使用默认)${NC}: "
read -r PROXY_PORT
PROXY_PORT=${PROXY_PORT:-17897}

export http_proxy="http://127.0.0.1:${PROXY_PORT}"
export https_proxy="http://127.0.0.1:${PROXY_PORT}"
export all_proxy="socks5://127.0.0.1:${PROXY_PORT}"

ok "代理 → 127.0.0.1:${PROXY_PORT}"

# ---- 测试连通性 ----
step "测试 GitHub 连通性"
if wget -q --timeout=10 --spider https://github.com 2>/dev/null; then
    ok "GitHub 可达"
else
    warn "无法连接 GitHub，请确认代理端口正确"
    echo -ne "  ${YELLOW}是否继续？(y/N)${NC}: "
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

# ---- SSH 密钥名称（可选）----
step "SSH 密钥配置（可选，用于 yazi 远程传输）"
echo -ne "  输入 SSH 密钥名称 ${DIM}(留空跳过此步骤)${NC}: "
read -r SSH_KEY_NAME
if [[ -n "$SSH_KEY_NAME" ]]; then
    ok "密钥名称: ${SSH_KEY_NAME}"
else
    skip "SSH 配置"
fi

# ---- 基础依赖 ----
step "安装基础依赖 (wget / curl / unzip)"
run_quiet "apt update" sudo apt-get update -qq
sudo apt-get install -y -qq wget curl unzip > /dev/null 2>&1
ok "基础依赖就绪"

# ####################################################################
#  Phase 1 · Git / Zsh / Oh My Zsh / Powerlevel10k / 插件
# ####################################################################
phase "Phase 1 · Shell 环境"

# ---- Git ----
step "Git"
need_git_upgrade=false
if [[ "$UBUNTU_VER" != "unknown" ]]; then
    ubuntu_major=$(echo "$UBUNTU_VER" | cut -d. -f1)
    if (( ubuntu_major < 22 )); then
        need_git_upgrade=true
    fi
fi

if $need_git_upgrade; then
    info "Ubuntu ${UBUNTU_VER} 检测到旧版本系统，通过 PPA 升级 Git..."
    sudo apt-get install -y -qq software-properties-common > /dev/null 2>&1
    sudo add-apt-repository -y ppa:git-core/ppa > /dev/null 2>&1
    run_quiet "升级 Git" sudo apt-get install -y git
else
    if cmd_exists git; then
        ok "Git $(git --version | awk '{print $3}') 已安装"
    else
        run_quiet "安装 Git" sudo apt-get install -y git
    fi
fi
STATUS["Git"]="$(git --version 2>/dev/null | awk '{print $3}' || echo '✘')"

# ---- Zsh ----
step "Zsh"
if cmd_exists zsh; then
    ok "Zsh $(zsh --version | awk '{print $2}') 已安装"
else
    run_quiet "安装 Zsh" sudo apt-get install -y zsh
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
step "配置 ~/.zshrc"
backup_if_exists "$HOME/.zshrc"

if [[ -f "$HOME/.zshrc" ]]; then
    sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
    sed -i 's|^plugins=(.*)|plugins=(git zsh-completions zsh-autosuggestions zsh-syntax-highlighting)|' "$HOME/.zshrc"
    ok ".zshrc 已更新（主题 + 插件）"
else
    cat > "$HOME/.zshrc" << 'ZSHRC_EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(git zsh-completions zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh
ZSHRC_EOF
    ok ".zshrc 已创建"
fi

# ####################################################################
#  Phase 2 · Vim / Tmux
# ####################################################################
phase "Phase 2 · 编辑器与终端复用"

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
    run_quiet "安装 vim-gtk3" sudo apt-get install -y vim-gtk3
fi
STATUS["Vim"]="$(vim --version 2>/dev/null | head -1 | grep -oP 'Vi IMproved \K[0-9.]+' || echo '✘')"

# ---- .vimrc ----
step "配置 ~/.vimrc"
backup_if_exists "$HOME/.vimrc"
cat > "$HOME/.vimrc" << 'VIMRC_EOF'
set number
set clipboard=unnamed,unnamedplus

syntax on
filetype plugin indent on
set t_Co=256
set encoding=utf-8

set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
set expandtab
set softtabstop=4

" OSC 52 clipboard support (works over SSH / inside tmux)
function! OSC52Copy()
    let b64 = system('base64 | tr -d "\n"', getreg(v:event.regname))
    let osc52 = "\e]52;c;" . b64 . "\x07"
    if !empty($TMUX)
        let osc52 = "\ePtmux;\e" . substitute(osc52, "\e", "\e\e", 'g') . "\e\\"
    endif
    silent! call writefile([osc52], '/dev/tty', 'b')
endfunction

augroup osc52
    autocmd!
    autocmd TextYankPost * if v:event.operator == 'y' | call OSC52Copy() | endif
augroup END
VIMRC_EOF
ok ".vimrc 已写入"

# ---- Tmux 源码编译 ----
step "Tmux ${TMUX_VER} (源码编译)"

tmux_need_install=true
if cmd_exists tmux; then
    current_tmux=$(tmux -V 2>/dev/null | awk '{print $2}')
    if [[ "$current_tmux" == "$TMUX_VER" ]]; then
        tmux_need_install=false
        skip "Tmux ${TMUX_VER} 已安装"
    else
        info "当前 Tmux ${current_tmux}，将升级到 ${TMUX_VER}"
    fi
fi

if $tmux_need_install; then
    info "安装编译依赖..."
    sudo apt-get install -y -qq libevent-dev ncurses-dev build-essential bison pkg-config > /dev/null 2>&1
    ok "编译依赖就绪"

    info "下载 tmux-${TMUX_VER} 源码..."
    wget -q --show-progress -P "$WORK_DIR" \
        "https://github.com/tmux/tmux/releases/download/${TMUX_VER}/tmux-${TMUX_VER}.tar.gz"

    tar -xzf "$WORK_DIR/tmux-${TMUX_VER}.tar.gz" -C "$WORK_DIR"

    if pushd "$WORK_DIR/tmux-${TMUX_VER}" > /dev/null; then
        # configure
        ./configure > "$WORK_DIR/configure.log" 2>&1 &
        cfg_pid=$!
        spinner "$cfg_pid" "配置编译环境 (./configure)..."
        if wait "$cfg_pid"; then
            ok "配置完成"
        else
            fail "配置失败，日志: $WORK_DIR/configure.log"
        fi

        # make
        make -j"$(nproc)" > "$WORK_DIR/make.log" 2>&1 &
        make_pid=$!
        spinner "$make_pid" "编译 tmux（可能需要 1-3 分钟）..."
        if wait "$make_pid"; then
            ok "编译完成"
        else
            fail "编译失败，日志: $WORK_DIR/make.log"
        fi

        # install
        sudo make install > /dev/null 2>&1
        popd > /dev/null

        if cmd_exists tmux && [[ "$(tmux -V 2>/dev/null | awk '{print $2}')" == "$TMUX_VER" ]]; then
            ok "Tmux ${TMUX_VER} 安装成功"
        else
            fail "Tmux 安装可能不完整，请手动检查"
        fi
    else
        fail "进入 tmux 源码目录失败，跳过编译"
    fi
fi
STATUS["Tmux"]="$(tmux -V 2>/dev/null | awk '{print $2}' || echo '✘')"

# ---- TPM ----
step "Tmux Plugin Manager (TPM)"
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ -d "$TPM_DIR" ]]; then
    skip "TPM 已存在"
else
    mkdir -p "$HOME/.tmux/plugins"
    if git_proxy_clone --depth=1 https://github.com/tmux-plugins/tpm "$TPM_DIR" 2>/dev/null; then
        ok "TPM 安装完成"
    else
        fail "TPM 安装失败"
    fi
fi

# ---- .tmux.conf ----
step "配置 ~/.tmux.conf"
backup_if_exists "$HOME/.tmux.conf"
cat > "$HOME/.tmux.conf" << 'TMUX_EOF'
set -g mouse on
set -g allow-passthrough on
set -g default-terminal "screen-256color"
set-option -ga terminal-overrides ",xterm-256color:Tc"

set -g status-left-length 20
set -g status-left "#{?client_prefix,#[bg=yellow]#[fg=black] WAITING... #[default], [#S] }"

setw -g mode-keys vi

set -s set-clipboard on
set -as terminal-overrides ',xterm*:Ms=\E]52;c;%p2%s\a'

bind -T copy-mode-vi v send-keys -X begin-selection
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

set -g @continuum-restore 'on'

run '~/.tmux/plugins/tpm/tpm'
TMUX_EOF
ok ".tmux.conf 已写入"

# ---- 自动安装 Tmux 插件 ----
step "安装 Tmux 插件 (resurrect / continuum)"
if [[ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" > "$WORK_DIR/tpm_install.log" 2>&1 &
    tpm_pid=$!
    spinner "$tpm_pid" "正在下载 Tmux 插件..."
    if wait "$tpm_pid"; then
        ok "Tmux 插件安装完成"
    else
        warn "Tmux 插件自动安装失败，请稍后手动执行: ~/.tmux/plugins/tpm/bin/install_plugins"
    fi
else
    warn "TPM 未就绪，请稍后在 tmux 中按 Prefix + I 安装插件"
fi

# ####################################################################
#  Phase 3 · Yazi / Lazygit / Rsync
# ####################################################################
phase "Phase 3 · 文件管理与 Git 工具"

# ---- Yazi ----
step "Yazi (终端文件管理器)"
if cmd_exists yazi; then
    skip "Yazi 已安装"
else
    if [[ "$ARCH_TAG" == "x86_64" ]]; then
        YAZI_FILE="yazi-x86_64-unknown-linux-musl.zip"
    else
        YAZI_FILE="yazi-aarch64-unknown-linux-musl.zip"
    fi
    YAZI_URL="https://github.com/sxyazi/yazi/releases/download/${YAZI_VER}/${YAZI_FILE}"

    info "下载 Yazi ${YAZI_VER} (${ARCH_TAG})..."
    if wget -q --show-progress -P "$WORK_DIR" "$YAZI_URL"; then
        unzip -qo "$WORK_DIR/$YAZI_FILE" -d "$WORK_DIR"
        YAZI_DIR=$(find "$WORK_DIR" -maxdepth 1 -type d -name 'yazi-*' | head -1)
        if [[ -n "$YAZI_DIR" ]]; then
            sudo mv "$YAZI_DIR/yazi" /usr/bin/
            sudo mv "$YAZI_DIR/ya" /usr/bin/
            ok "Yazi 安装完成"
        else
            fail "Yazi 解压异常"
        fi
    else
        fail "Yazi 下载失败"
    fi
fi
STATUS["Yazi"]="$(cmd_exists yazi && echo '✔' || echo '✘')"

# ---- Yazi keymap.toml ----
step "Yazi 快捷键配置"
mkdir -p "$HOME/.config/yazi"
backup_if_exists "$HOME/.config/yazi/keymap.toml"
cat > "$HOME/.config/yazi/keymap.toml" << 'YAZI_KEY_EOF'
[[mgr.prepend_keymap]]
on   = [ "g", "l" ]
run  = '''
    shell '
        cwd="$PWD"
        todo_file="yazi_todo.yazi"
        target=$(tmux new-window -c "$cwd" -P -F "#{window_id}")
        if [ -f "$todo_file" ]; then
            pre_cmd=$(cat "$todo_file")
            sleep 0.3
            tmux send-keys -t "$target" "$pre_cmd" C-m
        fi
    '
'''
desc = "精准锁定新窗口激活环境"

[[mgr.prepend_keymap]]
on   = [ "g", "i" ]
run  = "shell 'lazygit' --block"
desc = "Git (Lazygit)"

[[mgr.prepend_keymap]]
on   = [ "R" ]
run  = '''
    shell 'tmux split-window -h "rsync -avzP \"$@\" macos-yx:~/Downloads/; echo 传输完成，2秒后关闭...; sleep 2"'
'''
desc = "Tmux 分屏下载"
YAZI_KEY_EOF
ok "keymap.toml 已写入"

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

# ---- Rsync ----
step "Rsync"
if cmd_exists rsync; then
    skip "Rsync 已安装"
else
    run_quiet "安装 Rsync" sudo apt-get install -y rsync
fi
STATUS["Rsync"]="$(cmd_exists rsync && echo '✔' || echo '✘')"

# ####################################################################
#  Phase 4 · SSH 配置（可选）
# ####################################################################
if [[ -n "${SSH_KEY_NAME:-}" ]]; then
    phase "Phase 4 · SSH 密钥与远程传输配置"

    # ---- 生成密钥 ----
    step "生成 SSH 密钥 (ed25519)"
    SSH_KEY_PATH="$HOME/.ssh/${SSH_KEY_NAME}_key"
    if [[ -f "$SSH_KEY_PATH" ]]; then
        skip "密钥 ${SSH_KEY_PATH} 已存在"
    else
        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -C "$SSH_KEY_NAME" -f "$SSH_KEY_PATH" -N ""
        ok "密钥已生成: ${SSH_KEY_PATH}"
        info "公钥内容:"
        echo ""
        echo -e "  ${DIM}$(cat "${SSH_KEY_PATH}.pub")${NC}"
        echo ""
    fi
    STATUS["SSH Key"]="✔"

    # ---- SSH Config ----
    step "SSH Config (Host macos-yx)"
    echo -ne "  远程主机 HostName ${DIM}(默认 127.0.0.1)${NC}: "
    read -r SSH_HOST
    SSH_HOST=${SSH_HOST:-127.0.0.1}

    echo -ne "  远程用户名 ${DIM}(默认 timo)${NC}: "
    read -r SSH_USER
    SSH_USER=${SSH_USER:-timo}

    echo -ne "  SSH 端口 ${DIM}(默认 12025)${NC}: "
    read -r SSH_PORT
    SSH_PORT=${SSH_PORT:-12025}

    SSH_CONFIG="$HOME/.ssh/config"

    if [[ -f "$SSH_CONFIG" ]] && grep -q "Host macos-yx" "$SSH_CONFIG" 2>/dev/null; then
        skip "Host macos-yx 已存在于 SSH config"
    else
        cat >> "$SSH_CONFIG" << SSH_CONF_EOF

Host macos-yx
    HostName ${SSH_HOST}
    User ${SSH_USER}
    Port ${SSH_PORT}
    IdentityFile ~/.ssh/${SSH_KEY_NAME}_key
    IdentitiesOnly yes
    PreferredAuthentications publickey
SSH_CONF_EOF
        chmod 600 "$SSH_CONFIG"
        ok "SSH config 已追加 Host macos-yx"
    fi
else
    phase "Phase 4 · SSH 配置（已跳过）"
fi

# ####################################################################
#  Phase 5 · 收尾
# ####################################################################
phase "Phase 5 · 安装完成"

step "清理临时文件"
rm -rf "$WORK_DIR"
ok "已清理 ${WORK_DIR}"

# ---- 安装摘要 ----
step "安装摘要"
echo ""
echo -e "  ${BOLD}┌────────────────────┬────────────────┐${NC}"
printf "  ${BOLD}│${NC} %-18s ${BOLD}│${NC} %-14s ${BOLD}│${NC}\n" "工具" "状态"
echo -e "  ${BOLD}├────────────────────┼────────────────┤${NC}"

TOOL_ORDER=("Git" "Zsh" "Oh My Zsh" "Powerlevel10k" "Vim" "Tmux" "Yazi" "Lazygit" "Rsync")
if [[ -n "${SSH_KEY_NAME:-}" ]]; then
    TOOL_ORDER+=("SSH Key")
fi

for tool in "${TOOL_ORDER[@]}"; do
    val="${STATUS[$tool]:-—}"
    if [[ "$val" == "✘" ]]; then
        color="$RED"
    elif [[ "$val" == "✔" ]]; then
        color="$GREEN"
    else
        color="$GREEN"
    fi
    printf "  ${BOLD}│${NC} %-18s ${BOLD}│${NC} ${color}%-14s${NC} ${BOLD}│${NC}\n" "$tool" "$val"
done
echo -e "  ${BOLD}└────────────────────┴────────────────┘${NC}"

# ---- 交互操作提示 ----
echo ""
echo -e "  ${YELLOW}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${YELLOW}${BOLD}║          以下操作需要您手动完成                      ║${NC}"
echo -e "  ${YELLOW}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}1.${NC} 将默认 Shell 切换为 Zsh（需要输入密码）:"
echo -e "     ${CYAN}chsh -s \$(which zsh)${NC}"
echo ""
echo -e "  ${BOLD}2.${NC} 重新登录终端，或执行以下命令立即进入 Zsh:"
echo -e "     ${CYAN}exec zsh${NC}"
echo ""
echo -e "  ${BOLD}3.${NC} 配置 Powerlevel10k 主题（首次进入 Zsh 会自动弹出，或手动运行）:"
echo -e "     ${CYAN}p10k configure${NC}"
echo ""
echo -e "  ${BOLD}4.${NC} p10k configure 完成后，修改路径显示最大长度（可选）:"
echo -e "     ${CYAN}sed -i 's/typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=.*/typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=20/' ~/.p10k.zsh && source ~/.p10k.zsh${NC}"
echo ""
echo -e "  ${BOLD}5.${NC} 验证 Tmux 插件是否安装成功:"
echo -e "     ${CYAN}ls ~/.tmux/plugins/${NC}"
echo -e "     ${DIM}应看到 tpm、tmux-resurrect、tmux-continuum 三个目录${NC}"
echo ""
echo -e "  ${BOLD}6.${NC} 如果 Tmux 插件未自动安装，请进入 tmux 后按 ${BOLD}Prefix + I${NC}，或运行:"
echo -e "     ${CYAN}~/.tmux/plugins/tpm/bin/install_plugins${NC}"
echo ""

if [[ -n "${SSH_KEY_NAME:-}" ]]; then
    echo -e "  ${BOLD}7.${NC} 将公钥添加到远程主机以启用免密登录:"
    echo -e "     ${CYAN}cat ~/.ssh/${SSH_KEY_NAME}_key.pub${NC}"
    echo -e "     ${DIM}复制输出内容，追加到远程主机的 ~/.ssh/authorized_keys${NC}"
    echo ""
fi

echo -e "  ${GREEN}${BOLD}  全部安装流程已完成！${NC}"
echo ""
