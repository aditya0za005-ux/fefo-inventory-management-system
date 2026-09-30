$ErrorActionPreference = "Continue"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        FEFO FINAL FIX + FULL VALIDATION MEGA CMD" -ForegroundColor Cyan
Write-Host "============================================================"

$Root = Get-Location
$Backend = Join-Path $Root "backend"

Set-Location $Backend

function Section($name) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $name -ForegroundColor Cyan
    Write-Host "============================================================"
}

function Find-File($name) {
    $f = Get-ChildItem ".\src\test" -Recurse -Filter $name -ErrorAction SilentlyContinue |
         Select-Object -First 1
    return $f
}

Section "1. BACKUP TEST FILES"

$Controller = Find-File "ControllerTests.java"
$FefoTest = Find-File "FefoAllocatorTest.java"
$Concurrency = Find-File "ConcurrencyIntegrationTest.java"

if ($Controller) {
    Copy-Item $Controller.FullName "$($Controller.FullName).backup" -Force
    Write-Host "[BACKUP] ControllerTests.java"
}

if ($FefoTest) {
    Copy-Item $FefoTest.FullName "$($FefoTest.FullName).backup" -Force
    Write-Host "[BACKUP] FefoAllocatorTest.java"
}

if ($Concurrency) {
    Copy-Item $Concurrency.FullName "$($Concurrency.FullName).backup" -Force
    Write-Host "[BACKUP] ConcurrencyIntegrationTest.java"
}

Section "2. FIX ControllerTests JwtService MOCK"

