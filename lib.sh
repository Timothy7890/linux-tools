#!/usr/bin/env bash
# ============================================================================
#  linux-tools 公共函数库：由 install.sh / install-unitree.sh source
#  使用前需设置: REPO_DIR（仓库根目录）
# ============================================================================

CONFIG_DIR="$REPO_DIR/config"
FORCE_CONFIG=${FORCE_CONFIG:-false}
VIZ_ENV="$HOME/.local/share/yazi-viz"

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

# ========================= 配置部署 =========================
# deploy_config <模板> <目标> [user|managed]
#   目标不存在          → 写入
#   与模板相同          → 跳过
#   不同 + user（默认） → 保留用户版本；FORCE_CONFIG=true 时备份后覆盖
#   不同 + managed      → 备份后更新（仓库自带的脚本，不是用户配置）
deploy_config() {
    local src="$1" dest="$2" kind="${3:-user}"
    local name="${dest/#$HOME/\~}"
    if [[ ! -f "$src" ]]; then
        fail "缺少模板 ${src}（请在完整的仓库目录内运行）"
        return 1
    fi
    mkdir -p "$(dirname "$dest")"
    if [[ ! -e "$dest" ]]; then
        cp "$src" "$dest"
        ok "${name} 已写入"
    elif cmp -s "$src" "$dest"; then
        skip "${name} 已是最新"
    elif [[ "$kind" == managed ]] || $FORCE_CONFIG; then
        backup_if_exists "$dest"
        cp "$src" "$dest"
        ok "${name} 已更新"
    else
        skip "${name} 已存在且有改动，保留（--force-config 可用模板覆盖）"
    fi
}

# keymap_has <keymap.toml> <块文件>：按 on = [...] 判断键位是否已存在（忽略空白）
keymap_has() {
    local on
    on=$(grep -m1 -E '^[[:space:]]*on[[:space:]]*=' "$2" | tr -d '[:space:]')
    tr -d '[:space:]' < "$1" | grep -qF "$on"
}

# deploy_yazi_keymap <块名...>：块位于 config/yazi/keymap.d/<名>.toml
#   不存在 / --force-config → 用所选块生成整个文件
#   已存在                  → 只追加缺少的键位，保留其他内容
deploy_yazi_keymap() {
    local dest="$HOME/.config/yazi/keymap.toml" dir="$CONFIG_DIR/yazi/keymap.d"
    local b f missing=()
    for b in "$@"; do
        [[ -f "$dir/$b.toml" ]] || { fail "缺少模板 $dir/$b.toml"; return 1; }
    done
    mkdir -p "$(dirname "$dest")"

    if [[ ! -f "$dest" ]] || $FORCE_CONFIG; then
        [[ -f "$dest" ]] && backup_if_exists "$dest"
        : > "$dest"
        for b in "$@"; do
            [[ -s "$dest" ]] && echo "" >> "$dest"
            cat "$dir/$b.toml" >> "$dest"
        done
        ok "~/.config/yazi/keymap.toml 已写入 (${*})"
        return 0
    fi

    for b in "$@"; do
        keymap_has "$dest" "$dir/$b.toml" || missing+=("$b")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        skip "keymap.toml 已包含全部键位，保留现有配置"
        return 0
    fi
    # 内联数组写法（prepend_keymap = [ ... ]）不能再追加 [[mgr.prepend_keymap]]
    if grep -qE '^[[:space:]]*prepend_keymap[[:space:]]*=' "$dest"; then
        warn "keymap.toml 使用内联 prepend_keymap 数组，无法自动追加: ${missing[*]}"
        info "请手动合并 $dir 中对应文件，或使用 --force-config 覆盖"
        return 0
    fi
    backup_if_exists "$dest"
    for b in "${missing[@]}"; do
        printf '\n' >> "$dest"
        cat "$dir/$b.toml" >> "$dest"
    done
    ok "keymap.toml 已追加缺少的键位: ${missing[*]}（其余保留）"
}

# ========================= 环境检测 =========================
detect_system() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_TAG="x86_64" ;;
        aarch64) ARCH_TAG="aarch64" ;;
        *)
            echo -e "\n  ${RED}不支持的系统架构: $ARCH${NC}"
            exit 1
            ;;
    esac

    UBUNTU_VER="unknown"
    if [[ -f /etc/os-release ]]; then
        UBUNTU_VER=$(. /etc/os-release && echo "${VERSION_ID:-unknown}")
    elif cmd_exists lsb_release; then
        UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")
    fi
}

