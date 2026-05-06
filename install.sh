#!/usr/bin/env bash
# ============================================================
# macOS / Linux 开发工具一键安装与配置
# 支持: Ghostty / Yazi / Lazygit / Claude Code / OpenClaw / Hermes / OrbStack / Obsidian / Maccy / JDK / VS Code
# 用法:
#   全部安装:  ./install.sh
#   选择安装:  ./install.sh ghostty yazi lazygit claude codex openclaw orbstack obsidian maccy jdk vscode
#   查看帮助:  ./install.sh --help
# ============================================================
set -uo pipefail

# ── 颜色输出 ──────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR ]${NC} $*"; }

# ── 系统检测 ─────────────────────────────────────────
OS="$(uname -s)"          # Darwin / Linux
ARCH="$(uname -m)"        # x86_64 / arm64 / aarch64
DISTRO=""                 # ubuntu / debian / fedora / arch / ...
PKG_MGR=""                # apt / dnf / yum / pacman / zypper
NO_BREW=false             # Linux 精简模式：跳过 brew 和 zsh 切换，全部走原生包管理器

is_macos() { [[ "$OS" == "Darwin" ]]; }
is_linux() { [[ "$OS" == "Linux" ]]; }
is_root()  { [[ "$EUID" -eq 0 ]]; }

if is_linux; then
    if [[ -f /etc/os-release ]]; then
        DISTRO=$(. /etc/os-release && echo "${ID}")
    fi
    if command -v apt-get &>/dev/null; then
        PKG_MGR="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MGR="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MGR="yum"
    elif command -v pacman &>/dev/null; then
        PKG_MGR="pacman"
    elif command -v zypper &>/dev/null; then
        PKG_MGR="zypper"
    fi
fi

# 跨平台 sed -i (BSD vs GNU)
sed_i() {
    if is_macos; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# 跨平台剪贴板复制命令
clipboard_copy_cmd() {
    if is_macos; then
        echo "pbcopy"
    elif command -v xclip &>/dev/null; then
        echo "xclip -selection clipboard"
    elif command -v xsel &>/dev/null; then
        echo "xsel --clipboard --input"
    elif command -v wl-copy &>/dev/null; then
        echo "wl-copy"
    else
        echo "xclip -selection clipboard"
    fi
}

# 跨平台 open 命令
open_cmd() {
    if is_macos; then
        echo "open"
    else
        echo "xdg-open"
    fi
}

# Linux 原生包安装 (用于 brew 不可用时的后备)
native_install() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)    sudo apt-get install -y "$pkg" ;;
        dnf)    sudo dnf install -y "$pkg" ;;
        yum)    sudo yum install -y "$pkg" ;;
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        zypper) sudo zypper install -y "$pkg" ;;
        *)      err "未知包管理器，请手动安装: $pkg"; return 1 ;;
    esac
}

# ── 国内加速配置 ──────────────────────────────────────
USE_MIRROR=false
GITHUB_PROXY=""
MIRROR_PROVIDER="${MIRROR:-ghfast}"

setup_mirror() {
    # 如果已通过 --mirror 标志启用，跳过检测
    if ! $USE_MIRROR; then
        echo ""
        echo -en "  ${BOLD}正在检测网络...${NC}"
        if curl -fsSL --connect-timeout 3 https://raw.githubusercontent.com/github/gitignore/main/README.md &>/dev/null; then
            ok " 网络正常"
        else
            warn " 国外网站连接较慢，已自动开启加速"
            USE_MIRROR=true
        fi
    fi

    if $USE_MIRROR; then
        case "$MIRROR_PROVIDER" in
            ghfast)   GITHUB_PROXY="https://ghfast.top/" ;;
            ghproxy)  GITHUB_PROXY="https://ghproxy.com/" ;;
            jsdelivr) GITHUB_PROXY="https://ghfast.top/" ;;  # jsDelivr 只能代理 raw 文件，其他资源回退
            *)
                warn "未知 MIRROR=${MIRROR_PROVIDER} (可选: ghfast/ghproxy/jsdelivr)，回退到 ghfast"
                MIRROR_PROVIDER="ghfast"
                GITHUB_PROXY="https://ghfast.top/"
                ;;
        esac

        # Homebrew 镜像 (USTC)
        export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
        export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
        export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
        export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"

        # Node.js 镜像 (npmmirror)
        export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"
        export npm_config_registry="https://registry.npmmirror.com"

        ok "已启用国内镜像加速 (MIRROR=${MIRROR_PROVIDER})"
        if [[ "$MIRROR_PROVIDER" == "jsdelivr" ]]; then
            info "  Raw 文件:      cdn.jsdelivr.net/gh (~12h CDN 缓存)"
            info "  其他 GitHub:   ${GITHUB_PROXY}"
        else
            info "  GitHub 代理:   ${GITHUB_PROXY}"
        fi
        info "  Homebrew 镜像: USTC"
        info "  Node.js 镜像:  npmmirror"
    fi
}

# GitHub 原始文件 URL 加速
# jsdelivr 模式: raw.githubusercontent.com/user/repo/branch/path -> cdn.jsdelivr.net/gh/user/repo@branch/path
# 其他模式: 前缀代理
github_raw_url() {
    local url="$1"
    if ! $USE_MIRROR; then
        echo "$url"
        return
    fi
    if [[ "$MIRROR_PROVIDER" == "jsdelivr" && "$url" =~ ^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.*)$ ]]; then
        echo "https://cdn.jsdelivr.net/gh/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}@${BASH_REMATCH[3]}/${BASH_REMATCH[4]}"
    else
        echo "${GITHUB_PROXY}${url}"
    fi
}

# GitHub 仓库 clone URL 加速 (jsDelivr 不支持 git clone, 统一走 GITHUB_PROXY)
github_clone_url() {
    local url="$1"
    if $USE_MIRROR; then
        echo "${GITHUB_PROXY}${url}"
    else
        echo "$url"
    fi
}

# ── 启动时清理残留 brew 进程和锁文件 ─────────────────
pkill -9 -f 'brew install\|brew fetch' 2>/dev/null
if is_macos; then
    find "$HOME/Library/Caches/Homebrew/downloads" -name '*incomplete*' -delete 2>/dev/null
fi

# ── 帮助信息 ──────────────────────────────────────────
show_help() {
    cat << 'EOF'
macOS / Linux 开发工具一键安装脚本

用法:
  ./install.sh                 交互式选择要安装的工具
  ./install.sh --all           安装全部工具
  ./install.sh --uninstall     交互式选择卸载工具
  ./install.sh --skip          跳过工具安装，仅修改配置
  ./install.sh --mirror        强制使用国内镜像加速
  ./install.sh --no-brew       Linux 精简模式: 跳过 Homebrew 和 zsh 切换 (root/容器/服务器场景)
  ./install.sh <tool> ...      只安装指定工具

环境变量:
  MIRROR=<provider>            指定镜像源 (ghfast | ghproxy | jsdelivr, 默认 ghfast)
                               jsdelivr 仅加速 raw 文件, 其余资源回退 ghfast

可选工具:
  ghostty          GPU 加速终端模拟器
  yazi             终端文件管理器
  lazygit          终端 Git UI
  claude           Claude Code (Anthropic AI 编程助手)
  codex            Codex CLI (OpenAI AI 编程助手)
  openclaw         OpenClaw (本地 AI 助手)
  antigravity      Google Antigravity (AI 开发平台)
  orbstack         OrbStack (Docker 容器 & Linux 虚拟机, 仅 macOS)
  obsidian         Obsidian (知识管理 & 笔记工具)
  hermes           Hermes Agent (Nous Research 自学习 AI Agent)
  maccy            Maccy (剪贴板管理工具, 仅 macOS; Linux 安装 CopyQ)
  jdk              JDK (通过 SDKMAN 安装，支持版本选择)
  vscode           VS Code (代码编辑器 + Catppuccin 主题)
  claude-provider  仅修改 Claude API 提供商配置
  lark-mcp         配置飞书/Lark MCP (私有化部署)

示例:
  ./install.sh ghostty yazi          只安装 Ghostty 和 Yazi
  ./install.sh claude codex          只安装 AI 编程助手
  ./install.sh claude openclaw       只安装 AI 工具
  ./install.sh claude-provider       仅切换 Claude 提供商
  ./install.sh lark-mcp              配置飞书 MCP 私有化部署
  ./install.sh --skip                跳过安装，进入配置菜单
  ./install.sh --all                 全部安装
EOF
    exit 0
}

# ── 工具定义 ──────────────────────────────────────────
ALL_TOOLS=("ghostty" "yazi" "lazygit" "claude" "codex" "lark-mcp" "openclaw" "hermes" "antigravity" "orbstack" "obsidian" "maccy" "jdk" "vscode")
SELECTED_TOOLS=()
SKIP_PREREQUISITES=false
UNINSTALL_MODE=false

# ── 解析参数 ──────────────────────────────────────────
parse_args() {
    if [[ $# -eq 0 ]]; then
        interactive_select
        return
    fi

    for arg in "$@"; do
        case "$arg" in
            --help|-h) show_help ;;
            --all|-a)  SELECTED_TOOLS=("${ALL_TOOLS[@]}"); return ;;
            --uninstall|-u) UNINSTALL_MODE=true; return ;;
            --skip|-s) SKIP_PREREQUISITES=true; return ;;
            --mirror|-m) USE_MIRROR=true ;;
            --no-brew) NO_BREW=true ;;
            claude-provider)
                SKIP_PREREQUISITES=true
                SELECTED_TOOLS+=("claude-provider") ;;
            ghostty|yazi|lazygit|claude|codex|lark-mcp|openclaw|hermes|antigravity|orbstack|obsidian|maccy|jdk|vscode)
                SELECTED_TOOLS+=("$arg") ;;
            *)
                err "未知选项: $arg"
                echo "运行 ./install.sh --help 查看帮助"
                exit 1 ;;
        esac
    done

    # 只传了 --mirror 这类修饰性参数而没选工具时，仍然展示菜单
    if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]] && ! $UNINSTALL_MODE && ! $SKIP_PREREQUISITES; then
        interactive_select
    fi
}

# ── 交互式多选菜单 (方向键导航 + 空格选择) ───────────
interactive_select() {
    local orbstack_label="OrbStack     轻量容器工具 (替代 Docker Desktop)"
    local maccy_label="Maccy        剪贴板历史 (找回之前复制的内容)"
    if is_linux; then
        orbstack_label="Docker       容器工具 (运行服务器程序)"
        maccy_label="CopyQ        剪贴板历史 (找回之前复制的内容)"
    fi
    local labels=(
        "Ghostty      好看的终端窗口 (替代系统自带终端)"
        "Yazi         文件管理器 (在终端里浏览文件)"
        "Lazygit      Git 图形界面 (不用记 Git 命令)"
        "Claude Code  AI 编程助手 (Anthropic)"
        "Codex CLI    AI 编程助手 (OpenAI)"
        "Lark MCP    飞书文档接入 (私有化部署)"
        "OpenClaw     本地 AI 助手 (不联网也能用)"
        "Hermes       AI 智能体 (自动完成复杂任务)"
        "Antigravity  Google AI 平台"
        "$orbstack_label"
        "Obsidian     笔记软件 (写文档/知识管理)"
        "$maccy_label"
        "JDK          Java 环境 (Java 开发必备)"
        "VS Code      代码编辑器 (自动装中文和主题)"
    )
    local count=${#labels[@]}
    local selected=()
    local cursor=0

    for ((i=0; i<count; i++)); do
        selected+=("off")
    done

    # 绘制整个菜单 (光标当前在菜单底部下方一行)
    draw_menu() {
        # 光标上移 count 行回到菜单顶部
        printf '\033[%dA' "$count" > /dev/tty
        for ((i=0; i<count; i++)); do
            # 清除当前行
            printf '\033[2K' > /dev/tty
            local check=" "
            [[ "${selected[$i]}" == "on" ]] && check="*"
            if [[ $i -eq $cursor ]]; then
                printf '  \033[0;36m>\033[0m [\033[0;32m%s\033[0m] %s\n' "$check" "${labels[$i]}" > /dev/tty
            else
                printf '    [%s] %s\n' "$check" "${labels[$i]}" > /dev/tty
            fi
        done
    }

    # 打印标题
    printf '\n' > /dev/tty
    local os_label="macOS"
    is_linux && os_label="Linux"
    printf '\033[1;36m========================================\033[0m\n' > /dev/tty
    printf '\033[1;36m  Kaishi - %s 开发工具一键安装\033[0m\n' "$os_label" > /dev/tty
    printf '\033[1;36m========================================\033[0m\n' > /dev/tty
    printf '\n' > /dev/tty
    printf '\033[1m操作: ↑↓ 移动  空格 选择  a 全选  u 卸载  回车 开始安装  q 退出\033[0m\n' > /dev/tty
    printf '\n' > /dev/tty

    # 首次绘制 (打印 count 行，光标停在最后一行之后)
    for ((i=0; i<count; i++)); do
        local check=" "
        if [[ $i -eq $cursor ]]; then
            printf '  \033[0;36m>\033[0m [%s] %s\n' "$check" "${labels[$i]}" > /dev/tty
        else
            printf '    [%s] %s\n' "$check" "${labels[$i]}" > /dev/tty
        fi
    done

    # 隐藏光标
    printf '\033[?25l' > /dev/tty

    # 读取按键循环
    while true; do
        IFS= read -rsn1 key < /dev/tty

        case "$key" in
            $'\x1b')
                # 读取方向键剩余字节
                IFS= read -rsn1 bracket < /dev/tty
                IFS= read -rsn1 code < /dev/tty
                if [[ "$bracket" == "[" ]]; then
                    case "$code" in
                        A) ((cursor > 0)) && ((cursor--)) ;;          # 上
                        B) ((cursor < count-1)) && ((cursor++)) ;;    # 下
                    esac
                fi
                ;;
            ' ')
                if [[ "${selected[$cursor]}" == "off" ]]; then
                    selected[$cursor]="on"
                else
                    selected[$cursor]="off"
                fi
                ;;
            a|A)
                local all_on=true
                for ((i=0; i<count; i++)); do
                    [[ "${selected[$i]}" == "off" ]] && all_on=false && break
                done
                if $all_on; then
                    for ((i=0; i<count; i++)); do selected[$i]="off"; done
                else
                    for ((i=0; i<count; i++)); do selected[$i]="on"; done
                fi
                ;;
            '')
                # 显示光标并换行
                printf '\033[?25h' > /dev/tty
                printf '\n' > /dev/tty
                break
                ;;
            u|U)
                printf '\033[?25h\n' > /dev/tty
                UNINSTALL_MODE=true
                return
                ;;
            q|Q)
                printf '\033[?25h\n' > /dev/tty
                echo "已取消。" > /dev/tty
                exit 0
                ;;
        esac

        draw_menu
    done

    # 收集选中的工具
    for ((i=0; i<count; i++)); do
        if [[ "${selected[$i]}" == "on" ]]; then
            SELECTED_TOOLS+=("${ALL_TOOLS[$i]}")
        fi
    done

    if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
        info "未选择工具，退出"
        exit 0
    fi
}

