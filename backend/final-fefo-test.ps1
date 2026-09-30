$ErrorActionPreference = "Continue"

$Root = Split-Path (Get-Location).Path -Parent
$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"

$BaseUrl = "http://localhost:8080"
$FrontendUrl = "http://localhost"
$ProductId = "10000000-0000-0000-0000-000000000001"

$Results = @()

function PASS($name,$detail="") {
    $script:Results += [PSCustomObject]@{
        Test=$name
        Result="PASS"
        Detail=$detail
    }
    Write-Host "[PASS] $name $detail" -ForegroundColor Green
}

function FAIL($name,$detail="") {
    $script:Results += [PSCustomObject]@{
        Test=$name
        Result="FAIL"
        Detail=$detail
    }
    Write-Host "[FAIL] $name $detail" -ForegroundColor Red
}

function INFO($msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Yellow
}

function SECTION($msg) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $msg -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

SECTION "FEFO FINAL VALIDATION"

# ------------------------------------------------------------
# DOCKER
# ------------------------------------------------------------

docker compose ps

foreach ($svc in @("backend","frontend","postgres","redis")) {
    $status = docker compose ps --status running --services | Select-String "^$svc$"
    if ($status) {
        PASS "Docker service $svc"
    } else {
        FAIL "Docker service $svc"
    }
}

# ------------------------------------------------------------
# POSTGRES / REDIS
# ------------------------------------------------------------

$pg = docker compose exec -T postgres pg_isready -U fefo -d fefo 2>&1
if ($pg -match "accepting connections") {
    PASS "PostgreSQL"
} else {
    FAIL "PostgreSQL" $pg
}

$redis = docker compose exec -T redis redis-cli ping 2>&1
if ($redis -match "PONG") {
    PASS "Redis"
} else {
    FAIL "Redis" $redis
}

# ------------------------------------------------------------
# FLYWAY
# ------------------------------------------------------------

