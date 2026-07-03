param(
    [string] $BrowserPath = "C:\Program Files\Google\Chrome\Application\chrome.exe",
    [string] $Url = "http://127.0.0.1:5185/",
    [int] $DebugPort = 9223,
    [int] $ServerPort = 5185,
    [string] $StaticRoot = "dist-dnd-harness"
)

$ErrorActionPreference = "Stop"

$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$profilePath = Join-Path $workspaceRoot (".tmp-dnd-cdp-" + [guid]::NewGuid().ToString("N"))
$browser = $null
$staticServer = $null
$socket = $null

function ConvertTo-Bytes([string] $Text) {
    return [System.Text.Encoding]::UTF8.GetBytes($Text)
}

function Receive-CdpMessage([System.Net.WebSockets.ClientWebSocket] $Socket) {
    $buffer = New-Object byte[] 65536
    $segments = New-Object System.Collections.Generic.List[byte]

    do {
        $segment = [System.ArraySegment[byte]]::new($buffer)
        $result = $Socket.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        if ($result.Count -gt 0) {
            for ($i = 0; $i -lt $result.Count; $i++) {
                $segments.Add($buffer[$i])
            }
        }
    } while (-not $result.EndOfMessage)

    $json = [System.Text.Encoding]::UTF8.GetString($segments.ToArray())
    return $json | ConvertFrom-Json
}

function Send-CdpCommand(
    [System.Net.WebSockets.ClientWebSocket] $Socket,
    [int] $Id,
    [string] $Method,
    [object] $Params = @{}
) {
    $payload = @{
        id = $Id
        method = $Method
        params = $Params
    } | ConvertTo-Json -Depth 20 -Compress

    $bytes = ConvertTo-Bytes $payload
    $Socket.SendAsync(
        [System.ArraySegment[byte]]::new($bytes),
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None
    ).GetAwaiter().GetResult() | Out-Null

    while ($true) {
        $message = Receive-CdpMessage $Socket
        if ($message.id -eq $Id) {
            if ($message.error) {
                throw ($message.error | ConvertTo-Json -Depth 10)
            }
            return $message
        }
    }
}

