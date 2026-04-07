param(
  [string]$EditorUrl = "https://download.unity3d.com/download_unity/8535861f39e1/Windows64EditorInstaller/UnitySetup64-6000.4.1f1.exe",

  [string]$ModuleUrl = "https://download.unity3d.com/download_unity/8535861f39e1/TargetSupportInstaller/UnitySetup-Windows-IL2CPP-Support-for-Editor-6000.4.1f1.exe",

  [long]$RangeBytes = 67108864,

  [switch]$SkipRangeTest
)

$ErrorActionPreference = "Stop"

$pipeName = "verge-mihomo"
$controllerSecret = "set-your-secret"
$clashProxyUrl = "http://127.0.0.1:7897"

function Read-AllBytes {
  param([System.IO.Stream]$Stream)

  $buffer = New-Object byte[] 8192
  $memory = New-Object System.IO.MemoryStream

  while (($count = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $memory.Write($buffer, 0, $count)
  }

  return $memory.ToArray()
}

function Decode-ChunkedBody {
  param([byte[]]$BodyBytes)

  $offset = 0
  $decoded = New-Object System.IO.MemoryStream

  while ($offset -lt $BodyBytes.Length) {
    $lineEnd = -1
    for ($i = $offset; $i -lt ($BodyBytes.Length - 1); $i++) {
      if ($BodyBytes[$i] -eq 13 -and $BodyBytes[$i + 1] -eq 10) {
        $lineEnd = $i
        break
      }
    }

    if ($lineEnd -lt 0) {
      break
    }

    $lineLength = $lineEnd - $offset
    $chunkLine = [System.Text.Encoding]::ASCII.GetString($BodyBytes, $offset, $lineLength)
    $chunkLengthText = $chunkLine.Split(";")[0]
    $chunkLength = [Convert]::ToInt32($chunkLengthText, 16)
    $offset = $lineEnd + 2

    if ($chunkLength -eq 0) {
      break
    }

    $decoded.Write($BodyBytes, $offset, $chunkLength)
    $offset += $chunkLength + 2
  }

  return $decoded.ToArray()
}

function Invoke-ClashPipeRequest {
  param(
    [string]$Method,
    [string]$Path,
    [string]$Body = ""
  )

  $client = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)

  try {
    $client.Connect(3000)

    $headers = @(
      "$Method $Path HTTP/1.1",
      "Host: localhost",
      "Authorization: Bearer $controllerSecret"
    )

    $bodyBytes = @()
    if ($Body) {
      $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
      $headers += "Content-Type: application/json"
      $headers += "Content-Length: $($bodyBytes.Length)"
    }

    $headers += "Connection: close"
    $requestBytes = [System.Text.Encoding]::ASCII.GetBytes(($headers -join "`r`n") + "`r`n`r`n")
    $client.Write($requestBytes, 0, $requestBytes.Length)

    if ($Body) {
      $client.Write($bodyBytes, 0, $bodyBytes.Length)
    }

    $client.Flush()
    $responseBytes = Read-AllBytes -Stream $client
  }
  finally {
    $client.Dispose()
  }

  $separator = [System.Text.Encoding]::ASCII.GetBytes("`r`n`r`n")
  $headerEnd = -1

  for ($i = 0; $i -le ($responseBytes.Length - $separator.Length); $i++) {
    $match = $true
    for ($j = 0; $j -lt $separator.Length; $j++) {
      if ($responseBytes[$i + $j] -ne $separator[$j]) {
        $match = $false
        break
      }
    }

    if ($match) {
      $headerEnd = $i
      break
    }
  }

  if ($headerEnd -lt 0) {
    throw "Failed to parse Clash controller response."
  }

  $headersText = [System.Text.Encoding]::UTF8.GetString($responseBytes, 0, $headerEnd)
  $bodyStart = $headerEnd + $separator.Length
  [byte[]]$rawBodyBytes = if ($bodyStart -lt $responseBytes.Length) {
    [byte[]]$responseBytes[$bodyStart..($responseBytes.Length - 1)]
  }
  else {
    [byte[]]@()
  }

  [byte[]]$bodyBytes = if ($headersText -match "(?im)^Transfer-Encoding:\s*chunked\s*$") {
    Decode-ChunkedBody -BodyBytes $rawBodyBytes
  }
  else {
    $rawBodyBytes
  }

  return [pscustomobject]@{
    StatusLine = ($headersText -split "`r?`n")[0]
    HeadersText = $headersText
    BodyBytes   = if ($null -ne $bodyBytes) { $bodyBytes } else { [byte[]]@() }
    BodyText    = if ($null -ne $bodyBytes) { [System.Text.Encoding]::UTF8.GetString($bodyBytes) } else { "" }
  }
}

