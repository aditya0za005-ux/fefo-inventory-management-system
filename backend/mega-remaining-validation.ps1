$ErrorActionPreference = "Continue"

$Root = Split-Path (Get-Location).Path -Parent
$Backend = Join-Path $Root "backend"
$BaseUrl = "http://localhost:8080"
$ProductId = "10000000-0000-0000-0000-000000000001"

function SECTION($msg) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $msg -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function PASS($msg) {
    Write-Host "[PASS] $msg" -ForegroundColor Green
}

function FAIL($msg) {
    Write-Host "[FAIL] $msg" -ForegroundColor Red
}

function INFO($msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Yellow
}

SECTION "1. PROJECT / DOCKER STATUS"

docker compose ps

SECTION "2. FIND RELEVANT TEST FILES"

Push-Location $Backend

Write-Host ""
Write-Host "--- ControllerTests.java ---"
if (Test-Path ".\src\test\java\com\aditya\fefo\controller\ControllerTests.java") {
    Get-Content ".\src\test\java\com\aditya\fefo\controller\ControllerTests.java"
} else {
    FAIL "ControllerTests.java not found"
}

Write-Host ""
Write-Host "--- ConcurrencyIntegrationTest.java ---"
$conc = Get-ChildItem ".\src\test" -Recurse -Filter "*ConcurrencyIntegrationTest*.java" -ErrorAction SilentlyContinue
if ($conc) {
    Get-Content $conc.FullName
} else {
    FAIL "ConcurrencyIntegrationTest.java not found"
}

Write-Host ""
Write-Host "--- FefoAllocatorTest.java ---"
$fefoTest = Get-ChildItem ".\src\test" -Recurse -Filter "*FefoAllocatorTest*.java" -ErrorAction SilentlyContinue
if ($fefoTest) {
    Get-Content $fefoTest.FullName
} else {
    FAIL "FefoAllocatorTest.java not found"
}

Write-Host ""
Write-Host "--- JwtService / JwtAuthFilter ---"
Get-ChildItem ".\src\main\java" -Recurse -Filter "*.java" |
    Select-String -Pattern "class JwtService|@Service.*JwtService|class JwtAuthFilter" |
    Select-Object Path,LineNumber,Line

SECTION "3. VERIFY DOCKER / DATABASE / REDIS"

$pg = docker compose exec -T postgres pg_isready -U fefo -d fefo 2>&1
if ($pg -match "accepting connections") {
    PASS "PostgreSQL"
} else {
    FAIL "PostgreSQL: $pg"
}

$redis = docker compose exec -T redis redis-cli ping 2>&1
if ($redis -match "PONG") {
    PASS "Redis"
} else {
    FAIL "Redis: $redis"
}

SECTION "4. VERIFY FLYWAY"

