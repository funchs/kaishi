#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  Kaishi 清理脚本 — 清理上次安装失败留下的残留
# ────────────────────────────────────────────────────────────
#  默认 dry-run（只显示会做什么，不真删），加 -y 才执行。
#
#  用法:
#    ./cleanup.sh              dry-run，列出待清理项 (默认只清 shell rc 块)
#    ./cleanup.sh -y           真清理 shell rc 配置块
#    ./cleanup.sh --all        dry-run，含目录 + 全局 npm 包
#    ./cleanup.sh --all -y     真清理一切
#    ./cleanup.sh --rc-only    只清 shell rc 块 (默认行为)
#
#  远程运行:
#    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/funchs/kaishi/main/cleanup.sh | bash
#    curl -fsSL ... | bash -s -- -y
#    curl -fsSL ... | bash -s -- --all -y
# ════════════════════════════════════════════════════════════

set -uo pipefail

# 颜色
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

info() { echo -e "${CYAN}ℹ${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

# 参数
DRY_RUN=true
INCLUDE_ALL=false
RC_ONLY=true

for arg in "$@"; do
    case "$arg" in
        -y|--yes|--confirm) DRY_RUN=false ;;
        -a|--all)           INCLUDE_ALL=true; RC_ONLY=false ;;
        --rc-only)          RC_ONLY=true; INCLUDE_ALL=false ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^#//' | sed 's/^ //'
            exit 0
            ;;
        *) err "未知参数: $arg"; exit 1 ;;
    esac
done

# 执行或预览
run() {
    if $DRY_RUN; then
        echo -e "  ${YELLOW}[dry-run]${NC} $*"
    else
        echo -e "  ${CYAN}[执行]${NC} $*"
        eval "$@"
    fi
}

# 备份文件 (真执行时)
backup_file() {
    local f="$1"
    [[ ! -f "$f" ]] && return
    if ! $DRY_RUN; then
        cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
    fi
}

# 从文件中删除整段 (含 marker 行)
# 用法: remove_block <file> <start-pattern> <end-pattern>
remove_block() {
    local file="$1" start="$2" end="$3"
    [[ ! -f "$file" ]] && return
    if grep -qF "$start" "$file" 2>/dev/null; then
        echo "    - 删除 [$file] 里的块: $start ... $end"
        if ! $DRY_RUN; then
            local tmp; tmp=$(mktemp)
            # 用 awk 处理 (sed 在不同 BSD/GNU 实现下行为不一致)
            awk -v s="$start" -v e="$end" '
                index($0, s) { skip=1 }
                !skip { print }
                index($0, e) && skip { skip=0; next }
            ' "$file" > "$tmp"
            mv "$tmp" "$file"
        fi
    fi
}

# 删除单行 + 紧随其后的 N 行
# 用法: remove_lines_after <file> <marker> <count>
remove_lines_after() {
    local file="$1" marker="$2" count="$3"
    [[ ! -f "$file" ]] && return
    if grep -qF "$marker" "$file" 2>/dev/null; then
        echo "    - 删除 [$file] 中的 marker '$marker' 起 $count 行"
        if ! $DRY_RUN; then
            local tmp; tmp=$(mktemp)
            awk -v m="$marker" -v n="$count" '
                index($0, m) { skip=n+1; next }
                skip > 0 { skip--; next }
                { print }
            ' "$file" > "$tmp"
            mv "$tmp" "$file"
        fi
    fi
}

