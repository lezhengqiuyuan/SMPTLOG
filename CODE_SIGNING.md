# 代码签名政策 / Code Signing Policy

**Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org).**

本项目正在申请 SignPath Foundation 的免费开源代码签名。审核通过后，下方列出的发布产物将由该证书签名。

---

## 会被签名的内容

仅签名**本仓库源码构建**的 Windows 发布产物：

| 产物 | 说明 |
|---|---|
| `SMPTLOG-Setup-x.y.z.exe` | 单文件安装程序（内含程序本体与卸载程序） |

以下内容**不会**被签名：

- `smptlog.exe`（程序本体）与 `uninstall.exe`（卸载程序）：两者在打包阶段被嵌入安装包内部的 `app.zip`，签名只作用于发布出去的安装包文件本身；它们与安装包来自**同一提交**的源码
- Android APK（由 Android 自身签名机制处理，使用项目自有 keystore）
- 第三方依赖（Flutter 引擎、SQLite 等随包 DLL 属上游库，不单独签名）

> 后续计划：扩大签名覆盖范围 —— 先签名 `smptlog.exe`，再打包安装包并第二次签名。

## 构建与签名流程

1. 代码合并到 `main` 分支
2. 打标签（如 `v1.0.0`）触发 GitHub Actions 工作流 [`.github/workflows/release.yml`](.github/workflows/release.yml)
3. CI 在 **GitHub 托管的 Windows/Ubuntu runner** 上从源码构建：
   - `flutter build windows --release`
   - `flutter build apk --release`
   - 安装程序由仓库内 `SRC/smptlog/installer/src/Installer.cs`、`Uninstaller.cs` 编译而成（不使用自解压外壳）
4. 构建产物作为 workflow artifact 上传
5. 每个 Release 的签名请求由 **Approver 在 SignPath 网页端人工批准**
6. 签名后的产物由 CI 发布到 GitHub Releases

> 任何二进制都可从本仓库的源码与构建脚本重现；签名只证明"该二进制由本仓库在指定提交上自动构建"。
>
> 签名私钥由 SignPath 托管在硬件安全模块（HSM）中，项目方不接触也不保存私钥；每个 Release 的签名请求都必须由 Approver 人工批准。

## 如何验证签名

右键安装包 → 属性 → 数字签名，签名者应显示为 **SignPath Foundation**；也可以用 PowerShell 查看：

```powershell
Get-AuthenticodeSignature .\SMPTLOG-Setup-1.1.0.exe | Format-List Status, SignerCertificate
```

其中 `Status`（校验状态）应为 `Valid`，`SignerCertificate`（签名证书）的主体应为 `SignPath Foundation`。

## 团队角色

本项目目前为**单人维护**，角色均指向仓库所有者：

- **Authors（提交者）**：[lezhengqiuyuan](https://github.com/lezhengqiuyuan) —— 唯一代码提交者
- **Reviewers（审核者）**：[lezhengqiuyuan](https://github.com/lezhengqiuyuan) —— 外部 PR 由仓库所有者审核后合并
- **Approvers（签名批准）**：[lezhengqiuyuan](https://github.com/lezhengqiuyuan) —— 每个 Release 的签名请求由其本人批准

所有角色均已启用 GitHub 双因素认证（MFA）。

## 隐私政策 / Privacy Policy

> **This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.**

补充说明：

- 程序默认**纯本地运行**，不联网、不上报任何数据。
- 唯一的网络行为有两处，都需要**用户主动触发**：
  1. 点击「同步」：将日志上传到**用户自己配置**的存储服务（腾讯云 EdgeOne Makers Blob 或用户自选的 WebDAV 服务）。地址与凭据均由用户填写，项目方不持有任何服务器。
  2. 点击「检查更新」：向 GitHub 公共 API 查询本项目的最新 Release 版本号，不发送任何本地数据。
- 同步凭据（API Token / 应用密码）只保存在用户本机（Windows DPAPI、Android Keystore），不写入数据库、不进入任何导出文件。
- 程序不含统计、埋点、广告或自动更新检查。

第三方组件说明：Flutter 引擎、SQLite（`sqlite3_flutter_libs`）等随包组件按其各自许可证分发，详见 `LICENSE` 与 `NOTICES`。

## 用户交互方面的承诺

- **安装与卸载**：安装程序为图形界面（中文），控制面板可卸载；卸载时明确询问是否保留通联数据，默认保留。
- **系统更改**：安装仅写入 `%LOCALAPPDATA%\Programs\SMPTLOG`、创建开始菜单/桌面快捷方式、写入标准卸载注册表项，不修改系统其他配置。

## 许可证

本项目以 **GNU General Public License v3.0** 发布，无商业双许可。详见 [LICENSE](LICENSE)。

---

如有关于本政策的疑问或发现签名产物异常，请提交 [Issue](https://github.com/lezhengqiuyuan/SMPTLOG/issues)。