# ── 工具函数 ──────────────────────────────────────────
is_selected() {
    local tool="$1"
    [[ ${#SELECTED_TOOLS[@]} -eq 0 ]] && return 1
    for t in "${SELECTED_TOOLS[@]}"; do
        [[ "$t" == "$tool" ]] && return 0
    done
    return 1
}

source_zshrc() {
    if [[ -f "$HOME/.zshrc" ]]; then
        source "$HOME/.zshrc" 2>/dev/null || true
    fi
}

# 把一段配置块追加到合适的 shell rc 文件中。
# - 默认写入 ~/.zshrc
# - NO_BREW 模式（通常没装 zsh）下写入 ~/.bashrc
# - 通过 marker 关键字判断是否已存在，已存在则跳过
# 用法: append_shell_rc <marker> <<'EOF' ... EOF
append_shell_rc() {
    local marker="$1"
    local content
    content="$(cat)"
    local files=()
    if $NO_BREW || [[ ! -f "$HOME/.zshrc" && -f "$HOME/.bashrc" ]]; then
        files+=("$HOME/.bashrc")
        # 如果用户也有 .zshrc，顺便也写进去（双 shell 用户）
        [[ -f "$HOME/.zshrc" ]] && files+=("$HOME/.zshrc")
    else
        files+=("$HOME/.zshrc")
        # 如果用户也用 bash，bash 登录时也能用到
        [[ -f "$HOME/.bashrc" ]] && files+=("$HOME/.bashrc")
    fi
    for rc in "${files[@]}"; do
        if [[ ! -e "$rc" ]] || ! grep -q "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\n' "$content" >> "$rc"
        fi
    done
}

backup_if_exists() {
    local path="$1"
    if [[ -e "$path" ]]; then
        local backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
        warn "备份已有配置: $path -> $backup"
        cp -r "$path" "$backup"
    fi
}

# ══════════════════════════════════════════════════════
# 环境基础检查 (默认安装，无需选择)
# ══════════════════════════════════════════════════════
check_prerequisites() {
    echo ""
    echo -e "  ${BOLD}正在准备基础环境 (首次较慢，请耐心等待)...${NC}"
    echo ""

    # root 用户在 Linux 上自动启用 --no-brew (Homebrew 拒绝 root 安装)
    if is_linux && is_root && ! $NO_BREW; then
        warn "检测到当前是 root 用户，Homebrew 不允许 root 安装"
        warn "自动启用 --no-brew 模式: 跳过 Homebrew 和 zsh 切换，全部走原生包管理器"
        NO_BREW=true
    fi

    # ── 步骤 1/7: 网络 ──────────────────────────────
    info "[1/7] 检测网络环境..."
    setup_mirror

    local need_source_zshrc=false

    # ── 步骤 2/7: 编译工具链 ──────────────────────────
    info "[2/7] 检查编译工具 (安装软件必需的基础组件)..."
    if is_macos; then
        # macOS: Xcode Command Line Tools
        if xcode-select -p &>/dev/null && xcrun --version &>/dev/null; then
            ok "Xcode Command Line Tools 已安装"
        else
            if xcode-select -p &>/dev/null; then
                warn "Xcode Command Line Tools 路径存在但工具损坏，正在重置..."
                sudo xcode-select --reset 2>/dev/null < /dev/tty
            fi
            info "正在安装 Xcode Command Line Tools (Homebrew 编译依赖)..."
            xcode-select --install 2>/dev/null
            info "请在弹出的对话框中点击「安装」，等待完成后按回车继续..."
            read -r < /dev/tty
            if xcrun --version &>/dev/null; then
                ok "Xcode Command Line Tools 安装完成"
            else
                err "Xcode Command Line Tools 安装失败，部分 brew 包可能无法编译安装"
            fi
        fi
    else
        # Linux: build-essential / base-devel
        if command -v gcc &>/dev/null && command -v make &>/dev/null; then
            ok "编译工具链已安装 (gcc, make)"
        else
            info "正在安装编译工具链 (Homebrew 编译依赖)..."
            case "$PKG_MGR" in
                apt)    sudo apt-get update && sudo apt-get install -y build-essential curl file git procps ;;
                dnf)    sudo dnf groupinstall -y "Development Tools" && sudo dnf install -y curl file git procps-ng ;;
                yum)    sudo yum groupinstall -y "Development Tools" && sudo yum install -y curl file git procps ;;
                pacman) sudo pacman -S --noconfirm base-devel curl file git procps-ng ;;
                zypper) sudo zypper install -y -t pattern devel_basis && sudo zypper install -y curl file git procps ;;
                *)      warn "请手动安装编译工具链 (gcc, make, curl, git)" ;;
            esac
            ok "编译工具链安装完成"
        fi
    fi

    # ── 步骤 2/7 续: Zsh ──────────────────────────────
    if $NO_BREW; then
        # 精简模式：zsh 改为可选；不切换默认 shell（避免 chsh 静默失败留隐患）
        if command -v zsh &>/dev/null; then
            ok "Zsh 已安装: $(zsh --version)"
            info "精简模式不切换默认 Shell，可手动: chsh -s $(which zsh)"
        else
            info "精简模式跳过 Zsh 安装 (可后续手动: native_install zsh 或包管理器自行安装)"
        fi
    elif command -v zsh &>/dev/null; then
        ok "Zsh 已安装: $(zsh --version)"
        if [[ "$SHELL" == *zsh ]]; then
            ok "Zsh 已是默认 Shell"
        else
            warn "当前默认 Shell 为 $SHELL，正在切换到 Zsh..."
            if is_linux; then
                # Linux 上 chsh 可能需要 sudo，且 zsh 路径可能不在 /etc/shells
                local zsh_path
                zsh_path="$(which zsh)"
                grep -qxF "$zsh_path" /etc/shells 2>/dev/null || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
                sudo chsh -s "$zsh_path" "$(whoami)" 2>/dev/null || chsh -s "$zsh_path" 2>/dev/null < /dev/tty
            else
                chsh -s "$(which zsh)"
            fi
            ok "已将默认 Shell 切换为 Zsh (重新登录后生效)"
        fi
    else
        info "正在安装 Zsh..."
        if is_linux && [[ -n "$PKG_MGR" ]]; then
            native_install zsh
        else
            brew install zsh
        fi
        local zsh_path
        zsh_path="$(which zsh)"
        if is_linux; then
            grep -qxF "$zsh_path" /etc/shells 2>/dev/null || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
            sudo chsh -s "$zsh_path" "$(whoami)" 2>/dev/null || chsh -s "$zsh_path" 2>/dev/null < /dev/tty
        else
            chsh -s "$zsh_path"
        fi
        ok "Zsh 安装完成，已设为默认 Shell"
    fi

    # ── 步骤 3/7: Homebrew ─────────────────────────────
    info "[3/7] 检查 Homebrew (用来安装软件的工具)..."
    if $NO_BREW; then
        info "精简模式跳过 Homebrew，所有 brew 包将走原生包管理器 ($PKG_MGR)"
        # 清理可能残留的无效 shellenv (避免下次登录 zsh 报错)
        if [[ -f "$HOME/.zshrc" ]] && grep -q 'linuxbrew' "$HOME/.zshrc" 2>/dev/null; then
            if ! command -v brew &>/dev/null && [[ ! -f /home/linuxbrew/.linuxbrew/bin/brew && ! -f "$HOME/.linuxbrew/bin/brew" ]]; then
                warn "检测到 ~/.zshrc 残留无效的 Linuxbrew shellenv，正在清理..."
                sed_i '/linuxbrew/d' "$HOME/.zshrc"
            fi
        fi
    elif command -v brew &>/dev/null; then
        ok "Homebrew 已安装: $(brew --version | head -1)"
    else
        info "未检测到 Homebrew，正在安装..."
        info "Homebrew 需要管理员权限，请输入密码:"
        sudo -v < /dev/tty
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$(github_raw_url https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)")" < /dev/tty
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        elif [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        elif [[ -f "$HOME/.linuxbrew/bin/brew" ]]; then
            eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
        fi

        # 验证 brew 真的可用，否则降级到 NO_BREW 模式 (避免后续静默失败)
        if ! command -v brew &>/dev/null; then
            err "Homebrew 安装失败，自动降级到精简模式 (--no-brew)"
            NO_BREW=true
        else
            ok "Homebrew 安装完成: $(brew --version | head -1)"
            # Linux: 将 Homebrew 环境变量写入 shell 配置 (zsh + bash 都覆盖)
            if is_linux; then
                append_shell_rc 'linuxbrew' << 'BREW_LINUX_EOF'
# Homebrew (Linuxbrew)
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null || $HOME/.linuxbrew/bin/brew shellenv 2>/dev/null)"
BREW_LINUX_EOF
                ok "Homebrew 环境变量已写入 shell 配置"
            fi
        fi
    fi

    # ── 步骤 4/7: Git ────────────────────────────────
    info "[4/7] 检查 Git (代码版本管理工具)..."
    if command -v git &>/dev/null; then
        ok "Git 已安装: $(git --version)"
    else
        info "正在安装 Git..."
        if $NO_BREW; then
            native_install git || err "Git 原生安装失败，请手动安装"
        else
            brew install git
        fi
        ok "Git 安装完成: $(git --version 2>/dev/null || echo '')"
    fi

    # ── 步骤 5/7: NVM ─────────────────────────────────
    info "[5/7] 检查 Node.js (很多工具依赖它)..."
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    # 尝试加载已有的 nvm
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null

    if command -v nvm &>/dev/null; then
        ok "NVM 已安装: $(nvm --version)"
    else
        info "正在安装 NVM..."
        # PROFILE=/dev/null 防止 NVM 安装脚本修改 shell 配置导致管道中断
        curl -fsSL "$(github_raw_url https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh)" | PROFILE=/dev/null bash
        # 立即加载 nvm
        export NVM_DIR="$HOME/.nvm"
        [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
        ok "NVM 安装完成: $(nvm --version 2>/dev/null || echo '已安装')"
        # 手动写入 shell 配置 (因为上面用了 PROFILE=/dev/null 跳过了自动写入)
        append_shell_rc 'NVM_DIR' << 'NVM_EOF'
# NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
NVM_EOF
        ok "NVM 配置已写入 shell 配置"
        need_source_zshrc=true
    fi

    # ── 步骤 6/7: Node.js ─────────────────────────────
    if command -v node &>/dev/null; then
        ok "Node.js 已安装: $(node --version)"
    else
        if command -v nvm &>/dev/null; then
            info "正在通过 NVM 安装 Node.js LTS..."
            nvm install --lts
            nvm use --lts
            nvm alias default lts/*
            ok "Node.js 安装完成: $(node --version)"
        else
            if $NO_BREW; then
                info "NVM 不可用，通过原生包管理器安装 Node.js..."
                native_install nodejs || warn "Node.js 原生安装失败，可手动: nvm install --lts"
            else
                info "NVM 不可用，通过 Homebrew 安装 Node.js..."
                brew install node
            fi
            ok "Node.js 安装完成: $(node --version 2>/dev/null || echo '')"
        fi
    fi

    # ── 步骤 7/7: Bun ─────────────────────────────────
    info "[7/7] 检查 Bun (高性能开发工具)..."
    if command -v bun &>/dev/null; then
        ok "Bun 已安装: $(bun --version)"
    else
        info "正在安装 Bun..."
        local bun_installed=false
        if ! $NO_BREW && brew install oven-sh/bun/bun 2>&1; then
            bun_installed=true
            ok "Bun 安装完成: $(bun --version)"
        fi
        if ! $bun_installed; then
            $NO_BREW || warn "Homebrew 安装失败，尝试官方脚本..."
            curl -fsSL https://bun.sh/install | bash
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:$PATH"
            append_shell_rc 'BUN_INSTALL' << 'BUN_EOF'
# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
BUN_EOF
            ok "Bun 配置已写入 shell 配置"
            need_source_zshrc=true
            ok "Bun 安装完成: $(bun --version 2>/dev/null || echo '已安装')"
        fi
    fi

    echo ""
    echo -e "${GREEN}${BOLD}  基础环境准备完成!${NC}"

    if $need_source_zshrc; then
        echo -e "${YELLOW}提示: 部分配置需要 source ~/.zshrc 或重新打开终端后生效${NC}"
    fi

    echo ""
}

# 强制清理 brew 残留锁文件和僵尸进程
brew_cleanup_locks() {
    local default_cache="$HOME/Library/Caches/Homebrew/downloads"
    is_linux && default_cache="$HOME/.cache/Homebrew/downloads"
    local cache_dir
    cache_dir="$(brew --cache 2>/dev/null || echo "$default_cache")"
    # 杀掉所有残留的 brew 子进程
    local stale_pids
    stale_pids=$(ps aux | grep '[b]rew install\|[b]rew fetch' | awk '{print $2}')
    if [[ -n "$stale_pids" ]]; then
        warn "终止残留 brew 进程..."
        echo "$stale_pids" | xargs kill -9 2>/dev/null
        sleep 1
    fi
    # 删除所有锁文件
    find "$cache_dir" -name '*incomplete*' -maxdepth 1 -delete 2>/dev/null
}

# brew formula → 原生包名映射 (NO_BREW 模式 fallback 使用)
brew_to_native() {
    local formula="$1"
    case "$PKG_MGR" in
        apt)
            case "$formula" in
                fd) echo "fd-find" ;;
                ripgrep) echo "ripgrep" ;;
                git-delta) echo "git-delta" ;;
                sevenzip) echo "p7zip-full" ;;
                ffmpegthumbnailer) echo "ffmpegthumbnailer" ;;
                font-symbols-only-nerd-font) echo "" ;;  # 无对应包，走二进制下载
                *) echo "$formula" ;;
            esac ;;
        dnf|yum)
            case "$formula" in
                fd) echo "fd-find" ;;
                ripgrep) echo "ripgrep" ;;
                git-delta) echo "git-delta" ;;
                sevenzip) echo "p7zip" ;;
                ffmpegthumbnailer) echo "ffmpegthumbnailer" ;;
                imagemagick) echo "ImageMagick" ;;
                font-symbols-only-nerd-font) echo "" ;;
                *) echo "$formula" ;;
            esac ;;
        pacman)
            case "$formula" in
                fd) echo "fd" ;;
                git-delta) echo "git-delta" ;;
                sevenzip) echo "7zip" ;;
                font-symbols-only-nerd-font) echo "ttf-nerd-fonts-symbols" ;;
                *) echo "$formula" ;;
            esac ;;
        zypper)
            case "$formula" in
                fd) echo "fd" ;;
                ripgrep) echo "ripgrep" ;;
                git-delta) echo "git-delta" ;;
                sevenzip) echo "p7zip" ;;
                font-symbols-only-nerd-font) echo "" ;;
                *) echo "$formula" ;;
            esac ;;
        *) echo "$formula" ;;
    esac
}

# 带重试的 brew install (最多 3 次，每次失败自动清锁)
# NO_BREW 模式下: 转发到原生包管理器，无对应包则 warn 跳过
brew_install() {
    local formula="$1"
    local name="${2:-$formula}"

    if $NO_BREW; then
        local pkg
        pkg="$(brew_to_native "$formula")"
        if [[ -z "$pkg" ]]; then
            warn "$name 在 $PKG_MGR 下无对应原生包，已跳过 (可手动从 GitHub release 下载)"
            return
        fi
        info "正在安装 $name ($pkg) ..."
        if native_install "$pkg" 2>&1; then
            ok "$name 安装完成"
        else
            warn "$name 原生安装失败，已跳过"
        fi
        return
    fi

    if brew list "$formula" &>/dev/null; then
        ok "$name 已安装"
        return
    fi

    local max_retries=3
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        brew_cleanup_locks
        if [[ $attempt -gt 1 ]]; then
            warn "$name 第 $attempt 次重试..."
        else
            info "正在安装 $name ..."
        fi
        if brew install "$formula" 2>&1; then
            ok "$name 安装完成"
            return
        fi
        err "$name 安装失败 (第 $attempt/$max_retries 次)"
        ((attempt++))
    done
    err "$name 安装失败，已跳过。可稍后手动运行: brew install $formula"
}

brew_install_cask() {
    local cask="$1"
    local name="${2:-$cask}"

    if $NO_BREW; then
        warn "$name 是 GUI 应用 (cask)，精简模式跳过"
        return
    fi

    if is_macos; then
        if brew list --cask "$cask" &>/dev/null; then
            ok "$name (cask) 已安装"
            return
        fi

        local max_retries=3
        local attempt=1
        while [[ $attempt -le $max_retries ]]; do
            brew_cleanup_locks
            if [[ $attempt -gt 1 ]]; then
                warn "$name 第 $attempt 次重试..."
            else
                info "正在安装 $name ..."
            fi
            if brew install --cask "$cask" 2>&1; then
                ok "$name 安装完成"
                return
            fi
            err "$name 安装失败 (第 $attempt/$max_retries 次)"
            ((attempt++))
        done
        err "$name 安装失败，已跳过。可稍后手动运行: brew install --cask $cask"
    else
        # Linux: cask 不可用，尝试 flatpak 或提示手动安装
        warn "$name 为 macOS GUI 应用，Linux 上跳过 cask 安装"
    fi
}

# 从 GitHub release 下载二进制并安装到 ~/.local/bin
# 用于 Linux 上 native 包不可用的工具 (lazygit, yazi, delta 等)
# 用法: github_bin_install <name> <repo> <asset-pattern> [extracted-binary-path]
#   asset-pattern: 文件名模式，{ARCH} 会被替换为 x86_64 / aarch64 / arm64
#   extracted-binary-path: 解压后二进制相对路径 (默认与 name 同名)
github_bin_install() {
    local name="$1"
    local repo="$2"
    local pattern="$3"
    local bin_path="${4:-$name}"

    if command -v "$name" &>/dev/null; then
        ok "$name 已安装"
        return
    fi

    local arch="$ARCH"
    [[ "$arch" == "arm64" ]] && arch="aarch64"
    pattern="${pattern//\{ARCH\}/$arch}"

    info "从 GitHub release 下载 $name ..."
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local asset_url
    asset_url=$(curl -fsSL "$api_url" 2>/dev/null \
        | grep -oE "\"browser_download_url\": *\"[^\"]*$pattern[^\"]*\"" \
        | head -1 \
        | sed -E 's/.*"(https[^"]+)".*/\1/')
    if [[ -z "$asset_url" ]]; then
        warn "$name: 未在 GitHub release 中匹配到 $pattern (架构=$arch)，已跳过"
        return 1
    fi

    # 走镜像加速
    if $USE_MIRROR && [[ -n "$GITHUB_PROXY" ]]; then
        asset_url="${GITHUB_PROXY}${asset_url}"
    fi

    local tmp
    tmp="$(mktemp -d)"
    local asset_file="$tmp/${asset_url##*/}"
    if ! curl -fsSL -o "$asset_file" "$asset_url"; then
        warn "$name: 下载失败 ($asset_url)"
        rm -rf "$tmp"
        return 1
    fi

    mkdir -p "$HOME/.local/bin"
    case "$asset_file" in
        *.tar.gz|*.tgz) tar -xzf "$asset_file" -C "$tmp" ;;
        *.tar.xz)       tar -xJf "$asset_file" -C "$tmp" ;;
        *.zip)          unzip -q -o "$asset_file" -d "$tmp" ;;
        *)              cp "$asset_file" "$tmp/$bin_path" ;;
    esac

    local found
    found=$(find "$tmp" -type f -name "$(basename "$bin_path")" -perm -u+x 2>/dev/null | head -1)
    [[ -z "$found" ]] && found=$(find "$tmp" -type f -name "$(basename "$bin_path")" 2>/dev/null | head -1)
    if [[ -z "$found" ]]; then
        warn "$name: 解压后未找到二进制 $bin_path，已跳过"
        rm -rf "$tmp"
        return 1
    fi

    install -m 0755 "$found" "$HOME/.local/bin/$name"
    rm -rf "$tmp"

    # 确保 ~/.local/bin 在 PATH 中
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
        append_shell_rc 'HOME/.local/bin' << 'LOCALBIN_EOF'