init_workdir() {
    WORK_DIR=$(mktemp -d /tmp/linux-tool-install-XXXXXX)
    trap cleanup EXIT
}

cleanup() {
    [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    rm -rf "$WORK_DIR"
}

check_sudo() {
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
}

# setup_proxy <默认地址>
setup_proxy() {
    local def="$1"
    step "代理配置"
    echo -ne "  输入代理地址 ${DIM}(默认 ${def}，回车使用默认)${NC}: "
    read -r PROXY_ADDR
    PROXY_ADDR=${PROXY_ADDR:-$def}

    export http_proxy="http://${PROXY_ADDR}"
    export https_proxy="http://${PROXY_ADDR}"
    export all_proxy="socks5://${PROXY_ADDR}"

    ok "代理 → ${PROXY_ADDR}"
}

check_github() {
    step "测试 GitHub 连通性"
    if wget -q --timeout=10 --spider https://github.com 2>/dev/null; then
        ok "GitHub 可达"
    else
        warn "无法连接 GitHub，请确认代理端口正确"
        echo -ne "  ${YELLOW}是否继续？(y/N)${NC}: "
        read -r ans
        [[ "$ans" =~ ^[Yy]$ ]] || exit 1
    fi
}

ask_ssh_key_name() {
    step "SSH 密钥配置（可选，用于 yazi 远程传输）"
    echo -ne "  输入 SSH 密钥名称 ${DIM}(留空跳过此步骤)${NC}: "
    read -r SSH_KEY_NAME
    if [[ -n "$SSH_KEY_NAME" ]]; then
        ok "密钥名称: ${SSH_KEY_NAME}"
    else
        skip "SSH 配置"
    fi
}

# ========================= APT =========================
# apt 统一走代理（不询问）
apt_use_proxy() {
    APT_USE_PROXY=true
    APT_SUDO=(sudo -E)
    APT_PPA_PROXY=()
}

# 改写为官方源：先备份原文件，deb822（ubuntu.sources / debian.sources）与传统 sources.list 两种格式都处理
restore_official_sources() {
    local os_id codename ts arch url sec_url suites sec_suite comps
    os_id=$(. /etc/os-release && echo "${ID:-}")
    codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
    ts=$(date +%Y%m%d%H%M%S)
    arch=$(dpkg --print-architecture 2>/dev/null)

    case "$os_id" in
        ubuntu)
            if [[ "$arch" == amd64 || "$arch" == i386 ]]; then
                url="http://archive.ubuntu.com/ubuntu/"
                sec_url="http://security.ubuntu.com/ubuntu/"
            else
                url="http://ports.ubuntu.com/ubuntu-ports/"
                sec_url="$url"
            fi
            suites="${codename} ${codename}-updates ${codename}-backports"
            sec_suite="${codename}-security"
            comps="main restricted universe multiverse"
            ;;
        debian)
            url="http://deb.debian.org/debian/"
            sec_url="http://deb.debian.org/debian-security/"
            suites="${codename} ${codename}-updates"
            sec_suite="${codename}-security"
            comps="main contrib non-free non-free-firmware"
            ;;
        *)
            fail "不支持的系统: ${os_id:-unknown}，未修改软件源"
            return 1
            ;;
    esac
    [[ -n "$codename" ]] || { fail "无法获取系统版本代号，未修改软件源"; return 1; }

    local deb822="/etc/apt/sources.list.d/${os_id}.sources"
    if [[ -f "$deb822" ]]; then
        sudo cp -a "$deb822" "${deb822}.bak.${ts}"
        sudo tee "$deb822" > /dev/null <<EOF
Types: deb
URIs: ${url}
Suites: ${suites}
Components: ${comps}
Signed-By: /usr/share/keyrings/${os_id}-archive-keyring.gpg

Types: deb
URIs: ${sec_url}
Suites: ${sec_suite}
Components: ${comps}
Signed-By: /usr/share/keyrings/${os_id}-archive-keyring.gpg
EOF
        info "已备份 ${deb822} → ${deb822}.bak.${ts}"
        # deb822 生效时 sources.list 只留注释，避免与镜像源重复
        if [[ -s /etc/apt/sources.list ]]; then
            sudo cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.${ts}"
            echo "# 已迁移至 ${deb822}" | sudo tee /etc/apt/sources.list > /dev/null
            info "已备份 /etc/apt/sources.list → /etc/apt/sources.list.bak.${ts}"
        fi
    else
        [[ -f /etc/apt/sources.list ]] && sudo cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.${ts}"
        {
            local s
            for s in $suites; do echo "deb ${url} ${s} ${comps}"; done
            echo "deb ${sec_url} ${sec_suite} ${comps}"
        } | sudo tee /etc/apt/sources.list > /dev/null
        info "已备份 /etc/apt/sources.list → /etc/apt/sources.list.bak.${ts}"
    fi
    ok "已切换为 ${os_id} 官方源"
}

