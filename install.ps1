# ============================================================
# Windows 开发工具一键安装与配置
# 支持: Ghostty / Yazi / Lazygit / Claude Code / OpenClaw / Hermes Agent / Docker Desktop / Obsidian / Ditto / JDK / VS Code
# 用法:
#   全部安装:  .\install.ps1
#   选择安装:  .\install.ps1 ghostty yazi lazygit claude codex openclaw hermes orbstack obsidian maccy jdk vscode
#   查看帮助:  .\install.ps1 --help
# 要求: Windows 10+ / PowerShell 5.1+
# ============================================================

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ── 颜色输出 ──────────────────────────────────────────
function Info  { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Ok    { param([string]$msg) Write-Host "[ OK ] $msg" -ForegroundColor Green }
function Warn  { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Err   { param([string]$msg) Write-Host "[ERR ] $msg" -ForegroundColor Red }

# ── 系统检测 ─────────────────────────────────────────
$ARCH = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }

# ── 国内加速配置 ──────────────────────────────────────
$script:USE_MIRROR = $false
$script:GITHUB_PROXY = ""
$script:MIRROR_PROVIDER = if ($env:MIRROR) { $env:MIRROR } else { "ghfast" }

function Setup-Mirror {
    if (-not $script:USE_MIRROR) {
        Write-Host ""
        Write-Host "  正在检测网络..." -ForegroundColor White -NoNewline
        try {
            $null = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/github/gitignore/main/README.md" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            Ok " 网络正常"
        } catch {
            Warn " 国外网站连接较慢，已自动开启加速"
            $script:USE_MIRROR = $true
        }
    }

    if ($script:USE_MIRROR) {
        switch ($script:MIRROR_PROVIDER) {
            "ghfast"   { $script:GITHUB_PROXY = "https://ghfast.top/" }
            "ghproxy"  { $script:GITHUB_PROXY = "https://ghproxy.com/" }
            "jsdelivr" { $script:GITHUB_PROXY = "https://ghfast.top/" }  # jsDelivr 只代理 raw 文件，其他资源回退
            default    {
                Warn "未知 MIRROR=$($script:MIRROR_PROVIDER) (可选: ghfast/ghproxy/jsdelivr)，回退到 ghfast"
                $script:MIRROR_PROVIDER = "ghfast"
                $script:GITHUB_PROXY = "https://ghfast.top/"
            }
        }
        $env:GIT_TERMINAL_PROMPT = "0"
        Ok "已启用国内加速 (MIRROR=$($script:MIRROR_PROVIDER))"
    }
}

function GitHub-RawUrl {
    param([string]$url)
    if (-not $script:USE_MIRROR) { return $url }
    if ($script:MIRROR_PROVIDER -eq "jsdelivr" -and $url -match '^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.*)$') {
        return "https://cdn.jsdelivr.net/gh/$($matches[1])/$($matches[2])@$($matches[3])/$($matches[4])"
    }
    return "$($script:GITHUB_PROXY)$url"
}

# ── 帮助信息 ──────────────────────────────────────────
function Show-Help {
    @"
Windows 开发工具一键安装脚本

用法:
  .\install.ps1                 交互式选择要安装的工具
  .\install.ps1 --all           安装全部工具
  .\install.ps1 --uninstall     交互式选择卸载工具
  .\install.ps1 --skip          跳过工具安装，仅修改配置
  .\install.ps1 --mirror        强制使用国内镜像加速
  .\install.ps1 <tool> ...      只安装指定工具

环境变量:
  $env:MIRROR=<provider>        指定镜像源 (ghfast | ghproxy | jsdelivr, 默认 ghfast)
                                jsdelivr 仅加速 raw 文件, 其余资源回退 ghfast

可选工具:
  ghostty          GPU 加速终端模拟器
  yazi             终端文件管理器
  lazygit          终端 Git UI
  claude           Claude Code (Anthropic AI 编程助手)
  codex            Codex CLI (OpenAI AI 编程助手)
  openclaw         OpenClaw (本地 AI 助手)
  hermes           Hermes Agent (Nous Research 自学习 AI Agent)
  antigravity      Google Antigravity (AI 开发平台)
  orbstack         Docker Desktop (容器 & Kubernetes)
  obsidian         Obsidian (知识管理 & 笔记工具)
  maccy            Ditto (剪贴板管理工具, Maccy 替代)
  jdk              JDK (通过 winget/scoop 安装)
  vscode           VS Code (代码编辑器 + Catppuccin 主题)
  claude-provider  仅修改 Claude API 提供商配置

示例:
  .\install.ps1 ghostty yazi          只安装 Ghostty 和 Yazi
  .\install.ps1 claude codex          只安装 AI 编程助手
  .\install.ps1 claude openclaw       只安装 AI 工具
  .\install.ps1 claude-provider       仅切换 Claude 提供商
  .\install.ps1 --skip                跳过安装，进入配置菜单
  .\install.ps1 --all                 全部安装
"@
    exit 0
}

# ── 工具定义 ──────────────────────────────────────────
$ALL_TOOLS = @("ghostty", "yazi", "lazygit", "claude", "codex", "openclaw", "hermes", "antigravity", "orbstack", "obsidian", "maccy", "jdk", "vscode")
$script:SELECTED_TOOLS = @()
$script:SKIP_PREREQUISITES = $false
$script:UNINSTALL_MODE = $false

# ── 带超时的命令执行 ──────────────────────────────────
function Run-WithTimeout {
    param(
        [string]$Command,
        [string]$Name,
        [int]$TimeoutSec = 120
    )
    Info "$Name ..."
    $job = Start-Job -ScriptBlock ([scriptblock]::Create($Command))
    $finished = $job | Wait-Job -Timeout $TimeoutSec
    if ($finished) {
        $output = Receive-Job $job 2>&1
        $exitCode = if ($job.State -eq "Completed") { 0 } else { 1 }
        Remove-Job $job -Force
        if ($exitCode -eq 0) {
            Ok "$Name 完成"
            return $true
        }
        Warn "$Name 失败: $output"
        return $false
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force
        Warn "$Name 超时 (${TimeoutSec}s)，已跳过"
        return $false
    }
}

# ── 包管理器辅助 ──────────────────────────────────────
function Ensure-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Ok "Scoop 已安装"
        return
    }
    Info "正在安装 Scoop..."
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    try {
        if ($isAdmin) {
            Invoke-Expression "& {$(Invoke-RestMethod -Uri 'https://get.scoop.sh' -TimeoutSec 30)} -RunAsAdmin"
        } else {
            Invoke-RestMethod -Uri "https://get.scoop.sh" -TimeoutSec 30 | Invoke-Expression
        }
    } catch {
        Err "Scoop 安装失败 (网络超时)，请手动安装: https://scoop.sh"
        return
    }
    Refresh-Path
    $scoopShim = "$env:USERPROFILE\scoop\shims"
    if (Test-Path $scoopShim) { $env:Path = "$scoopShim;$env:Path" }
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Ok "Scoop 安装完成"
    } else {
        Err "Scoop 安装后命令不可用，请关闭终端重新运行脚本"
    }
}

function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Ok "winget 已可用"
        return $true
    }
    Warn "winget 不可用 (Windows 10 需要手动安装 App Installer)"
    return $false
}

function Winget-Install {
    param(
        [string]$Id,
        [string]$Name,
        [switch]$Interactive
    )

    $installed = winget list --id $Id 2>$null | Select-String $Id
    if ($installed) {
        Ok "$Name 已安装"
        return
    }

    Info "正在安装 $Name ..."
    $wingetArgs = @("install", "--id", $Id, "--accept-source-agreements", "--accept-package-agreements")
    if (-not $Interactive) { $wingetArgs += "--silent" }

    & winget @wingetArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Ok "$Name 安装完成"
    } else {
        Err "$Name 安装失败"
    }
}

function Scoop-Install {
    param(
        [string]$Package,
        [string]$Name,
        [string]$Bucket,
        [int]$TimeoutSec = 120
    )

    if (scoop list $Package 2>$null | Select-String $Package) {
        Ok "$Name 已安装 (scoop)"
        return $true
    }

    if ($Bucket) {
        scoop bucket add $Bucket 2>$null
    }

    Info "正在安装 $Name (scoop, ${TimeoutSec}s 超时)..."
    $job = Start-Job -ScriptBlock { param($p) scoop install $p 2>&1 } -ArgumentList $Package
    $finished = $job | Wait-Job -Timeout $TimeoutSec
    if ($finished) {
        $output = Receive-Job $job 2>&1
        Remove-Job $job -Force
        Refresh-Path
        Ok "$Name 安装完成"
        return $true
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force
        Warn "$Name 安装超时 (${TimeoutSec}s)，已跳过"
        return $false
    }
}

