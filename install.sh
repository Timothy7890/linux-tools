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
    git -c "http.proxy=http://${PROXY_ADDR}" \
        -c "https.proxy=http://${PROXY_ADDR}" \
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
#  组件选择（按需安装）
# ####################################################################
ALL_COMPONENTS=(git zsh vim tmux yazi lazygit rsync ssh)
declare -A SELECTED=()
SELECT_ALL=true

want()     { $SELECT_ALL && return 0; [[ -n "${SELECTED[$1]:-}" ]]; }
any_want() { local _c; for _c in "$@"; do want "$_c" && return 0; done; return 1; }

show_help() {
    banner
    echo -e "  ${BOLD}用法:${NC} ./install.sh [组件...]"
    echo ""
    echo -e "  不带参数 = 安装${BOLD}全部${NC}组件（默认行为）"
    echo -e "  指定组件 = ${BOLD}仅${NC}安装列出的组件，空格分隔多个"
    echo ""
    echo -e "  ${BOLD}可选组件:${NC}"
    echo -e "    ${CYAN}git${NC}      Git（旧系统自动 PPA 升级）"
    echo -e "    ${CYAN}zsh${NC}      Zsh + Oh My Zsh + Powerlevel10k + 插件 + .zshrc"
    echo -e "    ${CYAN}vim${NC}      Vim (vim-gtk3) + .vimrc"
    echo -e "    ${CYAN}tmux${NC}     Tmux（源码编译）+ TPM + .tmux.conf + 插件"
    echo -e "    ${CYAN}yazi${NC}     Yazi + keymap.toml + transfer.sh"
    echo -e "    ${CYAN}lazygit${NC}  Lazygit"
    echo -e "    ${CYAN}rsync${NC}    Rsync"
    echo -e "    ${CYAN}ssh${NC}      生成 SSH 密钥 + ~/.ssh/config"
    echo ""
    echo -e "  ${BOLD}示例:${NC}"
    echo -e "    ${DIM}./install.sh${NC}                    # 全部"
    echo -e "    ${DIM}./install.sh yazi${NC}               # 只装 yazi"
    echo -e "    ${DIM}./install.sh yazi lazygit tmux${NC}  # 装多个"
    echo -e "    ${DIM}./install.sh --only zsh vim${NC}     # --only 为可选兼容写法"
    echo ""
}

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help; exit 0 ;;
        -l|--list)
            echo "可选组件: ${ALL_COMPONENTS[*]}"; exit 0 ;;
        --only|--option|--components)
            continue ;;   # 可选兼容写法，本身不代表组件
        git|zsh|vim|tmux|yazi|lazygit|rsync|ssh)
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
echo -ne "  输入代理地址 ${DIM}(默认 127.0.0.1:17897，回车使用默认)${NC}: "
read -r PROXY_ADDR
PROXY_ADDR=${PROXY_ADDR:-127.0.0.1:17897}

export http_proxy="http://${PROXY_ADDR}"
export https_proxy="http://${PROXY_ADDR}"
export all_proxy="socks5://${PROXY_ADDR}"

ok "代理 → ${PROXY_ADDR}"

# ---- 测试连通性 ----
if any_want git zsh tmux yazi lazygit; then
    step "测试 GitHub 连通性"
    if wget -q --timeout=10 --spider https://github.com 2>/dev/null; then
        ok "GitHub 可达"
    else
        warn "无法连接 GitHub，请确认代理端口正确"
        echo -ne "  ${YELLOW}是否继续？(y/N)${NC}: "
        read -r ans
        [[ "$ans" =~ ^[Yy]$ ]] || exit 1
    fi
fi

# ---- SSH 密钥名称（可选）----
if want ssh; then
    step "SSH 密钥配置（可选，用于 yazi 远程传输）"
    echo -ne "  输入 SSH 密钥名称 ${DIM}(留空跳过此步骤)${NC}: "
    read -r SSH_KEY_NAME
    if [[ -n "$SSH_KEY_NAME" ]]; then
        ok "密钥名称: ${SSH_KEY_NAME}"
    else
        skip "SSH 配置"
    fi
fi

# ---- 检测 APT 软件源（决定 apt 是否走代理）----
# 国内/云厂商内网镜像只能直连，塞进出海代理会 502；官方境外源才需要代理。
step "检测 APT 软件源"
apt_hosts=$(grep -rhoE 'https?://[^/[:space:]]+' \
    /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | sort -u)

