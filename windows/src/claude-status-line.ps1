$ErrorActionPreference = 'Stop'
try {
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.enabled -notcontains $profileId) { exit 0 }
    $limits = ($input | Out-String | ConvertFrom-Json).rate_limits
    $now = [DateTimeOffset]::UtcNow
    $reading = @{ observedAt = $now.ToUnixTimeMilliseconds() }
    foreach ($key in @('five_hour', 'seven_day')) {
        $window = $limits.$key
        $used = $window.used_percentage
        $reset = $window.resets_at
        if (($used -is [ValueType]) -and ($used -isnot [bool]) -and $used -ge 0 -and $used -le 100 -and
            ($reset -is [ValueType]) -and ($reset -isnot [bool]) -and $reset -gt $now.ToUnixTimeSeconds() -and $reset -le 8640000000000) {
            $reading[$key] = @{ used_percentage = $used; resets_at = $reset }
        }
    }
    if ($reading.Count -eq 1) { exit 0 }

    $temp = "$readingPath.$PID.tmp"
    try {
        [IO.File]::WriteAllText($temp, ($reading | ConvertTo-Json -Compress))
        if ([IO.File]::Exists($readingPath)) { [IO.File]::Replace($temp, $readingPath, [NullString]::Value) }
        else { [IO.File]::Move($temp, $readingPath) }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
} catch {
    [Console]::Error.WriteLine('AI Notch could not save Claude Code usage.')
}