try {
    $build = Start-Process -FilePath "pnpm.cmd" -ArgumentList @(
        "exec",
        "vite",
        "build",
        "--config",
        "tests/dnd-harness/vite.config.ts",
        "--outDir",
        "../../dist-dnd-harness",
        "tests/dnd-harness",
        "--emptyOutDir"
    ) -WorkingDirectory $workspaceRoot -WindowStyle Hidden -Wait -PassThru
    if ($build.ExitCode -ne 0) {
        throw "Harness build failed with exit code $($build.ExitCode)."
    }

    $staticRootPath = Join-Path $workspaceRoot $StaticRoot
    if (-not (Test-Path (Join-Path $staticRootPath "index.html"))) {
        throw "Missing harness build at $staticRootPath."
    }

    $staticServer = Start-Process -FilePath "node" -ArgumentList @(
        "tests/dnd-harness/serve-static.mjs",
        $staticRootPath,
        "$ServerPort"
    ) -WorkingDirectory $workspaceRoot -WindowStyle Hidden -PassThru

    $serverReady = $false
    for ($i = 0; $i -lt 50; $i++) {
        try {
            Invoke-RestMethod -Uri $Url | Out-Null
            $serverReady = $true
            break
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    if (-not $serverReady) {
        throw "Static harness server did not start on $Url."
    }

    $browserArgs = @(
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--remote-debugging-port=$DebugPort",
        "--user-data-dir=$profilePath",
        "about:blank"
    )

    $browser = Start-Process -FilePath $BrowserPath -ArgumentList $browserArgs -WindowStyle Hidden -PassThru

    $version = $null
    for ($i = 0; $i -lt 50; $i++) {
        try {
            $version = Invoke-RestMethod -Uri "http://127.0.0.1:$DebugPort/json/version"
            break
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    if (-not $version) {
        throw "Chrome did not expose a CDP endpoint on port $DebugPort."
    }

    $page = $null
    try {
        $page = Invoke-RestMethod -Method Put -Uri "http://127.0.0.1:$DebugPort/json/new?about:blank"
    } catch {
        $pages = Invoke-RestMethod -Uri "http://127.0.0.1:$DebugPort/json/list"
        $page = @($pages | Where-Object { $_.type -eq "page" })[0]
    }
    if (-not $page -or -not $page.webSocketDebuggerUrl) {
        throw "Chrome did not expose a page CDP endpoint."
    }

    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    $socket.ConnectAsync([Uri] $page.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null

    $id = 1
    Send-CdpCommand $socket $id "Page.enable" | Out-Null; $id++
    Send-CdpCommand $socket $id "Runtime.enable" | Out-Null; $id++
    Send-CdpCommand $socket $id "Page.navigate" @{ url = $Url } | Out-Null; $id++

    $readyExpression = @"
new Promise((resolve) => {
    const started = Date.now();
    const tick = () => {
        if (window.dndHarness && document.querySelector('[data-dnd-draggable-id="a"]')) {
            resolve('ready');
            return;
        }
        if (Date.now() - started > 5000) {
            resolve('timeout');
            return;
        }
        setTimeout(tick, 50);
    };
    tick();
})
"@
    $ready = Send-CdpCommand $socket $id "Runtime.evaluate" @{
        awaitPromise = $true
        expression = $readyExpression
        returnByValue = $true
    }; $id++
    if ($ready.result.result.value -ne "ready") {
        $debug = Send-CdpCommand $socket $id "Runtime.evaluate" @{
            expression = "JSON.stringify({ href: location.href, hasHarness: !!window.dndHarness, body: document.body.innerText, html: document.documentElement.outerHTML.slice(0, 1200) })"
            returnByValue = $true
        }; $id++
        throw "Harness did not become ready. Page debug: $($debug.result.result.value)"
    }

    $testExpression = @"
(() => {
    function event(type, target, dataTransfer) {
        const event = new DragEvent(type, {
            bubbles: true,
            cancelable: true,
            clientX: target.getBoundingClientRect().left + 12,
            clientY: target.getBoundingClientRect().top + 12,
            dataTransfer
        });
        target.dispatchEvent(event);
        return event.defaultPrevented;
    }

    const source = document.querySelector('[data-dnd-draggable-id="a"]');
    const targetZone = document.querySelector('[data-dnd-dropzone-id="target"]');
    const targetChild = document.querySelector('[data-dnd-draggable-id="c"]');
    const controlledZone = document.querySelector('[data-dnd-dropzone-id="controlled"]');
    const dataTransfer = new DataTransfer();

    event('dragstart', source, dataTransfer);
    event('dragenter', targetZone, dataTransfer);
    event('dragover', targetChild, dataTransfer);
    event('drop', targetZone, dataTransfer);
    event('dragend', source, dataTransfer);

    const afterMove = {
        source: window.dndHarness.order('source'),
        target: window.dndHarness.order('target'),
        events: window.dndHarness.events.value
    };

    const beta = document.querySelector('[data-dnd-draggable-id="b"]');
    const dataTransfer2 = new DataTransfer();

    event('dragstart', beta, dataTransfer2);
    event('dragenter', controlledZone, dataTransfer2);
    event('dragover', controlledZone, dataTransfer2);
    event('drop', controlledZone, dataTransfer2);
    event('dragend', beta, dataTransfer2);

    return JSON.stringify({
        moveOnDrop: afterMove,
        controlled: {
            source: window.dndHarness.order('source'),
            controlled: window.dndHarness.order('controlled'),
            events: window.dndHarness.events.value
        }
    });
})()
"@

    $result = Send-CdpCommand $socket $id "Runtime.evaluate" @{
        expression = $testExpression
        returnByValue = $true
    }; $id++

    $value = $result.result.result.value | ConvertFrom-Json
    $targetOrder = @($value.moveOnDrop.target)
    $sourceOrder = @($value.moveOnDrop.source)
    $firstDrop = $value.moveOnDrop.events[0]
    $controlledOrder = @($value.controlled.controlled)
    $controlledSource = @($value.controlled.source)
    $secondDrop = $value.controlled.events[1]

    if (($targetOrder -join ",") -ne "a,c") {
        throw "Expected target order a,c after moveOnDrop; got $($targetOrder -join ',')."
    }
    if (($sourceOrder -join ",") -ne "b") {
        throw "Expected source order b after moveOnDrop; got $($sourceOrder -join ',')."
    }
    if ($firstDrop.id -ne "a" -or $firstDrop.zoneId -ne "target" -or $firstDrop.index -ne 0 -or $firstDrop.beforeId -ne "c") {
        throw "Unexpected first drop payload: $($firstDrop | ConvertTo-Json -Compress -Depth 10)"
    }
    if (($controlledOrder -join ",") -ne "") {
        throw "Expected controlled zone to remain empty when moveOnDrop=false; got $($controlledOrder -join ',')."
    }
    if (($controlledSource -join ",") -ne "b") {
        throw "Expected beta to remain in source in controlled mode; got $($controlledSource -join ',')."
    }
    if ($secondDrop.id -ne "b" -or $secondDrop.zoneId -ne "controlled" -or $secondDrop.index -ne 0) {
        throw "Unexpected second drop payload: $($secondDrop | ConvertTo-Json -Compress -Depth 10)"
    }

    "CDP drag/drop tests passed"
} finally {
    if ($socket) {
        $socket.Dispose()
    }
    if ($browser -and -not $browser.HasExited) {
        Stop-Process -Id $browser.Id -Force
        $browser.WaitForExit(3000) | Out-Null
    }
    if ($staticServer -and -not $staticServer.HasExited) {
        Stop-Process -Id $staticServer.Id -Force
        $staticServer.WaitForExit(3000) | Out-Null
    }
    if (Test-Path $profilePath) {
        try {
            Remove-Item -LiteralPath $profilePath -Recurse -Force
        } catch {
            Write-Warning "Could not remove temporary browser profile: $profilePath"
        }
    }
}