# ── 交互式多选菜单 (数字输入，兼容 irm | iex) ───────
function Interactive-Select {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Kaishi - Windows 开发工具一键安装" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  -- 终端工具 --" -ForegroundColor White
    Write-Host "   1) Ghostty       好看的终端窗口 (替代系统自带终端)" -ForegroundColor Cyan
    Write-Host "   2) Yazi          文件管理器 (在终端里浏览文件)" -ForegroundColor Cyan
    Write-Host "   3) Lazygit       Git 图形界面 (不用记 Git 命令)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  -- AI 工具 --" -ForegroundColor White
    Write-Host "   4) Claude Code   AI 编程助手 (Anthropic)" -ForegroundColor Cyan
    Write-Host "   5) Codex CLI     AI 编程助手 (OpenAI)" -ForegroundColor Cyan
    Write-Host "   6) OpenClaw      本地 AI 助手 (不联网也能用)" -ForegroundColor Cyan
    Write-Host "   7) Hermes        AI 智能体 (自动完成复杂任务)" -ForegroundColor Cyan
    Write-Host "   8) Antigravity   Google AI 平台" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  -- 常用软件 --" -ForegroundColor White
    Write-Host "   9) Docker        容器工具 (运行服务器程序)" -ForegroundColor Cyan
    Write-Host "  10) Obsidian      笔记软件 (写文档/知识管理)" -ForegroundColor Cyan
    Write-Host "  11) Ditto         剪贴板历史 (找回之前复制的内容)" -ForegroundColor Cyan
    Write-Host "  12) JDK           Java 环境 (Java 开发必备)" -ForegroundColor Cyan
    Write-Host "  13) VS Code       代码编辑器 (自动装中文和主题)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "   A) 全部安装 (推荐新电脑选这个)" -ForegroundColor Green
    Write-Host "   U) 卸载已安装的工具" -ForegroundColor Yellow
    Write-Host "   Q) 退出" -ForegroundColor Red
    Write-Host ""
    Write-Host "  提示: 直接输入数字选择，多个用逗号隔开" -ForegroundColor DarkGray
    Write-Host "  举例: 输入 4,13 = 只装 AI 助手和编辑器" -ForegroundColor DarkGray
    Write-Host ""
    $input = Read-Host "请输入"

    if (-not $input -or $input -match '^[qQ]$') {
        Write-Host "已取消。"
        exit 0
    }

    if ($input -match '^[aA]$') {
        $script:SELECTED_TOOLS = @() + $ALL_TOOLS
        return
    }

    if ($input -match '^[uU]$') {
        $script:UNINSTALL_MODE = $true
        return
    }

    if ($input -match '^[sS]$') {
        $script:SKIP_PREREQUISITES = $true
        $script:SELECTED_TOOLS = @()
        Info "跳过工具安装，进入配置菜单"
        return
    }

    # 解析逗号分隔的编号
    $nums = $input -split '[,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
    foreach ($num in $nums) {
        $idx = [int]$num - 1
        if ($idx -ge 0 -and $idx -lt $ALL_TOOLS.Count) {
            if ($ALL_TOOLS[$idx] -notin $script:SELECTED_TOOLS) {
                $script:SELECTED_TOOLS += $ALL_TOOLS[$idx]
            }
        } else {
            Warn "无效编号: $num (有效范围 1-$($ALL_TOOLS.Count))"
        }
    }

    if ($script:SELECTED_TOOLS.Count -eq 0) {
        $script:SKIP_PREREQUISITES = $true
        Info "未选择工具，跳过安装"
    }
}

# ── 解析参数 ──────────────────────────────────────────
function Parse-Args {
    param([string[]]$Arguments)

    if ($Arguments.Count -eq 0) {
        Interactive-Select
        return
    }

    foreach ($arg in $Arguments) {
        switch ($arg) {
            "--help"  { Show-Help }
            "-h"      { Show-Help }
            "--all"   { $script:SELECTED_TOOLS = $ALL_TOOLS; return }
            "-a"      { $script:SELECTED_TOOLS = $ALL_TOOLS; return }
            "--skip"  { $script:SKIP_PREREQUISITES = $true; return }
            "-s"      { $script:SKIP_PREREQUISITES = $true; return }
            "--uninstall" { $script:UNINSTALL_MODE = $true; return }
            "-u"      { $script:UNINSTALL_MODE = $true; return }
            "--mirror" { $script:USE_MIRROR = $true }
            "-m"      { $script:USE_MIRROR = $true }
            "claude-provider" {
                $script:SKIP_PREREQUISITES = $true
                $script:SELECTED_TOOLS += "claude-provider"
            }
            { $_ -in @("ghostty","yazi","lazygit","claude","codex","openclaw","hermes","antigravity","orbstack","obsidian","maccy","jdk","vscode") } {
                $script:SELECTED_TOOLS += $_
            }
            default {
                Err "未知选项: $arg"
                Write-Host "运行 .\install.ps1 --help 查看帮助"
                exit 1
            }
        }
    }

    # 只传了 --mirror 这类修饰性参数而没选工具时，仍然展示菜单
    if ($script:SELECTED_TOOLS.Count -eq 0 -and -not $script:UNINSTALL_MODE -and -not $script:SKIP_PREREQUISITES) {
        Interactive-Select
    }
}

function Is-Selected {
    param([string]$tool)
    return ($script:SELECTED_TOOLS -contains $tool)
}

function Backup-IfExists {
    param([string]$Path)
    if (Test-Path $Path) {
        $backup = "$Path.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Warn "备份已有配置: $Path -> $backup"
        Copy-Item -Path $Path -Destination $backup -Recurse -Force
    }
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# ── PowerShell Profile 辅助 ──────────────────────────
function Ensure-ProfileInit {
    param(
        [string]$InitLine,
        [string]$Name
    )

    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path $profilePath
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains($InitLine)) {
        Ok "$Name 已在 PowerShell Profile 中配置"
    } else {
        Add-Content -Path $profilePath -Value "`n# $Name`n$InitLine"
        Ok "$Name 初始化已写入 PowerShell Profile"
    }
}

function Add-ToProfile {
    param(
        [string]$Content,
        [string]$Marker
    )

    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $existing = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($existing -and $existing.Contains($Marker)) {
        return $false
    }

    Add-Content -Path $profilePath -Value "`n$Content"
    return $true
}

# ══════════════════════════════════════════════════════
# 环境基础检查 (按依赖顺序: 网络 → 包管理器 → 基础工具 → 运行时 → 配置)
# ══════════════════════════════════════════════════════
function Check-Prerequisites {
    Write-Host ""
    Write-Host "  正在准备基础环境 (首次较慢，请耐心等待)..." -ForegroundColor White
    Write-Host ""

    # ── 步骤 1/6: 网络 ──────────────────────────────
    Info "[1/6] 检测网络环境..."
    Setup-Mirror

    # ── 步骤 2/6: 包管理器 ──────────────────────────
    Info "[2/6] 检查包管理器 (用来安装软件的工具)..."
    $hasWinget = Ensure-Winget
    Ensure-Scoop

    # ── 步骤 3/6: Git ───────────────────────────────
    Info "[3/6] 检查 Git (代码版本管理工具)..."
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Ok "Git 已就绪"
    } else {
        Scoop-Install -Package "git" -Name "Git" -TimeoutSec 60
        Refresh-Path
    }

    if ($script:USE_MIRROR) { $env:GIT_TERMINAL_PROMPT = "0" }

    # ── 步骤 4/6: 软件源 ───────────────────────────
    Info "[4/6] 添加软件源 (让包管理器能找到更多软件)..."
    $buckets = @("extras", "versions", "nerd-fonts")
    foreach ($bucket in $buckets) {
        $existing = scoop bucket list 2>$null | Select-String $bucket
        if (-not $existing) {
            $job = Start-Job -ScriptBlock { param($b) scoop bucket add $b 2>&1 } -ArgumentList $bucket
            $finished = $job | Wait-Job -Timeout 30
            if ($finished) { Receive-Job $job | Out-Null }
            else { Stop-Job $job -ErrorAction SilentlyContinue }
            Remove-Job $job -Force
        }
    }
    Ok "软件源已就绪"

    # ── 步骤 5/6: Node.js ──────────────────────────
    Info "[5/6] 检查 Node.js (很多工具依赖它)..."
    if (-not (Get-Command nvm -ErrorAction SilentlyContinue)) {
        Scoop-Install -Package "nvm" -Name "Node 版本管理器" -TimeoutSec 60
    }
    Refresh-Path

    if (Get-Command node -ErrorAction SilentlyContinue) {
        Ok "Node.js 已就绪: $(node --version)"
    } else {
        if (Get-Command nvm -ErrorAction SilentlyContinue) {
            Info "正在安装 Node.js (可能需要 1-2 分钟)..."
            nvm install lts
            nvm use lts
            Ok "Node.js 安装完成"
        } else {
            Scoop-Install -Package "nodejs-lts" -Name "Node.js" -TimeoutSec 60
        }
    }
    Refresh-Path

    # ── 步骤 6/6: Bun ──────────────────────────────
    Info "[6/6] 检查 Bun (高性能开发工具)..."
    if (Get-Command bun -ErrorAction SilentlyContinue) {
        Ok "Bun 已就绪: $(bun --version)"
    } else {
        Scoop-Install -Package "bun" -Name "Bun" -TimeoutSec 60
    }

    Write-Host ""
    Write-Host "环境基础检查完成" -ForegroundColor Green
    Write-Host ""
}