# 常见国内镜像关键词（阿里云 / 腾讯云 / 华为云 / 火山 / 清华 / 中科大 / 网易 / 南大 / 交大 / 北外 等）
DOMESTIC_MIRROR_RE='aliyun|aliyuncs|tencent|tencentyun|myhuaweicloud|huaweicloud|volces|tuna\.tsinghua|mirrors\.ustc|mirrors\.163|mirror\.nju|nju\.edu|sjtug|bfsu|mirrors\.cloud'

if [[ -n "$apt_hosts" ]] && echo "$apt_hosts" | grep -qiE "$DOMESTIC_MIRROR_RE"; then
    APT_USE_PROXY=false
    APT_SUDO=(sudo)            # 去掉 -E：apt 直连国内镜像
    # PPA（launchpad）在境外，即使整体直连也需单独给它挂代理
    APT_PPA_PROXY=(
        -o "Acquire::http::Proxy::ppa.launchpad.net=http://${PROXY_ADDR}"
        -o "Acquire::http::Proxy::ppa.launchpadcontent.net=http://${PROXY_ADDR}"
        -o "Acquire::https::Proxy::ppa.launchpadcontent.net=http://${PROXY_ADDR}"
    )
    ok "检测到国内镜像源，apt 将直连（不走代理）"
else
    APT_USE_PROXY=true
    APT_SUDO=(sudo -E)         # 保留 -E：apt 通过代理访问境外源
    APT_PPA_PROXY=()
    ok "使用官方/境外源，apt 将通过代理"
fi

# ---- 基础依赖 ----
step "安装基础依赖 (wget / curl / unzip)"
run_quiet "apt update" "${APT_SUDO[@]}" apt-get update -qq
"${APT_SUDO[@]}" apt-get install -y -qq wget curl unzip > /dev/null 2>&1
ok "基础依赖就绪"

# ####################################################################
#  Phase 1 · Git / Zsh / Oh My Zsh / Powerlevel10k / 插件
# ####################################################################
if any_want git zsh; then
    phase "Phase 1 · Shell 环境"
fi

if want git; then
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
fi

# ####################################################################
#  Phase 2 · Vim / Tmux
# ####################################################################
if any_want vim tmux; then
    phase "Phase 2 · 编辑器与终端复用"
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
fi

if want tmux; then
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
    "${APT_SUDO[@]}" apt-get install -y -qq libevent-dev ncurses-dev build-essential bison pkg-config > /dev/null 2>&1
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
fi

# ####################################################################
#  Phase 3 · Yazi / Lazygit / Rsync
# ####################################################################
if any_want yazi lazygit rsync; then
    phase "Phase 3 · 文件管理与 Git 工具"
fi

if want yazi; then
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
    shell 'printf "%%s\n" %s > /tmp/yazi_transfer_files && tmux split-window -h "bash ~/.config/yazi/scripts/transfer.sh"'