# 用户本地二进制目录
export PATH="$HOME/.local/bin:$PATH"
LOCALBIN_EOF
    fi

    ok "$name 安装完成: $HOME/.local/bin/$name"
}

# ── Shell 提示符配置 (安装终端时调用) ────────────────
configure_shell_prompt() {
    echo ""
    echo -e "${BOLD}请选择 Shell 提示符工具:${NC}"
    echo -e "  ${CYAN}1)${NC} Oh My Zsh + 插件 (经典方案，功能丰富)"
    echo -e "  ${CYAN}2)${NC} Starship (跨平台极速提示符)"
    echo -e "  ${CYAN}3)${NC} 跳过 (保持现有配置)"
    echo -en "${CYAN}请输入选项 [1/2/3] (默认 1): ${NC}" > /dev/tty
    local prompt_choice
    read -r prompt_choice < /dev/tty
    prompt_choice="${prompt_choice:-1}"

    if [[ "$prompt_choice" == "2" ]]; then
        # ── Starship ────────────────────────────────────
        if command -v starship &>/dev/null; then
            ok "Starship 已安装"
        else
            info "正在安装 Starship..."
            if $NO_BREW; then
                # 官方安装脚本，不依赖 brew
                curl -sS "$(github_raw_url https://starship.rs/install.sh)" | sh -s -- --yes 2>/dev/null \
                    || warn "Starship 官方脚本安装失败，可手动: curl -sS https://starship.rs/install.sh | sh"
            else
                brew install starship
            fi
            command -v starship &>/dev/null && ok "Starship 安装完成"
        fi

        # Nerd Font
        echo ""
        echo -e "${BOLD}选择 Nerd Font 字体:${NC}"
        echo -e "  ${CYAN}1)${NC} Hack Nerd Font (推荐)"
        echo -e "  ${CYAN}2)${NC} JetBrainsMono Nerd Font"
        echo -e "  ${CYAN}3)${NC} FiraCode Nerd Font"
        echo -e "  ${CYAN}4)${NC} MesloLG Nerd Font"
        echo -e "  ${CYAN}5)${NC} CascadiaCode Nerd Font"
        echo -e "  ${CYAN}6)${NC} 跳过"
        echo -en "${CYAN}请输入选项 [1-6] (默认 1): ${NC}" > /dev/tty
        local font_choice
        read -r font_choice < /dev/tty
        font_choice="${font_choice:-1}"

        local font_pkg=""
        case "$font_choice" in
            1) font_pkg="font-hack-nerd-font" ;;
            2) font_pkg="font-jetbrains-mono-nerd-font" ;;
            3) font_pkg="font-fira-code-nerd-font" ;;
            4) font_pkg="font-meslo-lg-nerd-font" ;;
            5) font_pkg="font-cascadia-code-nerd-font" ;;
            6) font_pkg="" ;;
            *) font_pkg="font-hack-nerd-font" ;;
        esac

        if [[ -n "$font_pkg" ]]; then
            if is_macos; then
                brew list --cask "$font_pkg" &>/dev/null || brew install --cask "$font_pkg"
                ok "$font_pkg 已安装"
            else
                local font_dir="$HOME/.local/share/fonts"
                local nf_name=""
                case "$font_pkg" in
                    font-hack-nerd-font)           nf_name="Hack" ;;
                    font-jetbrains-mono-nerd-font) nf_name="JetBrainsMono" ;;
                    font-fira-code-nerd-font)      nf_name="FiraCode" ;;
                    font-meslo-lg-nerd-font)       nf_name="Meslo" ;;
                    font-cascadia-code-nerd-font)  nf_name="CascadiaCode" ;;
                esac
                if ! fc-list 2>/dev/null | grep -qi "$nf_name" 2>/dev/null; then
                    mkdir -p "$font_dir"
                    local nf_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${nf_name}.zip"
                    local tmp_zip
                    tmp_zip=$(mktemp /tmp/nerd-font-XXXXXX.zip)
                    curl -fsSL "$(github_raw_url "$nf_url")" -o "$tmp_zip" 2>/dev/null && \
                        unzip -o "$tmp_zip" -d "$font_dir/${nf_name}" >/dev/null 2>&1 && \
                        fc-cache -f "$font_dir" 2>/dev/null
                    rm -f "$tmp_zip"
                fi
                ok "$nf_name Nerd Font 已安装"
            fi
            warn "请在终端设置中将字体切换为对应的 Nerd Font"
        fi

        # Starship 主题
        local STARSHIP_CONFIG="$HOME/.config/starship.toml"
        mkdir -p "$HOME/.config"

        echo ""
        echo -e "${BOLD}选择 Starship 主题:${NC}"
        echo -e "  ${CYAN} 1)${NC} Catppuccin Mocha Powerline (推荐)"
        echo -e "  ${CYAN} 2)${NC} catppuccin-powerline"
        echo -e "  ${CYAN} 3)${NC} gruvbox-rainbow"
        echo -e "  ${CYAN} 4)${NC} tokyo-night"
        echo -e "  ${CYAN} 5)${NC} pastel-powerline"
        echo -e "  ${CYAN} 6)${NC} jetpack"
        echo -e "  ${CYAN} 7)${NC} pure-preset"
        echo -e "  ${CYAN} 8)${NC} nerd-font-symbols"
        echo -e "  ${CYAN} 9)${NC} plain-text-symbols"
        echo -e "  ${CYAN}10)${NC} 跳过"
        echo -en "${CYAN}请输入选项 [1-10] (默认 1): ${NC}" > /dev/tty
        local theme_choice
        read -r theme_choice < /dev/tty
        theme_choice="${theme_choice:-1}"

        local GIST_URL="https://gist.githubusercontent.com/zhangchitc/62f5dca64c599084f936fda9963f1100/raw/starship.toml"
        case "$theme_choice" in
            1) curl -fsSL "$(github_raw_url "$GIST_URL")" -o "$STARSHIP_CONFIG" 2>/dev/null || starship preset catppuccin-powerline -o "$STARSHIP_CONFIG" 2>/dev/null
               ok "Starship 主题: Catppuccin Mocha" ;;
            2)  starship preset catppuccin-powerline -o "$STARSHIP_CONFIG" 2>/dev/null; ok "主题: catppuccin-powerline" ;;
            3)  starship preset gruvbox-rainbow -o "$STARSHIP_CONFIG" 2>/dev/null; ok "主题: gruvbox-rainbow" ;;
            4)  starship preset tokyo-night -o "$STARSHIP_CONFIG" 2>/dev/null; ok "主题: tokyo-night" ;;
            5)  starship preset pastel-powerline -o "$STARSHIP_CONFIG" 2>/dev/null; ok "主题: pastel-powerline" ;;
            6)  starship preset jetpack -o "$STARSHIP_CONFIG" 2>/dev/null; ok "主题: jetpack" ;;
            7)  starship preset pure-preset -o "$STARSHIP_CONFIG" 2>/dev/null; ok "主题: pure-preset" ;;
            8)  starship preset nerd-font-symbols -o "$STARSHIP_CONFIG" 2>/dev/null; ok "主题: nerd-font-symbols" ;;
            9)  starship preset plain-text-symbols -o "$STARSHIP_CONFIG" 2>/dev/null; ok "主题: plain-text-symbols" ;;
            10) ok "保持现有 Starship 配置" ;;
        esac

        # 写入 shell 初始化 (zsh + bash 都覆盖)
        if [[ -f "$HOME/.zshrc" ]] || ! $NO_BREW; then
            append_shell_rc 'starship init zsh' << 'STARSHIP_ZSH_EOF'
# Starship (zsh)
eval "$(starship init zsh)"
STARSHIP_ZSH_EOF
        fi
        if [[ -f "$HOME/.bashrc" ]]; then
            if ! grep -q 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
                printf '\n# Starship (bash)\neval "$(starship init bash)"\n' >> "$HOME/.bashrc"
            fi
        fi
        ok "Starship 初始化已写入 shell 配置"

        # Zsh 插件
        local ZSH_PLUGIN_DIR="${HOME}/.zsh/plugins"
        mkdir -p "$ZSH_PLUGIN_DIR"
        [[ ! -d "$ZSH_PLUGIN_DIR/zsh-autosuggestions" ]] && git clone "$(github_clone_url https://github.com/zsh-users/zsh-autosuggestions)" "$ZSH_PLUGIN_DIR/zsh-autosuggestions" 2>/dev/null
        [[ ! -d "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting" ]] && git clone "$(github_clone_url https://github.com/zsh-users/zsh-syntax-highlighting)" "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting" 2>/dev/null
        if ! grep -q 'zsh-autosuggestions.zsh' "$ZSHRC" 2>/dev/null; then
            cat >> "$ZSHRC" << PLUGIN_EOF

# Zsh 插件
[[ -f "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
PLUGIN_EOF
        fi
        ok "Zsh 插件已配置"

    elif [[ "$prompt_choice" == "1" ]]; then
        # ── Oh My Zsh ────────────────────────────────────
        if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
            info "正在安装 Oh My Zsh..."
            RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL "$(github_raw_url https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)")" < /dev/tty
            ok "Oh My Zsh 安装完成"
        else
            ok "Oh My Zsh 已安装"
        fi

        local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] && git clone "$(github_clone_url https://github.com/zsh-users/zsh-autosuggestions)" "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null
        [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && git clone "$(github_clone_url https://github.com/zsh-users/zsh-syntax-highlighting)" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null

        local ZSHRC="$HOME/.zshrc"
        if [[ -f "$ZSHRC" ]] && grep -q "^plugins=" "$ZSHRC" && ! grep -q "zsh-autosuggestions" "$ZSHRC"; then
            sed_i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
            ok "已将插件添加到 .zshrc"
        fi
    else
        ok "已跳过 Shell 提示符配置"
    fi
}

# ══════════════════════════════════════════════════════
# 安装模块
# ══════════════════════════════════════════════════════

# ── Ghostty ───────────────────────────────────────────
install_ghostty() {
    echo ""
    info "========== [1/13] Ghostty =========="
    if is_macos; then
        brew_install_cask ghostty "Ghostty"
    else
        # Linux: 通过包管理器或 brew 安装
        if command -v ghostty &>/dev/null; then
            ok "Ghostty 已安装"
        else
            info "正在安装 Ghostty..."
            local installed=false
            case "$PKG_MGR" in
                apt)
                    # Ubuntu/Debian: 尝试官方 PPA 或 snap
                    if snap install ghostty 2>/dev/null; then
                        installed=true
                    fi
                    ;;
                dnf)
                    # Fedora: 官方仓库可能有
                    if sudo dnf install -y ghostty 2>/dev/null; then
                        installed=true
                    fi
                    ;;
                pacman)
                    # Arch: AUR 或官方仓库
                    if sudo pacman -S --noconfirm ghostty 2>/dev/null; then
                        installed=true
                    fi
                    ;;
            esac
            if ! $installed; then
                # 后备: 通过 brew 安装
                brew_install ghostty "Ghostty"
            else
                ok "Ghostty 安装完成"
            fi
        fi
    fi

    GHOSTTY_DIR="$HOME/.config/ghostty"
    GHOSTTY_CONF="$GHOSTTY_DIR/config"
    mkdir -p "$GHOSTTY_DIR"

    echo ""
    echo -e "  ${CYAN}1)${NC} 使用推荐配置 (Maple Mono + Catppuccin + 毛玻璃)"
    echo -e "  ${CYAN}2)${NC} 使用默认配置 / 保留当前配置"
    echo ""
    read -rp "$(echo -e "${BOLD}选择 Ghostty 配置方案 [1/2] (默认 1): ${NC}")" ghostty_choice < /dev/tty

    if [[ "$ghostty_choice" != "2" ]]; then
        backup_if_exists "$GHOSTTY_CONF"
        if is_macos; then
        cat > "$GHOSTTY_CONF" << 'GHOSTTY_EOF'
# ============================================
# Ghostty Terminal - 完整配置
# ============================================
# 文件路径: ~/.config/ghostty/config
# 重新加载: Cmd+Shift+, (macOS)
# 查看所有选项: ghostty +show-config --default --docs

# --- 字体排版 ---
# 主字体（Maple Mono 等宽字体，含 Nerd Font 图标和中文）
font-family = "Maple Mono NF CN"
# 字号
font-size = 12
# 加粗渲染，让字体在低分辨率下更清晰
font-thicken = true
# 行高微调，增加 2px 让行间距更舒适
adjust-cell-height = 2

# --- 主题与颜色 ---
# 使用 Catppuccin Latte 亮色主题
theme = Catppuccin Latte
#theme = Ayu Light

# --- 窗口与外观 ---
# 背景透明度（0.0 全透明 ~ 1.0 不透明）
background-opacity = 0.85
# 背景模糊半径，配合透明度实现毛玻璃效果
background-blur-radius = 30
# macOS 标题栏透明，与终端背景融为一体
macos-titlebar-style = transparent
# 窗口左右内边距（像素）
window-padding-x = 10
# 窗口上下内边距（像素）
window-padding-y = 8
# 始终保存窗口状态（位置、大小），重启后恢复
window-save-state = always
# 窗口主题跟随系统明暗模式
window-theme = auto

# --- 光标 ---
# 光标样式：bar（竖线）/ block（方块）/ underline（下划线）
cursor-style = bar
# 光标闪烁
cursor-style-blink = true
# 光标透明度
cursor-opacity = 0.8

# --- 鼠标 ---
# 打字时自动隐藏鼠标指针
mouse-hide-while-typing = true
# 选中文本自动复制到系统剪贴板
copy-on-select = clipboard

