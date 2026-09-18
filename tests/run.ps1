<#
.SYNOPSIS
    Runs the test suites under tests/.

.DESCRIPTION
    Finds the Godot binary, makes sure the global class cache knows about the test
    framework, and hands everything else to tests/framework/test_runner.gd.

    Exits 0 when everything passed or skipped, 1 on any failure, 2 on a bad
    argument or a missing Godot.

.PARAMETER Filters
    Suites or tests to run; everything runs when none are given. A filter matches
    on substrings, and "::" splits suite from test, so "driving",
    "turnout_driving", "driving::held" and "::spanning" all work.

.PARAMETER Windowed
    Keep a window, so the tests that feed synthetic clicks run instead of skipping
    themselves. Its size is its own business: every click position is worked out
    from the window the run actually got - see tests/turnout_click_test.gd.

.PARAMETER Window
    Where that window goes. It only has to exist, not to be looked at:

      desktop    (the default) on a private Windows desktop, where nothing of it
                 reaches the screen and it cannot take the keyboard
      minimized  parked below every screen and minimized, on your own desktop
      offscreen  parked below every screen, keeping the focus it took
      visible    left where it opened, for watching a click test fail

    See tests/private_desktop.ps1 and _place_window in tests/framework/test_runner.gd.
    Naming one implies -Windowed.

.PARAMETER Color
    always, never or auto. The default colours the report when the output is a
    console and leaves it plain when it is piped or redirected, which is a
    decision the runner itself cannot make: Godot emits its escapes either way.
    NO_COLOR in the environment turns it off as well.

.PARAMETER Speed
    How many times faster than real time to run the clock (default 128). The physics
    delta stays at 1/60 s either way, so this changes how long the run takes and
    nothing about what it simulates. Diminishing returns past a few hundred, and
    values in the thousands make it slower or hang - see the gotcha in CLAUDE.md.

.EXAMPLE
    tests/run.ps1

.EXAMPLE
    tests/run.ps1 driving passage

.EXAMPLE
    tests/run.ps1 -Windowed click

.EXAMPLE
    tests/run.ps1 -Window visible click

.EXAMPLE
    tests/run.ps1 -Json results.json
#>
# Filters comes first so that bare words land there: PowerShell hands positional
# arguments to whichever parameter is declared first, and "run.ps1 driving" must not
# try to parse "driving" as -Speed.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Filters,
    [switch]$Windowed,
    [ValidateSet("", "desktop", "minimized", "offscreen", "visible")][string]$Window = "",
    [switch]$List,
    [switch]$Quiet,
    [switch]$NoColor,
    [ValidateSet("", "auto", "always", "never")][string]$Color = "",
    [int]$Speed = 0,
    [string]$Json = ""
)

$ErrorActionPreference = "Stop"

$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found at $godot - set `$env:GODOT to its path." -ForegroundColor Red
    exit 2
}

$root = Split-Path -Parent $PSScriptRoot

# The suites reach each other through class_name, which only resolves once the
# import cache has seen them. Costs a few seconds on a fresh checkout and nothing
# afterwards.
$cache = Join-Path $root ".godot\global_script_class_cache.cfg"
$known = $false
if (Test-Path $cache) {
    $known = Select-String -Path $cache -Pattern '"TestCase"' -Quiet
}
if (-not $known) {
    Write-Host "building the script class cache..."
    & $godot --headless --path $root --import | Out-Null
}

# --windowed as well as -Windowed, since the runner's own usage text spells it the
# long way and it is the wrapper that has to act on it.
if ($Filters -contains "--windowed") {
    $Windowed = $true
    $Filters = $Filters | Where-Object { $_ -ne "--windowed" }
}

# --window <where> spelled out among the filters, the way the runner's own usage
# text writes it. Lifted out rather than passed through, because where the window
# goes is decided here: on a private desktop there is a whole extra process to
# start, and nothing downstream would know to.
$spelledWindow = @($Filters | Where-Object { $_ -eq "--window" -or $_ -like "--window=*" })
if ($spelledWindow) {
    $kept = @()
    for ($i = 0; $i -lt $Filters.Count; $i++) {
        if ($Filters[$i] -like "--window=*") {
            $Window = $Filters[$i].Substring("--window=".Length)
        } elseif ($Filters[$i] -eq "--window") {
            $i++
            $Window = if ($i -lt $Filters.Count) { $Filters[$i] } else { "" }
        } else {
            $kept += $Filters[$i]
        }
    }
    $Filters = $kept
}

# Asking where the window goes only makes sense if there is one, so saying so is
# enough - nobody should have to pass both.
if ($Window) { $Windowed = $true }

# A windowed run gets a desktop of its own unless it was told otherwise: it is the
# only placement that never shows a pixel and never takes the keyboard.
$where = $Window
if ($Windowed -and -not $where) { $where = "desktop" }

$engineArgs = @()
if (-not $Windowed) { $engineArgs += "--headless" }
# A window that is going to be parked or minimized on the first frame may as well
# be born too small to see: Godot clamps --position back onto the screen, so the
# only thing left to shrink is how much of the screen it covers while it is there.
# The runner puts the size back before anything lays itself out - see _place_window.
if ($where -eq "minimized" -or $where -eq "offscreen") {
    $engineArgs += @("--resolution", "1x1", "--position", "0,99999")
}
$engineArgs += @("--path", $root, "--script", "res://tests/framework/test_runner.gd", "--")

# Godot has no idea whether its stdout is a console or a pipe and prints the
# colour escapes regardless, so the caller decides. An explicit --color / --no-color
# among the filters is left to speak for itself.
$colour = if ($NoColor) { "never" } else { $Color }
$spelledOut = $Filters | Where-Object { $_ -eq "--no-color" -or $_ -like "--color*" }
if (-not $colour -and -not $spelledOut -and [Console]::IsOutputRedirected) {
    $colour = "never"
}

$runnerArgs = @()
if ($List) { $runnerArgs += "--list" }
if ($colour) { $runnerArgs += @("--color", $colour) }
if ($Quiet) { $runnerArgs += "--quiet" }
if ($Speed -gt 0) { $runnerArgs += @("--speed", "$Speed") }
if ($where) { $runnerArgs += @("--window", $where) }
if ($Json) {
    if (-not [System.IO.Path]::IsPathRooted($Json)) {
        $Json = Join-Path (Get-Location).Path $Json
    }
    $runnerArgs += @("--json", $Json)
}
if ($Filters) { $runnerArgs += $Filters }

# CreateProcess takes one command line rather than an argument list, and it is
# Windows' own quoting rules that put it back together on the other side.
function Format-CommandLine([string[]]$parts) {
    ($parts | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join " "
}

if ($where -eq "desktop") {
    $line = Format-CommandLine (@($godot) + $engineArgs + $runnerArgs)
    & (Join-Path $PSScriptRoot "private_desktop.ps1") -CommandLine $line
    # 200 is "this machine would not give us a desktop"; anything else is the
    # runner's own verdict and we are done.
    if ($LASTEXITCODE -ne 200) { exit $LASTEXITCODE }

    # Fall back to the next best hiding place, which needs the small window the
    # desktop run had no use for.
    $engineArgs = @("--resolution", "1x1", "--position", "0,99999") + $engineArgs
    $runnerArgs = $runnerArgs | ForEach-Object { if ($_ -eq "desktop") { "minimized" } else { $_ } }
}

& $godot @engineArgs @runnerArgs
exit $LASTEXITCODE