function Get-ClashConfig {
  return (Invoke-ClashPipeRequest -Method "GET" -Path "/configs").BodyText | ConvertFrom-Json
}

function Get-ClashProxies {
  return ((Invoke-ClashPipeRequest -Method "GET" -Path "/proxies").BodyText | ConvertFrom-Json).proxies
}

function Set-ClashSelector {
  param(
    [string]$GroupName,
    [string]$TargetName
  )

  $payload = @{ name = $TargetName } | ConvertTo-Json -Compress
  $escapedGroupName = [System.Uri]::EscapeDataString($GroupName)
  Invoke-ClashPipeRequest -Method "PUT" -Path "/proxies/$escapedGroupName" -Body $payload | Out-Null
}

function Get-SystemProxyState {
  $internetSettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  $winHttpOutput = netsh winhttp show proxy 2>$null
  $winHttpText = ($winHttpOutput | Out-String).Trim()

  $winHttpSummary = if ($winHttpText -match "Direct access \(no proxy server\)") {
    "Direct"
  }
  elseif ($winHttpText -match "Proxy Server\(s\)\s*:\s*(.+)") {
    $Matches[1].Trim()
  }
  else {
    $winHttpText -replace "\s+", " "
  }

  return [pscustomobject]@{
    ProxyEnabled  = [bool]$internetSettings.ProxyEnable
    ProxyServer   = $internetSettings.ProxyServer
    AutoConfigUrl = $internetSettings.AutoConfigURL
    WinHttpProxy  = $winHttpSummary
  }
}

function Invoke-CurlCapture {
  param([string[]]$Arguments)

  $previousErrorActionPreference = $ErrorActionPreference

  try {
    $ErrorActionPreference = "Continue"
    $output = & curl.exe @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  $normalizedOutput = @($output | ForEach-Object { "$_" })

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output   = ($normalizedOutput -join "`n")
  }
}

function Parse-CurlHeaders {
  param([string]$Output)

  $statusLines = New-Object System.Collections.Generic.List[string]
  $locations = New-Object System.Collections.Generic.List[string]

  foreach ($line in ($Output -split "`r?`n")) {
    $trimmed = $line.Trim()
    if (-not $trimmed) {
      continue
    }

    if ($trimmed -like "HTTP/*") {
      $statusLines.Add($trimmed)
      continue
    }

    if ($trimmed -match "^(?i)Location:\s*(.+)$") {
      $locations.Add($Matches[1].Trim())
    }
  }

  $finalStatus = if ($statusLines.Count -gt 0) { $statusLines[$statusLines.Count - 1] } else { "" }
  return [pscustomobject]@{
    StatusLines        = @($statusLines)
    FinalStatus        = $finalStatus
    Locations          = @($locations)
    RedirectsToChina   = @($locations | Where-Object { $_ -match "unitychina\.cn" }).Count -gt 0
    RawOutput          = $Output
  }
}