# --- 快捷终端（Quake 风格下拉终端）---
# 快捷终端从屏幕顶部滑出
quick-terminal-position = top
# 在鼠标所在的屏幕上显示
quick-terminal-screen = mouse
# 失去焦点时自动隐藏
quick-terminal-autohide = true
# 滑出/收回动画时长（秒）
quick-terminal-animation-duration = 0.15

# --- 安全 ---
# 粘贴保护：粘贴含危险命令时弹出确认
clipboard-paste-protection = true
# 括号粘贴模式安全检查，防止粘贴注入攻击
clipboard-paste-bracketed-safe = true

# --- Shell 集成 ---
# 自动检测并启用 Shell 集成（支持 zsh/bash/fish）
shell-integration = detect

# --- 快捷键 ---
# 标签页
# 新建标签页
keybind = cmd+t=new_tab
# 切换到上一个标签页
keybind = cmd+shift+left=previous_tab
# 切换到下一个标签页
keybind = cmd+shift+right=next_tab
# 关闭当前标签页/分屏
keybind = cmd+w=close_surface

# 分屏
# 向右新建分屏
keybind = cmd+d=new_split:right
# 向下新建分屏
keybind = cmd+shift+d=new_split:down
# 焦点移到左侧分屏
keybind = cmd+alt+left=goto_split:left
# 焦点移到右侧分屏
keybind = cmd+alt+right=goto_split:right
# 焦点移到上方分屏
keybind = cmd+alt+up=goto_split:top
# 焦点移到下方分屏
keybind = cmd+alt+down=goto_split:bottom

# 字号调整
# 放大字号
keybind = cmd+plus=increase_font_size:1
# 缩小字号
keybind = cmd+minus=decrease_font_size:1
# 重置字号为默认值
keybind = cmd+zero=reset_font_size

# 快捷终端全局热键
# Ctrl+` 全局唤出/隐藏快捷终端
keybind = global:ctrl+grave_accent=toggle_quick_terminal

# 分屏管理
# 均分所有分屏大小
keybind = cmd+shift+e=equalize_splits
# 切换当前分屏全屏/还原
keybind = cmd+shift+f=toggle_split_zoom

# 重新加载配置
# 重新加载此配置文件
keybind = cmd+shift+comma=reload_config

# --- 性能 ---
# 回滚缓冲区大小（约 25MB），可回看大量历史输出
scrollback-limit = 25000000
GHOSTTY_EOF
        ok "Ghostty 配置已写入 (macOS)"
        else
        # Linux: 不含 macOS 专属配置 (macos-titlebar-style 等)
        cat > "$GHOSTTY_CONF" << 'GHOSTTY_EOF'
# ============================================
# Ghostty Terminal - Linux 配置
# ============================================

# --- 字体排版 ---
font-family = "Maple Mono NF CN"
font-size = 12
font-thicken = true
adjust-cell-height = 2

# --- 主题与颜色 ---
theme = Catppuccin Latte

# --- 窗口与外观 ---
background-opacity = 0.85
window-padding-x = 10
window-padding-y = 8
window-save-state = always
window-theme = auto

# --- 光标 ---
cursor-style = bar
cursor-style-blink = true
cursor-opacity = 0.8

# --- 鼠标 ---
mouse-hide-while-typing = true
copy-on-select = clipboard

# --- 快捷终端 (Quake 风格) ---
quick-terminal-position = top
quick-terminal-screen = mouse
quick-terminal-autohide = true
quick-terminal-animation-duration = 0.15

# --- 安全 ---
clipboard-paste-protection = true
clipboard-paste-bracketed-safe = true

# --- Shell 集成 ---
shell-integration = detect

# --- 快捷键 ---
keybind = ctrl+shift+t=new_tab
keybind = ctrl+shift+left=previous_tab
keybind = ctrl+shift+right=next_tab
keybind = ctrl+shift+w=close_surface
keybind = ctrl+shift+d=new_split:right
keybind = ctrl+shift+e=new_split:down
keybind = ctrl+shift+h=goto_split:left
keybind = ctrl+shift+l=goto_split:right
keybind = ctrl+shift+k=goto_split:top
keybind = ctrl+shift+j=goto_split:bottom
keybind = ctrl+plus=increase_font_size:1
keybind = ctrl+minus=decrease_font_size:1
keybind = ctrl+zero=reset_font_size

# --- 性能 ---
scrollback-limit = 25000000
GHOSTTY_EOF
        ok "Ghostty 配置已写入 (Linux)"
        fi  # end is_macos config
    fi

    # 安装终端时顺便配置 Shell 提示符
    configure_shell_prompt

    source_zshrc
}

# ── Yazi ──────────────────────────────────────────────
install_yazi() {
    echo ""
    info "========== [2/13] Yazi =========="
    brew_install yazi "Yazi"
    # native 失败 fallback (CentOS/RHEL 默认仓库没有 yazi)
    if $NO_BREW && ! command -v yazi &>/dev/null; then
        github_bin_install yazi sxyazi/yazi "{ARCH}-unknown-linux-gnu.zip" yazi || true
        # yazi 包内还附带 ya 命令行
        if [[ -f "$HOME/.local/bin/ya" ]] || command -v ya &>/dev/null; then
            :
        else
            local tmp_ya
            tmp_ya=$(find /tmp -type f -name 'ya' -path '*yazi*' 2>/dev/null | head -1)
            [[ -n "$tmp_ya" ]] && install -m 0755 "$tmp_ya" "$HOME/.local/bin/ya" 2>/dev/null || true
        fi
    fi

    # 辅助依赖
    info "安装 Yazi 辅助依赖..."
    brew_install fd "fd (快速文件查找)"
    brew_install ripgrep "ripgrep (内容搜索)"
    brew_install fzf "fzf (模糊搜索)"
    brew_install zoxide "zoxide (智能目录跳转)"
    brew_install poppler "poppler (PDF 预览)"
    brew_install ffmpegthumbnailer "ffmpegthumbnailer (视频缩略图)"
    brew_install sevenzip "7zip (压缩包预览)"
    brew_install jq "jq (JSON 预览)"
    brew_install imagemagick "ImageMagick (图片处理)"
    if is_macos; then
        brew_install font-symbols-only-nerd-font "Nerd Font Symbols"
    fi

    YAZI_DIR="$HOME/.config/yazi"
    mkdir -p "$YAZI_DIR"

    echo ""
    echo -e "  ${CYAN}1)${NC} 使用推荐配置 (glow 预览 + 大预览区 + 快捷跳转)"
    echo -e "  ${CYAN}2)${NC} 使用默认配置 / 保留当前配置"
    echo ""
    read -rp "$(echo -e "${BOLD}选择 Yazi 配置方案 [1/2] (默认 1): ${NC}")" yazi_choice < /dev/tty

    if [[ "$yazi_choice" != "2" ]]; then

    # yazi.toml
    backup_if_exists "$YAZI_DIR/yazi.toml"
    # 安装 glow (Markdown 终端渲染，用于 Yazi 预览)
    brew_install glow "glow (Markdown 预览)"

    cat > "$YAZI_DIR/yazi.toml" << 'YAZI_EOF'
# ============================================
# Yazi 文件管理器 - 主配置
# ============================================

[mgr]
ratio         = [1, 3, 5]
sort_by       = "natural"
sort_sensitive = false
sort_reverse  = false
sort_dir_first = true
show_hidden   = false
show_symlink  = true
linemode      = "size"

# Markdown 文件使用 glow 渲染预览
[[plugin.prepend_previewers]]
url = "*.md"
run = 'piper -- CLICOLOR_FORCE=1 glow -w=$w -s=auto "$1"'

[preview]
wrap       = "yes"
tab_size   = 2
max_width  = 1000
max_height = 1000

[opener]
edit = [
    { run = '${EDITOR:-vim} "$@"', block = true, for = "unix" },
]
open = [
    { run = 'open "$@"', for = "macos" },
    { run = 'xdg-open "$@"', for = "linux" },
]
reveal = [
    { run = 'open -R "$1"', for = "macos" },
    { run = 'xdg-open "$(dirname "$1")"', for = "linux" },
]

[[open.rules]]
name = "*.{md,txt,json,yaml,yml,toml,lua,py,go,rs,js,ts,tsx,jsx,sh,zsh,css,html,sql,env,conf,cfg}"
use = "edit"

[[open.rules]]
mime = "text/*"
use = "edit"

[[open.rules]]
mime = "image/*"
use = "open"

[[open.rules]]
mime = "video/*"
use = "open"

[[open.rules]]
mime = "audio/*"
use = "open"

[[open.rules]]
use = "open"
YAZI_EOF
    ok "yazi.toml 已写入"

    # keymap.toml
    backup_if_exists "$YAZI_DIR/keymap.toml"
    cat > "$YAZI_DIR/keymap.toml" << 'YAZI_EOF'
# ============================================
# Yazi - 快捷键配置
# ============================================

# --- 快速跳转 ---
[[mgr.prepend_keymap]]
on   = ["g", "d"]
run  = "cd ~/Downloads"
desc = "Go to Downloads"

[[mgr.prepend_keymap]]
on   = ["g", "D"]
run  = "cd ~/Desktop"
desc = "Go to Desktop"

[[mgr.prepend_keymap]]
on   = ["g", "c"]
run  = "cd ~/.config"
desc = "Go to .config"

[[mgr.prepend_keymap]]
on   = ["g", "p"]
run  = "cd ~/Projects"
desc = "Go to Projects"

[[mgr.prepend_keymap]]
on   = ["g", "h"]
run  = "cd ~"
desc = "Go to Home"

# --- 实用操作 ---
[[mgr.prepend_keymap]]
on   = ["T"]
run  = "shell 'ghostty --working-directory=\"$PWD\" &' --confirm"
desc = "Open in Ghostty"

[[mgr.prepend_keymap]]
on   = ["C"]
run  = "shell 'code \"$PWD\"' --confirm"
desc = "Open in VS Code"

[[mgr.prepend_keymap]]
on   = ["S"]
run  = "shell '$SHELL' --block --confirm"
desc = "Open shell here"
YAZI_EOF
    ok "keymap.toml 已写入"

    # theme.toml
    backup_if_exists "$YAZI_DIR/theme.toml"
    cat > "$YAZI_DIR/theme.toml" << 'YAZI_EOF'
# Yazi 主题配置 (使用默认主题)
# Catppuccin 主题: ya pack -a yazi-rs/flavors:catppuccin-mocha
# 然后取消注释:
# [flavor]
# use = "catppuccin-mocha"
YAZI_EOF
    ok "theme.toml 已写入"

    # init.lua
    backup_if_exists "$YAZI_DIR/init.lua"
    cat > "$YAZI_DIR/init.lua" << 'YAZI_EOF'
-- Yazi 插件初始化
local ok_border, full_border = pcall(require, "full-border")
if ok_border then full_border:setup() end

local ok_git, git = pcall(require, "git")
if ok_git then git:setup() end
YAZI_EOF
    ok "init.lua 已写入"

    # 安装插件
    if command -v ya &>/dev/null; then
        info "安装 Yazi 插件..."
        ya pack -a yazi-rs/plugins:full-border 2>/dev/null && ok "full-border 插件已安装" || warn "full-border 可能已安装"
        ya pack -a yazi-rs/plugins:git 2>/dev/null && ok "git 插件已安装" || warn "git 可能已安装"
        ya pack -a yazi-rs/plugins:chmod 2>/dev/null && ok "chmod 插件已安装" || warn "chmod 可能已安装"
    fi

    fi  # end apply_yazi_config

    # Shell 集成 (y 命令)
    setup_yazi_shell_wrapper
}

setup_yazi_shell_wrapper() {
    local ZSHRC="$HOME/.zshrc"
    local YAZI_WRAPPER='# Yazi: 退出后自动 cd 到最后浏览的目录
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}'

    if [[ -f "$ZSHRC" ]] && grep -q "function y()" "$ZSHRC" 2>/dev/null; then
        ok "Yazi shell wrapper (y 命令) 已存在"
    else
        echo "" >> "$ZSHRC"
        echo "$YAZI_WRAPPER" >> "$ZSHRC"
        ok "已添加 y 命令到 .zshrc"
    fi

    source_zshrc
}

# ── Lazygit ───────────────────────────────────────────
install_lazygit() {
    echo ""
    info "========== [3/13] Lazygit =========="
    brew_install lazygit "Lazygit"
    # native 失败 fallback (CentOS/RHEL 默认仓库没有 lazygit)
    if $NO_BREW && ! command -v lazygit &>/dev/null; then
        github_bin_install lazygit jesseduffield/lazygit "Linux_{ARCH}.tar.gz" lazygit || true
    fi
    brew_install git-delta "delta (语法高亮 diff)"
    if $NO_BREW && ! command -v delta &>/dev/null; then
        github_bin_install delta dandavison/delta "{ARCH}-unknown-linux-gnu.tar.gz" delta || true
    fi

    # Linux: 安装 xclip 用于剪贴板支持
    if is_linux && ! command -v xclip &>/dev/null && ! command -v xsel &>/dev/null && ! command -v wl-copy &>/dev/null; then
        info "安装 xclip (剪贴板支持)..."
        native_install xclip 2>/dev/null || true
    fi

    LAZYGIT_DIR="$HOME/.config/lazygit"
    LAZYGIT_CONF="$LAZYGIT_DIR/config.yml"
    mkdir -p "$LAZYGIT_DIR"

    backup_if_exists "$LAZYGIT_CONF"
    local clip_cmd
    clip_cmd="$(clipboard_copy_cmd)"
    cat > "$LAZYGIT_CONF" << LAZYGIT_EOF
# ============================================
# Lazygit - 推荐配置
# ============================================

gui:
  nerdFontsVersion: "3"
  showFileIcons: true
  border: rounded
  showCommandLog: true
  theme:
    selectedLineBgColor:
      - reverse
    selectedRangeBgColor:
      - reverse
  showRandomTip: true
  showFileTree: true
  showDivergenceFromBaseBranch: arrowAndNumber

git:
  paging:
    colorArg: always
    pager: delta --dark --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format="lazygit-edit://{path}:{line}"
  autoFetch: true
  autoRefresh: true
  parseEmoji: true

os:
  editPreset: vim

promptToReturnFromSubprocess: false
quitOnTopLevelReturn: true
disableStartupPopups: true

keybinding:
  universal:
    quit: q
    return: <esc>
    togglePanel: <tab>
    prevPage: "["
    nextPage: "]"

customCommands:
  - key: "O"
    context: global
    command: "gh browse"
    description: "Open repo in browser"

  - key: "F"
    context: commits
    command: "git commit --fixup={{.SelectedLocalCommit.Hash}}"
    description: "Create fixup commit"

  - key: "Y"
    context: localBranches
    command: "echo -n {{.SelectedLocalBranch.Name}} | ${clip_cmd}"
    description: "Copy branch name"
LAZYGIT_EOF
    ok "Lazygit 配置已写入"

    # 配置 Git Delta
    if ! git config --global core.pager 2>/dev/null | grep -q delta; then
        git config --global core.pager "delta"
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.dark true
        git config --global delta.line-numbers true
        git config --global delta.side-by-side false
        git config --global delta.hyperlinks true
        git config --global merge.conflictstyle "zdiff3"
        ok "Git Delta 全局配置已写入"
    else
        ok "Git Delta 已配置"
    fi

    source_zshrc
}

# ── Claude Code 提供商配置 ────────────────────────────
# 标记块的起止标识，用于在 .zshrc 中定位和替换
CLAUDE_BLOCK_START="# >>> Claude Code Provider Config >>>"
CLAUDE_BLOCK_END="# <<< Claude Code Provider Config <<<"

# 从 .zshrc 中读取当前生效的提供商
detect_claude_provider() {
    local zshrc="$HOME/.zshrc"
    if [[ ! -f "$zshrc" ]] || ! grep -q "$CLAUDE_BLOCK_START" "$zshrc"; then
        echo "未配置"
        return
    fi
    local block
    block=$(sed -n "/$CLAUDE_BLOCK_START/,/$CLAUDE_BLOCK_END/p" "$zshrc")
    if echo "$block" | grep -q "CLAUDE_CODE_USE_BEDROCK"; then
        echo "Amazon Bedrock"
    elif echo "$block" | grep -q "CLAUDE_CODE_USE_VERTEX"; then
        echo "Google Vertex AI"
    elif echo "$block" | grep -q "ANTHROPIC_BASE_URL"; then
        echo "自定义 API 代理"
    elif echo "$block" | grep -q "ANTHROPIC_API_KEY"; then
        echo "Anthropic 直连"
    else
        echo "未知"
    fi
}

