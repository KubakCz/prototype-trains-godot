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
    themselves. Do not resize that window - see tests/turnout_click_test.gd.

.PARAMETER Color
    always, never or auto. The default colours the report when the output is a
    console and leaves it plain when it is piped or redirected, which is a
    decision the runner itself cannot make: Godot emits its escapes either way.
    NO_COLOR in the environment turns it off as well.

.PARAMETER Speed
    How many times faster than real time to run the clock (default 16). The physics
    delta stays at 1/60 s either way, so this changes how long the run takes and
    nothing about what it simulates.

.EXAMPLE
    tests/run.ps1

.EXAMPLE
    tests/run.ps1 driving passage

.EXAMPLE
    tests/run.ps1 -Windowed click

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

$engineArgs = @()
if (-not $Windowed) { $engineArgs += "--headless" }
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
if ($Json) {
    if (-not [System.IO.Path]::IsPathRooted($Json)) {
        $Json = Join-Path (Get-Location).Path $Json
    }
    $runnerArgs += @("--json", $Json)
}
if ($Filters) { $runnerArgs += $Filters }

& $godot @engineArgs @runnerArgs
exit $LASTEXITCODE
