// Update checker for ChatterFix.
//
// Fetches a small signed manifest from chatterfix.app, and if it advertises a
// newer version offers to install it. The manifest is signed with a key held
// offline; the matching public key is compiled in below. Nothing is installed
// unless both the signature over the manifest and the SHA-256 of the downloaded
// executable match, because ChatterFix installs a low-level keyboard hook and a
// spoofed update would be a keylogger.

using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ChatterFix
{
    sealed class Appcast
    {
        public string Version;
        public string NotesUrl;
        public string Url;
        public string Sha256;
    }

    static class Updater
    {
        public const string CurrentVersion = "1.0.0";

        const string AppcastUrl = "https://chatterfix.app/appcast.json";
        const string SettingsKeyPath = @"Software\ChatterFix";

        // RSA-2048 public key, modulus base64. Pairs with ~/.chatterfix/release_private.pem.
        const string ModulusB64 =
            "0bYycxxWZE0puOiWEyyXd/FM2KMsGE9/1WrRDPeFYC8SJ2wa2iHcgugbcohvdXEKiYWXwILnVQRe" +
            "xy/o4dRQWR+M/e/mJOBaqQV0MdTnbDthkV+sSxcSwSj7Cct1ZLWIxOk1IVmEyl47UuniQcrfJCfs" +
            "ANbXQviiOTQGsSw7uHp9x+0lTmkghKdigih+Qc+yuTKMVlMWsMOdNMxT7qO3xYtV9rfrBctvmI8V" +
            "y/xU+UDLBdGCjJ0evEQV8EAFa3VaWTBpb+ki7TjwpHX8qcINHrvt+cxbVbcLuL7LR2uf18yw/yLZ" +
            "hEcPxNvModpbb6fuKNRNzbQj3SyZw/j7I6mVyw==";
        static readonly byte[] Exponent = { 1, 0, 1 };

        // ---- preferences ----
        public static bool AutoInstall
        {
            get
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(SettingsKeyPath))
                    return k != null && (k.GetValue("AutoUpdate") as int? ?? 0) == 1;
            }
            set
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(SettingsKeyPath))
                    k.SetValue("AutoUpdate", value ? 1 : 0, RegistryValueKind.DWord);
            }
        }

        static string SkippedVersion
        {
            get
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(SettingsKeyPath))
                    return k == null ? null : k.GetValue("SkippedVersion") as string;
            }
            set
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(SettingsKeyPath))
                    k.SetValue("SkippedVersion", value ?? "");
            }
        }

        static DateTime LastCheck
        {
            get
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(SettingsKeyPath))
                {
                    string s = k == null ? null : k.GetValue("LastUpdateCheck") as string;
                    DateTime d;
                    if (s != null && DateTime.TryParse(s, CultureInfo.InvariantCulture,
                            DateTimeStyles.RoundtripKind, out d)) return d;
                    return DateTime.MinValue;
                }
            }
            set
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(SettingsKeyPath))
                    k.SetValue("LastUpdateCheck", value.ToString("o", CultureInfo.InvariantCulture));
            }
        }

        // "1.10.0" > "1.9.0": compare numerically per component, not as strings.
        public static bool IsNewer(string candidate, string current)
        {
            string[] a = candidate.Split('.'), b = current.Split('.');
            int n = Math.Max(a.Length, b.Length);
            for (int i = 0; i < n; i++)
            {
                int x = 0, y = 0;
                if (i < a.Length) int.TryParse(a[i], out x);
                if (i < b.Length) int.TryParse(b[i], out y);
                if (x != y) return x > y;
            }
            return false;
        }

        static string Field(string json, string name)
        {
            Match m = Regex.Match(json, "\"" + name + "\"\\s*:\\s*\"([^\"]*)\"");
            return m.Success ? m.Groups[1].Value : null;
        }

        // Pulls a field out of the "mac" or "win" object specifically.
        static string NestedField(string json, string obj, string name)
        {
            Match block = Regex.Match(json, "\"" + obj + "\"\\s*:\\s*\\{(.*?)\\}", RegexOptions.Singleline);
            return block.Success ? Field(block.Groups[1].Value, name) : null;
        }

        static bool Verify(string payload, string signatureB64)
        {
            try
            {
                using (RSACryptoServiceProvider rsa = new RSACryptoServiceProvider())
                {
                    RSAParameters p = new RSAParameters();
                    p.Modulus = Convert.FromBase64String(ModulusB64);
                    p.Exponent = Exponent;
                    rsa.ImportParameters(p);
                    return rsa.VerifyData(Encoding.UTF8.GetBytes(payload),
                        "SHA256", Convert.FromBase64String(signatureB64));
                }
            }
            catch { return false; }
        }

        public static Appcast Fetch()
        {
            try
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                using (WebClient wc = new WebClient())
                {
                    wc.Headers.Add("User-Agent", "ChatterFix/" + CurrentVersion);
                    string json = wc.DownloadString(AppcastUrl + "?t=" +
                        DateTime.UtcNow.Ticks); // defeat any intermediate cache

                    string version = Field(json, "version");
                    string notes = Field(json, "notesUrl");
                    string sig = Field(json, "signature");
                    string macUrl = NestedField(json, "mac", "url");
                    string macSha = NestedField(json, "mac", "sha256");
                    string winUrl = NestedField(json, "win", "url");
                    string winSha = NestedField(json, "win", "sha256");
                    if (version == null || notes == null || sig == null ||
                        macUrl == null || macSha == null || winUrl == null || winSha == null)
                        return null;

                    // Must match tools/sign_release.sh exactly, field for field.
                    string payload = version + "\n" + macUrl + "\n" + macSha + "\n" +
                                     winUrl + "\n" + winSha + "\n" + notes;
                    if (!Verify(payload, sig)) return null;

                    Appcast a = new Appcast();
                    a.Version = version; a.NotesUrl = notes;
                    a.Url = winUrl; a.Sha256 = winSha;
                    return a;
                }
            }
            catch { return null; }
        }

        static string DownloadAndVerify(Appcast a)
        {
            try
            {
                string dest = Path.Combine(Path.GetTempPath(),
                    "ChatterFix-" + a.Version + ".exe");
                using (WebClient wc = new WebClient())
                {
                    wc.Headers.Add("User-Agent", "ChatterFix/" + CurrentVersion);
                    wc.DownloadFile(a.Url, dest);
                }
                using (SHA256 sha = SHA256.Create())
                using (FileStream fs = File.OpenRead(dest))
                {
                    string hex = BitConverter.ToString(sha.ComputeHash(fs))
                        .Replace("-", "").ToLowerInvariant();
                    if (!string.Equals(hex, a.Sha256, StringComparison.OrdinalIgnoreCase))
                    {
                        File.Delete(dest);
                        return null;
                    }
                }
                return dest;
            }
            catch { return null; }
        }

        // A .exe cannot overwrite itself while running, so a throwaway batch file
        // waits for this process to exit, swaps the file, and relaunches.
        static bool Install(string newExe)
        {
            try
            {
                string current = Application.ExecutablePath;
                string bat = Path.Combine(Path.GetTempPath(), "chatterfix_update.cmd");
                File.WriteAllText(bat,
                    "@echo off\r\n" +
                    ":wait\r\n" +
                    "tasklist /fi \"PID eq " + Process.GetCurrentProcess().Id +
                        "\" | find \"" + Process.GetCurrentProcess().Id + "\" >nul\r\n" +
                    "if not errorlevel 1 (ping -n 2 127.0.0.1 >nul & goto wait)\r\n" +
                    "move /y \"" + newExe + "\" \"" + current + "\" >nul\r\n" +
                    "start \"\" \"" + current + "\"\r\n" +
                    "del \"%~f0\"\r\n");

                ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c \"" + bat + "\"");
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                psi.CreateNoWindow = true;
                Process.Start(psi);
                return true;
            }
            catch { return false; }
        }

        // Runs on a background thread; UI work is marshalled back by the caller.
        public static void Check(bool userInitiated, Action<Action> onUiThread)
        {
            if (!userInitiated && (DateTime.UtcNow - LastCheck).TotalHours < 24) return;
            LastCheck = DateTime.UtcNow;

            Appcast a = Fetch();
            onUiThread(delegate
            {
                if (a == null)
                {
                    if (userInitiated)
                        MessageBox.Show("ChatterFix couldn't reach the update server. " +
                            "Please try again later.", "ChatterFix",
                            MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                if (!IsNewer(a.Version, CurrentVersion))
                {
                    if (userInitiated)
                        MessageBox.Show("ChatterFix " + CurrentVersion +
                            " is the latest version.", "ChatterFix",
                            MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                if (!userInitiated && SkippedVersion == a.Version) return;

                if (AutoInstall) { DoInstall(a, true); return; }

                using (UpdatePrompt prompt = new UpdatePrompt(a.Version, CurrentVersion))
                {
                    DialogResult r = prompt.ShowDialog();
                    AutoInstall = prompt.AutoChecked;
                    if (r == DialogResult.Yes) DoInstall(a, false);
                    else if (r == DialogResult.Abort) SkippedVersion = a.Version;
                }
            });
        }

        static void DoInstall(Appcast a, bool silent)
        {
            string exe = DownloadAndVerify(a);
            if (exe == null)
            {
                if (!silent)
                    MessageBox.Show("The download couldn't be verified, so nothing " +
                        "was installed.", "ChatterFix", MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);
                return;
            }
            if (!Install(exe))
            {
                if (!silent)
                    MessageBox.Show("ChatterFix couldn't install the update.",
                        "ChatterFix", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            Application.Exit(); // the helper relaunches the new build
        }
    }

    // Small dialog: Install / Remind Me Later / Skip This Version, plus the
    // "install automatically" checkbox. Built by hand to avoid a designer file.
    sealed class UpdatePrompt : Form
    {
        readonly CheckBox _auto;
        public bool AutoChecked { get { return _auto.Checked; } }

        public UpdatePrompt(string newVersion, string currentVersion)
        {
            Text = "ChatterFix";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            MinimizeBox = false; MaximizeBox = false; ShowInTaskbar = true;
            ClientSize = new System.Drawing.Size(420, 170);

            Label title = new Label();
            title.Text = "ChatterFix " + newVersion + " is available";
            title.Font = new System.Drawing.Font(Font.FontFamily, 10.5f,
                System.Drawing.FontStyle.Bold);
            title.SetBounds(16, 16, 388, 24);

            Label body = new Label();
            body.Text = "You have " + currentVersion + ". Installing takes a few seconds " +
                        "and ChatterFix will reopen automatically.";
            body.SetBounds(16, 44, 388, 36);

            _auto = new CheckBox();
            _auto.Text = "Install updates automatically from now on";
            _auto.Checked = Updater.AutoInstall;
            _auto.SetBounds(16, 88, 388, 22);

            Button install = new Button();
            install.Text = "Install Update";
            install.DialogResult = DialogResult.Yes;
            install.SetBounds(196, 124, 100, 28);

            Button later = new Button();
            later.Text = "Later";
            later.DialogResult = DialogResult.Cancel;
            later.SetBounds(304, 124, 100, 28);

            Button skip = new Button();
            skip.Text = "Skip This Version";
            skip.DialogResult = DialogResult.Abort;
            skip.SetBounds(16, 124, 120, 28);

            Controls.AddRange(new Control[] { title, body, _auto, install, later, skip });
            AcceptButton = install;
            CancelButton = later;
        }
    }
}