# 删除包含特定关键字的所有行
remove_lines_matching() {
    local file="$1" pattern="$2"
    [[ ! -f "$file" ]] && return
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        local n
        n=$(grep -cE "$pattern" "$file" 2>/dev/null || echo 0)
        echo "    - 删除 [$file] 中匹配 '$pattern' 的行 ($n 处)"
        if ! $DRY_RUN; then
            local tmp; tmp=$(mktemp)
            grep -vE "$pattern" "$file" > "$tmp" || true
            mv "$tmp" "$file"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────
# 主流程
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Kaishi 清理脚本${NC}"
if $DRY_RUN; then
    echo -e "${YELLOW}模式: dry-run (只预览，不真删)${NC} — 加 -y 真清理"
else
    echo -e "${RED}${BOLD}模式: 真执行${NC}"
fi
echo ""

# ── 1. Shell rc 配置块 ─────────────────────────────────────
info "[1/3] 清理 shell 配置块 (~/.zshrc, ~/.bashrc)"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [[ ! -f "$rc" ]] && continue
    echo ""
    echo "  目标: $rc"
    backup_file "$rc"

    # Linuxbrew shellenv (失效)
    remove_lines_after "$rc" "# Homebrew (Linuxbrew)" 1
    remove_lines_matching "$rc" 'linuxbrew/bin/brew shellenv'

    # NVM
    remove_lines_after "$rc" "# NVM (Node Version Manager)" 3

    # Bun
    remove_lines_after "$rc" "# Bun" 2
    remove_lines_matching "$rc" 'BUN_INSTALL'

    # 用户本地二进制
    remove_lines_after "$rc" "# 用户本地二进制目录" 1

    # Starship
    remove_lines_after "$rc" "# Starship (zsh)" 1
    remove_lines_after "$rc" "# Starship (bash)" 1
    remove_lines_matching "$rc" 'starship init'

    # Zsh 插件
    remove_lines_after "$rc" "# Zsh 插件" 2

    # Claude Code provider
    remove_block "$rc" "# >>> Claude Code Provider Config >>>" "# <<< Claude Code Provider Config <<<"

    # Yazi y() wrapper (kaishi 写入的版本以 "# Yazi:" 注释开头)
    remove_block "$rc" "# Yazi: 退出后自动 cd" "}"
done

# ── 2. 残留目录 ───────────────────────────────────────────
if $INCLUDE_ALL; then
    echo ""
    info "[2/3] 清理残留目录 (--all)"

    # NVM
    if [[ -d "$HOME/.nvm" ]]; then
        if command -v node &>/dev/null && [[ -f "$HOME/.nvm/nvm.sh" ]]; then
            warn "  ~/.nvm 看起来工作正常，跳过 (如要强制清理，先 rm -rf ~/.nvm)"
        else
            run "rm -rf $HOME/.nvm"
        fi
    fi

    # Bun
    if [[ -d "$HOME/.bun" ]]; then
        if command -v bun &>/dev/null; then
            warn "  ~/.bun 看起来工作正常，跳过"
        else
            run "rm -rf $HOME/.bun"
        fi
    fi

    # Linuxbrew (root 装失败的常见情况)
    for brew_dir in /home/linuxbrew/.linuxbrew "$HOME/.linuxbrew"; do
        if [[ -d "$brew_dir" ]] && [[ ! -x "$brew_dir/bin/brew" ]]; then
            run "rm -rf $brew_dir"
        elif [[ -d "$brew_dir" ]]; then
            warn "  $brew_dir 包含可用的 brew，跳过"
        fi
    done

    # ~/.local/bin 中我们脚本下载的二进制
    if [[ -d "$HOME/.local/bin" ]]; then
        for bin in lazygit yazi ya delta starship; do
            if [[ -f "$HOME/.local/bin/$bin" ]]; then
                run "rm -f $HOME/.local/bin/$bin"
            fi
        done
    fi

    # ── 3. 全局 npm 包 ────────────────────────────────────
    echo ""
    info "[3/3] 卸载全局 npm 包 (--all)"
    if command -v npm &>/dev/null; then
        for pkg in '@anthropic-ai/claude-code' '@openai/codex'; do
            if npm list -g --depth=0 2>/dev/null | grep -q "$pkg"; then
                run "npm uninstall -g $pkg"
            fi
        done
    else
        warn "  npm 不可用，跳过"
    fi
else
    echo ""
    info "[2-3/3] 跳过目录清理和全局 npm 卸载 (加 --all 启用)"
fi

# ─────────────────────────────────────────────────────────────
echo ""
if $DRY_RUN; then
    echo -e "${YELLOW}dry-run 完成，未真删任何东西。${NC}"
    echo -e "确认无误后再跑: ${BOLD}$0 ${INCLUDE_ALL:+--all }-y${NC}"
else
    ok "清理完成"
    echo ""
    echo "原配置已备份到 ~/.zshrc.bak.* 和 ~/.bashrc.bak.*"
    echo "现在可以重跑安装脚本，从干净状态开始:"
    echo "  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/funchs/kaishi/main/install.sh | bash"
fi
echo ""