# ── Shell 提示符配置 (独立可选，仅 --all 或交互全选时调用) ──
function Configure-ShellPrompt {
    Write-Host ""
    Write-Host "请选择 Shell 提示符工具:" -ForegroundColor White
    Write-Host "  1) Starship (跨平台极速提示符，推荐)" -ForegroundColor Cyan
    Write-Host "  2) Oh My Posh (PowerShell 美化方案)" -ForegroundColor Cyan
    Write-Host "  3) 跳过 (保持现有配置)" -ForegroundColor Cyan
    $promptChoice = Read-Host "请输入选项 [1/2/3] (默认 3)"
    if (-not $promptChoice) { $promptChoice = "3" }

    if ($promptChoice -eq "1") {
        if (Get-Command starship -ErrorAction SilentlyContinue) {
            Ok "Starship 已安装"
        } else {
            Scoop-Install -Package "starship" -Name "Starship" -TimeoutSec 60
        }

        # Nerd Font
        Write-Host ""
        Write-Host "选择 Nerd Font 字体:" -ForegroundColor White
        Write-Host "  1) Hack Nerd Font (推荐)" -ForegroundColor Cyan
        Write-Host "  2) JetBrainsMono Nerd Font" -ForegroundColor Cyan
        Write-Host "  3) FiraCode Nerd Font" -ForegroundColor Cyan
        Write-Host "  4) MesloLG Nerd Font" -ForegroundColor Cyan
        Write-Host "  5) CascadiaCode Nerd Font" -ForegroundColor Cyan
        Write-Host "  6) 跳过" -ForegroundColor Cyan
        $fontChoice = Read-Host "请输入选项 [1-6] (默认 1)"
        if (-not $fontChoice) { $fontChoice = "1" }

        $fontPkg = switch ($fontChoice) {
            "1" { "Hack-NF" }
            "2" { "JetBrainsMono-NF" }
            "3" { "FiraCode-NF" }
            "4" { "Meslo-NF" }
            "5" { "CascadiaCode-NF" }
            "6" { "" }
            default { "Hack-NF" }
        }

        if ($fontPkg) {
            Scoop-Install -Package $fontPkg -Name $fontPkg -Bucket "nerd-fonts"
            Warn "请在终端设置中将字体切换为对应的 Nerd Font"
        }

        # Starship 主题
        $starshipConfig = "$env:USERPROFILE\.config\starship.toml"
        $starshipDir = Split-Path $starshipConfig
        if (-not (Test-Path $starshipDir)) { New-Item -ItemType Directory -Path $starshipDir -Force | Out-Null }

        Write-Host ""
        Write-Host "选择 Starship 主题:" -ForegroundColor White
        Write-Host "   1) Catppuccin Mocha Powerline (推荐)" -ForegroundColor Cyan
        Write-Host "   2) catppuccin-powerline" -ForegroundColor Cyan
        Write-Host "   3) gruvbox-rainbow" -ForegroundColor Cyan
        Write-Host "   4) tokyo-night" -ForegroundColor Cyan
        Write-Host "   5) pastel-powerline" -ForegroundColor Cyan
        Write-Host "   6) jetpack" -ForegroundColor Cyan
        Write-Host "   7) pure-preset" -ForegroundColor Cyan
        Write-Host "   8) nerd-font-symbols" -ForegroundColor Cyan
        Write-Host "   9) plain-text-symbols (无需 Nerd Font)" -ForegroundColor Cyan
        Write-Host "  10) 跳过" -ForegroundColor Cyan
        $themeChoice = Read-Host "请输入选项 [1-10] (默认 1)"
        if (-not $themeChoice) { $themeChoice = "1" }

        $gistUrl = "https://gist.githubusercontent.com/zhangchitc/62f5dca64c599084f936fda9963f1100/raw/starship.toml"

        switch ($themeChoice) {
            "1"  {
                Info "下载 Catppuccin Mocha 主题..."
                try {
                    Invoke-WebRequest -Uri (GitHub-RawUrl $gistUrl) -OutFile $starshipConfig -UseBasicParsing -TimeoutSec 15
                    Ok "Starship 主题已应用: Catppuccin Mocha Powerline"
                } catch {
                    Warn "下载失败，使用内置 catppuccin-powerline"
                    starship preset catppuccin-powerline -o $starshipConfig 2>$null
                }
            }
            "2"  { starship preset catppuccin-powerline -o $starshipConfig 2>$null; Ok "主题: catppuccin-powerline" }
            "3"  { starship preset gruvbox-rainbow -o $starshipConfig 2>$null; Ok "主题: gruvbox-rainbow" }
            "4"  { starship preset tokyo-night -o $starshipConfig 2>$null; Ok "主题: tokyo-night" }
            "5"  { starship preset pastel-powerline -o $starshipConfig 2>$null; Ok "主题: pastel-powerline" }
            "6"  { starship preset jetpack -o $starshipConfig 2>$null; Ok "主题: jetpack" }
            "7"  { starship preset pure-preset -o $starshipConfig 2>$null; Ok "主题: pure-preset" }
            "8"  { starship preset nerd-font-symbols -o $starshipConfig 2>$null; Ok "主题: nerd-font-symbols" }
            "9"  { starship preset plain-text-symbols -o $starshipConfig 2>$null; Ok "主题: plain-text-symbols" }
            "10" { Ok "保持现有 Starship 配置" }
        }

        Ensure-ProfileInit 'Invoke-Expression (&starship init powershell)' "Starship"

    } elseif ($promptChoice -eq "2") {
        if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            Ok "Oh My Posh 已安装"
        } else {
            Scoop-Install -Package "oh-my-posh" -Name "Oh My Posh" -TimeoutSec 60
        }
        Ensure-ProfileInit 'oh-my-posh init pwsh | Invoke-Expression' "Oh My Posh"
    } else {
        Ok "已跳过 Shell 提示符配置"
    }
}

# ══════════════════════════════════════════════════════
# 安装模块
# ══════════════════════════════════════════════════════

# ── Ghostty ───────────────────────────────────────────
function Install-Ghostty {
    Write-Host ""
    Info "========== [1/13] Ghostty =========="

    if (Get-Command ghostty -ErrorAction SilentlyContinue) {
        Ok "Ghostty 已安装"
    } else {
        Info "正在安装 Ghostty..."
        $installed = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                Winget-Install -Id "com.mitchellh.ghostty" -Name "Ghostty"
                $installed = $true
            } catch {}
        }
        if (-not $installed) {
            Warn "Ghostty Windows 版可能不可用，请从 https://ghostty.org/download 手动下载"
            Warn "替代方案: winget install Microsoft.WindowsTerminal"
        }
    }

    $ghosttyDir = "$env:APPDATA\ghostty"
    $ghosttyConf = "$ghosttyDir\config"
    if (-not (Test-Path $ghosttyDir)) { New-Item -ItemType Directory -Path $ghosttyDir -Force | Out-Null }

    Write-Host ""
    Write-Host "  1) 使用推荐配置 (Maple Mono + Catppuccin + 毛玻璃)" -ForegroundColor Cyan
    Write-Host "  2) 使用默认配置 / 保留当前配置" -ForegroundColor Cyan
    Write-Host ""
    $ghosttyChoice = Read-Host "选择 Ghostty 配置方案 [1/2] (默认 1)"
    if (-not $ghosttyChoice) { $ghosttyChoice = "1" }

    if ($ghosttyChoice -ne "2") {
        Backup-IfExists $ghosttyConf
        @"
# ============================================
# Ghostty Terminal - Windows 配置
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
"@ | Set-Content -Path $ghosttyConf -Encoding UTF8
        Ok "Ghostty 配置已写入 (Windows)"
    }

    # 安装终端时顺便配置 Shell 提示符
    Configure-ShellPrompt
}

