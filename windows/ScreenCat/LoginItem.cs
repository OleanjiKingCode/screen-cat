using System;
using Microsoft.Win32;

namespace ScreenCat;

/// Start at login, from the menu. A value under the current user's Run key,
/// so no admin rights are needed and nothing else on the PC changes.
public static class LoginItem
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "ScreenCat";

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey);
                return key?.GetValue(ValueName) is string;
            }
            catch
            {
                return false;
            }
        }
    }

    public static void SetEnabled(bool on)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (key == null) return;
            if (!on)
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
                return;
            }
            var exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe)) return;
            key.SetValue(ValueName, $"\"{exe}\"");
        }
        catch
        {
            // Policy can lock the Run key; the menu tick then just stays as it was.
        }
    }
}