# 国内/云厂商内网镜像只能直连，塞进出海代理会 502；官方境外源才需要代理。
choose_apt_mode() {
    step "APT 代理配置"
    local apt_hosts apt_choice=""
    apt_hosts=$(grep -rhoE 'https?://[^/[:space:]]+' \
        /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | sort -u)
    if [[ -n "$apt_hosts" ]]; then
        info "当前 APT 软件源:"
        echo "$apt_hosts" | sed 's/^/      /'
    fi
    echo -e "  ${BOLD}1)${NC} 直连（国内镜像源，PPA 单独走代理）"
    echo -e "  ${BOLD}2)${NC} 走代理（官方/境外源）"
    echo -e "  ${BOLD}3)${NC} 切换为国外官方源（原始版本），并走代理"
    until [[ "$apt_choice" =~ ^[123]$ ]]; do
        echo -ne "  请选择 apt 访问方式 [1-3]: "
        read -r apt_choice
    done

    if [[ "$apt_choice" == 3 ]]; then
        restore_official_sources || warn "官方源切换失败，保持原软件源，apt 仍将走代理"
        apt_choice=2
    fi

    if [[ "$apt_choice" == 1 ]]; then
        APT_USE_PROXY=false
        APT_SUDO=(sudo)            # 去掉 -E：apt 直连国内镜像
        # PPA（launchpad）在境外，即使整体直连也需单独给它挂代理
        APT_PPA_PROXY=(
            -o "Acquire::http::Proxy::ppa.launchpad.net=http://${PROXY_ADDR}"
            -o "Acquire::http::Proxy::ppa.launchpadcontent.net=http://${PROXY_ADDR}"
            -o "Acquire::https::Proxy::ppa.launchpadcontent.net=http://${PROXY_ADDR}"
        )
        ok "apt 将直连（不走代理）"
    else
        apt_use_proxy
        ok "apt 将通过代理"
    fi
}

install_base_deps() {
    step "安装基础依赖 (wget / curl / unzip)"
    run_quiet "apt update" "${APT_SUDO[@]}" apt-get update -qq
    "${APT_SUDO[@]}" apt-get install -y -qq wget curl unzip > /dev/null 2>&1
    ok "基础依赖就绪"
}