# ── Yazi ──────────────────────────────────────────────
function Install-Yazi {
    Write-Host ""
    Info "========== [2/13] Yazi =========="

    Scoop-Install -Package "yazi" -Name "Yazi"

    Info "安装 Yazi 辅助依赖..."
    Scoop-Install -Package "fd" -Name "fd (快速文件查找)"
    Scoop-Install -Package "ripgrep" -Name "ripgrep (内容搜索)"
    Scoop-Install -Package "fzf" -Name "fzf (模糊搜索)"
    Scoop-Install -Package "zoxide" -Name "zoxide (智能目录跳转)"
    Scoop-Install -Package "poppler" -Name "poppler (PDF 预览)"
    Scoop-Install -Package "ffmpeg" -Name "ffmpeg (视频处理)"
    Scoop-Install -Package "7zip" -Name "7zip (压缩包预览)"
    Scoop-Install -Package "jq" -Name "jq (JSON 预览)"
    Scoop-Install -Package "imagemagick" -Name "ImageMagick (图片处理)"

    $yaziDir = "$env:APPDATA\yazi\config"
    if (-not (Test-Path $yaziDir)) { New-Item -ItemType Directory -Path $yaziDir -Force | Out-Null }

    Write-Host ""
    Write-Host "  1) 使用推荐配置 (glow 预览 + 大预览区 + 快捷跳转)" -ForegroundColor Cyan
    Write-Host "  2) 使用默认配置 / 保留当前配置" -ForegroundColor Cyan
    Write-Host ""
    $yaziChoice = Read-Host "选择 Yazi 配置方案 [1/2] (默认 1)"
    if (-not $yaziChoice) { $yaziChoice = "1" }

    if ($yaziChoice -ne "2") {
        Scoop-Install -Package "glow" -Name "glow (Markdown 预览)"

        Backup-IfExists "$yaziDir\yazi.toml"
        @"
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

[[plugin.prepend_previewers]]
url = "*.md"
run = 'piper -- glow -w=`$w -s=auto "`$1"'

[preview]
wrap       = "yes"
tab_size   = 2
max_width  = 1000
max_height = 1000

[opener]
edit = [
    { run = '`${EDITOR:-code} "%*"', block = true, for = "windows" },
]
open = [
    { run = 'start "" "%1"', for = "windows" },
]
reveal = [
    { run = 'explorer /select,"%1"', for = "windows" },
]

[[open.rules]]
name = "*.{md,txt,json,yaml,yml,toml,lua,py,go,rs,js,ts,tsx,jsx,sh,css,html,sql,env,conf,cfg,ps1}"
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
use = "open"
"@ | Set-Content -Path "$yaziDir\yazi.toml" -Encoding UTF8
        Ok "yazi.toml 已写入"

        Backup-IfExists "$yaziDir\keymap.toml"
        @"
# ============================================
# Yazi - 快捷键配置
# ============================================

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

[[mgr.prepend_keymap]]
on   = ["C"]
run  = "shell 'code \"%PWD%\"' --confirm"
desc = "Open in VS Code"

[[mgr.prepend_keymap]]
on   = ["S"]
run  = "shell 'pwsh' --block --confirm"
desc = "Open PowerShell here"
"@ | Set-Content -Path "$yaziDir\keymap.toml" -Encoding UTF8
        Ok "keymap.toml 已写入"

        Backup-IfExists "$yaziDir\theme.toml"
        @"
# Yazi 主题配置 (使用默认主题)
# Catppuccin: ya pack -a yazi-rs/flavors:catppuccin-mocha
"@ | Set-Content -Path "$yaziDir\theme.toml" -Encoding UTF8
        Ok "theme.toml 已写入"

        Backup-IfExists "$yaziDir\init.lua"
        @"
-- Yazi 插件初始化
local ok_border, full_border = pcall(require, "full-border")
if ok_border then full_border:setup() end

local ok_git, git = pcall(require, "git")
if ok_git then git:setup() end
"@ | Set-Content -Path "$yaziDir\init.lua" -Encoding UTF8
        Ok "init.lua 已写入"

        if (Get-Command ya -ErrorAction SilentlyContinue) {
            Info "安装 Yazi 插件..."
            ya pack -a yazi-rs/plugins:full-border 2>$null
            ya pack -a yazi-rs/plugins:git 2>$null
            ya pack -a yazi-rs/plugins:chmod 2>$null
            Ok "Yazi 插件已安装"
        }
    }

    # Shell 集成 (y 函数)
    $yaziWrapper = @'
# Yazi: 退出后自动 cd 到最后浏览的目录
function y {
    $tmp = [System.IO.Path]::GetTempFileName()
    yazi $args --cwd-file="$tmp"
    $cwd = Get-Content $tmp -ErrorAction SilentlyContinue
    if ($cwd -and $cwd -ne $PWD.Path) {
        Set-Location $cwd
    }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
'@
    $added = Add-ToProfile -Content $yaziWrapper -Marker "function y {"
    if ($added) { Ok "已添加 y 命令到 PowerShell Profile" }
    else { Ok "Yazi shell wrapper (y 命令) 已存在" }
}

# ── Lazygit ───────────────────────────────────────────
function Install-Lazygit {
    Write-Host ""
    Info "========== [3/13] Lazygit =========="

    Scoop-Install -Package "lazygit" -Name "Lazygit"
    Scoop-Install -Package "delta" -Name "delta (语法高亮 diff)"

    $lazygitDir = "$env:APPDATA\lazygit"
    $lazygitConf = "$lazygitDir\config.yml"
    if (-not (Test-Path $lazygitDir)) { New-Item -ItemType Directory -Path $lazygitDir -Force | Out-Null }

    Backup-IfExists $lazygitConf
    @"
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
    command: "echo {{.SelectedLocalBranch.Name}} | clip"
    description: "Copy branch name"
"@ | Set-Content -Path $lazygitConf -Encoding UTF8
    Ok "Lazygit 配置已写入"

    $pager = git config --global core.pager 2>$null
    if ($pager -notlike "*delta*") {
        git config --global core.pager "delta"
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.dark true
        git config --global delta.line-numbers true
        git config --global delta.side-by-side false
        git config --global delta.hyperlinks true
        git config --global merge.conflictstyle "zdiff3"
        Ok "Git Delta 全局配置已写入"
    } else {
        Ok "Git Delta 已配置"
    }
}

# ── Claude Code 提供商配置 ────────────────────────────
# 双写策略: 同时设置 Windows 用户环境变量 + ~/.claude/settings.json
# 确保无论 Claude Code 从何处启动都能读到配置

$CLAUDE_SETTINGS_PATH = "$env:USERPROFILE\.claude\settings.json"

$script:PROVIDER_KEYS = @(
    "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL",
    "CLAUDE_CODE_USE_BEDROCK", "AWS_REGION", "AWS_PROFILE",
    "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
    "CLAUDE_CODE_USE_VERTEX", "CLOUD_ML_REGION", "ANTHROPIC_VERTEX_PROJECT_ID"
)

function Detect-ClaudeProvider {
    # 优先从用户环境变量检测
    $userBedrock = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_USE_BEDROCK", "User")
    $userVertex  = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_USE_VERTEX", "User")
    $userBaseUrl = [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")
    $userApiKey  = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User")

    if ($userBedrock) { return "Amazon Bedrock" }
    if ($userVertex)  { return "Google Vertex AI" }
    if ($userBaseUrl) { return "自定义 API 代理" }
    if ($userApiKey)  { return "Anthropic 直连" }
    return "未配置"
}

function Write-ClaudeEnv {
    param([hashtable]$EnvVars)

    # 1. 先清除旧的提供商环境变量
    foreach ($key in $script:PROVIDER_KEYS) {
        [Environment]::SetEnvironmentVariable($key, $null, "User")
    }

    # 2. 设置新的用户环境变量 (立即对所有新进程生效)
    foreach ($k in $EnvVars.Keys) {
        [Environment]::SetEnvironmentVariable($k, $EnvVars[$k], "User")
        # 同时设置当前进程环境变量 (立即生效)
        Set-Item -Path "Env:\$k" -Value $EnvVars[$k]
    }

    # 3. 同时写入 ~/.claude/settings.json (双保险)
    $settingsDir = Split-Path $CLAUDE_SETTINGS_PATH
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }

    $settings = @{}
    if (Test-Path $CLAUDE_SETTINGS_PATH) {
        try {
            $raw = Get-Content $CLAUDE_SETTINGS_PATH -Raw -ErrorAction Stop
            $parsed = $raw | ConvertFrom-Json
            $parsed.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
        } catch {}
    }

    # 构建 env 字段: 保留非提供商 key + 写入新 key
    $envHash = [ordered]@{}
    if ($settings.ContainsKey("env") -and $settings["env"]) {
        $settings["env"].PSObject.Properties | ForEach-Object {
            if ($_.Name -notin $script:PROVIDER_KEYS) {
                $envHash[$_.Name] = $_.Value
            }
        }
    }
    foreach ($k in $EnvVars.Keys) {
        $envHash[$k] = $EnvVars[$k]
    }
    $settings["env"] = $envHash

    [PSCustomObject]$settings | ConvertTo-Json -Depth 10 | Set-Content -Path $CLAUDE_SETTINGS_PATH -Encoding UTF8
}

function Clear-ClaudeEnv {
    $cleared = $false

    # 清除用户环境变量
    foreach ($key in $script:PROVIDER_KEYS) {
        $val = [Environment]::GetEnvironmentVariable($key, "User")
        if ($val) {
            [Environment]::SetEnvironmentVariable($key, $null, "User")
            Remove-Item -Path "Env:\$key" -ErrorAction SilentlyContinue
            $cleared = $true
        }
    }

    # 清除 settings.json 中的提供商 key
    if (Test-Path $CLAUDE_SETTINGS_PATH) {
        try {
            $raw = Get-Content $CLAUDE_SETTINGS_PATH -Raw -ErrorAction Stop
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.env) {
                $envHash = [ordered]@{}
                $parsed.env.PSObject.Properties | ForEach-Object {
                    if ($_.Name -notin $script:PROVIDER_KEYS) {
                        $envHash[$_.Name] = $_.Value
                    } else {
                        $cleared = $true
                    }
                }
                $settings = [ordered]@{}
                $parsed.PSObject.Properties | ForEach-Object {
                    if ($_.Name -ne "env") { $settings[$_.Name] = $_.Value }
                }
                if ($envHash.Count -gt 0) { $settings["env"] = $envHash }
                [PSCustomObject]$settings | ConvertTo-Json -Depth 10 | Set-Content -Path $CLAUDE_SETTINGS_PATH -Encoding UTF8
            }
        } catch {}
    }

    return $cleared
}

function Get-ExistingValue {
    param([string]$VarName)
    # 优先从用户环境变量读取
    $val = [Environment]::GetEnvironmentVariable($VarName, "User")
    if ($val) { return $val }
    return ""
}

function Read-WithDefault {
    param(
        [string]$Prompt,
        [string]$Default
    )
    if ($Default) {
        $result = Read-Host "$Prompt [$Default]"
    } else {
        $result = Read-Host $Prompt
    }
    if (-not $result -and $Default) { return $Default }
    return $result
}