function Parse-CurlWriteOut {
  param(
    [string]$Output,
    [int]$ExitCode
  )

  $text = $Output.Trim()
  $result = [ordered]@{
    ExitCode = $ExitCode
    HttpCode = ""
    Size     = ""
    Speed    = ""
    Time     = ""
    Raw      = $text
  }

  if ($text -match "http=(\d+)") {
    $result.HttpCode = $Matches[1]
  }
  if ($text -match "size=([0-9]+)") {
    $result.Size = $Matches[1]
  }
  if ($text -match "speed=([0-9.]+)") {
    $result.Speed = $Matches[1]
  }
  if ($text -match "time=([0-9.]+)") {
    $result.Time = $Matches[1]
  }

  return [pscustomobject]$result
}

function Format-RangeSummary {
  param($RangeResult)

  if (-not $RangeResult) {
    return "skipped"
  }

  if ($RangeResult.ExitCode -ne 0) {
    return "exit=$($RangeResult.ExitCode) raw=$($RangeResult.Raw)"
  }

  $sizeMiB = if ($RangeResult.Size) {
    [math]::Round(([double]$RangeResult.Size / 1MB), 2)
  }
  else {
    0
  }

  $speedMiB = if ($RangeResult.Speed) {
    [math]::Round(([double]$RangeResult.Speed / 1MB), 2)
  }
  else {
    0
  }

  return "http=$($RangeResult.HttpCode), size=${sizeMiB}MiB, speed=${speedMiB}MiB/s, time=$($RangeResult.Time)s"
}

function Test-UnityUrl {
  param(
    [string]$Label,
    [string]$Url
  )

  $directFollow = Invoke-CurlCapture -Arguments @(
    "-sS", "-I", "-L", "--max-time", "30", "--noproxy", "*", $Url
  )

  $proxyHead = Invoke-CurlCapture -Arguments @(
    "-sS", "-I", "--max-time", "30", "-x", $clashProxyUrl, $Url
  )

  $rangeResult = $null
  if (-not $SkipRangeTest) {
    $rangeOutput = Invoke-CurlCapture -Arguments @(
      "-sS", "-L", "--max-time", "90", "-x", $clashProxyUrl,
      "-r", "0-$($RangeBytes - 1)",
      "-o", "NUL",
      "-w", "http=%{http_code} size=%{size_download} speed=%{speed_download} time=%{time_total}",
      $Url
    )
    $rangeResult = Parse-CurlWriteOut -Output $rangeOutput.Output -ExitCode $rangeOutput.ExitCode
  }

  return [pscustomobject]@{
    Label        = $Label
    Url          = $Url
    DirectFollow = Parse-CurlHeaders -Output $directFollow.Output
    DirectExit   = $directFollow.ExitCode
    ProxyHead    = Parse-CurlHeaders -Output $proxyHead.Output
    ProxyExit    = $proxyHead.ExitCode
    RangeResult  = $rangeResult
  }
}

function Get-DiagnosisLines {
  param(
    [object[]]$UrlResults,
    $ClashConfig,
    $ProxyState
  )

  $lines = New-Object System.Collections.Generic.List[string]

  if (-not $ClashConfig.tun.enable) {
    $lines.Add("TUN is currently disabled. In plain system-proxy mode, Unity Hub validation may bypass Clash and fall back to the China mirror.")
  }

  if ($ProxyState.ProxyEnabled -and $ProxyState.WinHttpProxy -eq "Direct") {
    $lines.Add("System proxy is enabled but WinHTTP is still direct. Some Windows components may ignore the browser proxy state.")
  }

  foreach ($result in $UrlResults) {
    if ($result.DirectFollow.RedirectsToChina -and $result.DirectFollow.FinalStatus -match "404") {
      $lines.Add("$($result.Label): direct path ends at Unity China and returns 404. This is the exact failure signature behind the Unity Hub 404 case.")
    }

    if ($result.ProxyHead.FinalStatus -match "200 OK") {
      $lines.Add("$($result.Label): Clash proxy path is healthy for the current Unity node selection.")
    }
    elseif ($result.ProxyHead.RedirectsToChina -or $result.ProxyHead.FinalStatus -match "302") {
      $lines.Add("$($result.Label): even through Clash, the current node still redirects Unity to the China mirror. Switch UnityHub and UnityDownload together to another tested-good node.")
    }
    else {
      $lines.Add("$($result.Label): Clash proxy path is not healthy yet. Re-test after changing the Unity node.")
    }

    if ($result.RangeResult) {
      if ($result.RangeResult.ExitCode -eq 0 -and $result.RangeResult.HttpCode -eq "206") {
        $lines.Add("$($result.Label): range download test succeeded. The current node can at least sustain partial Unity downloads.")
      }
      elseif ($result.RangeResult.ExitCode -ne 0) {
        $lines.Add("$($result.Label): range download test failed. Prefer another node even if the HEAD check looks fine.")
      }
    }
  }

  $lines.Add("Recommended stable pattern: keep Clash in Rule mode, set UnityGlobal to a tested-good node, point UnityHub, UnityEditor, and UnityDownload to UnityGlobal unless you need an override, keep UnityChina on REJECT, and enable TUN when Unity does not reliably honor the system proxy.")
  return @($lines)
}