$flyway = docker compose exec -T postgres psql -U fefo -d fefo -t -A `
    -c "SELECT version,success,checksum FROM flyway_schema_history ORDER BY installed_rank;" 2>&1

Write-Host $flyway

if ($flyway -match "1\|t\|685315921" -and
    $flyway -match "2\|t\|-1180217577") {
    PASS "Flyway migrations"
} else {
    FAIL "Flyway migrations" $flyway
}

# ------------------------------------------------------------
# MAVEN
# ------------------------------------------------------------

Push-Location $Backend

mvn clean test

if ($LASTEXITCODE -eq 0) {
    PASS "Maven automated tests"
} else {
    FAIL "Maven automated tests" "Exit code $LASTEXITCODE"
}

mvn clean package -DskipTests

if ($LASTEXITCODE -eq 0) {
    PASS "Maven production package"
} else {
    FAIL "Maven production package" "Exit code $LASTEXITCODE"
}

Pop-Location

# ------------------------------------------------------------
# DOCKER BUILD / START
# ------------------------------------------------------------

docker compose build

if ($LASTEXITCODE -eq 0) {
    PASS "Docker build"
} else {
    FAIL "Docker build"
}

docker compose up -d

if ($LASTEXITCODE -eq 0) {
    PASS "Docker startup"
} else {
    FAIL "Docker startup"
}

Start-Sleep -Seconds 10

# ------------------------------------------------------------
# OPENAPI
# ------------------------------------------------------------

try {
    $api = Invoke-WebRequest "$BaseUrl/v3/api-docs" -UseBasicParsing

    if ($api.StatusCode -eq 200) {
        PASS "Backend/OpenAPI"
    } else {
        FAIL "Backend/OpenAPI" "HTTP $($api.StatusCode)"
    }
}
catch {
    FAIL "Backend/OpenAPI" $_.Exception.Message
}

# ------------------------------------------------------------
# LOGIN
# ------------------------------------------------------------

$token = $null

try {
    $login = Invoke-RestMethod `
        "$BaseUrl/api/v1/auth/login" `
        -Method POST `
        -ContentType "application/json" `
        -Body '{"username":"admin","password":"password"}'

    $token = $login.accessToken

    if ($token) {
        PASS "Admin login"
    } else {
        FAIL "Admin login" "No accessToken"
    }
}
catch {
    FAIL "Admin login" $_.Exception.Message
}

if (-not $token) {
    Write-Host ""
    Write-Host "Cannot continue without JWT." -ForegroundColor Red
    $Results | Format-Table -AutoSize
    exit
}

$Headers = @{
    Authorization="Bearer $token"
}

# ------------------------------------------------------------
# PRODUCTS
# ------------------------------------------------------------

try {
    $products = Invoke-RestMethod `
        "$BaseUrl/api/v1/products" `
        -Headers $Headers

    if ($products) {
        PASS "Products GET"
    } else {
        FAIL "Products GET"
    }
}
catch {
    FAIL "Products GET" $_.Exception.Message
}

# ------------------------------------------------------------
# BATCHES
# ------------------------------------------------------------

try {
    $before = Invoke-RestMethod `
        "$BaseUrl/api/v1/batches" `
        -Headers $Headers

    if ($before) {
        PASS "Batches GET"
    } else {
        FAIL "Batches GET"
    }
}
catch {
    FAIL "Batches GET" $_.Exception.Message
}

# ------------------------------------------------------------
# FEFO
# ------------------------------------------------------------

$fefoKey = "final-fefo-$([guid]::NewGuid())"

try {

    $body = @{
        productId=$ProductId
        quantity=1
    } | ConvertTo-Json

    $reservation = Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations" `
        -Method POST `
        -Headers @{
            Authorization="Bearer $token"
            "Idempotency-Key"=$fefoKey
        } `
        -ContentType "application/json" `
        -Body $body

    Write-Host ($reservation | ConvertTo-Json -Depth 20)

    if ($reservation.status -eq "RESERVED" -and
        $reservation.items.Count -gt 0) {

        PASS "FEFO allocation" $reservation.items[0].batchNumber

    } else {
        FAIL "FEFO allocation"
    }

}
catch {
    FAIL "FEFO allocation" $_.Exception.Message
}

# ------------------------------------------------------------
# CONCURRENT DIFFERENT KEYS
# ------------------------------------------------------------

$jobs = @()

1..10 | ForEach-Object {

    $key = "final-concurrent-$([guid]::NewGuid())"

    $jobs += Start-Job -ScriptBlock {

        param($url,$token,$productId,$key)

        try {

            $body = @{
                productId=$productId
                quantity=1
            } | ConvertTo-Json

            $r = Invoke-RestMethod `
                "$url/api/v1/reservations" `
                -Method POST `
                -Headers @{
                    Authorization="Bearer $token"
                    "Idempotency-Key"=$key
                } `
                -ContentType "application/json" `
                -Body $body

            [PSCustomObject]@{
                Success=$true
                Id=$r.id
            }

        }
        catch {

            [PSCustomObject]@{
                Success=$false
                Id=""
            }

        }

    } -ArgumentList $BaseUrl,$token,$ProductId,$key
}

$concurrentResults = @()

foreach ($job in $jobs) {
    Wait-Job $job | Out-Null
    $concurrentResults += @(Receive-Job $job)
    Remove-Job $job -Force
}

$success = @(
    $concurrentResults |
    Where-Object {$_.Success -eq $true}
)

$uniqueIds = @(
    $success |
    Select-Object -ExpandProperty Id -Unique
)

if ($success.Count -eq 10 -and $uniqueIds.Count -eq 10) {
    PASS "Concurrent reservations" "10/10 successful, 10 unique"
} else {
    FAIL "Concurrent reservations" "Success=$($success.Count), Unique=$($uniqueIds.Count)"
}

# ------------------------------------------------------------
# SAME KEY
# ------------------------------------------------------------

$sameKey = "final-same-$([guid]::NewGuid())"
$sameJobs = @()