function Configure-ClaudeProvider {
    Info "配置 Claude Code API 提供商"

    $currentProvider = Detect-ClaudeProvider
    Write-Host ""
    Write-Host "  当前提供商: $currentProvider" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Anthropic 直连        (使用 Anthropic API Key)" -ForegroundColor Green
    Write-Host "  2) Amazon Bedrock        (使用 AWS 凭证)" -ForegroundColor Green
    Write-Host "  3) Google Vertex AI      (使用 GCP 项目)" -ForegroundColor Green
    Write-Host "  4) 自定义 API 代理       (OpenRouter / 中转站等)" -ForegroundColor Green
    Write-Host "  5) 清除配置              (移除当前提供商设置)" -ForegroundColor Green
    Write-Host "  0) 跳过                  (保持现有配置不变)" -ForegroundColor Green
    Write-Host ""
    $providerChoice = Read-Host "  请输入选项 [0-5]"

    switch ($providerChoice) {
        "1" {
            Info "配置 Anthropic 直连..."
            $existingKey = Get-ExistingValue "ANTHROPIC_API_KEY"
            $apiKey = Read-WithDefault "  Anthropic API Key" $existingKey
            if (-not $apiKey) {
                Err "API Key 不能为空，跳过配置"
            } else {
                $masked = "$($apiKey.Substring(0,8))...$($apiKey.Substring($apiKey.Length-4))"
                Write-ClaudeEnv @{ "ANTHROPIC_API_KEY" = $apiKey }
                Ok "Anthropic 直连已配置 (Key: $masked)"
                Info "已写入用户环境变量 + $CLAUDE_SETTINGS_PATH"
            }
        }
        "2" {
            Info "配置 Amazon Bedrock..."
            Write-Host ""
            Write-Host "  认证方式:" -ForegroundColor White
            Write-Host "    a) AWS Access Key (AK/SK)" -ForegroundColor Green
            Write-Host "    b) AWS Profile (~/.aws/credentials)" -ForegroundColor Green
            Write-Host ""
            $awsAuthMode = Read-Host "  选择认证方式 [a/b]"

            $existingRegion = Get-ExistingValue "AWS_REGION"
            $defaultRegion = if ($existingRegion) { $existingRegion } else { "us-east-1" }
            $awsRegion = Read-WithDefault "  AWS Region" $defaultRegion

            $envVars = [ordered]@{
                "CLAUDE_CODE_USE_BEDROCK" = "1"
                "AWS_REGION" = $awsRegion
            }

            if ($awsAuthMode -eq "b") {
                $existingProfile = Get-ExistingValue "AWS_PROFILE"
                $defaultProfile = if ($existingProfile) { $existingProfile } else { "default" }
                $awsProfile = Read-WithDefault "  AWS Profile 名称" $defaultProfile
                $envVars["AWS_PROFILE"] = $awsProfile
                Write-ClaudeEnv $envVars
                Ok "Amazon Bedrock 已配置 (Profile: $awsProfile, Region: $awsRegion)"
                Info "已写入用户环境变量 + $CLAUDE_SETTINGS_PATH"
            } else {
                $existingAK = Get-ExistingValue "AWS_ACCESS_KEY_ID"
                $existingSK = Get-ExistingValue "AWS_SECRET_ACCESS_KEY"
                $existingToken = Get-ExistingValue "AWS_SESSION_TOKEN"

                $accessKey = Read-WithDefault "  AWS Access Key ID" $existingAK
                $secretKey = Read-WithDefault "  AWS Secret Access Key" $existingSK
                $sessionToken = Read-WithDefault "  AWS Session Token (可选, 回车跳过)" $existingToken

                if (-not $accessKey -or -not $secretKey) {
                    Err "Access Key 和 Secret Key 不能为空，跳过配置"
                } else {
                    $envVars["AWS_ACCESS_KEY_ID"] = $accessKey
                    $envVars["AWS_SECRET_ACCESS_KEY"] = $secretKey
                    if ($sessionToken) {
                        $envVars["AWS_SESSION_TOKEN"] = $sessionToken
                    }
                    Write-ClaudeEnv $envVars
                    $maskedAK = "$($accessKey.Substring(0,4))...$($accessKey.Substring($accessKey.Length-4))"
                    Ok "Amazon Bedrock 已配置 (AK: $maskedAK, Region: $awsRegion)"
                    Info "已写入用户环境变量 + $CLAUDE_SETTINGS_PATH"
                }
            }
        }
        "3" {
            Info "配置 Google Vertex AI..."
            $existingRegion = Get-ExistingValue "CLOUD_ML_REGION"
            $existingProject = Get-ExistingValue "ANTHROPIC_VERTEX_PROJECT_ID"

            $gcpProject = Read-WithDefault "  GCP 项目 ID" $existingProject
            $defaultRegion = if ($existingRegion) { $existingRegion } else { "us-east5" }
            $gcpRegion = Read-WithDefault "  GCP Region" $defaultRegion

            if (-not $gcpProject) {
                Err "GCP 项目 ID 不能为空，跳过配置"
            } else {
                Write-ClaudeEnv @{
                    "CLAUDE_CODE_USE_VERTEX" = "1"
                    "CLOUD_ML_REGION" = $gcpRegion
                    "ANTHROPIC_VERTEX_PROJECT_ID" = $gcpProject
                }
                Ok "Google Vertex AI 已配置 (项目: $gcpProject, Region: $gcpRegion)"
                Info "已写入用户环境变量 + $CLAUDE_SETTINGS_PATH"
                Write-Host ""
                Info "提示: 请确保已通过 gcloud auth application-default login 完成认证"
            }
        }
        "4" {
            Info "配置自定义 API 代理..."
            $existingUrl = Get-ExistingValue "ANTHROPIC_BASE_URL"
            $existingKey = Get-ExistingValue "ANTHROPIC_API_KEY"

            $baseUrl = Read-WithDefault "  API Base URL (例: https://openrouter.ai/api/v1)" $existingUrl
            $apiKey = Read-WithDefault "  API Key" $existingKey

            if (-not $baseUrl -or -not $apiKey) {
                Err "Base URL 和 API Key 不能为空，跳过配置"
            } else {
                $masked = "$($apiKey.Substring(0,8))...$($apiKey.Substring($apiKey.Length-4))"
                Write-ClaudeEnv @{
                    "ANTHROPIC_BASE_URL" = $baseUrl
                    "ANTHROPIC_API_KEY" = $apiKey
                }
                Ok "自定义 API 代理已配置 (URL: $baseUrl, Key: $masked)"
                Info "已写入用户环境变量 + $CLAUDE_SETTINGS_PATH"
            }
        }
        "5" {
            if (Clear-ClaudeEnv) {
                Ok "已清除 Claude 提供商配置"
                Info "已清除用户环境变量 + $CLAUDE_SETTINGS_PATH"
            } else {
                Warn "未找到已有的 Claude 提供商配置"
            }
        }
        { $_ -in @("0", "") } {
            Ok "保持现有配置不变"
        }
        default {
            Warn "无效选项，跳过 Claude 提供商配置"
        }
    }
}

# ── Claude Code ───────────────────────────────────────
function Install-Claude {
    Write-Host ""
    Info "========== [4/13] Claude Code =========="

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Ok "Claude Code 已安装"
    } else {
        Info "正在安装 Claude Code..."
        $installed = $false

        # 尝试官方安装脚本 (15s 超时)
        try {
            $script = Invoke-RestMethod -Uri "https://claude.ai/install.ps1" -TimeoutSec 15
            Invoke-Expression $script
            $installed = $true
            Ok "Claude Code 安装完成"
        } catch {
            Warn "官方脚本安装失败，尝试其他方式..."
        }

        if (-not $installed -and (Get-Command npm -ErrorAction SilentlyContinue)) {
            npm install -g @anthropic-ai/claude-code 2>$null
            if ($LASTEXITCODE -eq 0) {
                Ok "Claude Code (npm) 安装完成"
                $installed = $true
            }
        }

        if (-not $installed -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            try {
                Winget-Install -Id "Anthropic.ClaudeCode" -Name "Claude Code"
                $installed = $true
            } catch {}
        }

        if (-not $installed) {
            Err "Claude Code 安装失败，请手动安装: https://docs.anthropic.com/en/docs/claude-code"
        }
    }

    Refresh-Path

    Write-Host ""
    Configure-ClaudeProvider

    Write-Host ""
    Info "Claude Code 使用提示:"
    Write-Host "   claude              启动交互式会话"
    Write-Host '   claude "问题"       直接提问'
    Write-Host '   claude -p "问题"    非交互模式 (管道友好)'
    Write-Host "   首次使用需要登录:    claude login"
}

# ── Codex CLI ────────────────────────────────────────
function Install-Codex {
    Write-Host ""
    Info "========== [5/13] Codex CLI =========="

    if (Get-Command codex -ErrorAction SilentlyContinue) {
        Ok "Codex CLI 已安装"
    } else {
        Info "正在安装 Codex CLI..."
        $installed = $false

        # 优先 npm 全局安装 (官方推荐方式)
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            npm install -g @openai/codex 2>$null
            if ($LASTEXITCODE -eq 0) {
                Ok "Codex CLI (npm) 安装完成"
                $installed = $true
            }
        }

        # 后备: scoop
        if (-not $installed -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
            try {
                scoop install codex 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Ok "Codex CLI (scoop) 安装完成"
                    $installed = $true
                }
            } catch {}
        }

        # 后备: winget
        if (-not $installed -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            try {
                Winget-Install -Id "OpenAI.Codex" -Name "Codex CLI"
                if (Get-Command codex -ErrorAction SilentlyContinue) {
                    $installed = $true
                }
            } catch {}
        }

        if (-not $installed) {
            Err "Codex CLI 安装失败，请手动安装: https://github.com/openai/codex"
        }
    }

    Refresh-Path

    Write-Host ""
    Info "Codex CLI 使用提示:"
    Write-Host "   codex                启动交互式会话"
    Write-Host '   codex "问题"         直接提问'
    Write-Host "   codex --help         查看完整帮助"
    Write-Host "   首次使用需要登录:     codex login"
}

# ── OpenClaw ──────────────────────────────────────────
function Install-OpenClaw {
    Write-Host ""
    Info "========== [6/13] OpenClaw =========="

    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        Ok "OpenClaw 已安装"
    } else {
        Info "正在安装 OpenClaw..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try { Winget-Install -Id "OpenClaw.OpenClaw" -Name "OpenClaw" } catch {}
        }
        if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
            Warn "请从 https://openclaw.ai 手动下载安装 OpenClaw"
        }
    }

    Write-Host ""
    Info "OpenClaw 使用提示:"
    Write-Host "   openclaw            启动 OpenClaw"
    Write-Host "   openclaw onboard    首次设置向导"
}

# ── Hermes Agent ─────────────────────────────────────
function Install-Hermes {
    Write-Host ""
    Info "========== [7/13] Hermes Agent =========="

    if (Get-Command hermes -ErrorAction SilentlyContinue) {
        Ok "Hermes Agent 已安装"
    } else {
        Info "正在安装 Hermes Agent..."
        try {
            $installUrl = GitHub-RawUrl "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"
            Invoke-RestMethod -Uri $installUrl -TimeoutSec 15 | Invoke-Expression
            Ok "Hermes Agent 安装完成"
        } catch {
            Warn "自动安装失败，请从 https://github.com/nousresearch/hermes-agent 手动安装"
        }
    }

    # 检查 OpenClaw 迁移
    if ((Test-Path "$env:USERPROFILE\.openclaw") -and (Get-Command hermes -ErrorAction SilentlyContinue)) {
        Write-Host ""
        $migrateChoice = Read-Host "检测到 OpenClaw 数据，是否迁移到 Hermes? [y/N]"
        if ($migrateChoice -match '^[yY]$') {
            Info "正在迁移 OpenClaw 数据..."
            hermes claw migrate
        }
    }

    Write-Host ""
    Info "Hermes Agent 使用提示:"
    Write-Host "   hermes              启动交互式会话"
    Write-Host "   hermes setup        运行完整设置向导"
    Write-Host "   hermes model        选择 LLM 提供商和模型"
    Write-Host "   hermes tools        配置可用工具"
    Write-Host "   hermes update       更新到最新版本"
}

# ── Antigravity ──────────────────────────────────────
function Install-Antigravity {
    Write-Host ""
    Info "========== [8/13] Antigravity =========="

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Winget-Install -Id "Google.Antigravity" -Name "Antigravity"
    } else {
        Warn "请从 Google 官方网站下载 Antigravity"
    }

    Write-Host ""
    Info "Antigravity 使用提示:"
    Write-Host "   从开始菜单启动 Antigravity"
    Write-Host "   首次启动需要 Google 账号登录"
}

