// SMPTLOG 卸载程序（WinForms，中文）
// 编译：csc /target:winexe /out:uninstall.exe /r:System.Windows.Forms.dll
//        /r:System.Drawing.dll Uninstaller.cs
//
// 自删除思路：把自身复制到 %TEMP% 再以 --run 参数拉起，
// 由临时副本删除安装目录（含原 exe），最后留下一个无害的临时文件。

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

static class UninstallerProgram
{
    static readonly string Dest = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        @"Programs\SMPTLOG");

    static readonly string DataDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SMPTLOG");

    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length >= 2 && args[0] == "--run")
        {
            string target = args[1];
            bool deleteData = args.Length >= 3 && args[2] == "1";

            // 若当前运行的 exe 就在目标目录里，无法删除自身，
            // 先复制到 %TEMP% 重新拉起，再退出。
            string self = Assembly.GetExecutingAssembly().Location;
            if (self.StartsWith(target, StringComparison.OrdinalIgnoreCase))
            {
                string moved = Path.Combine(Path.GetTempPath(),
                    "smptlog-uninst2-" + DateTime.Now.Ticks + ".exe");
                File.Copy(self, moved, true);
                Process.Start(new ProcessStartInfo(moved,
                    "--run \"" + target + "\" " + (deleteData ? "1" : "0")));
                return;
            }

            PerformUninstall(target, deleteData);
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        Form f = new Form();
        f.Text = "卸载 SMPTLOG 通联日志";
        f.ClientSize = new Size(460, 290);
        f.StartPosition = FormStartPosition.CenterScreen;
        f.FormBorderStyle = FormBorderStyle.FixedDialog;
        f.MaximizeBox = false;
        f.MinimizeBox = false;
        f.BackColor = Color.FromArgb(245, 248, 254);
        f.Font = new Font("Microsoft YaHei UI", 9F);

        Label title = new Label();
        title.Text = "卸载 SMPTLOG 通联日志";
        title.Font = new Font("Microsoft YaHei UI", 15F, FontStyle.Bold);
        title.ForeColor = Color.FromArgb(27, 42, 65);
        title.SetBounds(22, 20, 410, 32);
        f.Controls.Add(title);

        Label info = new Label();
        info.Text = "程序位置：" + Dest + "\r\n数据位置：" + DataDir;
        info.ForeColor = Color.FromArgb(107, 124, 153);
        info.SetBounds(24, 62, 412, 44);
        f.Controls.Add(info);

        CheckBox chkData = new CheckBox();
        chkData.Text = "同时删除我的通联数据（不可恢复）";
        chkData.Checked = false;
        chkData.SetBounds(24, 122, 320, 24);
        f.Controls.Add(chkData);

        Label warn = new Label();
        warn.Text = "不勾选时，通联记录、中继台与设置都会保留，重新安装后可继续使用。";
        warn.ForeColor = Color.FromArgb(107, 124, 153);
        warn.SetBounds(42, 148, 396, 36);
        f.Controls.Add(warn);

        Button ok = new Button();
        ok.Text = "卸载";
        ok.SetBounds(180, 200, 120, 36);
        ok.BackColor = Color.FromArgb(229, 72, 77);
        ok.ForeColor = Color.White;
        ok.FlatStyle = FlatStyle.Flat;
        ok.FlatAppearance.BorderSize = 0;
        f.Controls.Add(ok);

        Button cancel = new Button();
        cancel.Text = "取消";
        cancel.SetBounds(310, 200, 90, 36);
        cancel.FlatStyle = FlatStyle.Flat;
        cancel.FlatAppearance.BorderSize = 0;
        cancel.Click += delegate { f.Close(); };
        f.Controls.Add(cancel);

        ok.Click += delegate
        {
            ok.Enabled = false;
            ok.Text = "正在卸载…";
            f.Refresh();
            try
            {
                string temp = Path.Combine(Path.GetTempPath(),
                    "smptlog-uninst-" + DateTime.Now.Ticks + ".exe");
                File.Copy(Assembly.GetExecutingAssembly().Location, temp, true);
                Process.Start(new ProcessStartInfo(temp,
                    "--run \"" + Dest + "\" " + (chkData.Checked ? "1" : "0")));
                Application.Exit();
            }
            catch (Exception e)
            {
                MessageBox.Show("卸载失败：" + e.Message, "SMPTLOG 卸载",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                ok.Enabled = true;
                ok.Text = "卸载";
            }
        };

        Application.Run(f);
    }

    static void PerformUninstall(string dest, bool deleteData)
    {
        Thread.Sleep(600);

        try
        {
            string startLnk = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                "SMPTLOG.lnk");
            if (File.Exists(startLnk)) File.Delete(startLnk);

            string deskLnk = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                "SMPTLOG.lnk");
            if (File.Exists(deskLnk)) File.Delete(deskLnk);

            Registry.CurrentUser.DeleteSubKeyTree(
                @"Software\Microsoft\Windows\CurrentVersion\Uninstall\SMPTLOG", false);

            if (deleteData && Directory.Exists(DataDir))
            {
                try { Directory.Delete(DataDir, true); }
                catch { }
            }

            if (Directory.Exists(dest))
            {
                for (int i = 0; i < 5; i++)
                {
                    try
                    {
                        Directory.Delete(dest, true);
                        break;
                    }
                    catch
                    {
                        Thread.Sleep(400);
                    }
                }
            }
        }
        catch
        {
            // 卸载过程不抛出，尽量完成能完成的部分
        }
    }
}