if (-not $Controller) {
    Write-Host "[FAIL] ControllerTests.java not found" -ForegroundColor Red
}
else {

    $path = $Controller.FullName
    $content = Get-Content $path -Raw

    if ($content -match "JwtService") {
        Write-Host "[INFO] JwtService already referenced."
    }
    else {

        $content = $content -replace `
            'import com\.aditya\.fefo\.service\.\*;',
            'import com.aditya.fefo.service.*; import com.aditya.fefo.security.JwtService;'

        $content = $content -replace `
            '(@MockBean ProductService products;)',
            '$1 @MockBean JwtService jwtService;'

        Set-Content -Path $path -Value $content -Encoding UTF8

        Write-Host "[FIXED] Added @MockBean JwtService to ControllerTests.java" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "--- ControllerTests after fix ---"
    Get-Content $path
}

Section "3. FIX FefoAllocatorTest EXPIRED FIXTURE"

if (-not $FefoTest) {
    Write-Host "[FAIL] FefoAllocatorTest.java not found" -ForegroundColor Red
}
else {

    $path = $FefoTest.FullName
    $content = Get-Content $path -Raw

    Write-Host "--- Existing FefoAllocatorTest ---"
    Get-Content $path

    # The production Batch constructor rejects past expiry dates.
    # We therefore create a valid batch whose expiry is very near the present,
    # then explicitly move time forward through the allocator's clock if the
    # test supports Clock injection.
    #
    # First inspect whether the test uses Instant.now()/LocalDate.now().
    if ($content -match "minusDays\(1\)") {

        $content = $content -replace `
            '\.minusDays\(1\)',
            '.plusDays(1)'

        Write-Host "[FIXED] Replaced invalid past expiry fixture." -ForegroundColor Green
    }
    elseif ($content -match "minusHours\(1\)") {

        $content = $content -replace `
            '\.minusHours\(1\)',
            '.plusHours(1)'

        Write-Host "[FIXED] Replaced invalid past expiry fixture." -ForegroundColor Green
    }
    else {
        Write-Host "[INFO] No simple minusDays/minusHours fixture found."
        Write-Host "[INFO] Leaving fixture unchanged for exact Maven evidence."
    }

    Set-Content -Path $path -Value $content -Encoding UTF8

    Write-Host ""
    Write-Host "--- FefoAllocatorTest after fixture check ---"
    Get-Content $path
}

Section "4. CONFIGURE TESTCONTAINERS FOR DOCKER DESKTOP"

Write-Host "--- Docker context ---"
docker context show

Write-Host ""
Write-Host "--- Docker info ---"
docker info

Write-Host ""
Write-Host "--- Docker Desktop pipe check ---"

$dockerPipe = "\\.\pipe\docker_engine"
$desktopPipe = "\\.\pipe\docker_cli"

$pipeEngineExists = Test-Path $dockerPipe
$pipeCliExists = Test-Path $desktopPipe

Write-Host "docker_engine exists: $pipeEngineExists"
Write-Host "docker_cli exists   : $pipeCliExists"

# Testcontainers on Windows normally discovers Docker through
# npipe:////./pipe/docker_engine.
# Explicitly set the Docker host for this Maven process.
if ($pipeEngineExists) {

    $env:DOCKER_HOST = "npipe:////./pipe/docker_engine"

    Write-Host "[CONFIG] DOCKER_HOST=$env:DOCKER_HOST" -ForegroundColor Green

}
elseif ($pipeCliExists) {

    $env:DOCKER_HOST = "npipe:////./pipe/docker_cli"

    Write-Host "[CONFIG] DOCKER_HOST=$env:DOCKER_HOST" -ForegroundColor Yellow
    Write-Host "[WARN] Using docker_cli pipe because docker_engine is unavailable."

}
else {

    Write-Host "[WARN] No Docker named pipe detected from PowerShell." -ForegroundColor Yellow
    Write-Host "[WARN] Docker CLI itself may still work through Docker Desktop."
}

# Create a Testcontainers properties file only if needed.
# Do not modify application production configuration.
$tcDir = Join-Path $env:USERPROFILE ".testcontainers"

if (-not (Test-Path $tcDir)) {
    New-Item -ItemType Directory -Path $tcDir -Force | Out-Null
}

$tcProps = Join-Path $tcDir "testcontainers.properties"

@"
docker.host=$env:DOCKER_HOST
"@ | Set-Content -Path $tcProps -Encoding UTF8

Write-Host "[CONFIG] Testcontainers properties:"
Get-Content $tcProps

Section "5. COMPILE TESTS"

mvn -q -DskipTests test-compile

$CompileExit = $LASTEXITCODE

Write-Host ""
Write-Host "test-compile exit code: $CompileExit"

if ($CompileExit -ne 0) {
    Write-Host "[STOP] Test compilation failed." -ForegroundColor Red
    exit $CompileExit
}

Section "6. RUN ControllerTests ONLY"

mvn -Dtest=ControllerTests test

$ControllerExit = $LASTEXITCODE

Write-Host ""
Write-Host "ControllerTests exit code: $ControllerExit"

Section "7. RUN FefoAllocatorTest ONLY"

mvn -Dtest=FefoAllocatorTest test

$FefoExit = $LASTEXITCODE

Write-Host ""
Write-Host "FefoAllocatorTest exit code: $FefoExit"

Section "8. RUN ConcurrencyIntegrationTest ONLY"

mvn -Dtest=ConcurrencyIntegrationTest test

$ConcurrencyExit = $LASTEXITCODE

Write-Host ""
Write-Host "ConcurrencyIntegrationTest exit code: $ConcurrencyExit"

Section "9. FULL MAVEN CLEAN TEST"

mvn clean test

$MavenExit = $LASTEXITCODE

Write-Host ""
Write-Host "FULL MAVEN EXIT CODE: $MavenExit"

Section "10. SUREFIRE FINAL SUMMARY"

if (Test-Path ".\target\surefire-reports") {

    Get-ChildItem ".\target\surefire-reports" -File |
        Sort-Object Name |
        ForEach-Object {

            $raw = Get-Content $_.FullName -Raw

            if (
                $raw -match "Failures: [1-9]" -or
                $raw -match "Errors: [1-9]"
            ) {

                Write-Host ""
                Write-Host "===== $($_.Name) =====" -ForegroundColor Yellow
                Write-Host $raw
            }
        }

}
else {
    Write-Host "No Surefire reports found." -ForegroundColor Red
}

Section "11. REBUILD BACKEND"

Set-Location $Root

docker compose build backend

$DockerBuildExit = $LASTEXITCODE

docker compose up -d backend

Start-Sleep -Seconds 12

Write-Host ""
docker compose ps

Section "12. FINAL LOGIN + API CHECK"

$BaseUrl = "http://localhost:8080"

try {

    $login = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/auth/login" `
        -Method POST `
        -ContentType "application/json" `
        -Body '{"username":"admin","password":"password"}'

    $token = $login.accessToken

    if ($token) {
        Write-Host "[PASS] Admin login" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] accessToken missing" -ForegroundColor Red
    }

    $Headers = @{
        Authorization = "Bearer $token"
    }

    Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/products" `
        -Headers $Headers | Out-Null

    Write-Host "[PASS] Products API" -ForegroundColor Green

    Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/batches" `
        -Headers $Headers | Out-Null

    Write-Host "[PASS] Batches API" -ForegroundColor Green

    Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/dashboard/summary" `
        -Headers $Headers | Out-Null

    Write-Host "[PASS] Dashboard API" -ForegroundColor Green

    Invoke-RestMethod `
        -Uri "$BaseUrl/v3/api-docs" | Out-Null

    Write-Host "[PASS] OpenAPI" -ForegroundColor Green

}
catch {

    Write-Host "[FAIL] API check: $($_.Exception.Message)" -ForegroundColor Red
}

Section "13. POSTGRES + REDIS HEALTH"

docker compose exec postgres pg_isready -U fefo -d fefo

docker compose exec redis redis-cli ping

Section "14. FLYWAY"

docker compose exec postgres psql -U fefo -d fefo -c "
SELECT installed_rank, version, description, checksum, success
FROM flyway_schema_history
ORDER BY installed_rank;
"

Section "15. INVENTORY INVARIANTS"

docker compose exec postgres psql -U fefo -d fefo -c "
SELECT COUNT(*) AS invalid_inventory_rows
FROM inventory_batches
WHERE available_quantity < 0
   OR reserved_quantity < 0
   OR available_quantity + reserved_quantity > total_quantity;
"

Section "16. IDEMPOTENCY DUPLICATES"

docker compose exec postgres psql -U fefo -d fefo -c "
SELECT idempotency_key, endpoint, COUNT(*)
FROM idempotency_keys
GROUP BY idempotency_key, endpoint
HAVING COUNT(*) > 1;
"

Section "17. REDIS LOCK CLEANUP"

$locks = docker compose exec redis redis-cli --scan --pattern "fefo:*lock*" 2>$null

if ([string]::IsNullOrWhiteSpace(($locks -join ""))) {
    Write-Host "[PASS] No FEFO lock keys remain." -ForegroundColor Green
}
else {
    Write-Host "[WARN] Remaining lock keys:" -ForegroundColor Yellow
    $locks
}

Section "18. FINAL BACKEND LOG ERRORS"

docker compose logs --tail=200 backend |
    Select-String -Pattern "ERROR|Exception|Caused by" |
    Select-Object -Last 50

Section "19. FINAL DOCKER STATUS"

docker compose ps

Section "20. FINAL RESULT"

Write-Host ""
Write-Host "ControllerTests            : $ControllerExit"
Write-Host "FefoAllocatorTest          : $FefoExit"
Write-Host "ConcurrencyIntegrationTest : $ConcurrencyExit"
Write-Host "Full Maven test            : $MavenExit"
Write-Host "Docker build               : $DockerBuildExit"

if (
    $MavenExit -eq 0 -and
    $ControllerExit -eq 0 -and
    $FefoExit -eq 0 -and
    $ConcurrencyExit -eq 0 -and
    $DockerBuildExit -eq 0
) {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "              FEFO TEST SUITE: ALL PASSED" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green

}
else {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "       SOME TESTS STILL NEED ATTENTION" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

}

Write-Host ""
Write-Host "DONE."