# ── Docker Desktop (OrbStack 替代) ────────────────────
function Install-OrbStack {
    Write-Host ""
    Info "========== [9/13] Docker Desktop =========="
    Info "OrbStack 仅支持 macOS，Windows 上安装 Docker Desktop 替代"

    if (Get-Command docker -ErrorAction SilentlyContinue) {
        Ok "Docker 已安装: $(docker --version)"
    } else {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Winget-Install -Id "Docker.DockerDesktop" -Name "Docker Desktop"
        } else {
            Warn "请从 https://www.docker.com/products/docker-desktop/ 下载 Docker Desktop"
        }
    }

    Write-Host ""
    Info "Docker Desktop 使用提示:"
    Write-Host "   docker run hello-world     验证安装"
    Write-Host "   docker compose up -d       启动容器编排"
    Write-Host "   注意: 需要先启动 Docker Desktop 应用"
}

# ── Obsidian ──────────────────────────────────────────
function Install-Obsidian {
    Write-Host ""
    Info "========== [10/13] Obsidian =========="

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Winget-Install -Id "Obsidian.Obsidian" -Name "Obsidian"
    } else {
        Scoop-Install -Package "obsidian" -Name "Obsidian" -Bucket "extras"
    }

    # Excalidraw 插件
    Write-Host ""
    Info "配置 Excalidraw 插件..."
    Write-Host ""
    Write-Host "请选择 Obsidian Vault 路径:" -ForegroundColor White
    Write-Host "  1) 默认路径: ~/Obsidian" -ForegroundColor Cyan
    Write-Host "  2) 自定义路径" -ForegroundColor Cyan
    Write-Host "  3) 跳过插件安装" -ForegroundColor Cyan
    $vaultChoice = Read-Host "请输入选项 [1/2/3] (默认 1)"
    if (-not $vaultChoice) { $vaultChoice = "1" }

    $vaultPath = switch ($vaultChoice) {
        "1" { "$env:USERPROFILE\Obsidian" }
        "2" { Read-Host "请输入 Vault 路径" }
        "3" { "" }
        default { "$env:USERPROFILE\Obsidian" }
    }

    if (-not $vaultPath) {
        Ok "跳过 Excalidraw 插件安装"
    } else {
        $pluginDir = "$vaultPath\.obsidian\plugins\obsidian-excalidraw-plugin"
        if (Test-Path $pluginDir) {
            Ok "Excalidraw 插件已安装"
        } else {
            New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
            Info "正在下载 Excalidraw 插件..."

            try {
                $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/zsviczian/obsidian-excalidraw-plugin/releases/latest" -UseBasicParsing -TimeoutSec 15
                $tag = $releaseInfo.tag_name
                $baseUrl = "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/download/$tag"

                foreach ($file in @("main.js", "manifest.json", "styles.css")) {
                    $dlUrl = GitHub-RawUrl "$baseUrl/$file"
                    Invoke-WebRequest -Uri $dlUrl -OutFile "$pluginDir\$file" -UseBasicParsing -TimeoutSec 30
                }
                Ok "Excalidraw 插件安装完成 ($tag)"
            } catch {
                Err "下载失败，请手动在 Obsidian 设置中安装 Excalidraw 插件"
                Remove-Item -Path $pluginDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # 启用插件
        $communityPlugins = "$vaultPath\.obsidian\community-plugins.json"
        if (Test-Path $pluginDir) {
            if (Test-Path $communityPlugins) {
                $plugins = Get-Content $communityPlugins -Raw -ErrorAction SilentlyContinue
                if ($plugins -notlike "*obsidian-excalidraw-plugin*") {
                    $plugins = $plugins -replace '\]$', ',"obsidian-excalidraw-plugin"]'
                    Set-Content -Path $communityPlugins -Value $plugins
                    Ok "已将 Excalidraw 添加到启用列表"
                }
            } else {
                $obsidianDir = "$vaultPath\.obsidian"
                if (-not (Test-Path $obsidianDir)) { New-Item -ItemType Directory -Path $obsidianDir -Force | Out-Null }
                '["obsidian-excalidraw-plugin"]' | Set-Content -Path $communityPlugins
                Ok "已创建社区插件配置并启用 Excalidraw"
            }
        }

        Write-Host ""
        Info "Obsidian 使用提示:"
        Write-Host "   从开始菜单启动 Obsidian"
        Write-Host "   打开 Vault: $vaultPath"
        Write-Host "   Excalidraw: Ctrl+P 搜索 Excalidraw 命令"
    }
}

# ── Ditto (Maccy 替代) ────────────────────────────────
function Install-Maccy {
    Write-Host ""
    Info "========== [11/13] Ditto (剪贴板管理) =========="
    Info "Maccy 仅支持 macOS，Windows 上安装 Ditto 替代"

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Winget-Install -Id "Ditto.Ditto" -Name "Ditto"
    } else {
        Scoop-Install -Package "ditto" -Name "Ditto" -Bucket "extras"
    }

    Write-Host ""
    Info "Ditto 使用提示:"
    Write-Host "   默认快捷键: Ctrl+`` 打开剪贴板历史"
    Write-Host "   支持文本、图片、文件等多种格式"
    Write-Host "   也可使用 Windows 内置: Win+V"
}

# ── JDK ──────────────────────────────────────────────
function Install-JDK {
    Write-Host ""
    Info "========== [12/13] JDK =========="

    Write-Host ""
    Write-Host "选择 JDK 版本 (Eclipse Temurin):" -ForegroundColor White
    Write-Host "  1) JDK 21 (LTS，推荐)" -ForegroundColor Cyan
    Write-Host "  2) JDK 17 (LTS)" -ForegroundColor Cyan
    Write-Host "  3) JDK 11 (LTS)" -ForegroundColor Cyan
    Write-Host "  4) JDK 8  (LTS)" -ForegroundColor Cyan
    Write-Host "  5) 跳过" -ForegroundColor Cyan
    $jdkChoice = Read-Host "请输入选项 [1-5] (默认 1)"
    if (-not $jdkChoice) { $jdkChoice = "1" }

    $jdkId = switch ($jdkChoice) {
        "1" { "EclipseAdoptium.Temurin.21.JDK" }
        "2" { "EclipseAdoptium.Temurin.17.JDK" }
        "3" { "EclipseAdoptium.Temurin.11.JDK" }
        "4" { "EclipseAdoptium.Temurin.8.JDK" }
        "5" { "" }
        default { "EclipseAdoptium.Temurin.21.JDK" }
    }

    if ($jdkId) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Winget-Install -Id $jdkId -Name "JDK ($jdkId)"
        } else {
            $scoopPkg = switch ($jdkChoice) {
                "1" { "temurin21-jdk" }
                "2" { "temurin17-jdk" }
                "3" { "temurin11-jdk" }
                "4" { "temurin8-jdk" }
                default { "temurin21-jdk" }
            }
            scoop bucket add java 2>$null
            Scoop-Install -Package $scoopPkg -Name "JDK" -Bucket "java"
        }
    } else {
        Ok "跳过 JDK 安装"
    }

    Refresh-Path

    Write-Host ""
    Info "JDK 使用提示:"
    Write-Host "   java -version               查看当前 JDK 版本"
    Write-Host "   多版本管理: scoop install temurin17-jdk"
    Write-Host "   切换版本:   scoop reset temurin21-jdk"
}

