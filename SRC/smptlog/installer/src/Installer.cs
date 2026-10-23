// SMPTLOG 安装程序（WinForms，中文）
// 编译：csc /target:winexe /out:install.exe /r:System.Windows.Forms.dll
//        /r:System.Drawing.dll /r:System.IO.Compression.dll
//        /r:System.IO.Compression.FileSystem.dll /r:Microsoft.CSharp.dll Installer.cs
// 支持 --silent 无界面安装（自动化验证用）

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

static class InstallerProgram
{
    static readonly string Dest = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        @"Programs\SMPTLOG");

    static readonly string DataDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SMPTLOG");

    static string ExeDir
    {
        get
        {
            string p = Assembly.GetExecutingAssembly().Location;
            return Path.GetDirectoryName(p);
        }
    }

    /// 启动日志：万一被安全软件拦截或抛出异常，事后能查到入口。
    static void Log(string msg)
    {
        try
        {
            string f = Path.Combine(Path.GetTempPath(), "smptlog-setup.log");
            File.AppendAllText(f,
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg + "\r\n");
        }
        catch { }
    }

    [STAThread]
    static void Main(string[] args)
    {
        Log("启动，参数：" + string.Join(" ", args));
        AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e)
        {
            Log("未处理异常：" + e.ExceptionObject);
        };

        try
        {
            RunMain(args);
        }
        catch (Exception ex)
        {
            Log("致命错误：" + ex);
            MessageBox.Show("安装程序出错：" + ex.Message, "SMPTLOG 安装",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    static void RunMain(string[] args)
    {
        bool silent = Array.IndexOf(args, "--silent") >= 0;

        if (silent)
        {
            try
            {
                DoInstall(false, false);
                Console.WriteLine("OK");
            }
            catch (Exception e)
            {
                Log("静默安装失败：" + e);
                Console.Error.WriteLine("FAIL " + e.Message);
                Environment.Exit(1);
            }
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        Form f = new Form();
        f.Text = "SMPTLOG 安装程序";
        f.ClientSize = new Size(460, 300);
        f.StartPosition = FormStartPosition.CenterScreen;
        f.FormBorderStyle = FormBorderStyle.FixedDialog;
        f.MaximizeBox = false;
        f.MinimizeBox = false;
        f.BackColor = Color.FromArgb(245, 248, 254);
        f.Font = new Font("Microsoft YaHei UI", 9F);

        Label title = new Label();
        title.Text = "SMPTLOG 通联日志";
        title.Font = new Font("Microsoft YaHei UI", 16F, FontStyle.Bold);
        title.ForeColor = Color.FromArgb(27, 42, 65);
        title.SetBounds(22, 20, 410, 34);
        f.Controls.Add(title);

        Label sub = new Label();
        sub.Text = "版本 1.1.1 · 业余无线电通联日志助手";
        sub.ForeColor = Color.FromArgb(107, 124, 153);
        sub.SetBounds(24, 56, 410, 20);
        f.Controls.Add(sub);

        Label path = new Label();
        path.Text = "安装位置：" + Dest;
        path.ForeColor = Color.FromArgb(107, 124, 153);
        path.SetBounds(24, 96, 412, 22);
        f.Controls.Add(path);

        Label data = new Label();
        data.Text = "数据位置：" + DataDir + "（升级/卸载都不丢）";
        data.ForeColor = Color.FromArgb(107, 124, 153);
        data.SetBounds(24, 120, 412, 22);
        f.Controls.Add(data);

        CheckBox chkDesktop = new CheckBox();
        chkDesktop.Text = "创建桌面快捷方式";
        chkDesktop.Checked = true;
        chkDesktop.SetBounds(24, 158, 240, 24);
        f.Controls.Add(chkDesktop);

        CheckBox chkLaunch = new CheckBox();
        chkLaunch.Text = "安装完成后立即启动";
        chkLaunch.Checked = true;
        chkLaunch.SetBounds(24, 184, 240, 24);
        f.Controls.Add(chkLaunch);

        Button ok = new Button();
        ok.Text = "安装";
        ok.SetBounds(180, 232, 120, 36);
        ok.BackColor = Color.FromArgb(47, 111, 237);
        ok.ForeColor = Color.White;
        ok.FlatStyle = FlatStyle.Flat;
        ok.FlatAppearance.BorderSize = 0;
        f.Controls.Add(ok);

        Button cancel = new Button();
        cancel.Text = "取消";
        cancel.SetBounds(310, 232, 90, 36);
        cancel.FlatStyle = FlatStyle.Flat;
        cancel.FlatAppearance.BorderSize = 0;
        cancel.Click += delegate { f.Close(); };
        f.Controls.Add(cancel);

        ok.Click += delegate
        {
            ok.Enabled = false;
            ok.Text = "正在安装…";
            f.Refresh();
            try
            {
                DoInstall(chkDesktop.Checked, chkLaunch.Checked);
                MessageBox.Show(
                    "安装完成。\r\n\r\n程序位置：" + Dest + "\r\n数据位置：" + DataDir,
                    "SMPTLOG 安装", MessageBoxButtons.OK, MessageBoxIcon.Information);
                f.Close();
            }
            catch (Exception e)
            {
                MessageBox.Show("安装失败：" + e.Message, "SMPTLOG 安装",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                ok.Enabled = true;
                ok.Text = "安装";
            }
        };

        Application.Run(f);
    }

    /// 读取内嵌资源；若不存在（开发期直接运行）则回退到同目录文件。
    static Stream OpenResource(string name)
    {
        Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
        if (s != null) return s;

        string local = Path.Combine(ExeDir, name);
        if (File.Exists(local)) return File.OpenRead(local);

        throw new Exception("安装包缺少内嵌文件：" + name);
    }

    static void DoInstall(bool desktopShortcut, bool launch)
    {
        if (!Directory.Exists(Dest)) Directory.CreateDirectory(Dest);

        // app.zip 与 uninstall.exe 作为资源嵌入在安装程序内部，
        // 不再依赖同目录文件，也不需要任何自解压外壳。
        try
        {
            using (Stream res = OpenResource("app.zip"))
            using (ZipArchive archive = new ZipArchive(res, ZipArchiveMode.Read))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    if (string.IsNullOrEmpty(entry.Name)) continue;
                    string target = Path.Combine(Dest, entry.FullName.Replace('/', '\\'));
                    string dir = Path.GetDirectoryName(target);
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    entry.ExtractToFile(target, true);
                }
            }

            using (Stream us = OpenResource("uninstall.exe"))
            using (FileStream fs = File.Create(Path.Combine(Dest, "uninstall.exe")))
            {
                us.CopyTo(fs);
            }
        }
        catch (IOException)
        {
            throw new Exception(
                "SMPTLOG 正在运行，文件被占用。\r\n请先关闭程序（包括任务栏/托盘里的图标）再安装。");
        }
        catch (UnauthorizedAccessException)
        {
            throw new Exception(
                "没有写入权限。请关闭杀软拦截，或以同一用户身份运行安装程序。");
        }

        string appExe = Path.Combine(Dest, "smptlog.exe");

        // 快捷方式（WScript.Shell 晚绑定，避免额外的 COM 引用）
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType != null)
        {
            object shell = Activator.CreateInstance(shellType);
            object startLnk = shellType.InvokeMember("CreateShortcut",
                BindingFlags.InvokeMethod, null, shell,
                new object[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "SMPTLOG.lnk") });
            startLnk.GetType().InvokeMember("TargetPath", BindingFlags.SetProperty, null, startLnk, new object[] { appExe });
            startLnk.GetType().InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, startLnk, new object[] { Dest });
            startLnk.GetType().InvokeMember("Description", BindingFlags.SetProperty, null, startLnk, new object[] { "SMPTLOG 通联日志" });
            startLnk.GetType().InvokeMember("Save", BindingFlags.InvokeMethod, null, startLnk, null);

            if (desktopShortcut)
            {
                object deskLnk = shellType.InvokeMember("CreateShortcut",
                    BindingFlags.InvokeMethod, null, shell,
                    new object[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "SMPTLOG.lnk") });
                deskLnk.GetType().InvokeMember("TargetPath", BindingFlags.SetProperty, null, deskLnk, new object[] { appExe });
                deskLnk.GetType().InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, deskLnk, new object[] { Dest });
                deskLnk.GetType().InvokeMember("Save", BindingFlags.InvokeMethod, null, deskLnk, null);
            }
        }

        string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\SMPTLOG";
        using (RegistryKey key = Registry.CurrentUser.CreateSubKey(keyPath))
        {
            key.SetValue("DisplayName", "SMPTLOG 通联日志");
            key.SetValue("DisplayVersion", "1.1.1");
            key.SetValue("Publisher", "SMPTLOG");
            key.SetValue("InstallLocation", Dest);
            key.SetValue("DisplayIcon", appExe);
            key.SetValue("UninstallString", "\"" + Path.Combine(Dest, "uninstall.exe") + "\"");
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }

        if (launch && File.Exists(appExe))
        {
            Process.Start(appExe);
        }
    }
}
