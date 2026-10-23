# SMPTLOG 安装包构建脚本（零额外依赖，单文件安装包）
#
# 原理：
#   1. 用 .NET Framework 自带的 csc.exe 编译 Uninstaller.cs → uninstall.exe
#   2. 用系统自带 tar.exe 把 Windows 产物压成 app.zip
#   3. 再用 csc 把 app.zip 与 uninstall.exe **作为内嵌资源** 编进 Installer.cs
#      → 直接得到一个 13 MB 左右的单文件安装包（无自解压外壳、无批处理）
#
# 为什么不使用 IExpress / 批处理 / PowerShell：
#   - 批处理 + 隐藏窗口启动脚本 会被杀软判为 Heur:TrojanDownloader/PS.NetLoader 并删除
#   - IExpress 自解压后再释放 exe 到 %TEMP%，同样属于高危行为，会被拦截
#   - 单文件 .NET 程序双击即可弹出中文界面，最稳
#
# 前置：已执行 flutter build windows --release
# 用法：在 SRC/smptlog 目录下执行
#     powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1

$ErrorActionPreference = 'Stop'

$version  = '1.0.0'
$projRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $projRoot)
$release  = Join-Path $projRoot 'build\windows\x64\runner\Release'
$srcDir   = Join-Path $PSScriptRoot 'src'
$work     = Join-Path $env:TEMP 'smptlog_build'
$finalDir = Join-Path $repoRoot 'EXE'
$finalExe = Join-Path $finalDir "SMPTLOG-Setup-$version.exe"

if (-not (Test-Path (Join-Path $release 'smptlog.exe'))) {
    throw "未找到构建产物：$release。请先运行 flutter build windows --release"
}

$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw '找不到 csc.exe（需要 .NET Framework 4.x）' }

if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null

Write-Host '1/3 编译卸载程序…'
& $csc /nologo /target:winexe /out:"$work\uninstall.exe" `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll "$srcDir\Uninstaller.cs" "$srcDir\AssemblyInfo.cs"
if ($LASTEXITCODE -ne 0) { throw 'Uninstaller.cs 编译失败' }

Write-Host '2/3 打包程序文件…'
& "$env:SystemRoot\System32\tar.exe" -a -c -f "$work\app.zip" -C $release .
if ($LASTEXITCODE -ne 0) { throw 'tar 打包失败' }

Write-Host '3/3 生成单文件安装包…'
& $csc /nologo /target:winexe /out:"$work\Setup.exe" `
    "/resource:$work\app.zip,app.zip" `
    "/resource:$work\uninstall.exe,uninstall.exe" `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll `
    /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll `
    "$srcDir\Installer.cs" "$srcDir\AssemblyInfo.cs"
if ($LASTEXITCODE -ne 0) { throw 'Installer.cs 编译失败' }

if (-not (Test-Path $finalDir)) { New-Item -ItemType Directory -Path $finalDir -Force | Out-Null }
Copy-Item "$work\Setup.exe" $finalExe -Force

$sizeMb = [math]::Round((Get-Item $finalExe).Length / 1MB, 1)
Write-Host "完成：$finalExe（$sizeMb MB）"
