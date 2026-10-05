using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Windows.Forms;

internal static class AscentionNativeSetup
{
    private const string RuntimeHash = "2ECB614E68B1EA7BAA093A6D8255875430788CB5E580FAA3398268028C31765E";
    private const string PayloadName = "zhlAscention.dll";
    private const string ResourceName = "Ascention.Native";

    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        try
        {
            if (Process.GetProcessesByName("isaac-ng").Length != 0)
                throw new InvalidOperationException("Close Isaac before installing the native module.");

            string game = FindGame(AppDomain.CurrentDomain.BaseDirectory);
            if (game == null)
            {
                using (var picker = new FolderBrowserDialog())
                {
                    picker.Description = "Select The Binding of Isaac Rebirth game folder";
                    if (picker.ShowDialog() != DialogResult.OK) return;
                    game = picker.SelectedPath;
                }
            }

            string runtime = Path.Combine(game, "repentogon", "zhlREPENTOGON.dll");
            if (!File.Exists(runtime) || !Hash(runtime).Equals(RuntimeHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Unsupported REPENTOGON build. No files were changed. This installer only supports the build used for Ascention 0.5.0.");

            byte[] payload;
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
            {
                if (stream == null) throw new InvalidOperationException("Native payload is missing.");
                using (var buffer = new MemoryStream())
                {
                    stream.CopyTo(buffer);
                    payload = buffer.ToArray();
                }
            }

            string destination = Path.Combine(game, "repentogon", PayloadName);
            string marker = Path.Combine(game, "repentogon", "ascention_native.sha256");
            string payloadHash = Hash(payload);
            if (File.Exists(destination))
            {
                string installedHash = Hash(destination);
                if (installedHash.Equals(payloadHash, StringComparison.OrdinalIgnoreCase))
                {
                    MessageBox.Show("Ascention native module is already installed.", "Ascention Setup");
                    return;
                }
                if (!File.Exists(marker) || !File.ReadAllText(marker).Trim().Equals(installedHash, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("An unknown zhlAscention.dll is installed. No files were changed.");
            }

            string temporary = destination + ".new";
            try
            {
                File.WriteAllBytes(temporary, payload);
                if (!Hash(temporary).Equals(payloadHash, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("Native payload verification failed.");
                if (File.Exists(destination))
                    File.Replace(temporary, destination, null);
                else
                    File.Move(temporary, destination);
                File.WriteAllText(marker, payloadHash);
            }
            finally
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
            MessageBox.Show("Ascention native module installed. Launch Isaac through REPENTOGON.", "Ascention Setup");
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Ascention Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static string FindGame(string folder)
    {
        var current = new DirectoryInfo(folder);
        while (current != null)
        {
            if (File.Exists(Path.Combine(current.FullName, "isaac-ng.exe")) &&
                Directory.Exists(Path.Combine(current.FullName, "repentogon")))
                return current.FullName;
            if (current.Name.Equals("steamapps", StringComparison.OrdinalIgnoreCase))
            {
                string candidate = GameInLibrary(current.Parent.FullName);
                if (candidate != null) return candidate;
            }
            current = current.Parent;
        }

        string steam = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam");
        string local = GameInLibrary(steam);
        if (local != null) return local;
        string libraries = Path.Combine(steam, "steamapps", "libraryfolders.vdf");
        if (File.Exists(libraries))
        {
            foreach (Match match in Regex.Matches(File.ReadAllText(libraries),
                "\"path\"\\s+\"([^\"]+)\"", RegexOptions.IgnoreCase))
            {
                string candidate = GameInLibrary(match.Groups[1].Value.Replace("\\\\", "\\"));
                if (candidate != null) return candidate;
            }
        }
        return null;
    }

    private static string GameInLibrary(string library)
    {
        string game = Path.Combine(library, "steamapps", "common", "The Binding of Isaac Rebirth");
        return File.Exists(Path.Combine(game, "isaac-ng.exe")) ? game : null;
    }

    private static string Hash(string path)
    {
        using (var stream = File.OpenRead(path)) return Hash(stream);
    }

    private static string Hash(byte[] bytes)
    {
        using (var stream = new MemoryStream(bytes)) return Hash(stream);
    }

    private static string Hash(Stream stream)
    {
        using (var sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
    }
}