$clashConfig = Get-ClashConfig
$clashProxies = Get-ClashProxies
$proxyState = Get-SystemProxyState

$unityGlobalNow = if ($clashProxies.PSObject.Properties.Name -contains "UnityGlobal") { $clashProxies.UnityGlobal.now } else { $null }
$unityHubNow = $clashProxies.UnityHub.now
$unityEditorNow = if ($clashProxies.PSObject.Properties.Name -contains "UnityEditor") { $clashProxies.UnityEditor.now } else { $null }
$unityDownloadNow = $clashProxies.UnityDownload.now
$unityChinaNow = $clashProxies.UnityChina.now

$urlResults = @(
  Test-UnityUrl -Label "Editor" -Url $EditorUrl
  Test-UnityUrl -Label "IL2CPP Module" -Url $ModuleUrl
)

Write-Host "== Clash state =="
Write-Host "Mode: $($clashConfig.mode)"
Write-Host "TUN: $($clashConfig.tun.enable)"
Write-Host "Mixed Port: $($clashConfig.'mixed-port')"
Write-Host "System Proxy Enabled: $($proxyState.ProxyEnabled)"
Write-Host "System Proxy Server: $($proxyState.ProxyServer)"
Write-Host "WinHTTP Proxy: $($proxyState.WinHttpProxy)"
if ($unityGlobalNow) {
  Write-Host "UnityGlobal: $unityGlobalNow"
}
Write-Host "UnityHub: $unityHubNow"
if ($unityEditorNow) {
  Write-Host "UnityEditor: $unityEditorNow"
}
Write-Host "UnityDownload: $unityDownloadNow"
Write-Host "UnityChina: $unityChinaNow"
Write-Host ""

Write-Host "== Current route checks =="
foreach ($result in $urlResults) {
  Write-Host "[$($result.Label)]"
  Write-Host "Direct final: exit=$($result.DirectExit), status=$($result.DirectFollow.FinalStatus)"
  if ($result.DirectFollow.Locations.Count -gt 0) {
    Write-Host "Direct locations: $($result.DirectFollow.Locations -join ' -> ')"
  }
  Write-Host "Clash proxy: exit=$($result.ProxyExit), status=$($result.ProxyHead.FinalStatus)"
  if ($result.ProxyHead.Locations.Count -gt 0) {
    Write-Host "Clash locations: $($result.ProxyHead.Locations -join ' -> ')"
  }
  Write-Host "Range test: $(Format-RangeSummary -RangeResult $result.RangeResult)"
  Write-Host ""
}

Write-Host "== Diagnosis =="
foreach ($line in (Get-DiagnosisLines -UrlResults $urlResults -ClashConfig $clashConfig -ProxyState $proxyState)) {
  Write-Host "- $line"
}
