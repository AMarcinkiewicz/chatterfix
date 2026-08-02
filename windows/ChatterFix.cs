// ChatterFix — keyboard chatter (double-press) filter, tray-only.
// Build: build.cmd (csc.exe, .NET Framework 4.8, no external dependencies).

using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ChatterFix
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            bool createdNew;
            using (Mutex mutex = new Mutex(true, "ChatterFix_SingleInstance_Mutex", out createdNew))
            {
                if (!createdNew) return; // already running
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayApp());
            }
        }
    }

    sealed class TrayApp : ApplicationContext
    {
        // ---- Win32 ----
        const int WH_KEYBOARD_LL = 13;
        const int WM_KEYDOWN = 0x0100;
        const int WM_KEYUP = 0x0101;
        const int WM_SYSKEYDOWN = 0x0104;
        const int WM_SYSKEYUP = 0x0105;
        const uint LLKHF_INJECTED = 0x10;

        delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
        [DllImport("user32.dll", SetLastError = true)]
        static extern bool UnhookWindowsHookEx(IntPtr hhk);
        [DllImport("user32.dll")]
        static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
        [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
        static extern IntPtr GetModuleHandle(string lpModuleName);

        // KBDLLHOOKSTRUCT field offsets (vkCode=0, scanCode=4, flags=8, time=12).
        // Fields are read directly instead of marshaling the struct so the hook
        // callback performs no allocation.
        const int OFF_VKCODE = 0;
        const int OFF_FLAGS = 8;
        const int OFF_TIME = 12;

        static readonly IntPtr EAT = (IntPtr)1;

        // ---- settings/registry ----
        const string SettingsKeyPath = @"Software\ChatterFix";
        const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string RunValueName = "ChatterFix";
        const int DefaultThresholdMs = 50;
        static readonly int[] PresetMs = { 30, 40, 50, 65, 80 };
        static readonly string[] PresetNames = { "Gentle", "Moderate", "Standard", "Strong", "Maximum" };

        // ---- per-key state: fixed arrays indexed by virtual-key code ----
        readonly uint[] _lastReleaseTime = new uint[256];
        readonly bool[] _hasRelease = new bool[256];
        readonly bool[] _swallowNextUp = new bool[256];
        readonly long[] _blockedPerKey = new long[256];
        long _blockedTotal;

        volatile int _thresholdMs = DefaultThresholdMs;
        bool _paused;

        LowLevelKeyboardProc _hookProc; // kept referenced so the delegate is never GC'd
        IntPtr _hook = IntPtr.Zero;

        readonly NotifyIcon _trayIcon;
        readonly ContextMenuStrip _menu;
        readonly ToolStripMenuItem _statusItem;
        readonly ToolStripMenuItem _pauseItem;
        readonly ToolStripMenuItem _sensitivityItem;
        readonly ToolStripMenuItem _blockedKeysItem;
        readonly ToolStripMenuItem _startAtLoginItem;
        readonly ToolStripMenuItem _autoUpdateItem;
        Timer _startupUpdateTimer;

        public TrayApp()
        {
            LoadSettings();

            _statusItem = new ToolStripMenuItem("ChatterFix: On — no chatter yet");
            _statusItem.Enabled = false;

            _pauseItem = new ToolStripMenuItem("Pause Filtering", null, OnPauseResume);

            _sensitivityItem = new ToolStripMenuItem("Sensitivity");
            for (int i = 0; i < PresetMs.Length; i++)
            {
                ToolStripMenuItem item = new ToolStripMenuItem(
                    PresetNames[i] + " (" + PresetMs[i] + " ms)", null, OnPickSensitivity);
                item.Tag = PresetMs[i];
                _sensitivityItem.DropDownItems.Add(item);
            }

            _blockedKeysItem = new ToolStripMenuItem("Blocked Keys");

            _startAtLoginItem = new ToolStripMenuItem("Start at Login", null, OnToggleStartAtLogin);
            _autoUpdateItem = new ToolStripMenuItem("Install Updates Automatically",
                null, OnToggleAutoUpdate);

            _menu = new ContextMenuStrip();
            _menu.Items.Add(_statusItem);
            _menu.Items.Add(_pauseItem);
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(_sensitivityItem);
            _menu.Items.Add(_blockedKeysItem);
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(_startAtLoginItem);
            _menu.Items.Add(_autoUpdateItem);
            _menu.Items.Add(new ToolStripMenuItem("Check for Updates...", null, OnCheckUpdates));
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(new ToolStripMenuItem("Quit ChatterFix", null, OnQuit));
            _menu.Opening += OnMenuOpening;

            _trayIcon = new NotifyIcon();
            _trayIcon.Icon = LoadTrayIcon();
            _trayIcon.Text = "ChatterFix";
            _trayIcon.ContextMenuStrip = _menu;
            _trayIcon.MouseUp += OnTrayMouseUp;
            _trayIcon.Visible = true;

            InstallHook();

            // Deferred: SynchronizationContext.Current is not established until the
            // message loop is running, and this constructor runs before it.
            _startupUpdateTimer = new Timer();
            _startupUpdateTimer.Interval = 5000;
            _startupUpdateTimer.Tick += OnStartupUpdateCheck;
            _startupUpdateTimer.Start();
        }

        void OnStartupUpdateCheck(object sender, EventArgs e)
        {
            _startupUpdateTimer.Stop();
            _startupUpdateTimer.Dispose();
            _startupUpdateTimer = null;
            StartUpdateCheck(false);
        }

        // ---- the filter ----
        IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                int msg = (int)wParam;
                uint flags = (uint)Marshal.ReadInt32(lParam, OFF_FLAGS);
                if ((flags & LLKHF_INJECTED) == 0) // injected input passes untouched, updates nothing
                {
                    int vk = Marshal.ReadInt32(lParam, OFF_VKCODE) & 0xFF;
                    uint time = (uint)Marshal.ReadInt32(lParam, OFF_TIME);

                    if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                    {
                        // unchecked uint subtraction is rollover-safe
                        if (_hasRelease[vk] && (time - _lastReleaseTime[vk]) < (uint)_thresholdMs)
                        {
                            _swallowNextUp[vk] = true;
                            _blockedPerKey[vk]++;
                            _blockedTotal++;
                            return EAT;
                        }
                    }
                    else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
                    {
                        if (_swallowNextUp[vk])
                        {
                            // swallow the bounce's release; keep the original release
                            // timestamp as the reference so a burst of bounces is all
                            // measured against the real release
                            _swallowNextUp[vk] = false;
                            return EAT;
                        }
                        _lastReleaseTime[vk] = time;
                        _hasRelease[vk] = true;
                    }
                }
            }
            return CallNextHookEx(_hook, nCode, wParam, lParam);
        }

        void InstallHook()
        {
            if (_hook != IntPtr.Zero) return;
            if (_hookProc == null) _hookProc = HookCallback;
            _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _hookProc,
                GetModuleHandle(null), 0);
            if (_hook == IntPtr.Zero)
                MessageBox.Show("ChatterFix could not install the keyboard hook (error " +
                    Marshal.GetLastWin32Error() + ").", "ChatterFix",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        void RemoveHook()
        {
            if (_hook == IntPtr.Zero) return;
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
            // drop transient state so nothing stale carries across a pause
            Array.Clear(_swallowNextUp, 0, _swallowNextUp.Length);
            Array.Clear(_hasRelease, 0, _hasRelease.Length);
        }

        // ---- menu ----
        void OnMenuOpening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (_paused)
                _statusItem.Text = "ChatterFix: Paused";
            else if (_blockedTotal == 0)
                _statusItem.Text = "ChatterFix: On — no chatter yet";
            else
                _statusItem.Text = "ChatterFix: On — " + _blockedTotal +
                    (_blockedTotal == 1 ? " double-press blocked" : " double-presses blocked");

            _pauseItem.Text = _paused ? "Resume Filtering" : "Pause Filtering";

            foreach (ToolStripMenuItem item in _sensitivityItem.DropDownItems)
                item.Checked = ((int)item.Tag == _thresholdMs);

            RebuildBlockedKeysMenu();

            _startAtLoginItem.Checked = IsStartAtLoginEnabled();
            _autoUpdateItem.Checked = Updater.AutoInstall;
        }

        void RebuildBlockedKeysMenu()
        {
            _blockedKeysItem.DropDownItems.Clear();
            List<KeyValuePair<int, long>> hits = new List<KeyValuePair<int, long>>();
            for (int vk = 0; vk < 256; vk++)
                if (_blockedPerKey[vk] > 0)
                    hits.Add(new KeyValuePair<int, long>(vk, _blockedPerKey[vk]));

            if (hits.Count == 0)
            {
                ToolStripMenuItem none = new ToolStripMenuItem("No chatter detected yet");
                none.Enabled = false;
                _blockedKeysItem.DropDownItems.Add(none);
                return;
            }

            hits.Sort(delegate(KeyValuePair<int, long> a, KeyValuePair<int, long> b)
            {
                return b.Value.CompareTo(a.Value);
            });
            foreach (KeyValuePair<int, long> hit in hits)
            {
                ToolStripMenuItem item = new ToolStripMenuItem(
                    KeyName(hit.Key) + " — " + hit.Value + "×");
                item.Enabled = false;
                _blockedKeysItem.DropDownItems.Add(item);
            }
        }

        void OnTrayMouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            // NotifyIcon shows its menu only on right-click; invoke the same private
            // path for left-click so both buttons open it
            MethodInfo mi = typeof(NotifyIcon).GetMethod("ShowContextMenu",
                BindingFlags.Instance | BindingFlags.NonPublic);
            if (mi != null) mi.Invoke(_trayIcon, null);
        }

        void OnPauseResume(object sender, EventArgs e)
        {
            _paused = !_paused;
            if (_paused) RemoveHook(); else InstallHook();
        }

        void OnPickSensitivity(object sender, EventArgs e)
        {
            _thresholdMs = (int)((ToolStripMenuItem)sender).Tag;
            SaveThreshold();
        }

        void OnToggleStartAtLogin(object sender, EventArgs e)
        {
            SetStartAtLogin(!IsStartAtLoginEnabled());
        }

        void OnToggleAutoUpdate(object sender, EventArgs e)
        {
            Updater.AutoInstall = !Updater.AutoInstall;
        }

        void OnCheckUpdates(object sender, EventArgs e)
        {
            StartUpdateCheck(true);
        }

        // The check runs off the UI thread so a slow or unreachable server never
        // freezes the tray menu; results are posted back through the UI thread's
        // synchronization context so dialogs are always shown on it.
        void StartUpdateCheck(bool userInitiated)
        {
            SynchronizationContext ui = SynchronizationContext.Current;
            Thread t = new Thread(delegate()
            {
                Updater.Check(userInitiated, delegate(Action action)
                {
                    if (ui != null) ui.Post(delegate(object _) { action(); }, null);
                    else action();
                });
            });
            t.IsBackground = true;
            t.Start();
        }

        void OnQuit(object sender, EventArgs e)
        {
            RemoveHook();
            _trayIcon.Visible = false;
            _trayIcon.Dispose();
            ExitThread();
        }

        // ---- persistence ----
        void LoadSettings()
        {
            bool firstRun = true;
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(SettingsKeyPath))
            {
                if (key != null)
                {
                    firstRun = false;
                    object v = key.GetValue("ThresholdMs");
                    if (v is int && Array.IndexOf(PresetMs, (int)v) >= 0)
                        _thresholdMs = (int)v;
                }
            }
            if (firstRun)
            {
                SaveThreshold();        // creates Software\ChatterFix with the default
                SetStartAtLogin(true);  // Start at Login is on by default
            }
        }

        void SaveThreshold()
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(SettingsKeyPath))
                key.SetValue("ThresholdMs", _thresholdMs, RegistryValueKind.DWord);
        }

        static bool IsStartAtLoginEnabled()
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKeyPath))
                return key != null && key.GetValue(RunValueName) != null;
        }

        static void SetStartAtLogin(bool enable)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(RunKeyPath))
            {
                if (enable)
                    key.SetValue(RunValueName, "\"" + Application.ExecutablePath + "\"");
                else
                    key.DeleteValue(RunValueName, false);
            }
        }

        // ---- helpers ----
        static System.Drawing.Icon LoadTrayIcon()
        {
            try
            {
                Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("ChatterFix.ico");
                if (s != null)
                    return new System.Drawing.Icon(s, SystemInformation.SmallIconSize);
            }
            catch { }
            return System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        }

        static string KeyName(int vk)
        {
            if (vk >= 'A' && vk <= 'Z') return ((char)vk).ToString();
            if (vk >= '0' && vk <= '9') return ((char)vk).ToString();
            if (vk >= 0x70 && vk <= 0x87) return "F" + (vk - 0x6F);          // F1..F24
            if (vk >= 0x60 && vk <= 0x69) return "Num " + (vk - 0x60);       // numpad digits
            switch (vk)
            {
                case 0x08: return "Backspace";
                case 0x09: return "Tab";
                case 0x0D: return "Enter";
                case 0x13: return "Pause";
                case 0x14: return "Caps Lock";
                case 0x1B: return "Esc";
                case 0x20: return "Space";
                case 0x21: return "Page Up";
                case 0x22: return "Page Down";
                case 0x23: return "End";
                case 0x24: return "Home";
                case 0x25: return "Left Arrow";
                case 0x26: return "Up Arrow";
                case 0x27: return "Right Arrow";
                case 0x28: return "Down Arrow";
                case 0x2C: return "Print Screen";
                case 0x2D: return "Insert";
                case 0x2E: return "Delete";
                case 0x5B: return "Left Win";
                case 0x5C: return "Right Win";
                case 0x5D: return "Menu";
                case 0x6A: return "Num *";
                case 0x6B: return "Num +";
                case 0x6D: return "Num -";
                case 0x6E: return "Num .";
                case 0x6F: return "Num /";
                case 0x90: return "Num Lock";
                case 0x91: return "Scroll Lock";
                case 0xA0: return "Left Shift";
                case 0xA1: return "Right Shift";
                case 0xA2: return "Left Ctrl";
                case 0xA3: return "Right Ctrl";
                case 0xA4: return "Left Alt";
                case 0xA5: return "Right Alt";
                case 0xBA: return ";";
                case 0xBB: return "=";
                case 0xBC: return ",";
                case 0xBD: return "-";
                case 0xBE: return ".";
                case 0xBF: return "/";
                case 0xC0: return "`";
                case 0xDB: return "[";
                case 0xDC: return "\\";
                case 0xDD: return "]";
                case 0xDE: return "'";
                default: return ((Keys)vk).ToString();
            }
        }
    }
}