# ── VS Code ──────────────────────────────────────────
function Install-VSCode {
    Write-Host ""
    Info "========== [13/13] VS Code =========="

    if (Get-Command code -ErrorAction SilentlyContinue) {
        Ok "VS Code 已安装"
    } else {
        Info "正在安装 VS Code..."
        $installed = $false
        $installer = "$env:TEMP\vscode-installer.exe"

        # 检测架构: ARM64 / x64 / ia32
        $cpuArch = $env:PROCESSOR_ARCHITECTURE
        $arch = switch ($cpuArch) {
            "ARM64" { "arm64" }
            "AMD64" { "x64" }
            default { if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "ia32" } }
        }
        Info "系统架构: $cpuArch -> VS Code $arch"

        # 检测 Windows 版本
        $winVer = [Environment]::OSVersion.Version
        Info "Windows 版本: $($winVer.Major).$($winVer.Minor).$($winVer.Build)"

        # 方式1: 微软 CDN 直接下载
        $cdnUrls = @(
            "https://update.code.visualstudio.com/latest/win32-$arch-user/stable"
            "https://vscode.cdn.azure.cn/stable/latest/VSCodeUserSetup-$arch.exe"
        )
        foreach ($url in $cdnUrls) {
            if ($installed) { break }
            try {
                Info "正在下载: $url"
                Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -TimeoutSec 120
                if ((Test-Path $installer) -and (Get-Item $installer).Length -gt 1MB) {
                    Info "正在静默安装..."
                    $proc = Start-Process -FilePath $installer -ArgumentList "/verysilent", "/mergetasks=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath" -Wait -NoNewWindow -PassThru
                    Remove-Item $installer -Force -ErrorAction SilentlyContinue
                    if ($proc.ExitCode -ne 0) {
                        Warn "安装程序退出码: $($proc.ExitCode)，可能版本不兼容"
                        continue
                    }
                    Refresh-Path
                    $vscodePath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin"
                    if (Test-Path $vscodePath) { $env:Path = "$vscodePath;$env:Path" }
                    if (Get-Command code -ErrorAction SilentlyContinue) {
                        $installed = $true
                        Ok "VS Code 安装完成 (直接下载)"
                    }
                }
            } catch {
                Warn "下载失败: $($_.Exception.Message)"
                Remove-Item $installer -Force -ErrorAction SilentlyContinue
            }
        }

        # 方式2: winget (微软商店 CDN, 60s 超时)
        if (-not $installed -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            Info "尝试 winget 安装 (60s 超时)..."
            $job = Start-Job -ScriptBlock { winget install --id Microsoft.VisualStudioCode --accept-source-agreements --accept-package-agreements --silent 2>&1 }
            $finished = $job | Wait-Job -Timeout 60
            if ($finished) {
                Receive-Job $job | Out-Null
                Remove-Job $job -Force
            } else {
                Stop-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -Force
                Warn "winget 安装超时"
            }
            Refresh-Path
            $vscodePath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin"
            if (Test-Path $vscodePath) { $env:Path = "$vscodePath;$env:Path" }
            if (Get-Command code -ErrorAction SilentlyContinue) {
                $installed = $true
                Ok "VS Code 安装完成 (winget)"
            }
        }

        # 方式3: scoop (GitHub Releases, 60s 超时)
        if (-not $installed) {
            Info "尝试 scoop 安装 (60s 超时)..."
            $result = Scoop-Install -Package "vscode" -Name "VS Code" -Bucket "extras" -TimeoutSec 60
        }

        if (-not $installed -and -not (Get-Command code -ErrorAction SilentlyContinue)) {
            Err "VS Code 自动安装失败"
            Warn "可能原因: Windows 版本不兼容 (需要 Win10 1709+ 或 Win11)"
            Warn "ARM Mac 虚拟机请下载 ARM64 版: https://code.visualstudio.com/Download"
            Warn "旧版 Windows 请下载 VS Code 1.83: https://update.code.visualstudio.com/1.83.1/win32-$arch-user/stable"
        }
    }

    Refresh-Path

    # 确保 code 命令可用
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Err "VS Code CLI (code) 不可用，跳过扩展安装"
        Warn "请重新打开终端后运行: code --install-extension Catppuccin.catppuccin-vsc"
        return
    }

    # 安装 Catppuccin 主题
    Info "安装 Catppuccin 主题扩展..."

    $extensions = code --list-extensions 2>$null
    if ($extensions -match "Catppuccin.catppuccin-vsc$") {
        Ok "Catppuccin 主题已安装"
    } else {
        code --install-extension Catppuccin.catppuccin-vsc --force 2>$null
        Ok "Catppuccin 主题安装完成"
    }

    if ($extensions -match "Catppuccin.catppuccin-vsc-icons") {
        Ok "Catppuccin Icons 已安装"
    } else {
        code --install-extension Catppuccin.catppuccin-vsc-icons --force 2>$null
        Ok "Catppuccin Icons 安装完成"
    }

    if ($extensions -match "MS-CEINTL.vscode-language-pack-zh-hans") {
        Ok "中文语言包已安装"
    } else {
        code --install-extension MS-CEINTL.vscode-language-pack-zh-hans --force 2>$null
        Ok "中文语言包安装完成"
    }

    if ($extensions -match "anthropic.claude-code") {
        Ok "Claude Code 插件已安装"
    } else {
        code --install-extension anthropic.claude-code --force 2>$null
        Ok "Claude Code 插件安装完成"
    }

    # 切换 VS Code 界面语言为中文 (通过 argv.json)
    # argv.json 是 JSONC 格式，直接修改容易损坏，用重建方式处理
    $argvPath = "$env:USERPROFILE\.vscode\argv.json"
    $argvDir = Split-Path $argvPath
    if (-not (Test-Path $argvDir)) { New-Item -ItemType Directory -Path $argvDir -Force | Out-Null }

    # 从现有文件提取 crash-reporter-id (如果有)
    $crashId = ""
    if (Test-Path $argvPath) {
        $raw = Get-Content $argvPath -Raw -ErrorAction SilentlyContinue
        if ($raw -match '"crash-reporter-id"\s*:\s*"([^"]+)"') {
            $crashId = $Matches[1]
        }
    }

    # 重建干净的 argv.json (必须无 BOM，否则 VS Code 报错)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    if ($crashId) {
        $argvJson = @"
{
    "locale": "zh-cn",
    "enable-crash-reporter": true,
    "crash-reporter-id": "$crashId"
}
"@
    } else {
        $argvJson = @"
{
    "locale": "zh-cn"
}
"@
    }
    [System.IO.File]::WriteAllText($argvPath, $argvJson, $utf8NoBom)
    Ok "已切换 VS Code 界面语言为中文 (argv.json)"

    # 设置 Catppuccin 为默认主题
    $vscodSettingsDir = "$env:APPDATA\Code\User"
    $vscodeSettings = "$vscodSettingsDir\settings.json"
    if (-not (Test-Path $vscodSettingsDir)) { New-Item -ItemType Directory -Path $vscodSettingsDir -Force | Out-Null }

    if (Test-Path $vscodeSettings) {
        $content = Get-Content $vscodeSettings -Raw -ErrorAction SilentlyContinue
        if ($content -match '"workbench.colorTheme"') {
            $content = $content -replace '"workbench.colorTheme"\s*:\s*"[^"]*"', '"workbench.colorTheme": "Catppuccin Latte"'
            Ok "已将 VS Code 主题切换为 Catppuccin Latte"
        } else {
            $content = $content -replace '^\{', "{`n    `"workbench.colorTheme`": `"Catppuccin Latte`","
            Ok "已添加 Catppuccin Latte 主题到 settings.json"
        }
        if ($content -match '"workbench.iconTheme"') {
            $content = $content -replace '"workbench.iconTheme"\s*:\s*"[^"]*"', '"workbench.iconTheme": "catppuccin-latte"'
        } else {
            $content = $content -replace '^\{', "{`n    `"workbench.iconTheme`": `"catppuccin-latte`","
        }
        # 设置中文语言
        if ($content -match '"locale"') {
            $content = $content -replace '"locale"\s*:\s*"[^"]*"', '"locale": "zh-cn"'
        } else {
            $content = $content -replace '^\{', "{`n    `"locale`": `"zh-cn`","
        }
        Set-Content -Path $vscodeSettings -Value $content -Encoding UTF8
        Ok "已设置 Catppuccin 主题 + 中文语言"
    } else {
        @"
{
    "workbench.colorTheme": "Catppuccin Latte",
    "workbench.iconTheme": "catppuccin-latte",
    "locale": "zh-cn"
}
"@ | Set-Content -Path $vscodeSettings -Encoding UTF8
        Ok "已创建 VS Code settings.json (Catppuccin Latte + 中文)"
    }

    Write-Host ""
    Info "VS Code 使用提示:"
    Write-Host "   code .                打开当前目录"
    Write-Host "   code <file>           打开文件"
    Write-Host "   主题: Catppuccin Latte (已自动应用)"
    Write-Host "   切换主题: Ctrl+K Ctrl+T"
}

# ══════════════════════════════════════════════════════
# 卸载模块
# ══════════════════════════════════════════════════════