# 将配置写入 shell 配置（替换已有的 Claude 配置块）
# 默认写 .zshrc；NO_BREW 模式或已有 .bashrc 时同时写 .bashrc
write_claude_config() {
    local config_content="$1"
    local targets=("$HOME/.zshrc")
    if $NO_BREW || [[ -f "$HOME/.bashrc" ]]; then
        targets+=("$HOME/.bashrc")
    fi

    for rc in "${targets[@]}"; do
        touch "$rc"
        # 如果已有配置块，先移除
        if grep -q "$CLAUDE_BLOCK_START" "$rc"; then
            local tmpfile
            tmpfile=$(mktemp)
            sed "/$CLAUDE_BLOCK_START/,/$CLAUDE_BLOCK_END/d" "$rc" > "$tmpfile"
            mv "$tmpfile" "$rc"
        fi
        {
            echo ""
            echo "$CLAUDE_BLOCK_START"
            echo "$config_content"
            echo "$CLAUDE_BLOCK_END"
        } >> "$rc"
    done
}

# 读取用户输入（带默认值）
read_with_default() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ -n "$default" ]]; then
        echo -en "${CYAN}$prompt [${default}]: ${NC}" > /dev/tty
    else
        echo -en "${CYAN}$prompt: ${NC}" > /dev/tty
    fi
    read -r result < /dev/tty
    echo "${result:-$default}"
}

# 从 .zshrc 现有配置块中提取某个环境变量的值
get_existing_value() {
    local var_name="$1"
    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" ]] && grep -q "$CLAUDE_BLOCK_START" "$zshrc"; then
        sed -n "/$CLAUDE_BLOCK_START/,/$CLAUDE_BLOCK_END/p" "$zshrc" \
            | grep "export ${var_name}=" \
            | head -1 \
            | sed "s/.*export ${var_name}=\"\(.*\)\"/\1/" \
            | sed "s/.*export ${var_name}=\(.*\)/\1/"
    fi
}

# ── 飞书 MCP TUI 表单组件 ────────────────────────────
# 可行内编辑的文本输入框 (支持光标移动、删除、粘贴)
_lark_read_field() {
    local prompt="$1" default="$2" is_secret="${3:-false}"
    local buf="$default" pos=${#default}

    # 绘制输入行
    _lark_draw_input() {
        printf '\r\033[2K' > /dev/tty
        if [[ "$is_secret" == "true" && -n "$buf" ]]; then
            local masked
            masked=$(printf '%*s' ${#buf} '' | tr ' ' '*')
            printf '  %s: %s' "$prompt" "$masked" > /dev/tty
        else
            printf '  %s: %s' "$prompt" "$buf" > /dev/tty
        fi
        # 光标定位到 pos
        local offset=$(( ${#buf} - pos ))
        if (( offset > 0 )); then
            printf '\033[%dD' "$offset" > /dev/tty
        fi
    }

    _lark_draw_input

    while true; do
        IFS= read -rsn1 ch < /dev/tty
        case "$ch" in
            $'\x1b')  # 方向键
                IFS= read -rsn1 _ < /dev/tty
                IFS= read -rsn1 code < /dev/tty
                case "$code" in
                    C) (( pos < ${#buf} )) && (( pos++ )) ;;  # 右
                    D) (( pos > 0 )) && (( pos-- )) ;;        # 左
                    H) pos=0 ;;                                 # Home
                    F) pos=${#buf} ;;                           # End
                esac
                ;;
            $'\x7f'|$'\b')  # Backspace
                if (( pos > 0 )); then
                    buf="${buf:0:pos-1}${buf:pos}"
                    (( pos-- ))
                fi
                ;;
            '')  # Enter
                printf '\n' > /dev/tty
                echo "$buf"
                return
                ;;
            *)  # 普通字符 (含粘贴)
                buf="${buf:0:pos}${ch}${buf:pos}"
                (( pos++ ))
                ;;
        esac
        _lark_draw_input
    done
}

# ── 飞书 MCP: 各工具写入器 ───────────────────────────
# 生成 MCP server JSON 片段 (被多个写入器复用)
_lark_mcp_json_block() {
    local app_id="$1" app_secret="$2" base_url="$3" tools="$4" token_mode="$5"
    cat <<MCPJSON
{
      "command": "npx",
      "args": [
        "-y", "@larksuiteoapi/lark-mcp", "mcp",
        "-a", "${app_id}",
        "-s", "${app_secret}",
        "-d", "${base_url}",
        "-t", "${tools}",
        "--token-mode", "${token_mode}"
      ],
      "env": {}
    }
MCPJSON
}

# 写入 JSON 格式的 MCP 配置 (Cursor / Windsurf / VS Code Copilot)
_lark_write_json_mcp() {
    local config_path="$1" tool_name="$2"
    local app_id="$3" app_secret="$4" base_url="$5" tools="$6" token_mode="$7"

    # 确保目录存在
    mkdir -p "$(dirname "$config_path")"

    local block
    block=$(_lark_mcp_json_block "$app_id" "$app_secret" "$base_url" "$tools" "$token_mode")

    if [[ -f "$config_path" ]]; then
        # 已有配置: 用 python3 合并 JSON
        python3 - "$config_path" "$block" << 'PYEOF'
import json, sys
path, block = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    data = {}
data.setdefault("mcpServers", {})
data["mcpServers"]["lark-mcp"] = json.loads(block)
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
    else
        # 新建配置
        printf '{\n  "mcpServers": {\n    "lark-mcp": %s\n  }\n}\n' "$block" > "$config_path"
    fi

    if [[ $? -eq 0 ]]; then
        ok "${tool_name}: $config_path"
    else
        err "${tool_name}: 写入失败"
    fi
}

# 写入 Claude Code (通过 CLI)
_lark_write_claude() {
    local app_id="$1" app_secret="$2" base_url="$3" tools="$4" token_mode="$5"
    claude mcp remove lark-mcp -s user 2>/dev/null
    if claude mcp add -s user lark-mcp -- \
        npx -y @larksuiteoapi/lark-mcp mcp \
        -a "$app_id" -s "$app_secret" -d "$base_url" \
        -t "$tools" --token-mode "$token_mode" 2>/dev/null; then
        ok "Claude Code: claude mcp add (user scope)"
    else
        err "Claude Code: 配置失败"
    fi
}

# 写入 Codex (TOML 格式)
_lark_write_codex() {
    local app_id="$1" app_secret="$2" base_url="$3" tools="$4" token_mode="$5"
    local config_path="$HOME/.codex/config.toml"
    mkdir -p "$HOME/.codex"

    # 移除已有 lark-mcp 块, 追加新块
    if [[ -f "$config_path" ]]; then
        python3 - "$config_path" "$app_id" "$app_secret" "$base_url" "$tools" "$token_mode" << 'PYEOF'
import sys, re
path = sys.argv[1]
app_id, app_secret, base_url, tools, token_mode = sys.argv[2:7]
with open(path) as f:
    content = f.read()
# 移除已有 lark-mcp 块
content = re.sub(r'\[mcp_servers\.lark-mcp\].*?(?=\n\[|\Z)', '', content, flags=re.DOTALL).strip()
# 追加新块
args = f'-y @larksuiteoapi/lark-mcp mcp -a {app_id} -s {app_secret} -d {base_url} -t {tools} --token-mode {token_mode}'
block = f'\n\n[mcp_servers.lark-mcp]\ncommand = "npx"\nargs = "{args}"\n'
content = content + block
with open(path, "w") as f:
    f.write(content.strip() + "\n")
PYEOF
    else
        local args="-y @larksuiteoapi/lark-mcp mcp -a ${app_id} -s ${app_secret} -d ${base_url} -t ${tools} --token-mode ${token_mode}"
        cat > "$config_path" <<TOMLEOF
[mcp_servers.lark-mcp]
command = "npx"
args = "${args}"
TOMLEOF
    fi

    if [[ $? -eq 0 ]]; then
        ok "Codex: $config_path"
    else
        err "Codex: 写入失败"
    fi
}

# ── 飞书 MCP: 工具选择器 (多选 TUI) ─────────────────
_lark_select_tools() {
    # 返回值通过全局变量 _LARK_SELECTED_TOOLS
    _LARK_SELECTED_TOOLS=()

    local tool_ids=("claude" "cursor" "windsurf" "vscode" "codex")
    local tool_labels=(
        "Claude Code      AI 编程助手 (Anthropic)"
        "Cursor           AI 代码编辑器"
        "Windsurf         AI IDE (Codeium)"
        "VS Code Copilot  GitHub Copilot MCP"
        "Codex            CLI 编程助手 (OpenAI)"
    )
    local tool_detected=()
    local count=${#tool_ids[@]}
    local selected=()
    local cursor=0

    # 检测已安装的工具
    for ((i=0; i<count; i++)); do
        local detected=false
        case "${tool_ids[$i]}" in
            claude)   command -v claude &>/dev/null && detected=true ;;
            cursor)   command -v cursor &>/dev/null || [[ -d "$HOME/.cursor" ]] && detected=true ;;
            windsurf) [[ -d "$HOME/.codeium/windsurf" ]] || ls /Applications/Windsurf*.app &>/dev/null 2>&1 && detected=true ;;
            vscode)   command -v code &>/dev/null && detected=true ;;
            codex)    command -v codex &>/dev/null && detected=true ;;
        esac
        tool_detected+=("$detected")
        # 已安装的默认选中
        if $detected; then selected+=("on"); else selected+=("off"); fi
    done

    # 绘制
    _draw_tools() {
        printf '\033[%dA' "$((count + 4))" > /dev/tty
        printf '\033[2K\n' > /dev/tty
        printf '\033[2K  \033[1m选择要配置的 AI 编程工具:\033[0m\n' > /dev/tty
        printf '\033[2K\n' > /dev/tty
        for ((i=0; i<count; i++)); do
            printf '\033[2K' > /dev/tty
            local check=" "
            [[ "${selected[$i]}" == "on" ]] && check="*"
            local suffix=""
            if [[ "${tool_detected[$i]}" == "true" ]]; then
                suffix=" \033[32m✓ 已安装\033[0m"
            else
                suffix=" \033[2m未检测到\033[0m"
            fi
            if [[ $i -eq $cursor ]]; then
                printf '  \033[0;36m▸\033[0m [\033[0;32m%s\033[0m] %s%b\n' "$check" "${tool_labels[$i]}" "$suffix" > /dev/tty
            else
                printf '    [%s] %s%b\n' "$check" "${tool_labels[$i]}" "$suffix" > /dev/tty
            fi
        done
        printf '\033[2K  \033[2m↑↓ 移动  空格 选择  a 全选  回车 确认  q 退出\033[0m\n' > /dev/tty
    }

    printf '\n' > /dev/tty
    for ((i=0; i<count+4; i++)); do printf '\n' > /dev/tty; done
    printf '\033[?25l' > /dev/tty
    _draw_tools

    while true; do
        IFS= read -rsn1 key < /dev/tty
        case "$key" in
            $'\x1b')
                IFS= read -rsn1 _ < /dev/tty
                IFS= read -rsn1 code < /dev/tty
                case "$code" in
                    A) (( cursor > 0 )) && (( cursor-- )) ;;
                    B) (( cursor < count - 1 )) && (( cursor++ )) ;;
                esac
                ;;
            ' ')
                if [[ "${selected[$cursor]}" == "on" ]]; then
                    selected[$cursor]="off"
                else
                    selected[$cursor]="on"
                fi
                ;;
            a|A)
                local all_on=true
                for ((i=0; i<count; i++)); do
                    [[ "${selected[$i]}" == "off" ]] && all_on=false && break
                done
                if $all_on; then
                    for ((i=0; i<count; i++)); do selected[$i]="off"; done
                else
                    for ((i=0; i<count; i++)); do selected[$i]="on"; done
                fi
                ;;
            '')
                printf '\033[?25h\n' > /dev/tty
                break
                ;;
            q|Q)
                printf '\033[?25h\n' > /dev/tty
                return 1
                ;;
        esac
        _draw_tools
    done

    for ((i=0; i<count; i++)); do
        [[ "${selected[$i]}" == "on" ]] && _LARK_SELECTED_TOOLS+=("${tool_ids[$i]}")
    done
    [[ ${#_LARK_SELECTED_TOOLS[@]} -eq 0 ]] && { warn "未选择任何工具"; return 1; }
    return 0
}

configure_lark_mcp() {
    # ── 表单字段 ──
    local fields=("App ID" "App Secret" "部署地址" "API 工具列表" "认证模式")
    local values=("" "" "https://open.example.com" "docx.v1.document.rawContent" "user_access_token")
    local secrets=(false true false false false)
    local helps=(
        "飞书开放平台 → 应用凭证"
        "飞书开放平台 → 应用凭证"
        "私有化飞书服务地址"
        "逗号分隔多个 API"
        "← → 切换: user_access_token / tenant_access_token"
    )
    local token_modes=("user_access_token" "tenant_access_token")
    local token_idx=0
    local field_count=${#fields[@]}
    local cursor=0

    # ── 绘制表单 ──
    _draw_form() {
        printf '\033[%dA' "$((field_count + 6))" > /dev/tty
        printf '\033[2K\033[1;36m  ╔══════════════════════════════════════════════╗\033[0m\n' > /dev/tty
        printf '\033[2K\033[1;36m  ║   飞书 / Lark MCP 私有化部署配置            ║\033[0m\n' > /dev/tty
        printf '\033[2K\033[1;36m  ╚══════════════════════════════════════════════╝\033[0m\n' > /dev/tty

        for ((i=0; i<field_count; i++)); do
            printf '\033[2K' > /dev/tty
            local label="${fields[$i]}"
            local val="${values[$i]}"
            local display_val="$val"

            if [[ "${secrets[$i]}" == "true" && -n "$val" ]]; then
                if (( ${#val} > 8 )); then
                    display_val="${val:0:4}...${val: -4}"
                else
                    display_val=$(printf '%*s' ${#val} '' | tr ' ' '*')
                fi
            fi

            if [[ "$label" == "认证模式" ]]; then
                if [[ "$val" == "user_access_token" ]]; then
                    display_val="◉ user_access_token  ○ tenant_access_token"
                else
                    display_val="○ user_access_token  ◉ tenant_access_token"
                fi
            fi

            [[ -z "$display_val" ]] && display_val="\033[2m(未填写)\033[0m"

            if [[ $i -eq $cursor ]]; then
                printf '  \033[0;36m▸\033[0m \033[1m%-12s\033[0m  %b\n' "$label" "$display_val" > /dev/tty
            else
                printf '    \033[2m%-12s\033[0m  %b\n' "$label" "$display_val" > /dev/tty
            fi
        done

        printf '\033[2K\n' > /dev/tty
        printf '\033[2K  \033[2m💡 %s\033[0m\n' "${helps[$cursor]}" > /dev/tty
        printf '\033[2K  \033[2m↑↓ 切换字段  回车 编辑  Tab 下一个  Ctrl+S 下一步  q 退出\033[0m\n' > /dev/tty
    }

    # ── 初始绘制 ──
    printf '\n' > /dev/tty
    for ((i=0; i < field_count + 6; i++)); do printf '\n' > /dev/tty; done
    printf '\033[?25l' > /dev/tty
    _draw_form

    # ── 主循环 ──
    while true; do
        IFS= read -rsn1 key < /dev/tty
        case "$key" in
            $'\x1b')
                IFS= read -rsn1 _ < /dev/tty
                IFS= read -rsn1 code < /dev/tty
                case "$code" in
                    A) (( cursor > 0 )) && (( cursor-- )) ;;
                    B) (( cursor < field_count - 1 )) && (( cursor++ )) ;;
                    C|D)
                        if [[ "${fields[$cursor]}" == "认证模式" ]]; then
                            if [[ $token_idx -eq 0 ]]; then token_idx=1; else token_idx=0; fi
                            values[$cursor]="${token_modes[$token_idx]}"
                        fi
                        ;;
                esac
                ;;
            $'\t')
                (( cursor < field_count - 1 )) && (( cursor++ ))
                ;;
            $'\x13')
                printf '\033[?25h' > /dev/tty
                break
                ;;
            q|Q)
                printf '\033[?25h\n' > /dev/tty
                ok "已取消"
                return 0
                ;;
            '')
                if [[ "${fields[$cursor]}" == "认证模式" ]]; then
                    if [[ $token_idx -eq 0 ]]; then token_idx=1; else token_idx=0; fi
                    values[$cursor]="${token_modes[$token_idx]}"
                else
                    printf '\033[?25h' > /dev/tty
                    local up_lines=$(( field_count - cursor + 2 ))
                    printf '\033[%dA' "$up_lines" > /dev/tty
                    local new_val
                    new_val=$(_lark_read_field "${fields[$cursor]}" "${values[$cursor]}" "${secrets[$cursor]}")
                    values[$cursor]="$new_val"
                    local down_lines=$(( field_count - cursor + 1 ))
                    printf '\033[%dB' "$down_lines" > /dev/tty
                    printf '\033[?25l' > /dev/tty
                fi
                ;;
        esac
        _draw_form
    done

    # ── 收集结果 ──
    local app_id="${values[0]}"
    local app_secret="${values[1]}"
    local base_url="${values[2]}"
    local tools="${values[3]}"
    local token_mode="${values[4]}"

    if [[ -z "$app_id" || -z "$app_secret" || -z "$base_url" ]]; then
        err "App ID、App Secret 和部署地址不能为空"
        return 1
    fi

    # ── Step 2: 选择目标工具 ──
    _lark_select_tools || return 0

    # ── Step 3: 写入配置 ──
    echo ""
    info "正在写入 MCP 配置..."
    echo ""

    for tool in "${_LARK_SELECTED_TOOLS[@]}"; do
        case "$tool" in
            claude)
                _lark_write_claude "$app_id" "$app_secret" "$base_url" "$tools" "$token_mode"
                ;;
            cursor)
                _lark_write_json_mcp "$HOME/.cursor/mcp.json" "Cursor" \
                    "$app_id" "$app_secret" "$base_url" "$tools" "$token_mode"
                ;;
            windsurf)
                _lark_write_json_mcp "$HOME/.codeium/windsurf/mcp_config.json" "Windsurf" \
                    "$app_id" "$app_secret" "$base_url" "$tools" "$token_mode"
                ;;
            vscode)
                _lark_write_json_mcp "$HOME/.vscode/mcp.json" "VS Code Copilot" \
                    "$app_id" "$app_secret" "$base_url" "$tools" "$token_mode"
                ;;
            codex)
                _lark_write_codex "$app_id" "$app_secret" "$base_url" "$tools" "$token_mode"
                ;;
        esac
    done

    # ── 配置摘要 ──
    local masked_secret
    if (( ${#app_secret} > 8 )); then
        masked_secret="${app_secret:0:4}...${app_secret: -4}"
    else
        masked_secret="****"
    fi
    echo ""
    echo -e "  ${BOLD}配置摘要:${NC}"
    echo -e "  ┌─────────────────────────────────────────────┐"
    printf  "  │  App ID      %-31s │\n" "$app_id"
    printf  "  │  Secret      %-31s │\n" "$masked_secret"
    printf  "  │  Base URL    %-31s │\n" "$base_url"
    printf  "  │  Token Mode  %-31s │\n" "$token_mode"
    printf  "  │  Tools       %-31s │\n" "$tools"
    printf  "  │  已配置      %-31s │\n" "${_LARK_SELECTED_TOOLS[*]}"
    echo -e "  └─────────────────────────────────────────────┘"

    # ── OAuth 登录 ──
    if [[ "$token_mode" == "user_access_token" ]]; then
        echo ""
        echo -en "${CYAN}  现在进行 OAuth 登录? (将打开浏览器) [Y/n]: ${NC}" > /dev/tty
        local do_login
        read -r do_login < /dev/tty
        if [[ ! "$do_login" =~ ^[nN]$ ]]; then
            info "正在启动 OAuth 登录..."
            if npx -y @larksuiteoapi/lark-mcp login -a "$app_id" -s "$app_secret" -d "$base_url"; then
                ok "OAuth 登录成功"
            else
                warn "OAuth 登录失败，请稍后手动执行:"
                echo "  npx -y @larksuiteoapi/lark-mcp login -a $app_id -s $app_secret -d $base_url"
            fi
        else
            warn "已跳过登录，使用前请手动执行:"
            echo "  npx -y @larksuiteoapi/lark-mcp login -a $app_id -s $app_secret -d $base_url"
        fi
    fi

    echo ""
    ok "配置完成! 重启对应 AI 工具后即可使用飞书文档"
    echo ""
    info "使用提示:"
    echo "   在 AI 工具中让 AI 读取飞书文档即可"
    echo "   示例: \"帮我总结这个飞书文档 https://xxx.com/docx/xxx\""
}

configure_claude_provider() {
    info "配置 Claude Code API 提供商"

    local current_provider
    current_provider=$(detect_claude_provider)
    echo ""
    echo -e "  当前提供商: ${CYAN}${current_provider}${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Anthropic 直连        (使用 Anthropic API Key)"
    echo -e "  ${GREEN}2)${NC} Amazon Bedrock        (使用 AWS 凭证)"
    echo -e "  ${GREEN}3)${NC} Google Vertex AI      (使用 GCP 项目)"
    echo -e "  ${GREEN}4)${NC} 自定义 API 代理       (OpenRouter / 中转站等)"
    echo -e "  ${GREEN}5)${NC} 清除配置              (移除当前提供商设置)"
    echo -e "  ${GREEN}0)${NC} 跳过                  (保持现有配置不变)"
    echo ""
    echo -en "${CYAN}  请输入选项 [0-5]: ${NC}" > /dev/tty
    read -r provider_choice < /dev/tty

    case "${provider_choice}" in
        1)
            info "配置 Anthropic 直连..."
            local existing_key
            existing_key=$(get_existing_value "ANTHROPIC_API_KEY")
            local api_key
            api_key=$(read_with_default "  Anthropic API Key" "$existing_key")

            if [[ -z "$api_key" ]]; then
                err "API Key 不能为空，跳过配置"
            else
                local masked_key="${api_key:0:8}...${api_key: -4}"
                write_claude_config "export ANTHROPIC_API_KEY=\"${api_key}\""
                ok "Anthropic 直连已配置 (Key: ${masked_key})"
            fi
            ;;
        2)
            info "配置 Amazon Bedrock..."
            echo "" > /dev/tty
            echo -e "  认证方式:" > /dev/tty
            echo -e "    ${GREEN}a)${NC} AWS Access Key (AK/SK)" > /dev/tty
            echo -e "    ${GREEN}b)${NC} AWS Profile (~/.aws/credentials)" > /dev/tty
            echo "" > /dev/tty
            echo -en "${CYAN}  选择认证方式 [a/b]: ${NC}" > /dev/tty
            local aws_auth_mode
            read -r aws_auth_mode < /dev/tty

            local existing_region
            existing_region=$(get_existing_value "AWS_REGION")
            local aws_region
            aws_region=$(read_with_default "  AWS Region" "${existing_region:-us-east-1}")

            local config_lines="export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION=\"${aws_region}\""

            if [[ "$aws_auth_mode" == "b" ]]; then
                local existing_profile
                existing_profile=$(get_existing_value "AWS_PROFILE")
                local aws_profile
                aws_profile=$(read_with_default "  AWS Profile 名称" "${existing_profile:-default}")
                config_lines="${config_lines}
export AWS_PROFILE=\"${aws_profile}\""
                write_claude_config "$config_lines"
                ok "Amazon Bedrock 已配置 (Profile: ${aws_profile}, Region: ${aws_region})"
            else
                local existing_ak existing_sk existing_token
                existing_ak=$(get_existing_value "AWS_ACCESS_KEY_ID")
                existing_sk=$(get_existing_value "AWS_SECRET_ACCESS_KEY")
                existing_token=$(get_existing_value "AWS_SESSION_TOKEN")

                local access_key secret_key session_token
                access_key=$(read_with_default "  AWS Access Key ID" "$existing_ak")
                secret_key=$(read_with_default "  AWS Secret Access Key" "$existing_sk")
                session_token=$(read_with_default "  AWS Session Token (可选, 回车跳过)" "$existing_token")

                if [[ -z "$access_key" || -z "$secret_key" ]]; then
                    err "Access Key 和 Secret Key 不能为空，跳过配置"
                else
                    config_lines="${config_lines}
export AWS_ACCESS_KEY_ID=\"${access_key}\"
export AWS_SECRET_ACCESS_KEY=\"${secret_key}\""
                    [[ -n "$session_token" ]] && config_lines="${config_lines}
export AWS_SESSION_TOKEN=\"${session_token}\""
                    write_claude_config "$config_lines"
                    local masked_ak="${access_key:0:4}...${access_key: -4}"
                    ok "Amazon Bedrock 已配置 (AK: ${masked_ak}, Region: ${aws_region})"
                fi
            fi
            ;;
        3)
            info "配置 Google Vertex AI..."
            local existing_region existing_project
            existing_region=$(get_existing_value "CLOUD_ML_REGION")
            existing_project=$(get_existing_value "ANTHROPIC_VERTEX_PROJECT_ID")

            local gcp_project gcp_region
            gcp_project=$(read_with_default "  GCP 项目 ID" "$existing_project")
            gcp_region=$(read_with_default "  GCP Region" "${existing_region:-us-east5}")

            if [[ -z "$gcp_project" ]]; then
                err "GCP 项目 ID 不能为空，跳过配置"
            else
                write_claude_config "export CLAUDE_CODE_USE_VERTEX=1