$flyway = docker compose exec -T postgres psql -U fefo -d fefo -t -A `
    -c "SELECT version,success,checksum FROM flyway_schema_history ORDER BY installed_rank;" 2>&1

Write-Host $flyway

SECTION "5. REBUILD BACKEND"

mvn clean package -DskipTests

if ($LASTEXITCODE -eq 0) {
    PASS "Backend production package"
} else {
    FAIL "Backend production package"
}

SECTION "6. REBUILD DOCKER"

docker compose build backend

if ($LASTEXITCODE -eq 0) {
    PASS "Backend Docker build"
} else {
    FAIL "Backend Docker build"
}

docker compose up -d

if ($LASTEXITCODE -eq 0) {
    PASS "Docker startup"
} else {
    FAIL "Docker startup"
}

Start-Sleep -Seconds 10

SECTION "7. LOGIN"

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
        FAIL "No accessToken returned"
        exit
    }
}
catch {
    FAIL "Login failed: $($_.Exception.Message)"
    exit
}

$Headers = @{
    Authorization = "Bearer $token"
}

SECTION "8. CANCEL LIFECYCLE - CORRECT IDEMPOTENCY HEADER"

try {

    $cancelKey = "mega-cancel-create-$([guid]::NewGuid())"

    $body = @{
        productId = $ProductId
        quantity = 1
    } | ConvertTo-Json

    $r = Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations" `
        -Method POST `
        -Headers @{
            Authorization = "Bearer $token"
            "Idempotency-Key" = $cancelKey
        } `
        -ContentType "application/json" `
        -Body $body

    Write-Host "Created reservation: $($r.id)"

    $cancelActionKey = "mega-cancel-action-$([guid]::NewGuid())"

    $cancel = Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations/$($r.id)/cancel" `
        -Method POST `
        -Headers @{
            Authorization = "Bearer $token"
            "Idempotency-Key" = $cancelActionKey
        }

    Write-Host ($cancel | ConvertTo-Json -Depth 20)

    if ($cancel.status -eq "CANCELLED") {
        PASS "Cancel lifecycle"
    } else {
        FAIL "Cancel lifecycle returned status $($cancel.status)"
    }

}
catch {
    FAIL "Cancel lifecycle: $($_.Exception.Message)"
}

SECTION "9. CONFIRM LIFECYCLE - CORRECT IDEMPOTENCY HEADER"

try {

    $confirmKey = "mega-confirm-create-$([guid]::NewGuid())"

    $body = @{
        productId = $ProductId
        quantity = 1
    } | ConvertTo-Json

    $r = Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations" `
        -Method POST `
        -Headers @{
            Authorization = "Bearer $token"
            "Idempotency-Key" = $confirmKey
        } `
        -ContentType "application/json" `
        -Body $body

    Write-Host "Created reservation: $($r.id)"

    $confirmActionKey = "mega-confirm-action-$([guid]::NewGuid())"

    $confirmed = Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations/$($r.id)/confirm" `
        -Method POST `
        -Headers @{
            Authorization = "Bearer $token"
            "Idempotency-Key" = $confirmActionKey
        }

    Write-Host ($confirmed | ConvertTo-Json -Depth 20)

    if ($confirmed.status -eq "CONFIRMED") {
        PASS "Confirm lifecycle"
    } else {
        FAIL "Confirm lifecycle returned status $($confirmed.status)"
    }

}
catch {
    FAIL "Confirm lifecycle: $($_.Exception.Message)"
}

SECTION "10. CANCEL / CONFIRM IDEMPOTENCY RETRY"

try {

    $retryCreateKey = "mega-retry-create-$([guid]::NewGuid())"

    $body = @{
        productId = $ProductId
        quantity = 1
    } | ConvertTo-Json

    $r = Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations" `
        -Method POST `
        -Headers @{
            Authorization = "Bearer $token"
            "Idempotency-Key" = $retryCreateKey
        } `
        -ContentType "application/json" `
        -Body $body

    $actionKey = "mega-cancel-retry-$([guid]::NewGuid())"

    $c1 = Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations/$($r.id)/cancel" `
        -Method POST `
        -Headers @{
            Authorization = "Bearer $token"
            "Idempotency-Key" = $actionKey
        }

    $c2 = Invoke-RestMethod `
        "$BaseUrl/api/v1/reservations/$($r.id)/cancel" `
        -Method POST `
        -Headers @{
            Authorization = "Bearer $token"
            "Idempotency-Key" = $actionKey
        }

    if ($c1.id -eq $c2.id -and $c2.status -eq "CANCELLED") {
        PASS "Cancel idempotent retry"
    } else {
        FAIL "Cancel idempotent retry"
    }

}
catch {
    FAIL "Cancel idempotent retry: $($_.Exception.Message)"
}

SECTION "11. MAVEN TEST SUITE - FULL"

mvn clean test

$mavenExit = $LASTEXITCODE

if ($mavenExit -eq 0) {
    PASS "ALL Maven tests"
} else {
    FAIL "Maven tests failed - exit code $mavenExit"
}

SECTION "12. MAVEN TEST REPORT SUMMARY"

if (Test-Path ".\target\surefire-reports") {

    Get-ChildItem ".\target\surefire-reports" -Filter "*.txt" |
        ForEach-Object {

            $content = Get-Content $_.FullName -Raw

            if ($content -match "Tests run:") {

                Write-Host ""
                Write-Host "[$($_.Name)]"

                $content |
                    Select-String -Pattern "Tests run:" -AllMatches |
                    ForEach-Object { $_.Line }

            }

        }

} else {
    INFO "Surefire reports directory not found"
}

SECTION "13. MAVEN TEST FAILURES - EXACT"

if (Test-Path ".\target\surefire-reports") {

    Get-ChildItem ".\target\surefire-reports" -Filter "*.txt" |
        ForEach-Object {

            $content = Get-Content $_.FullName -Raw

            if ($content -match "Failures: [1-9]|Errors: [1-9]") {

                Write-Host ""
                Write-Host "FAILED TEST FILE: $($_.Name)" -ForegroundColor Red

                $content |
                    Select-String -Pattern "Tests run:|<<< FAILURE!|<<< ERROR!|Caused by:|NoSuchBeanDefinitionException|Docker environment|IllegalArgumentException" |
                    Select-Object -First 30 |
                    ForEach-Object { $_.Line }

            }

        }

}

