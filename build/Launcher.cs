// WinTurbo.exe: lanzador de un solo archivo.
// Lleva WinTurbo.ps1 como recurso embebido, lo extrae a una carpeta que solo pueden modificar
// SYSTEM y Administradores, comprueba su SHA-256 y lo ejecuta con Windows PowerShell 5.1 de 64 bits.
// Se ejecuta el .ps1 real (y no una conversión) porque la interfaz lanza sus tareas en segundo plano
// cargando el propio archivo del script.
// Compatible con el compilador csc.exe de .NET Framework 4 (C# 5): sin interpolación de cadenas.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("WinTurbo")]
[assembly: AssemblyDescription("Optimizador de Windows 10/11")]
[assembly: AssemblyProduct("WinTurbo")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Launcher
{
    private const string ResourceName = "WinTurbo.ps1";

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            byte[] script = ReadEmbeddedScript();
            string dir = PrepareSecureFolder();
            string path = Path.Combine(dir, "WinTurbo.ps1");
            string expected = Sha256(script);

            if (!File.Exists(path) || Sha256(File.ReadAllBytes(path)) != expected)
            {
                File.WriteAllBytes(path, script);
            }
            // Comprobación justo antes de ejecutar: el archivo debe ser exactamente el embebido.
            if (Sha256(File.ReadAllBytes(path)) != expected)
            {
                throw new InvalidOperationException("El script extraído no coincide con el embebido (hash SHA-256 distinto).");
            }

            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            // Desde un proceso de 32 bits en Windows de 64 bits, solo Sysnative llega al PowerShell de 64 bits.
            string sysDir = (Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess) ? "Sysnative" : "System32";
            string powershell = Path.Combine(windows, sysDir, "WindowsPowerShell", "v1.0", "powershell.exe");

            StringBuilder arguments = new StringBuilder("-NoProfile -STA -ExecutionPolicy Bypass");
            // Sin parámetros se abre la interfaz gráfica: la consola de PowerShell arranca minimizada.
            if (args.Length == 0) { arguments.Append(" -WindowStyle Minimized"); }
            arguments.Append(" -File ").Append(Quote(path));
            foreach (string a in args) { arguments.Append(' ').Append(Quote(a)); }

            ProcessStartInfo psi = new ProcessStartInfo(powershell, arguments.ToString());
            psi.UseShellExecute = false;
            psi.WorkingDirectory = dir;
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("No se pudo iniciar WinTurbo:\n\n" + ex.Message, "WinTurbo", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static byte[] ReadEmbeddedScript()
    {
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
        {
            if (s == null) { throw new InvalidOperationException("El ejecutable no contiene WinTurbo.ps1."); }
            using (MemoryStream ms = new MemoryStream())
            {
                s.CopyTo(ms);
                return ms.ToArray();
            }
        }
    }

    private static string PrepareSecureFolder()
    {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "WinTurbo");
        string dir = Path.Combine(root, "App");

        // Un enlace o unión plantado por otro usuario podría redirigir la extracción: se elimina y se recrea.
        if (Directory.Exists(dir) && (File.GetAttributes(dir) & FileAttributes.ReparsePoint) == FileAttributes.ReparsePoint)
        {
            Directory.Delete(dir);
        }
        Directory.CreateDirectory(dir);

        // Dueño: Administradores (si un usuario creó la carpeta antes, pierde el control).
        // Permisos: SYSTEM y Administradores control total; Usuarios solo lectura y ejecución.
        SecurityIdentifier admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        SecurityIdentifier system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        SecurityIdentifier users = new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null);
        InheritanceFlags inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;

        DirectorySecurity security = new DirectorySecurity();
        security.SetOwner(admins);
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new FileSystemAccessRule(system, FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule(admins, FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
        security.AddAccessRule(new FileSystemAccessRule(users, FileSystemRights.ReadAndExecute, inherit, PropagationFlags.None, AccessControlType.Allow));
        Directory.SetAccessControl(dir, security);

        // El archivo hereda los permisos protegidos: se reaplican por si existía de antes con otros.
        string file = Path.Combine(dir, "WinTurbo.ps1");
        if (File.Exists(file))
        {
            FileSecurity fs = new FileSecurity();
            fs.SetOwner(admins);
            fs.SetAccessRuleProtection(false, false);
            File.SetAccessControl(file, fs);
        }
        return dir;
    }

    private static string Sha256(byte[] data)
    {
        using (SHA256 sha = SHA256.Create())
        {
            return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "");
        }
    }

    private static string Quote(string arg)
    {
        // Comillas según las reglas de CommandLineToArgvW: barras antes de comillas se duplican.
        if (arg.Length > 0 && arg.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) { return arg; }
        StringBuilder sb = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char c in arg)
        {
            if (c == '\\') { backslashes++; continue; }
            if (c == '"') { sb.Append('\\', backslashes * 2 + 1); }
            else { sb.Append('\\', backslashes); }
            backslashes = 0;
            sb.Append(c);
        }
        sb.Append('\\', backslashes * 2);
        sb.Append('"');
        return sb.ToString();
    }
}
