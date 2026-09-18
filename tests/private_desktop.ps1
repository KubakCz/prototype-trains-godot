<#
.SYNOPSIS
    Runs a command on a private Windows desktop, where its windows cannot be seen.

.DESCRIPTION
    A Windows session can hold more than one desktop, and a window only ever exists
    on the desktop its process was started on. Only one desktop is composited at a
    time, so a process started on a desktop of our own can open, move and focus as
    many windows as it likes without a pixel of it reaching the screen and without
    taking the keyboard away from whatever the user is doing.

    That is what tests/run.ps1 -Windowed uses: the click tests need a real display
    server, not a window anybody looks at, and every other way of hiding one still
    flashes it up for a few milliseconds while the engine starts.

    The child inherits nothing visible and writes to a pipe this script relays a
    line at a time, so a caller can still pipe or capture the output. stderr is
    merged into stdout on the way through.

    Exits with the child's exit code, or 200 if the desktop could not be created -
    which is the caller's cue to fall back to running on the ordinary desktop.

.PARAMETER CommandLine
    The command to run, quoted as Windows expects it: the executable first, quoted
    if its path has spaces, then its arguments.

.EXAMPLE
    tests/private_desktop.ps1 -CommandLine '"C:\Godot\Godot.exe" --path . --script res://tests/framework/test_runner.gd'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CommandLine
)

$ErrorActionPreference = "Stop"

# Exit code for "no private desktop", distinct from the runner's own 0 / 1 / 2.
$DESKTOP_UNAVAILABLE = 200

if (-not ("PrivateDesktop" -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;

public static class PrivateDesktop {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb;
        public string lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars;
        public int dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    const int STARTF_USESTDHANDLES = 0x00000100;
    const uint DESKTOP_ALL = 0x10000000;            // GENERIC_ALL
    const int STD_INPUT_HANDLE = -10, STD_OUTPUT_HANDLE = -11;
    const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
    const uint INFINITE = 0xFFFFFFFF;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr mode, int flags, uint access, IntPtr sa);
    [DllImport("user32.dll", SetLastError = true)] static extern bool CloseDesktop(IntPtr handle);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcess(string application, string commandLine, IntPtr processAttributes,
            IntPtr threadAttributes, bool inheritHandles, uint flags, IntPtr environment,
            string currentDirectory, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr handle, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr GetStdHandle(int which);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetConsoleMode(IntPtr handle, out uint mode);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetConsoleMode(IntPtr handle, uint mode);

    static IntPtr _desktop = IntPtr.Zero;
    static PROCESS_INFORMATION _process;

    /// The child's merged stdout and stderr, for the caller to relay.
    public static StreamReader Output;

    /// Godot writes its colour escapes into a pipe as happily as into a console,
    /// and here they arrive as text this script prints - which a console renders
    /// as escapes only if somebody has asked it to. Godot asks for itself when it
    /// owns the handle; on this path it never touches it, so we ask instead.
    public static void EnableAnsi() {
        IntPtr handle = GetStdHandle(STD_OUTPUT_HANDLE);
        uint mode;
        if (GetConsoleMode(handle, out mode)) {
            SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
    }

    /// Starts [commandLine] on a desktop of its own. Returns false if the desktop
    /// could not be created, in which case nothing has been started.
    public static bool Start(string desktopName, string commandLine) {
        _desktop = CreateDesktop(desktopName, IntPtr.Zero, IntPtr.Zero, 0, DESKTOP_ALL, IntPtr.Zero);
        if (_desktop == IntPtr.Zero) {
            return false;
        }

        // One pipe for both streams: the runner's report is one stream of lines to
        // read in order, and interleaving it with itself would only scramble it.
        var pipe = new AnonymousPipeServerStream(PipeDirection.In, HandleInheritability.Inheritable);
        IntPtr childEnd = pipe.ClientSafePipeHandle.DangerousGetHandle();

        var si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.lpDesktop = desktopName;
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
        si.hStdOutput = childEnd;
        si.hStdError = childEnd;

        bool started = CreateProcess(null, commandLine, IntPtr.Zero, IntPtr.Zero, true, 0,
                IntPtr.Zero, null, ref si, out _process);
        if (!started) {
            int error = Marshal.GetLastWin32Error();
            CloseDesktop(_desktop);
            _desktop = IntPtr.Zero;
            throw new Exception("could not start the child process: Windows error " + error);
        }

        // Until our copy of the child's end is closed, the read end never reaches
        // the end of the stream and the relay below would hang after the child is
        // long gone.
        pipe.DisposeLocalCopyOfClientHandle();
        Output = new StreamReader(pipe, new System.Text.UTF8Encoding(false));
        return true;
    }

    /// Waits for the child and hands back its exit code. Call it once the output
    /// has been read to the end.
    public static int Wait() {
        WaitForSingleObject(_process.hProcess, INFINITE);
        uint code;
        GetExitCodeProcess(_process.hProcess, out code);
        CloseHandle(_process.hThread);
        CloseHandle(_process.hProcess);
        CloseDesktop(_desktop);
        _desktop = IntPtr.Zero;
        return (int)code;
    }
}
'@
}

# A name of its own per run, so a desktop left behind by a crashed run is never
# joined by accident.
$name = "godot-tests-{0}-{1}" -f $PID, (Get-Random -Maximum 100000)

[PrivateDesktop]::EnableAnsi()
if (-not [PrivateDesktop]::Start($name, $CommandLine)) {
    Write-Host "could not create a private desktop - running where you can see it." -ForegroundColor Yellow
    exit $DESKTOP_UNAVAILABLE
}

# Write-Output rather than Write-Host, so that piping or capturing run.ps1 still
# collects everything the runner printed.
$reader = [PrivateDesktop]::Output
while ($null -ne ($line = $reader.ReadLine())) {
    Write-Output $line
}
exit ([PrivateDesktop]::Wait())