export CLOUD_ML_REGION=\"${gcp_region}\"
export ANTHROPIC_VERTEX_PROJECT_ID=\"${gcp_project}\""
                ok "Google Vertex AI 已配置 (项目: ${gcp_project}, Region: ${gcp_region})"
                echo ""
                info "提示: 请确保已通过 gcloud auth application-default login 完成认证"
            fi
            ;;
        4)
            info "配置自定义 API 代理..."
            local existing_url existing_key
            existing_url=$(get_existing_value "ANTHROPIC_BASE_URL")
            existing_key=$(get_existing_value "ANTHROPIC_API_KEY")

            local base_url api_key
            base_url=$(read_with_default "  API Base URL (例: https://openrouter.ai/api/v1)" "$existing_url")
            api_key=$(read_with_default "  API Key" "$existing_key")

            if [[ -z "$base_url" || -z "$api_key" ]]; then
                err "Base URL 和 API Key 不能为空，跳过配置"
            else
                local masked_key="${api_key:0:8}...${api_key: -4}"
                write_claude_config "export ANTHROPIC_BASE_URL=\"${base_url}\"
export ANTHROPIC_API_KEY=\"${api_key}\""
                ok "自定义 API 代理已配置 (URL: ${base_url}, Key: ${masked_key})"
            fi
            ;;
        5)
            local zshrc="$HOME/.zshrc"
            if [[ -f "$zshrc" ]] && grep -q "$CLAUDE_BLOCK_START" "$zshrc"; then
                local tmpfile
                tmpfile=$(mktemp)
                sed "/$CLAUDE_BLOCK_START/,/$CLAUDE_BLOCK_END/d" "$zshrc" > "$tmpfile"
                mv "$tmpfile" "$zshrc"
                ok "已清除 Claude 提供商配置"
            else
                warn "未找到已有的 Claude 提供商配置"
            fi
            ;;
        0|"")
            ok "保持现有配置不变"
            ;;
        *)
            warn "无效选项，跳过 Claude 提供商配置"
            ;;
    esac
}

# ── Claude Code ───────────────────────────────────────
install_claude() {
    echo ""
    info "========== [4/13] Claude Code =========="

    if command -v claude &>/dev/null; then
        ok "Claude Code 已安装: $(claude --version 2>/dev/null || echo '已安装')"
    else
        info "正在安装 Claude Code..."
        # 确保默认 shell 是 zsh（Claude Code 安装脚本会检测并提示切换，导致管道中断）
        if [[ "$SHELL" != */zsh ]]; then
            if is_linux; then
                sudo chsh -s "$(which zsh)" "$(whoami)" 2>/dev/null || chsh -s "$(which zsh)" 2>/dev/null < /dev/tty
            else
                chsh -s "$(which zsh)" 2>/dev/null < /dev/tty
            fi
        fi
        # 优先使用官方安装脚本 (自包含二进制，无需 Node.js)
        if curl -fsSL https://claude.ai/install.sh | SHELL=/bin/zsh bash; then
            # 确保 ~/.local/bin 在 PATH 中
            local ZSHRC="$HOME/.zshrc"
            if ! grep -q '\.local/bin' "$ZSHRC" 2>/dev/null; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$ZSHRC"
                ok "已将 ~/.local/bin 添加到 PATH"
            fi
            export PATH="$HOME/.local/bin:$PATH"
            ok "Claude Code 安装完成"
        else
            warn "官方脚本安装失败，尝试其他方式..."
            if is_macos; then
                brew install --cask claude-code 2>/dev/null && ok "Claude Code (Homebrew) 安装完成" || err "Claude Code 安装失败，请手动安装"
            else
                # Linux: 尝试 npm 全局安装
                if command -v npm &>/dev/null; then
                    npm install -g @anthropic-ai/claude-code 2>/dev/null && ok "Claude Code (npm) 安装完成" || err "Claude Code 安装失败，请手动安装"
                else
                    err "Claude Code 安装失败，请手动安装: https://docs.anthropic.com/en/docs/claude-code"
                fi
            fi
        fi
    fi

    # ── 提供商配置 ──────────────────────────────────────
    echo ""
    configure_claude_provider

    echo ""
    info "Claude Code 使用提示:"
    echo "   claude              启动交互式会话"
    echo "   claude \"问题\"       直接提问"
    echo "   claude -p \"问题\"    非交互模式 (管道友好)"
    echo "   首次使用需要登录:    claude login"

    source_zshrc
}

# ── Codex CLI ────────────────────────────────────────
install_codex() {
    echo ""
    info "========== [5/13] Codex CLI =========="

    if command -v codex &>/dev/null; then
        ok "Codex CLI 已安装: $(codex --version 2>/dev/null || echo '已安装')"
    else
        info "正在安装 Codex CLI..."
        local installed=false

        # 优先 Homebrew (macOS / Linuxbrew 都支持官方 formula)
        if command -v brew &>/dev/null; then
            if brew install codex 2>/dev/null; then
                ok "Codex CLI (Homebrew) 安装完成"
                installed=true
            fi
        fi

        # 后备: npm 全局安装
        if ! $installed && command -v npm &>/dev/null; then
            if npm install -g @openai/codex 2>/dev/null; then
                ok "Codex CLI (npm) 安装完成"
                installed=true
            fi
        fi

        if ! $installed; then
            err "Codex CLI 安装失败，请手动安装: https://github.com/openai/codex"
        fi
    fi

    echo ""
    info "Codex CLI 使用提示:"
    echo "   codex                启动交互式会话"
    echo "   codex \"问题\"         直接提问"
    echo "   codex --help         查看完整帮助"
    echo "   首次使用需要登录:     codex login"

    source_zshrc
}

# ── OpenClaw ──────────────────────────────────────────
install_openclaw() {
    echo ""
    info "========== [6/13] OpenClaw =========="

    if command -v openclaw &>/dev/null; then
        ok "OpenClaw 已安装"
    else
        info "正在安装 OpenClaw..."
        brew_install openclaw-cli "OpenClaw CLI"
    fi

    # 可选安装 GUI 版本
    if ! brew list --cask openclaw &>/dev/null; then
        echo ""
        read -rp "$(echo -e "${BOLD}是否安装 OpenClaw 桌面应用? [y/N]: ${NC}")" install_gui < /dev/tty
        if [[ "$install_gui" =~ ^[yY]$ ]]; then
            brew_install_cask openclaw "OpenClaw Desktop"
        fi
    else
        ok "OpenClaw Desktop 已安装"
    fi

    echo ""
    info "OpenClaw 使用提示:"
    echo "   openclaw            启动 OpenClaw"
    echo "   openclaw onboard    首次设置向导"

    source_zshrc
}