'''
desc = "Tmux 分屏传输"
YAZI_KEY_EOF
ok "keymap.toml 已写入"

# ---- Yazi 传输脚本 ----
step "Yazi 传输脚本 (transfer.sh)"
mkdir -p "$HOME/.config/yazi/scripts"
backup_if_exists "$HOME/.config/yazi/scripts/transfer.sh"
cat > "$HOME/.config/yazi/scripts/transfer.sh" << 'YAZI_TRANSFER_EOF'
#!/bin/bash
mapfile -t files < /tmp/yazi_transfer_files
if [ ${#files[@]} -eq 0 ]; then
    echo "没有选中文件，已取消"; sleep 1; exit 0
fi

echo "==============================="
echo "  选择目标服务器"
echo "==============================="
echo ""
echo "  1) macos-yx    ~/Downloads/"
echo "  2) macmini     /Users/timo_clawd/Transfer/"
echo "  q) 取消"
echo ""
read -p "请选择 [1-2/q]: " choice

case $choice in
    1) dest="macos-yx:~/Downloads/";               use_scp=false ;;
    2) dest="macmini:/Users/timo_clawd/Transfer/"; use_scp=false ;;
    *) echo "已取消"; sleep 1; exit 0 ;;
esac

echo ""
echo "→ 目标: $dest"
echo "→ 文件: ${files[*]}"
echo ""
if $use_scp; then
    scp -r -p "${files[@]}" "$dest"
else
    rsync -avzP "${files[@]}" "$dest"
fi
echo ""
echo "传输完成，2秒后关闭..."
sleep 2
YAZI_TRANSFER_EOF
chmod +x "$HOME/.config/yazi/scripts/transfer.sh"
ok "transfer.sh 已写入"
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

if want rsync; then
# ---- Rsync ----
step "Rsync"
if cmd_exists rsync; then
    skip "Rsync 已安装"
else
    run_quiet "安装 Rsync" "${APT_SUDO[@]}" DEBIAN_FRONTEND=noninteractive apt-get install -y rsync
fi
STATUS["Rsync"]="$(cmd_exists rsync && echo '✔' || echo '✘')"
fi

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
elif want ssh; then
    phase "Phase 4 · SSH 配置（已跳过）"
fi

# ####################################################################
#  Phase 5 · 收尾
# ####################################################################
phase "Phase 5 · 安装完成"

# ---- Proxy 快捷函数（可选）----
step "Proxy 快捷函数 (proxy_on / proxy_off)"
echo -ne "  是否在 rc 中添加 proxy_on / proxy_off 快捷函数？${DIM}(y/N)${NC}: "
read -r proxy_helper_ans
if [[ "$proxy_helper_ans" =~ ^[Yy]$ ]]; then
    echo -ne "  代理地址 ${DIM}(默认 ${PROXY_ADDR}，回车使用)${NC}: "
    read -r PROXY_HELPER_ADDR
    PROXY_HELPER_ADDR=${PROXY_HELPER_ADDR:-$PROXY_ADDR}

    echo -ne "  写入哪个 rc 文件？${DIM}[1] ~/.bashrc  [2] ~/.zshrc (默认 1)${NC}: "
    read -r rc_choice
    case "$rc_choice" in
        2) RC_FILE="$HOME/.zshrc" ;;
        *) RC_FILE="$HOME/.bashrc" ;;
    esac

    backup_if_exists "$RC_FILE"

    if [[ -f "$RC_FILE" ]] && grep -q '# >>> proxy helpers >>>' "$RC_FILE" 2>/dev/null; then
        sed -i '/# >>> proxy helpers >>>/,/# <<< proxy helpers <<</d' "$RC_FILE"
        info "已移除旧的 proxy helpers 配置"
    fi

    cat >> "$RC_FILE" << PROXY_EOF

# >>> proxy helpers >>>
proxy_on() {
  export http_proxy=http://${PROXY_HELPER_ADDR}
  export https_proxy=http://${PROXY_HELPER_ADDR}
  echo "proxy on: \$http_proxy"
}

proxy_off() {
  unset http_proxy https_proxy
  echo "proxy off"
}
# <<< proxy helpers <<<
PROXY_EOF
    ok "proxy_on / proxy_off 已写入 ${RC_FILE} (地址 ${PROXY_HELPER_ADDR})"
    info "执行 ${BOLD}source ${RC_FILE}${NC} 或重开终端后，可用 proxy_on / proxy_off 切换代理"
else
    skip "Proxy 快捷函数"
fi

step "清理临时文件"
rm -rf "$WORK_DIR"
ok "已清理 ${WORK_DIR}"

# ---- 安装摘要 ----
step "安装摘要"
echo ""
echo -e "  ${BOLD}┌────────────────────┬────────────────┐${NC}"
printf "  ${BOLD}│${NC} %-18s ${BOLD}│${NC} %-14s ${BOLD}│${NC}\n" "工具" "状态"
echo -e "  ${BOLD}├────────────────────┼────────────────┤${NC}"

TOOL_ORDER=()
want git     && TOOL_ORDER+=("Git")
want zsh     && TOOL_ORDER+=("Zsh" "Oh My Zsh" "Powerlevel10k")
want vim     && TOOL_ORDER+=("Vim")
want tmux    && TOOL_ORDER+=("Tmux")
want yazi    && TOOL_ORDER+=("Yazi")
want lazygit && TOOL_ORDER+=("Lazygit")
want rsync   && TOOL_ORDER+=("Rsync")
[[ -n "${SSH_KEY_NAME:-}" ]] && TOOL_ORDER+=("SSH Key")

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
if want zsh || want tmux || [[ -n "${SSH_KEY_NAME:-}" ]]; then
    echo ""
    echo -e "  ${YELLOW}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${YELLOW}${BOLD}║          以下操作需要您手动完成                      ║${NC}"
    echo -e "  ${YELLOW}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

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