1..10 | ForEach-Object {

    $sameJobs += Start-Job -ScriptBlock {

        param($url,$token,$productId,$key)

        try {

            $body = @{
                productId=$productId
                quantity=1
            } | ConvertTo-Json

            $r = Invoke-RestMethod `
                "$url/api/v1/reservations" `
                -Method POST `
                -Headers @{
                    Authorization="Bearer $token"
                    "Idempotency-Key"=$key
                } `
                -ContentType "application/json" `
                -Body $body

            [PSCustomObject]@{
                Success=$true
                Id=$r.id
            }

        }
        catch {

            [PSCustomObject]@{
                Success=$false
                Id=""
            }

        }

    } -ArgumentList $BaseUrl,$token,$ProductId,$sameKey
}

$sameResults = @()

foreach ($job in $sameJobs) {
    Wait-Job $job | Out-Null
    $sameResults += @(Receive-Job $job)
    Remove-Job $job -Force
}

$sameSuccess = @(
    $sameResults |
    Where-Object {$_.Success -eq $true}
)

$sameIds = @(
    $sameSuccess |
    Select-Object -ExpandProperty Id -Unique
)

if ($sameSuccess.Count -eq 10 -and $sameIds.Count -eq 1) {
    PASS "Concurrent same-key idempotency" "10 -> 1 reservation"
} else {
    FAIL "Concurrent same-key idempotency" "Success=$($sameSuccess.Count), Unique=$($sameIds.Count)"
}

# ------------------------------------------------------------
# IDEMPOTENCY DB
# ------------------------------------------------------------

$idDb = docker compose exec -T postgres psql `
    -U fefo -d fefo -t -A -F "|" `
    -c "SELECT response_status,(response_body IS NOT NULL) FROM idempotency_keys WHERE idempotency_key='$sameKey';"

Write-Host "Idempotency DB: $idDb"

if ($idDb -match "201\|t") {
    PASS "Idempotency response persisted"
} else {
    FAIL "Idempotency response persisted" $idDb
}

# ------------------------------------------------------------
# MISMATCH
# ------------------------------------------------------------

$mismatchKey = "final-mismatch-$([guid]::NewGuid())"

try {

    $b1 = @{
        productId=$ProductId
        quantity=1
    } | ConvertTo-Json

    $b2 = @{
        productId=$ProductId
        quantity=99
    } | ConvertTo-Json

    Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations" `
        -Method POST `
        -Headers @{
            Authorization="Bearer $token"
            "Idempotency-Key"=$mismatchKey
        } `
        -ContentType "application/json" `
        -Body $b1 | Out-Null

    try {

        Invoke-WebRequest `
            "$BaseUrl/api/v1/reservations" `
            -Method POST `
            -Headers @{
                Authorization="Bearer $token"
                "Idempotency-Key"=$mismatchKey
            } `
            -ContentType "application/json" `
            -Body $b2 `
            -UseBasicParsing | Out-Null

        FAIL "Idempotency mismatch" "Unexpected success"

    }
    catch {

        $code=[int]$_.Exception.Response.StatusCode

        if ($code -eq 409) {
            PASS "Idempotency mismatch" "HTTP 409"
        } else {
            FAIL "Idempotency mismatch" "HTTP $code"
        }
    }

}
catch {
    FAIL "Idempotency mismatch" $_.Exception.Message
}

# ------------------------------------------------------------
# CANCEL RESTORES STOCK
# ------------------------------------------------------------

try {

    $pre = Invoke-RestMethod `
        "$BaseUrl/api/v1/batches" `
        -Headers $Headers

    $cancelKey="final-cancel-$([guid]::NewGuid())"

    $body=@{
        productId=$ProductId
        quantity=2
    } | ConvertTo-Json

    $r=Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations" `
        -Method POST `
        -Headers @{
            Authorization="Bearer $token"
            "Idempotency-Key"=$cancelKey
        } `
        -ContentType "application/json" `
        -Body $body

    $cancel=Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations/$($r.id)/cancel" `
        -Method POST `
        -Headers $Headers

    $post=Invoke-RestMethod `
        "$BaseUrl/api/v1/batches" `
        -Headers $Headers

    $ok=$true

    foreach ($b in $pre) {

        $after=$post |
            Where-Object {$_.id -eq $b.id}

        if ($after.availableQuantity -ne $b.availableQuantity -or
            $after.reservedQuantity -ne $b.reservedQuantity) {

            $ok=$false
        }
    }

    if ($cancel.status -eq "CANCELLED" -and $ok) {
        PASS "Cancel restores stock"
    } else {
        FAIL "Cancel restores stock"
    }

}
catch {
    FAIL "Cancel lifecycle" $_.Exception.Message
}

# ------------------------------------------------------------
# CONFIRM
# ------------------------------------------------------------

try {

    $confirmKey="final-confirm-$([guid]::NewGuid())"

    $body=@{
        productId=$ProductId
        quantity=1
    } | ConvertTo-Json

    $r=Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations" `
        -Method POST `
        -Headers @{
            Authorization="Bearer $token"
            "Idempotency-Key"=$confirmKey
        } `
        -ContentType "application/json" `
        -Body $body

    $confirmed=Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations/$($r.id)/confirm" `
        -Method POST `
        -Headers $Headers

    if ($confirmed.status -eq "CONFIRMED") {
        PASS "Confirm lifecycle"
    } else {
        FAIL "Confirm lifecycle" $confirmed.status
    }

}
catch {
    FAIL "Confirm lifecycle" $_.Exception.Message
}

# ------------------------------------------------------------
# INSUFFICIENT STOCK
# ------------------------------------------------------------

try {

    $body=@{
        productId=$ProductId
        quantity=999999
    } | ConvertTo-Json

    try {

        Invoke-WebRequest `
            "$BaseUrl/api/v1/reservations" `
            -Method POST `
            -Headers @{
                Authorization="Bearer $token"
                "Idempotency-Key"="final-stock-$([guid]::NewGuid())"
            } `
            -ContentType "application/json" `
            -Body $body `
            -UseBasicParsing | Out-Null

        FAIL "Insufficient stock" "Unexpected success"

    }
    catch {

        $code=[int]$_.Exception.Response.StatusCode

        if ($code -eq 409) {
            PASS "Insufficient stock" "HTTP 409"
        } else {
            FAIL "Insufficient stock" "HTTP $code"
        }
    }

}
catch {
    FAIL "Insufficient stock" $_.Exception.Message
}

# ------------------------------------------------------------
# INVALID JWT
# ------------------------------------------------------------

try {

    Invoke-WebRequest `
        "$BaseUrl/api/v1/batches" `
        -Headers @{Authorization="Bearer invalid"} `
        -UseBasicParsing | Out-Null

    FAIL "Invalid JWT" "Unexpected success"

}
catch {

    $code=[int]$_.Exception.Response.StatusCode

    if ($code -eq 401 -or $code -eq 403) {
        PASS "Invalid JWT" "HTTP $code"
    } else {
        FAIL "Invalid JWT" "HTTP $code"
    }
}

# ------------------------------------------------------------
# DASHBOARD
# ------------------------------------------------------------

try {

    $dash=Invoke-RestMethod `
        "$BaseUrl/api/v1/dashboard/summary" `
        -Headers $Headers

    if ($null -ne $dash) {
        PASS "Dashboard"
    } else {
        FAIL "Dashboard"
    }

}
catch {
    FAIL "Dashboard" $_.Exception.Message
}

# ------------------------------------------------------------
# AUDIT
# ------------------------------------------------------------

try {

    $audit=Invoke-RestMethod `
        "$BaseUrl/api/v1/audit-logs" `
        -Headers $Headers

    $json=$audit | ConvertTo-Json -Depth 30

    if ($json -match "STOCK_RESERVED") {
        PASS "Audit STOCK_RESERVED"
    } else {
        FAIL "Audit STOCK_RESERVED"
    }

    if ($json -match "STOCK_RELEASED") {
        PASS "Audit STOCK_RELEASED"
    } else {
        FAIL "Audit STOCK_RELEASED"
    }

    if ($json -match "STOCK_CONFIRMED") {
        PASS "Audit STOCK_CONFIRMED"
    } else {
        FAIL "Audit STOCK_CONFIRMED"
    }

}
catch {
    FAIL "Audit logs" $_.Exception.Message
}

# ------------------------------------------------------------
# INVENTORY INVARIANTS
# ------------------------------------------------------------

$bad = docker compose exec -T postgres psql `
    -U fefo -d fefo -t -A `
    -c "SELECT COUNT(*) FROM batches WHERE available_quantity < 0 OR reserved_quantity < 0 OR available_quantity + reserved_quantity > total_quantity;"

if ($bad.Trim() -eq "0") {
    PASS "Inventory invariants"
} else {
    FAIL "Inventory invariants" $bad
}

# ------------------------------------------------------------
# IDEMPOTENCY UNIQUENESS
# ------------------------------------------------------------

$dup = docker compose exec -T postgres psql `
    -U fefo -d fefo -t -A `
    -c "SELECT COUNT(*) FROM (SELECT idempotency_key,endpoint,COUNT(*) FROM idempotency_keys GROUP BY idempotency_key,endpoint HAVING COUNT(*)>1)x;"

if ($dup.Trim() -eq "0") {
    PASS "Idempotency uniqueness"
} else {
    FAIL "Idempotency uniqueness" $dup
}

# ------------------------------------------------------------
# RESERVATION EXPIRY INFORMATION
# ------------------------------------------------------------

$expiry = docker compose exec -T postgres psql `
    -U fefo -d fefo -t -A `
    -c "SELECT COUNT(*),COUNT(expires_at) FROM reservations;"

Write-Host "Reservation expiry data: $expiry"

if ($expiry) {
    PASS "Reservation expiry data"
} else {
    FAIL "Reservation expiry data"
}

# ------------------------------------------------------------
# REDIS
# ------------------------------------------------------------

$redisKeys=docker compose exec -T redis redis-cli --scan

$lockKeys=@(
    $redisKeys |
    Where-Object {$_ -match "lock"}
)

if ($lockKeys.Count -eq 0) {
    PASS "Redis lock cleanup"
} else {
    INFO "Redis lock keys:"
    $lockKeys
}

# ------------------------------------------------------------
# BENCHMARK DISCOVERY
# ------------------------------------------------------------

try {

    $apiDoc=Invoke-RestMethod "$BaseUrl/v3/api-docs"

    $paths=$apiDoc.paths.PSObject.Properties.Name

    if ($paths -contains "/api/v1/benchmarks/fefo-vs-lifo") {
        PASS "Benchmark endpoint exists"
    } else {
        FAIL "Benchmark endpoint exists"
    }

}
catch {
    FAIL "OpenAPI endpoint inspection" $_.Exception.Message
}

# ------------------------------------------------------------
# FRONTEND
# ------------------------------------------------------------

try {

    $front=Invoke-WebRequest `
        "$FrontendUrl" `
        -UseBasicParsing

    if ($front.StatusCode -eq 200) {
        PASS "Frontend reachable"
    } else {
        FAIL "Frontend reachable" "HTTP $($front.StatusCode)"
    }

}
catch {
    FAIL "Frontend reachable" $_.Exception.Message
}

# ------------------------------------------------------------
# FINAL DOCKER
# ------------------------------------------------------------

docker compose ps

# ------------------------------------------------------------
# FINAL REPORT
# ------------------------------------------------------------

SECTION "FINAL REPORT"

$passed=@(
    $script:Results |
    Where-Object {$_.Result -eq "PASS"}
).Count

$failed=@(
    $script:Results |
    Where-Object {$_.Result -eq "FAIL"}
).Count

$total=$script:Results.Count

Write-Host ""
Write-Host "PASSED : $passed" -ForegroundColor Green
Write-Host "FAILED : $failed" -ForegroundColor Red
Write-Host "TOTAL  : $total" -ForegroundColor Cyan

if ($total -gt 0) {
    Write-Host "RATE   : $([math]::Round(($passed/$total)*100,2))%"
}

Write-Host ""

$script:Results | Format-Table -AutoSize

if ($failed -eq 0) {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "          FEFO PROJECT VALIDATION COMPLETE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green

} else {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "          FIX THE FAILURES SHOWN ABOVE" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
}