# ── Hermes Agent ─────────────────────────────────────
install_hermes() {
    echo ""
    info "========== [7/13] Hermes Agent =========="

    if command -v hermes &>/dev/null; then
        ok "Hermes Agent 已安装: $(hermes --version 2>/dev/null || echo '已安装')"
    else
        info "正在安装 Hermes Agent..."
        if curl -fsSL "$(github_raw_url https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh)" | bash; then
            ok "Hermes Agent 安装完成"
        else
            err "Hermes Agent 安装失败，请手动安装: https://github.com/nousresearch/hermes-agent"
        fi
    fi

    # 检查是否有 OpenClaw 数据可迁移
    if [[ -d "$HOME/.openclaw" ]] && command -v hermes &>/dev/null; then
        echo ""
        echo -en "${CYAN}检测到 OpenClaw 数据，是否迁移到 Hermes? [y/N]: ${NC}" > /dev/tty
        local migrate_choice
        read -r migrate_choice < /dev/tty
        if [[ "$migrate_choice" =~ ^[yY]$ ]]; then
            info "正在迁移 OpenClaw 数据..."
            hermes claw migrate < /dev/tty || warn "迁移过程中出现问题，可稍后运行: hermes claw migrate"
        fi
    fi

    echo ""
    info "Hermes Agent 使用提示:"
    echo "   hermes              启动交互式会话"
    echo "   hermes setup        运行完整设置向导"
    echo "   hermes model        选择 LLM 提供商和模型"
    echo "   hermes tools        配置可用工具"
    echo "   hermes gateway      启动消息网关 (Telegram/Discord 等)"
    echo "   hermes update       更新到最新版本"

    source_zshrc
}

# ── Antigravity ──────────────────────────────────────
install_antigravity() {
    echo ""
    info "========== [8/13] Antigravity =========="

    if is_macos; then
        if brew list --cask antigravity &>/dev/null; then
            ok "Antigravity 已安装"
        else
            info "正在安装 Google Antigravity..."
            brew_install_cask antigravity "Antigravity"
        fi

        echo ""
        info "Antigravity 使用提示:"
        echo "   从 Applications 启动 Antigravity"
        echo "   首次启动需要 Google 账号登录"
    else
        warn "Antigravity 目前仅支持 macOS"
        info "请访问 https://developers.google.com/ 获取 Linux 版本信息"
    fi

    source_zshrc
}

# ── OrbStack ────────────────────────────────────────
install_orbstack() {
    echo ""
    info "========== [9/13] OrbStack =========="

    if is_macos; then
        brew_install_cask orbstack "OrbStack"

        echo ""
        info "OrbStack 使用提示:"
        echo "   从 Applications 启动 OrbStack"
        echo "   OrbStack 兼容 Docker CLI，安装后可直接使用 docker 命令"
        echo "   支持 Docker 容器、Kubernetes、Linux 虚拟机"
    else
        warn "OrbStack 仅支持 macOS，在 Linux 上安装 Docker Engine 替代"
        if command -v docker &>/dev/null; then
            ok "Docker 已安装: $(docker --version)"
        else
            info "正在安装 Docker Engine..."
            case "$PKG_MGR" in
                apt)
                    # Docker 官方安装脚本
                    curl -fsSL https://get.docker.com | sudo bash
                    sudo usermod -aG docker "$(whoami)" 2>/dev/null
                    ok "Docker 安装完成 (重新登录后 docker 组权限生效)"
                    ;;
                dnf)
                    sudo dnf install -y dnf-plugins-core
                    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null
                    sudo dnf install -y docker-ce docker-ce-cli containerd.io
                    sudo systemctl start docker && sudo systemctl enable docker
                    sudo usermod -aG docker "$(whoami)" 2>/dev/null
                    ok "Docker 安装完成"
                    ;;
                pacman)
                    sudo pacman -S --noconfirm docker
                    sudo systemctl start docker && sudo systemctl enable docker
                    sudo usermod -aG docker "$(whoami)" 2>/dev/null
                    ok "Docker 安装完成"
                    ;;
                *)
                    curl -fsSL https://get.docker.com | sudo bash
                    sudo usermod -aG docker "$(whoami)" 2>/dev/null
                    ok "Docker 安装完成"
                    ;;
            esac
        fi

        echo ""
        info "Docker 使用提示:"
        echo "   docker run hello-world     验证安装"
        echo "   docker compose up -d       启动容器编排"
    fi

    source_zshrc
}

# ── Obsidian ──────────────────────────────────────────
install_obsidian() {
    echo ""
    info "========== [10/13] Obsidian =========="

    if is_macos; then
        brew_install_cask obsidian "Obsidian"
    else
        # Linux: 通过 flatpak / snap / AppImage 安装
        if command -v obsidian &>/dev/null || flatpak list 2>/dev/null | grep -qi obsidian || snap list 2>/dev/null | grep -qi obsidian; then
            ok "Obsidian 已安装"
        else
            info "正在安装 Obsidian..."
            local installed=false
            if command -v flatpak &>/dev/null; then
                if flatpak install -y flathub md.obsidian.Obsidian 2>/dev/null; then
                    installed=true
                    ok "Obsidian (Flatpak) 安装完成"
                fi
            fi
            if ! $installed && command -v snap &>/dev/null; then
                if sudo snap install obsidian --classic 2>/dev/null; then
                    installed=true
                    ok "Obsidian (Snap) 安装完成"
                fi
            fi
            if ! $installed; then
                warn "请手动下载安装 Obsidian: https://obsidian.md/download"
            fi
        fi
    fi

    # 安装 Excalidraw 社区插件
    echo ""
    info "配置 Excalidraw 插件..."

    echo ""
    echo -e "${BOLD}请选择 Obsidian Vault 路径 (Excalidraw 插件将安装到此 Vault):${NC}"
    echo -e "  ${CYAN}1)${NC} 默认路径: ~/Obsidian"
    echo -e "  ${CYAN}2)${NC} 自定义路径"
    echo -e "  ${CYAN}3)${NC} 跳过插件安装"
    echo -en "${CYAN}请输入选项 [1/2/3] (默认 1): ${NC}" > /dev/tty
    local vault_choice
    read -r vault_choice < /dev/tty
    vault_choice="${vault_choice:-1}"

    local vault_path=""
    case "$vault_choice" in
        1) vault_path="$HOME/Obsidian" ;;
        2)
            echo -en "${CYAN}请输入 Vault 路径: ${NC}" > /dev/tty
            read -r vault_path < /dev/tty
            # 展开 ~ 为 $HOME
            vault_path="${vault_path/#\~/$HOME}"
            ;;
        3)
            ok "跳过 Excalidraw 插件安装"
            source_zshrc
            return
            ;;
        *)
            vault_path="$HOME/Obsidian"
            ;;
    esac

    if [[ -z "$vault_path" ]]; then
        warn "Vault 路径为空，跳过插件安装"
        source_zshrc
        return
    fi

    local plugin_dir="$vault_path/.obsidian/plugins/obsidian-excalidraw-plugin"

    if [[ -d "$plugin_dir" ]]; then
        ok "Excalidraw 插件已安装: $plugin_dir"
    else
        mkdir -p "$plugin_dir"
        info "正在下载 Excalidraw 插件..."

        # 获取最新 release 版本
        local release_url="https://api.github.com/repos/zsviczian/obsidian-excalidraw-plugin/releases/latest"
        local release_info
        release_info=$(curl -fsSL "$release_url" 2>/dev/null)

        if [[ -n "$release_info" ]]; then
            local tag
            tag=$(echo "$release_info" | grep '"tag_name"' | head -1 | sed 's/.*: *"//;s/".*//')

            if [[ -n "$tag" ]]; then
                local base_url="https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/download/${tag}"
                local dl_ok=true

                for file in main.js manifest.json styles.css; do
                    local dl_url
                    dl_url="$(github_raw_url "${base_url}/${file}")"
                    if ! curl -fsSL "$dl_url" -o "$plugin_dir/$file" 2>/dev/null; then
                        warn "下载 $file 失败"
                        dl_ok=false
                    fi
                done

                if $dl_ok; then
                    ok "Excalidraw 插件安装完成 (${tag})"
                else
                    err "部分文件下载失败，请手动在 Obsidian 设置中安装 Excalidraw 插件"
                    rm -rf "$plugin_dir"
                fi
            else
                err "无法获取最新版本号，请手动安装 Excalidraw 插件"
                rm -rf "$plugin_dir"
            fi
        else
            err "无法访问 GitHub API，请手动在 Obsidian 设置中安装 Excalidraw 插件"
            rm -rf "$plugin_dir"
        fi
    fi

    # 启用 Excalidraw 插件（将其加入社区插件启用列表）
    local community_plugins="$vault_path/.obsidian/community-plugins.json"
    if [[ -d "$plugin_dir" ]]; then
        if [[ -f "$community_plugins" ]]; then
            if grep -q 'obsidian-excalidraw-plugin' "$community_plugins" 2>/dev/null; then
                ok "Excalidraw 插件已在启用列表中"
            else
                # 在 JSON 数组末尾追加
                sed_i 's/\]$/,"obsidian-excalidraw-plugin"\]/' "$community_plugins"
                ok "已将 Excalidraw 添加到启用列表"
            fi
        else
            mkdir -p "$vault_path/.obsidian"
            echo '["obsidian-excalidraw-plugin"]' > "$community_plugins"
            ok "已创建社区插件配置并启用 Excalidraw"
        fi
    fi

    echo ""
    info "Obsidian 使用提示:"
    echo "   从 Applications 启动 Obsidian"
    echo "   打开 Vault: $vault_path"
    echo "   Excalidraw: 在笔记中使用 Ctrl/Cmd+P 搜索 Excalidraw 命令"

    source_zshrc
}

# ── Maccy ────────────────────────────────────────────
install_maccy() {
    echo ""
    info "========== [11/13] Maccy =========="

    if is_macos; then
        brew_install_cask maccy "Maccy"

        echo ""
        info "Maccy 使用提示:"
        echo "   默认快捷键: Cmd+Shift+C 打开剪贴板历史"
        echo "   支持文本、图片、文件等多种格式"
        echo "   可在设置中调整历史记录数量和快捷键"
    else
        warn "Maccy 仅支持 macOS，在 Linux 上安装 CopyQ 替代"
        if command -v copyq &>/dev/null; then
            ok "CopyQ 已安装"
        else
            info "正在安装 CopyQ (剪贴板管理工具)..."
            case "$PKG_MGR" in
                apt)    sudo apt-get install -y copyq ;;
                dnf)    sudo dnf install -y copyq ;;
                pacman) sudo pacman -S --noconfirm copyq ;;
                *)      brew_install copyq "CopyQ" ;;
            esac
            ok "CopyQ 安装完成"
        fi

        echo ""
        info "CopyQ 使用提示:"
        echo "   默认快捷键: Ctrl+Shift+V 打开剪贴板历史"
        echo "   支持文本、图片、文件等多种格式"
        echo "   可在设置中自定义快捷键和规则"
    fi

    source_zshrc
}

# ── JDK (SDKMAN) ─────────────────────────────────────
install_jdk() {
    echo ""
    info "========== [12/13] JDK (SDKMAN) =========="

    # 安装 SDKMAN
    export SDKMAN_DIR="$HOME/.sdkman"
    if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
        ok "SDKMAN 已安装"
        source "$SDKMAN_DIR/bin/sdkman-init.sh"
    else
        info "正在安装 SDKMAN..."
        if is_macos; then
            # macOS 自带 Bash 3.2，SDKMAN 要求 Bash 4+，需用 brew 安装的新版 Bash
            if ! command -v /opt/homebrew/bin/bash &>/dev/null && ! command -v /usr/local/bin/bash &>/dev/null; then
                info "SDKMAN 需要 Bash 4+，正在通过 Homebrew 安装新版 Bash..."
                brew install bash
            fi
            local new_bash="/opt/homebrew/bin/bash"
            [[ ! -x "$new_bash" ]] && new_bash="/usr/local/bin/bash"
            curl -fsSL "https://get.sdkman.io" | "$new_bash"
        else
            # Linux: 系统 bash 通常已是 4+
            curl -fsSL "https://get.sdkman.io" | bash
        fi
        if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
            source "$SDKMAN_DIR/bin/sdkman-init.sh"
            ok "SDKMAN 安装完成"
        else
            err "SDKMAN 安装失败，请手动安装: https://sdkman.io/install"
            return
        fi
    fi

    # 选择 JDK 版本
    echo ""
    echo -e "${BOLD}选择 JDK 版本 (Eclipse Temurin):${NC}"
    echo -e "  ${CYAN}1)${NC} JDK 21 (LTS，推荐)"
    echo -e "  ${CYAN}2)${NC} JDK 17 (LTS)"
    echo -e "  ${CYAN}3)${NC} JDK 11 (LTS)"
    echo -e "  ${CYAN}4)${NC} JDK 8  (LTS)"
    echo -e "  ${CYAN}5)${NC} 跳过 (仅安装 SDKMAN)"
    echo -en "${CYAN}请输入选项 [1-5] (默认 1): ${NC}" > /dev/tty
    local jdk_choice
    read -r jdk_choice < /dev/tty
    jdk_choice="${jdk_choice:-1}"

    local jdk_major=""
    case "$jdk_choice" in
        1) jdk_major="21" ;;
        2) jdk_major="17" ;;
        3) jdk_major="11" ;;
        4) jdk_major="8"  ;;
        5) ok "跳过 JDK 安装，仅保留 SDKMAN" ;;
        *) warn "无效选项，使用默认 JDK 21"
           jdk_major="21" ;;
    esac

    if [[ -n "$jdk_major" ]]; then
        # 检查是否已安装该版本
        if sdk list java 2>/dev/null | grep -q "${jdk_major}\.\S*-tem.*installed"; then
            ok "JDK ${jdk_major} (Temurin) 已安装"
        else
            info "正在安装 JDK ${jdk_major} (Eclipse Temurin)..."
            local jdk_version
            jdk_version=$(sdk list java 2>/dev/null | grep -oE "${jdk_major}\.[0-9.]*-tem" | head -1)
            if [[ -n "$jdk_version" ]]; then
                sdk install java "$jdk_version" < /dev/tty
                ok "JDK ${jdk_version} 安装完成"
            else
                warn "未找到精确版本号，尝试安装 ${jdk_major}-tem..."
                sdk install java "${jdk_major}-tem" < /dev/tty
                ok "JDK ${jdk_major} 安装完成"
            fi
        fi

        # 设置默认版本
        sdk default java "$(sdk current java 2>/dev/null | grep -oE "${jdk_major}\S*" || echo '')" 2>/dev/null
    fi

    echo ""
    info "JDK 使用提示:"
    echo "   java -version            查看当前 JDK 版本"
    echo "   sdk list java            查看可用 JDK 版本"
    echo "   sdk install java <ver>   安装指定版本"
    echo "   sdk use java <ver>       临时切换版本"
    echo "   sdk default java <ver>   设置默认版本"

    source_zshrc
}