SECTION "14. TESTCONTAINERS / DOCKER ENVIRONMENT"

docker version

Write-Host ""
Write-Host "--- Docker context ---"

docker context show

Write-Host ""
Write-Host "--- DOCKER_HOST ---"

$env:DOCKER_HOST

Write-Host ""
Write-Host "--- Testcontainers-related configuration ---"

Get-ChildItem Env: |
    Where-Object {
        $_.Name -match "DOCKER|TESTCONTAINERS"
    } |
    Format-Table -AutoSize

SECTION "15. BACKEND LOGS AFTER LIFECYCLE TESTS"

docker compose logs backend --since 5m |
    Select-String -Pattern "ERROR|Exception|Caused by|MissingRequestHeader" -Context 2,5

SECTION "16. FINAL API HEALTH"

try {
    $api = Invoke-WebRequest `
        "$BaseUrl/v3/api-docs" `
        -UseBasicParsing

    if ($api.StatusCode -eq 200) {
        PASS "OpenAPI"
    } else {
        FAIL "OpenAPI HTTP $($api.StatusCode)"
    }
}
catch {
    FAIL "OpenAPI: $($_.Exception.Message)"
}

try {
    $products = Invoke-RestMethod `
        "$BaseUrl/api/v1/products" `
        -Headers $Headers

    if ($products) {
        PASS "Products API"
    } else {
        FAIL "Products API"
    }
}
catch {
    FAIL "Products API: $($_.Exception.Message)"
}

try {
    $batches = Invoke-RestMethod `
        "$BaseUrl/api/v1/batches" `
        -Headers $Headers

    if ($batches) {
        PASS "Batches API"
    } else {
        FAIL "Batches API"
    }
}
catch {
    FAIL "Batches API: $($_.Exception.Message)"
}

try {
    $dash = Invoke-RestMethod `
        "$BaseUrl/api/v1/dashboard/summary" `
        -Headers $Headers

    if ($null -ne $dash) {
        PASS "Dashboard API"
    } else {
        FAIL "Dashboard API"
    }
}
catch {
    FAIL "Dashboard API: $($_.Exception.Message)"
}

SECTION "17. DATABASE INVARIANTS"

$bad = docker compose exec -T postgres psql `
    -U fefo -d fefo -t -A `
    -c "SELECT COUNT(*) FROM batches WHERE available_quantity < 0 OR reserved_quantity < 0 OR available_quantity + reserved_quantity > total_quantity;"

Write-Host "Invalid inventory rows: $bad"

if ($bad.Trim() -eq "0") {
    PASS "Inventory invariants"
} else {
    FAIL "Inventory invariants"
}

$dup = docker compose exec -T postgres psql `
    -U fefo -d fefo -t -A `
    -c "SELECT COUNT(*) FROM (SELECT idempotency_key,endpoint,COUNT(*) FROM idempotency_keys GROUP BY idempotency_key,endpoint HAVING COUNT(*) > 1)x;"

Write-Host "Duplicate idempotency groups: $dup"

if ($dup.Trim() -eq "0") {
    PASS "Idempotency uniqueness"
} else {
    FAIL "Idempotency uniqueness"
}

SECTION "18. REDIS LOCK CLEANUP"

$redisKeys = docker compose exec -T redis redis-cli --scan

$lockKeys = @(
    $redisKeys |
    Where-Object { $_ -match "lock" }
)

if ($lockKeys.Count -eq 0) {
    PASS "No leftover Redis lock keys"
} else {
    INFO "Redis lock keys still present:"
    $lockKeys
}

SECTION "19. FINAL DOCKER STATUS"

docker compose ps

SECTION "20. FINAL RESULT"

Pop-Location

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             FEFO REMAINING WORK VALIDATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "The two previous API failures were caused by missing Idempotency-Key headers."
Write-Host "Maven tests are the remaining genuine automated-test area."
Write-Host ""
Write-Host "NEXT ACTIONS ARE DETERMINED FROM THE OUTPUT ABOVE:"
Write-Host "1. Cancel/Confirm API"
Write-Host "2. ControllerTests JwtService"
Write-Host "3. Testcontainers Docker detection"
Write-Host "4. Expired-batch test fixture"
Write-Host "5. Any newly exposed failures"
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