# ========================= Tmux =========================
install_tmux() {
    step "Tmux ${TMUX_VER} (源码编译)"

    local tmux_need_install=true current_tmux
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
            ./configure > "$WORK_DIR/configure.log" 2>&1 &
            local cfg_pid=$!
            spinner "$cfg_pid" "配置编译环境 (./configure)..."
            if wait "$cfg_pid"; then
                ok "配置完成"
            else
                fail "配置失败，日志: $WORK_DIR/configure.log"
            fi

            make -j"$(nproc)" > "$WORK_DIR/make.log" 2>&1 &
            local make_pid=$!
            spinner "$make_pid" "编译 tmux（可能需要 1-3 分钟）..."
            if wait "$make_pid"; then
                ok "编译完成"
            else
                fail "编译失败，日志: $WORK_DIR/make.log"
            fi

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

    step "Tmux Plugin Manager (TPM)"
    local TPM_DIR="$HOME/.tmux/plugins/tpm"
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

    step "配置 ~/.tmux.conf"
    deploy_config "$CONFIG_DIR/tmux.conf" "$HOME/.tmux.conf"

    step "安装 Tmux 插件 (resurrect / continuum)"
    if [[ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
        "$HOME/.tmux/plugins/tpm/bin/install_plugins" > "$WORK_DIR/tpm_install.log" 2>&1 &
        local tpm_pid=$!
        spinner "$tpm_pid" "正在下载 Tmux 插件..."
        if wait "$tpm_pid"; then
            ok "Tmux 插件安装完成"
        else
            warn "Tmux 插件自动安装失败，请稍后手动执行: ~/.tmux/plugins/tpm/bin/install_plugins"
        fi
    else
        warn "TPM 未就绪，请稍后在 tmux 中按 Prefix + I 安装插件"
    fi
}

# ========================= Yazi =========================
install_yazi_bin() {
    step "Yazi (终端文件管理器)"
    if cmd_exists yazi; then
        skip "Yazi 已安装"
    else
        local YAZI_FILE YAZI_URL YAZI_DIR
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
}

# deploy_transfer_script <模板文件名>：部署为 ~/.config/yazi/scripts/transfer.sh（用户配置，默认保留）
deploy_transfer_script() {
    step "Yazi 传输脚本 (transfer.sh)"
    local dest="$HOME/.config/yazi/scripts/transfer.sh"
    deploy_config "$CONFIG_DIR/yazi/scripts/$1" "$dest"
    chmod +x "$dest" 2>/dev/null
}

deploy_yazi_viz() {
    step "Yazi 可视化脚本 (gv)"
    local f
    for f in visualize_web.sh visualize_transforms_web.py visualize_masks_web.py; do
        deploy_config "$CONFIG_DIR/yazi/scripts/$f" "$HOME/.config/yazi/scripts/$f" managed
    done
    chmod +x "$HOME/.config/yazi/scripts/visualize_web.sh" 2>/dev/null

    step "gv 可视化依赖 (venv: ${VIZ_ENV})"
    local VIZ_PKGS=(numpy pillow plotly fastapi uvicorn) viz_ans PIP_ARGS PIP_ENV
    if [[ -x "$VIZ_ENV/bin/python" ]] && "$VIZ_ENV/bin/python" -c "import numpy, PIL, plotly, fastapi, uvicorn" 2>/dev/null; then
        skip "venv 已存在且依赖齐全"
        STATUS["Yazi 可视化"]="✔"
        return 0
    fi
    echo -ne "  是否安装 gv 可视化依赖（约 150MB）？${DIM}(Y/n)${NC}: "
    read -r viz_ans
    if [[ "$viz_ans" =~ ^[Nn]$ ]]; then
        skip "gv 可视化依赖（按 gv 时会提示安装）"
        STATUS["Yazi 可视化"]="跳过"
        return 0
    fi
    if ! python3 -c "import venv, ensurepip" 2>/dev/null; then
        run_quiet "安装 python3-venv" "${APT_SUDO[@]}" apt-get install -y -qq python3-venv
    fi
    # 国内镜像直连；选了代理时走官方 PyPI
    if [[ "${APT_USE_PROXY:-true}" == false ]]; then
        PIP_ARGS=(-i https://pypi.tuna.tsinghua.edu.cn/simple)
        PIP_ENV=(env -u http_proxy -u https_proxy -u all_proxy)
    else
        PIP_ARGS=()
        PIP_ENV=(env)
    fi
    if run_quiet "创建 venv" python3 -m venv "$VIZ_ENV" \
        && run_quiet "升级 pip" "${PIP_ENV[@]}" "$VIZ_ENV/bin/pip" install -q "${PIP_ARGS[@]}" --upgrade pip \
        && run_quiet "安装 ${VIZ_PKGS[*]}" "${PIP_ENV[@]}" "$VIZ_ENV/bin/pip" install -q "${PIP_ARGS[@]}" "${VIZ_PKGS[@]}"; then
        STATUS["Yazi 可视化"]="✔"
    else
        STATUS["Yazi 可视化"]="✘"
    fi
}

# ========================= Rsync =========================
install_rsync() {
    step "Rsync"
    if cmd_exists rsync; then
        skip "Rsync 已安装"
    else
        run_quiet "安装 Rsync" "${APT_SUDO[@]}" DEBIAN_FRONTEND=noninteractive apt-get install -y rsync
    fi
    STATUS["Rsync"]="$(cmd_exists rsync && echo '✔' || echo '✘')"
}

# ========================= SSH =========================
setup_ssh_macos() {
    step "生成 SSH 密钥 (ed25519)"
    local SSH_KEY_PATH="$HOME/.ssh/${SSH_KEY_NAME}_key"
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

    step "SSH Config (Host macos-yx)"
    local SSH_CONFIG="$HOME/.ssh/config"
    # 已存在则直接保留，不再询问
    if [[ -f "$SSH_CONFIG" ]] && grep -qE '^[[:space:]]*Host[[:space:]]+macos-yx([[:space:]]|$)' "$SSH_CONFIG" 2>/dev/null; then
        skip "Host macos-yx 已存在于 SSH config，保留"
        return 0
    fi

    local SSH_HOST SSH_USER SSH_PORT
    echo -ne "  远程主机 HostName ${DIM}(默认 127.0.0.1)${NC}: "
    read -r SSH_HOST
    SSH_HOST=${SSH_HOST:-127.0.0.1}

    echo -ne "  远程用户名 ${DIM}(默认 timo)${NC}: "
    read -r SSH_USER
    SSH_USER=${SSH_USER:-timo}

    echo -ne "  SSH 端口 ${DIM}(默认 12025)${NC}: "
    read -r SSH_PORT
    SSH_PORT=${SSH_PORT:-12025}

    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
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
}

# ========================= Proxy 快捷函数 =========================
# setup_proxy_helpers [ask_rc]：传 ask_rc 时询问写入 bashrc 还是 zshrc，否则写 ~/.bashrc
setup_proxy_helpers() {
    step "Proxy 快捷函数 (proxy_on / proxy_off)"
    local proxy_helper_ans PROXY_HELPER_ADDR rc_choice RC_FILE block
    echo -ne "  是否在 rc 中添加 proxy_on / proxy_off 快捷函数？${DIM}(y/N)${NC}: "
    read -r proxy_helper_ans
    if [[ ! "$proxy_helper_ans" =~ ^[Yy]$ ]]; then
        skip "Proxy 快捷函数"
        return 0
    fi

    echo -ne "  代理地址 ${DIM}(默认 ${PROXY_ADDR}，回车使用)${NC}: "
    read -r PROXY_HELPER_ADDR
    PROXY_HELPER_ADDR=${PROXY_HELPER_ADDR:-$PROXY_ADDR}

    RC_FILE="$HOME/.bashrc"
    if [[ "${1:-}" == ask_rc ]]; then
        echo -ne "  写入哪个 rc 文件？${DIM}[1] ~/.bashrc  [2] ~/.zshrc (默认 1)${NC}: "
        read -r rc_choice
        [[ "$rc_choice" == 2 ]] && RC_FILE="$HOME/.zshrc"
    fi

    block=$(sed "s|@@PROXY_ADDR@@|${PROXY_HELPER_ADDR}|g" "$CONFIG_DIR/proxy-helpers.sh")
    # 内容相同则不动 rc 文件
    if [[ -f "$RC_FILE" ]] && grep -q '# >>> proxy helpers >>>' "$RC_FILE" &&
        [[ "$(sed -n '/# >>> proxy helpers >>>/,/# <<< proxy helpers <<</p' "$RC_FILE")" == "$block" ]]; then
        skip "${RC_FILE} 中的 proxy helpers 已是最新"
        return 0
    fi

    backup_if_exists "$RC_FILE"
    if [[ -f "$RC_FILE" ]] && grep -q '# >>> proxy helpers >>>' "$RC_FILE" 2>/dev/null; then
        sed -i '/# >>> proxy helpers >>>/,/# <<< proxy helpers <<</d' "$RC_FILE"
        info "已移除旧的 proxy helpers 配置"
    fi
    printf '\n%s\n' "$block" >> "$RC_FILE"
    ok "proxy_on / proxy_off 已写入 ${RC_FILE} (地址 ${PROXY_HELPER_ADDR})"
    info "执行 ${BOLD}source ${RC_FILE}${NC} 或重开终端后，可用 proxy_on / proxy_off 切换代理"
}

# ========================= 摘要 =========================
# print_summary <工具名...>
print_summary() {
    step "安装摘要"
    echo ""
    echo -e "  ${BOLD}┌────────────────────┬────────────────┐${NC}"
    printf "  ${BOLD}│${NC} %-18s ${BOLD}│${NC} %-14s ${BOLD}│${NC}\n" "工具" "状态"
    echo -e "  ${BOLD}├────────────────────┼────────────────┤${NC}"
    local tool val color
    for tool in "$@"; do
        val="${STATUS[$tool]:-—}"
        if [[ "$val" == "✘" ]]; then
            color="$RED"
        else
            color="$GREEN"
        fi
        printf "  ${BOLD}│${NC} %-18s ${BOLD}│${NC} ${color}%-14s${NC} ${BOLD}│${NC}\n" "$tool" "$val"
    done
    echo -e "  ${BOLD}└────────────────────┴────────────────┘${NC}"
}

print_manual_header() {
    echo ""
    echo -e "  ${YELLOW}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${YELLOW}${BOLD}║          以下操作需要您手动完成                      ║${NC}"
    echo -e "  ${YELLOW}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}
