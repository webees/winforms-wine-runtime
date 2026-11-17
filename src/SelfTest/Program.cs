using System.Windows.Forms;

namespace WinFormsWineRuntime.SelfTest;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        using var form = new MainForm(args);
        Application.Run(form);
        Environment.Exit(form.ExitCode);
    }
}