function Uninstall-Tools {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "   Windows 开发工具卸载                          " -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""

    # 检测已安装的工具 (cmd, 显示名, scoop包名)
    # 分两组: 应用工具 + 基础环境
    $checks = @(
        @("--- 应用工具 ---", "", ""),
        @("ghostty",  "Ghostty",        "ghostty"),
        @("yazi",     "Yazi",           "yazi"),
        @("lazygit",  "Lazygit",        "lazygit"),
        @("claude",   "Claude Code",    ""),
        @("codex",    "Codex CLI",      ""),
        @("openclaw", "OpenClaw",       ""),
        @("hermes",   "Hermes Agent",   ""),
        @("docker",   "Docker Desktop", ""),
        @("java",     "JDK",            ""),
        @("code",     "VS Code",        "vscode"),
        @("--- 基础环境 ---", "", ""),
        @("git",      "Git",            "git"),
        @("node",     "Node.js",        "nodejs-lts"),
        @("nvm",      "NVM",            "nvm"),
        @("bun",      "Bun",            "bun"),
        @("starship", "Starship",       "starship"),
        @("oh-my-posh", "Oh My Posh",   "oh-my-posh"),
        @("delta",    "Git Delta",      "delta")
    )

    Info "检测已安装的工具..."

    # 一次性获取 scoop 已安装列表
    $scoopInstalled = @()
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        $scoopInstalled = scoop list 2>$null | ForEach-Object {
            if ($_ -match '^\s*(\S+)\s+\d') { $Matches[1] }
        } | Where-Object { $_ }
    }

    $installedList = @()
    $idx = 1
    $hasItemsInGroup = $false
    foreach ($check in $checks) {
        $cmd = $check[0]
        $name = $check[1]
        $scoopPkg = $check[2]

        # 分组标题
        if ($cmd -match '^---') {
            if ($installedList.Count -gt 0 -and $hasItemsInGroup) { Write-Host "" }
            Write-Host "  $cmd" -ForegroundColor White
            $hasItemsInGroup = $false
            continue
        }

        $found = $false
        if (Get-Command $cmd -ErrorAction SilentlyContinue) { $found = $true }
        if (-not $found -and $scoopPkg -and ($scoopPkg -in $scoopInstalled)) { $found = $true }

        if ($found) {
            Write-Host "  $idx) $name" -ForegroundColor Cyan
            $installedList += @{ Idx = $idx; Cmd = $cmd; Name = $name }
            $idx++
            $hasItemsInGroup = $true
        }
    }

    if ($installedList.Count -eq 0) {
        Info "未检测到已安装的工具"
        return
    }

    Write-Host ""
    Write-Host "  A) 全部卸载" -ForegroundColor Red
    Write-Host "  Q) 取消" -ForegroundColor Yellow
    Write-Host ""
    $input = Read-Host "请输入编号 (多选用逗号分隔)"

    if (-not $input -or $input -match '^[qQ]$') {
        Ok "已取消卸载"
        return
    }

    $toUninstall = @()
    if ($input -match '^[aA]$') {
        $toUninstall = $installedList
    } else {
        $nums = $input -split '[,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        foreach ($num in $nums) {
            $match = $installedList | Where-Object { $_.Idx -eq [int]$num }
            if ($match) { $toUninstall += $match }
        }
    }

    if ($toUninstall.Count -eq 0) {
        Warn "未选择有效工具"
        return
    }

    # 确认
    $names = ($toUninstall | ForEach-Object { $_.Name }) -join ", "
    Write-Host ""
    Warn "即将卸载: $names"
    $confirm = Read-Host "确认卸载? [y/N]"
    if ($confirm -notmatch '^[yY]$') {
        Ok "已取消"
        return
    }

    Write-Host ""
    foreach ($tool in $toUninstall) {
        $cmd = $tool.Cmd
        $name = $tool.Name
        Info "正在卸载 $name..."

        # 优先 scoop 卸载
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            $scoopPkg = switch ($cmd) {
                "code"      { "vscode" }
                "node"      { "nodejs-lts" }
                "oh-my-posh" { "oh-my-posh" }
                "java"      { $null }
                default     { $cmd }
            }
            if ($scoopPkg -and ($scoopPkg -in $scoopInstalled)) {
                scoop uninstall $scoopPkg 2>&1 | Out-Null
                Ok "$name 已卸载 (scoop)"
                continue
            }
        }

        # 按工具类型处理
        switch ($cmd) {
            "ghostty" {
                if (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id "com.mitchellh.ghostty" --silent 2>$null }
                Remove-Item "$env:APPDATA\ghostty" -Recurse -Force -ErrorAction SilentlyContinue
            }
            "yazi" {
                Remove-Item "$env:APPDATA\yazi" -Recurse -Force -ErrorAction SilentlyContinue
            }
            "lazygit" {
                Remove-Item "$env:APPDATA\lazygit" -Recurse -Force -ErrorAction SilentlyContinue
            }
            "claude" {
                if (Get-Command npm -ErrorAction SilentlyContinue) { npm uninstall -g @anthropic-ai/claude-code 2>$null }
                $claudeBin = "$env:LOCALAPPDATA\Programs\claude-code"
                if (Test-Path $claudeBin) { Remove-Item $claudeBin -Recurse -Force -ErrorAction SilentlyContinue }
            }
            "codex" {
                if (Get-Command npm -ErrorAction SilentlyContinue) { npm uninstall -g @openai/codex 2>$null }
                if (Get-Command scoop -ErrorAction SilentlyContinue) { scoop uninstall codex 2>&1 | Out-Null }
                if (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id "OpenAI.Codex" --silent 2>$null }
            }
            "openclaw" {
                if (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id "OpenClaw.OpenClaw" --silent 2>$null }
            }
            "hermes" {
                Remove-Item "$env:USERPROFILE\.hermes" -Recurse -Force -ErrorAction SilentlyContinue
            }
            "docker" {
                if (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id "Docker.DockerDesktop" --silent 2>$null }
            }
            "java" {
                # scoop JDK
                scoop list 2>$null | Select-String "temurin|jdk" | ForEach-Object {
                    $pkg = ($_.Line -split '\s+')[0]
                    scoop uninstall $pkg 2>$null
                }
                # winget JDK
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    winget list 2>$null | Select-String "Temurin" | ForEach-Object {
                        if ($_.Line -match '(EclipseAdoptium\.\S+)') { winget uninstall --id $Matches[1] --silent 2>$null }
                    }
                }
            }
            "code" {
                # scoop
                if ("vscode" -in $scoopInstalled) { scoop uninstall vscode 2>&1 | Out-Null }
                # winget
                if (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id "Microsoft.VisualStudioCode" --silent 2>$null }
                # 手动安装
                $uninstaller = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\unins000.exe"
                if (Test-Path $uninstaller) { Start-Process $uninstaller -ArgumentList "/verysilent" -Wait -NoNewWindow }
                # 清理配置
                Remove-Item "$env:APPDATA\Code" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item "$env:USERPROFILE\.vscode" -Recurse -Force -ErrorAction SilentlyContinue
            }
            # ── 基础环境 ──
            "git" {
                if (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id "Git.Git" --silent 2>$null }
            }
            "node" {
                # NVM 安装的 Node
                if (Get-Command nvm -ErrorAction SilentlyContinue) {
                    $current = nvm current 2>$null
                    if ($current) { nvm uninstall $current 2>$null }
                }
                if (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id "OpenJS.NodeJS.LTS" --silent 2>$null }
            }
            "nvm" {
                # 清理 NVM 目录
                $nvmDir = $env:NVM_HOME
                if (-not $nvmDir) { $nvmDir = "$env:APPDATA\nvm" }
                if (Test-Path $nvmDir) { Remove-Item $nvmDir -Recurse -Force -ErrorAction SilentlyContinue }
                if (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id "CoreyButler.NVMforWindows" --silent 2>$null }
            }
            "bun" {
                $bunDir = "$env:USERPROFILE\.bun"
                if (Test-Path $bunDir) { Remove-Item $bunDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
            "starship" {
                # 从 PowerShell Profile 移除 starship init
                $profilePath = $PROFILE.CurrentUserAllHosts
                if (Test-Path $profilePath) {
                    $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
                    if ($content -match 'starship') {
                        $content = ($content -split "`n" | Where-Object { $_ -notmatch 'starship' }) -join "`n"
                        Set-Content -Path $profilePath -Value $content
                    }
                }
                Remove-Item "$env:USERPROFILE\.config\starship.toml" -Force -ErrorAction SilentlyContinue
            }
            "oh-my-posh" {
                $profilePath = $PROFILE.CurrentUserAllHosts
                if (Test-Path $profilePath) {
                    $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
                    if ($content -match 'oh-my-posh') {
                        $content = ($content -split "`n" | Where-Object { $_ -notmatch 'oh-my-posh' }) -join "`n"
                        Set-Content -Path $profilePath -Value $content
                    }
                }
            }
            "delta" {
                git config --global --unset core.pager 2>$null
                git config --global --unset interactive.diffFilter 2>$null
                git config --global --remove-section delta 2>$null
            }
        }

        Ok "$name 已卸载"
    }

    Write-Host ""
    Write-Host "卸载完成" -ForegroundColor Green
    Refresh-Path
}

# ══════════════════════════════════════════════════════
# 主流程
# ══════════════════════════════════════════════════════
function Main {
    # 检查管理员权限
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Warn "部分安装可能需要管理员权限，建议以管理员身份运行 PowerShell"
    }

    # 解析参数
    Parse-Args $args

    # 卸载模式
    if ($script:UNINSTALL_MODE) {
        Uninstall-Tools
        return
    }

    # 仅 claude-provider 模式
    if ($script:SKIP_PREREQUISITES -and ($script:SELECTED_TOOLS -contains "claude-provider")) {
        Write-Host ""
        Configure-ClaudeProvider
        return
    }

    # 环境基础检查
    if (-not $script:SKIP_PREREQUISITES) {
        Check-Prerequisites
    }


    # 安装选中的工具 (带进度)
    if ($script:SELECTED_TOOLS.Count -gt 0) {
        $total = $script:SELECTED_TOOLS.Count
        Write-Host ""
        Write-Host "  即将安装 $total 个工具，开始..." -ForegroundColor White
        Write-Host ""

        $step = 0
        $installMap = [ordered]@{
            "ghostty"     = { Install-Ghostty }
            "yazi"        = { Install-Yazi }
            "lazygit"     = { Install-Lazygit }
            "claude"      = { Install-Claude }
            "codex"       = { Install-Codex }
            "openclaw"    = { Install-OpenClaw }
            "hermes"      = { Install-Hermes }
            "antigravity" = { Install-Antigravity }
            "orbstack"    = { Install-OrbStack }
            "obsidian"    = { Install-Obsidian }
            "maccy"       = { Install-Maccy }
            "jdk"         = { Install-JDK }
            "vscode"      = { Install-VSCode }
        }

        foreach ($key in $installMap.Keys) {
            if (Is-Selected $key) {
                $step++
                # 进度条
                $pct = [math]::Floor($step / $total * 100)
                $filled = [math]::Floor($step / $total * 20)
                $empty = 20 - $filled
                $bar = ("=" * $filled) + ("-" * $empty)
                Write-Host "  [$bar] $pct% ($step/$total)" -ForegroundColor Cyan
                & $installMap[$key]
            }
        }
    }

    # 跳过模式：配置菜单
    if ($script:SKIP_PREREQUISITES -and $script:SELECTED_TOOLS.Count -eq 0) {
        Write-Host ""
        Info "========== 配置操作 =========="
        Write-Host ""
        Write-Host "  1) 修改 Claude 提供商配置" -ForegroundColor Green
        Write-Host "  0) 退出" -ForegroundColor Green
        Write-Host ""
        $configChoice = Read-Host "  请选择 [0-1]"
        switch ($configChoice) {
            "1" { Configure-ClaudeProvider }
            default { Ok "已退出" }
        }
    }

    # ── 完成汇总 ──────────────────────────────────────
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  安装完成!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""

    if ($script:SELECTED_TOOLS.Count -gt 0) {
        Write-Host "  已安装的工具:" -ForegroundColor White
        Write-Host ""
        if (Is-Selected "ghostty")     { Write-Host "    Ghostty       终端窗口" -ForegroundColor Green }
        if (Is-Selected "yazi")        { Write-Host "    Yazi          文件管理器" -ForegroundColor Green }
        if (Is-Selected "lazygit")     { Write-Host "    Lazygit       Git 图形界面" -ForegroundColor Green }
        if (Is-Selected "claude")      { Write-Host "    Claude Code   AI 编程助手 (Anthropic)" -ForegroundColor Green }
        if (Is-Selected "codex")       { Write-Host "    Codex CLI     AI 编程助手 (OpenAI)" -ForegroundColor Green }
        if (Is-Selected "openclaw")    { Write-Host "    OpenClaw      本地 AI 助手" -ForegroundColor Green }
        if (Is-Selected "hermes")      { Write-Host "    Hermes        AI 智能体" -ForegroundColor Green }
        if (Is-Selected "antigravity") { Write-Host "    Antigravity   Google AI 平台" -ForegroundColor Green }
        if (Is-Selected "orbstack")    { Write-Host "    Docker        容器工具" -ForegroundColor Green }
        if (Is-Selected "obsidian")    { Write-Host "    Obsidian      笔记软件" -ForegroundColor Green }
        if (Is-Selected "maccy")       { Write-Host "    Ditto         剪贴板历史 (按 Ctrl+`` 打开)" -ForegroundColor Green }
        if (Is-Selected "jdk")         { Write-Host "    JDK           Java 环境" -ForegroundColor Green }
        if (Is-Selected "vscode")      { Write-Host "    VS Code       代码编辑器 (已装好中文和主题)" -ForegroundColor Green }
        Write-Host ""
    }

    Write-Host "  接下来:" -ForegroundColor Yellow
    Write-Host "    1. 关闭并重新打开终端，让设置生效" -ForegroundColor White
    Write-Host "    2. 如需卸载，重新运行本脚本选 U" -ForegroundColor White
    Write-Host ""

    Refresh-Path
}

# 运行主流程
Main