# ── VS Code ──────────────────────────────────────────
install_vscode() {
    echo ""
    info "========== [13/13] VS Code =========="

    if command -v code &>/dev/null; then
        ok "VS Code 已安装: $(code --version 2>/dev/null | head -1)"
    else
        info "正在安装 VS Code..."
        if is_macos; then
            brew_install_cask visual-studio-code "VS Code"
        else
            local installed=false
            case "$PKG_MGR" in
                apt)
                    # Microsoft 官方 APT 源
                    if ! apt-cache policy code 2>/dev/null | grep -q 'Candidate'; then
                        info "添加 Microsoft APT 源..."
                        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
                        echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
                        sudo apt-get update
                    fi
                    if sudo apt-get install -y code 2>/dev/null; then
                        installed=true
                    fi
                    ;;
                dnf)
                    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
                    printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
                    if sudo dnf install -y code 2>/dev/null; then
                        installed=true
                    fi
                    ;;
                pacman)
                    # Arch: 尝试官方仓库 (code 或 visual-studio-code-bin from AUR)
                    if sudo pacman -S --noconfirm code 2>/dev/null; then
                        installed=true
                    fi
                    ;;
            esac
            if ! $installed; then
                # 后备: snap 或 brew
                if command -v snap &>/dev/null; then
                    sudo snap install code --classic 2>/dev/null && installed=true
                fi
                if ! $installed; then
                    brew_install_cask visual-studio-code "VS Code"
                fi
            fi
            if $installed; then
                ok "VS Code 安装完成"
            fi
        fi
    fi

    # 确保 code 命令可用
    if ! command -v code &>/dev/null; then
        err "VS Code CLI (code) 不可用，跳过扩展安装"
        return
    fi

    # ── 安装 Catppuccin 主题 ─────────────────────────
    info "安装 Catppuccin 主题扩展..."

    if code --list-extensions 2>/dev/null | grep -qi "catppuccin.catppuccin-vsc"; then
        ok "Catppuccin 主题已安装"
    else
        code --install-extension Catppuccin.catppuccin-vsc --force 2>/dev/null
        ok "Catppuccin 主题安装完成"
    fi

    if code --list-extensions 2>/dev/null | grep -qi "catppuccin.catppuccin-vsc-icons"; then
        ok "Catppuccin Icons 已安装"
    else
        code --install-extension Catppuccin.catppuccin-vsc-icons --force 2>/dev/null
        ok "Catppuccin Icons 安装完成"
    fi

    if code --list-extensions 2>/dev/null | grep -qi "MS-CEINTL.vscode-language-pack-zh-hans"; then
        ok "中文语言包已安装"
    else
        code --install-extension MS-CEINTL.vscode-language-pack-zh-hans --force 2>/dev/null
        ok "中文语言包安装完成"
    fi

    if code --list-extensions 2>/dev/null | grep -qi "anthropic.claude-code"; then
        ok "Claude Code 插件已安装"
    else
        code --install-extension anthropic.claude-code --force 2>/dev/null
        ok "Claude Code 插件安装完成"
    fi

    # 切换 VS Code 界面语言为中文 (通过 argv.json)
    # argv.json 是 JSONC 格式，直接修改容易损坏，用重建方式处理
    local ARGV_PATH="$HOME/.vscode/argv.json"
    mkdir -p "$HOME/.vscode"

    # 从现有文件提取 crash-reporter-id
    local crash_id=""
    if [[ -f "$ARGV_PATH" ]]; then
        crash_id=$(grep -o '"crash-reporter-id"[[:space:]]*:[[:space:]]*"[^"]*"' "$ARGV_PATH" 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"')
    fi

    # 重建干净的 argv.json
    if [[ -n "$crash_id" ]]; then
        cat > "$ARGV_PATH" << ARGV_EOF
{
    "locale": "zh-cn",
    "enable-crash-reporter": true,
    "crash-reporter-id": "$crash_id"
}
ARGV_EOF
    else
        cat > "$ARGV_PATH" << 'ARGV_EOF'
{
    "locale": "zh-cn"
}
ARGV_EOF
    fi
    ok "已切换 VS Code 界面语言为中文 (argv.json)"

    # ── 设置 Catppuccin 为默认主题 ───────────────────
    local VSCODE_SETTINGS_DIR
    if is_macos; then
        VSCODE_SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
    else
        VSCODE_SETTINGS_DIR="$HOME/.config/Code/User"
    fi
    local VSCODE_SETTINGS="$VSCODE_SETTINGS_DIR/settings.json"
    mkdir -p "$VSCODE_SETTINGS_DIR"

    if [[ -f "$VSCODE_SETTINGS" ]]; then
        # 检查是否已有主题设置
        if grep -q '"workbench.colorTheme"' "$VSCODE_SETTINGS" 2>/dev/null; then
            # 替换现有主题
            sed_i 's/"workbench.colorTheme"[[:space:]]*:[[:space:]]*"[^"]*"/"workbench.colorTheme": "Catppuccin Latte"/' "$VSCODE_SETTINGS"
            ok "已将 VS Code 主题切换为 Catppuccin Latte"
        else
            # 在第一个 { 后插入主题设置
            sed_i 's/^{$/{\n    "workbench.colorTheme": "Catppuccin Latte",/' "$VSCODE_SETTINGS"
            ok "已添加 Catppuccin Latte 主题到 settings.json"
        fi
        # 设置图标主题
        if grep -q '"workbench.iconTheme"' "$VSCODE_SETTINGS" 2>/dev/null; then
            sed_i 's/"workbench.iconTheme"[[:space:]]*:[[:space:]]*"[^"]*"/"workbench.iconTheme": "catppuccin-latte"/' "$VSCODE_SETTINGS"
        else
            sed_i 's/^{$/{\n    "workbench.iconTheme": "catppuccin-latte",/' "$VSCODE_SETTINGS"
        fi
        # 设置中文语言
        if grep -q '"locale"' "$VSCODE_SETTINGS" 2>/dev/null; then
            sed_i 's/"locale"[[:space:]]*:[[:space:]]*"[^"]*"/"locale": "zh-cn"/' "$VSCODE_SETTINGS"
        else
            sed_i 's/^{$/{\n    "locale": "zh-cn",/' "$VSCODE_SETTINGS"
        fi
        ok "已设置 Catppuccin 主题 + 中文语言"
    else
        cat > "$VSCODE_SETTINGS" << 'VSCODE_EOF'
{
    "workbench.colorTheme": "Catppuccin Latte",
    "workbench.iconTheme": "catppuccin-latte",
    "locale": "zh-cn"
}
VSCODE_EOF
        ok "已创建 VS Code settings.json (Catppuccin Latte + 中文)"
    fi

    echo ""
    info "VS Code 使用提示:"
    echo "   code .                打开当前目录"
    echo "   code <file>           打开文件"
    echo "   主题: Catppuccin Latte (已自动应用)"
    echo "   切换主题: Ctrl/Cmd+K Ctrl/Cmd+T"

    source_zshrc
}

# ══════════════════════════════════════════════════════
# 卸载模块
# ══════════════════════════════════════════════════════
uninstall_tools() {
    echo ""
    echo -e "${RED}${BOLD}================================================${NC}"
    echo -e "${RED}${BOLD}   开发工具卸载${NC}"
    echo -e "${RED}${BOLD}================================================${NC}"
    echo ""

    # 检测已安装的工具
    local -a installed_names=()
    local -a installed_keys=()
    local idx=1

    local tools_to_check=("ghostty:Ghostty" "yazi:Yazi" "lazygit:Lazygit" "claude:Claude Code" "codex:Codex CLI" "openclaw:OpenClaw" "hermes:Hermes Agent" "docker:Docker" "obsidian:Obsidian" "maccy:Maccy/CopyQ" "java:JDK" "code:VS Code")

    for entry in "${tools_to_check[@]}"; do
        local cmd="${entry%%:*}"
        local name="${entry##*:}"
        if command -v "$cmd" &>/dev/null; then
            echo -e "  ${CYAN}${idx})${NC} $name"
            installed_names+=("$name")
            installed_keys+=("$cmd")
            ((idx++))
        fi
    done

    if [[ ${#installed_names[@]} -eq 0 ]]; then
        info "未检测到已安装的工具"
        return
    fi

    echo ""
    echo -e "  ${RED}A)${NC} 全部卸载"
    echo -e "  ${YELLOW}Q)${NC} 取消"
    echo ""
    echo -en "${CYAN}请输入编号 (多选用逗号分隔): ${NC}" > /dev/tty
    local input
    read -r input < /dev/tty

    [[ -z "$input" || "$input" =~ ^[qQ]$ ]] && { ok "已取消卸载"; return; }

    local -a to_uninstall=()
    if [[ "$input" =~ ^[aA]$ ]]; then
        to_uninstall=("${installed_keys[@]}")
    else
        IFS=',' read -ra nums <<< "$input"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | tr -d ' ')
            local i=$((num - 1))
            if [[ $i -ge 0 && $i -lt ${#installed_keys[@]} ]]; then
                to_uninstall+=("${installed_keys[$i]}")
            fi
        done
    fi

    [[ ${#to_uninstall[@]} -eq 0 ]] && { warn "未选择有效工具"; return; }

    echo ""
    warn "即将卸载: ${to_uninstall[*]}"
    echo -en "${CYAN}确认卸载? [y/N]: ${NC}" > /dev/tty
    local confirm
    read -r confirm < /dev/tty
    [[ ! "$confirm" =~ ^[yY]$ ]] && { ok "已取消"; return; }

    echo ""
    for cmd in "${to_uninstall[@]}"; do
        case "$cmd" in
            ghostty)
                info "卸载 Ghostty..."
                if is_macos; then brew uninstall --cask ghostty 2>/dev/null
                else brew uninstall ghostty 2>/dev/null || native_install ghostty 2>/dev/null; fi
                rm -rf "$HOME/.config/ghostty"
                ok "Ghostty 已卸载"
                ;;
            yazi)
                info "卸载 Yazi..."
                brew uninstall yazi 2>/dev/null
                rm -rf "$HOME/.config/yazi"
                ok "Yazi 已卸载"
                ;;
            lazygit)
                info "卸载 Lazygit..."
                brew uninstall lazygit 2>/dev/null
                rm -rf "$HOME/.config/lazygit"
                ok "Lazygit 已卸载"
                ;;
            claude)
                info "卸载 Claude Code..."
                rm -f "$HOME/.local/bin/claude" 2>/dev/null
                npm uninstall -g @anthropic-ai/claude-code 2>/dev/null
                ok "Claude Code 已卸载"
                ;;
            codex)
                info "卸载 Codex CLI..."
                if command -v brew &>/dev/null; then
                    brew uninstall codex 2>/dev/null
                fi
                if command -v npm &>/dev/null; then
                    npm uninstall -g @openai/codex 2>/dev/null
                fi
                ok "Codex CLI 已卸载"
                ;;
            openclaw)
                info "卸载 OpenClaw..."
                brew uninstall openclaw-cli 2>/dev/null
                if is_macos; then brew uninstall --cask openclaw 2>/dev/null; fi
                ok "OpenClaw 已卸载"
                ;;
            hermes)
                info "卸载 Hermes Agent..."
                rm -rf "$HOME/.hermes" 2>/dev/null
                ok "Hermes Agent 已卸载"
                ;;
            docker)
                info "卸载 Docker..."
                if is_macos; then brew uninstall --cask orbstack 2>/dev/null
                else
                    case "$PKG_MGR" in
                        apt) sudo apt-get remove -y docker-ce docker-ce-cli containerd.io 2>/dev/null ;;
                        dnf) sudo dnf remove -y docker-ce docker-ce-cli containerd.io 2>/dev/null ;;
                        pacman) sudo pacman -Rns --noconfirm docker 2>/dev/null ;;
                    esac
                fi
                ok "Docker 已卸载"
                ;;
            obsidian)
                info "卸载 Obsidian..."
                if is_macos; then brew uninstall --cask obsidian 2>/dev/null
                else
                    flatpak uninstall -y md.obsidian.Obsidian 2>/dev/null
                    snap remove obsidian 2>/dev/null
                fi
                ok "Obsidian 已卸载"
                ;;
            maccy)
                info "卸载 Maccy/CopyQ..."
                if is_macos; then brew uninstall --cask maccy 2>/dev/null
                else
                    case "$PKG_MGR" in
                        apt) sudo apt-get remove -y copyq 2>/dev/null ;;
                        dnf) sudo dnf remove -y copyq 2>/dev/null ;;
                        pacman) sudo pacman -Rns --noconfirm copyq 2>/dev/null ;;
                    esac
                fi
                ok "Maccy/CopyQ 已卸载"
                ;;
            java)
                info "卸载 JDK..."
                if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
                    source "$HOME/.sdkman/bin/sdkman-init.sh"
                    sdk list java 2>/dev/null | grep -oE '\S*-tem' | while read -r ver; do
                        sdk uninstall java "$ver" 2>/dev/null
                    done
                fi
                ok "JDK 已卸载"
                ;;
            code)
                info "卸载 VS Code..."
                if is_macos; then brew uninstall --cask visual-studio-code 2>/dev/null
                else
                    case "$PKG_MGR" in
                        apt) sudo apt-get remove -y code 2>/dev/null ;;
                        dnf) sudo dnf remove -y code 2>/dev/null ;;
                        pacman) sudo pacman -Rns --noconfirm code 2>/dev/null ;;
                    esac
                    snap remove code 2>/dev/null
                fi
                if is_macos; then
                    rm -rf "$HOME/Library/Application Support/Code"
                else
                    rm -rf "$HOME/.config/Code"
                fi
                rm -rf "$HOME/.vscode"
                ok "VS Code 已卸载"
                ;;
        esac
    done

    echo ""
    echo -e "${GREEN}${BOLD}卸载完成${NC}"
}

# ══════════════════════════════════════════════════════
# 主流程
# ══════════════════════════════════════════════════════
main() {
    # 解析参数
    parse_args "$@"

    # 卸载模式
    if $UNINSTALL_MODE; then
        uninstall_tools
        return
    fi

    # 基础环境检查
    check_prerequisites

    # 仅修改 Claude 提供商配置
    if is_selected "claude-provider"; then
        echo ""
        configure_claude_provider
        source_zshrc
        return
    fi

    # 安装选中的工具
    if [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]; then
        echo ""
        info "即将安装: ${SELECTED_TOOLS[*]:-}"
        echo ""

        is_selected "ghostty" && install_ghostty
        is_selected "yazi"    && install_yazi
        is_selected "lazygit" && install_lazygit
        is_selected "claude"  && install_claude
        is_selected "codex"   && install_codex
        is_selected "lark-mcp" && configure_lark_mcp
        is_selected "openclaw" && install_openclaw
        is_selected "hermes"   && install_hermes
        is_selected "antigravity" && install_antigravity
        is_selected "orbstack" && install_orbstack
        is_selected "obsidian" && install_obsidian
        is_selected "maccy"    && install_maccy
        is_selected "jdk"      && install_jdk
        is_selected "vscode"   && install_vscode
    fi

    # 跳过模式：提供配置操作菜单
    if $SKIP_PREREQUISITES && [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
        echo ""
        info "========== 配置操作 =========="
        echo ""
        echo -e "  ${GREEN}1)${NC} 修改 Claude 提供商配置"
        echo -e "  ${GREEN}2)${NC} 配置飞书 MCP (私有化部署)"
        echo -e "  ${GREEN}0)${NC} 退出"
        echo ""
        echo -en "${CYAN}  请选择 [0-2]: ${NC}" > /dev/tty
        local config_choice
        read -r config_choice < /dev/tty

        case "$config_choice" in
            1) configure_claude_provider ;;
            2) configure_lark_mcp ;;
            *) ok "已退出" ;;
        esac
    fi

    # ── 完成 ──────────────────────────────────────────
    echo ""
    echo -e "${GREEN}${BOLD}============================================${NC}"
    echo -e "${GREEN}${BOLD}  All done! 全部完成${NC}"
    echo -e "${GREEN}${BOLD}============================================${NC}"
    echo ""

    if [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]; then
        echo "已安装: ${SELECTED_TOOLS[*]}"
        echo ""
    fi

    if is_selected "ghostty"; then
        echo "  Ghostty   ~/.config/ghostty/config"
    fi
    if is_selected "yazi"; then
        echo "  Yazi      ~/.config/yazi/"
    fi
    if is_selected "lazygit"; then
        echo "  Lazygit   ~/.config/lazygit/config.yml"
    fi
    if is_selected "claude"; then
        echo "  Claude    ~/.zshrc (>>> Claude Code Provider Config >>> 块)"
    fi
    if is_selected "codex"; then
        echo "  Codex     ~/.codex/ (登录后写入会话)"
    fi
    if is_selected "lark-mcp"; then
        echo "  Lark MCP  ~/.claude.json (飞书文档 MCP 服务器)"
    fi
    if is_selected "hermes"; then
        echo "  Hermes    ~/.hermes/ (配置/技能/记忆)"
    fi
    if is_selected "obsidian"; then
        echo "  Obsidian  ~/Obsidian (含 Excalidraw 插件)"
    fi
    if is_selected "maccy"; then
        echo "  Maccy     剪贴板管理 (Cmd+Shift+C)"
    fi
    if is_selected "jdk"; then
        echo "  JDK       ~/.sdkman/ (SDKMAN 管理)"
    fi
    if is_selected "vscode"; then
        echo "  VS Code   Catppuccin Latte 主题已应用"
    fi
    echo ""

    if $NO_BREW; then
        echo -e "${YELLOW}已运行精简模式 (--no-brew):${NC}"
        echo "  - 跳过了 Homebrew 和默认 Shell 切换"
        echo "  - 配置已写入 ~/.bashrc 和 ~/.zshrc (如存在)"
        echo "  - 让本次会话立即生效: source ~/.bashrc"
        echo ""
    fi

    source_zshrc
}

main "$@"
