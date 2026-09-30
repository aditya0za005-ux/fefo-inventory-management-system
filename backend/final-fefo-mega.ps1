$ErrorActionPreference = "Continue"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        FEFO FINAL MEGA VALIDATION + TEST FIX" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$Root = Get-Location
$Backend = Join-Path $Root "backend"

Set-Location $Backend

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "1. PROJECT / DOCKER STATE" -ForegroundColor Cyan
Write-Host "============================================================"

Write-Host "`n--- Docker version ---"
docker version

Write-Host "`n--- Docker context ---"
docker context show

Write-Host "`n--- Docker compose status ---"
docker compose ps

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "2. LOCATE REMAINING TESTS" -ForegroundColor Cyan
Write-Host "============================================================"

Write-Host "`n--- ControllerTests.java ---"
Get-ChildItem -Recurse -Filter "ControllerTests.java" |
    ForEach-Object {
        Write-Host "FILE: $($_.FullName)" -ForegroundColor Yellow
        Get-Content $_.FullName
    }

Write-Host "`n--- ConcurrencyIntegrationTest.java ---"
Get-ChildItem -Recurse -Filter "ConcurrencyIntegrationTest.java" |
    ForEach-Object {
        Write-Host "FILE: $($_.FullName)" -ForegroundColor Yellow
        Get-Content $_.FullName
    }

Write-Host "`n--- FefoAllocatorTest.java ---"
Get-ChildItem -Recurse -Filter "FefoAllocatorTest.java" |
    ForEach-Object {
        Write-Host "FILE: $($_.FullName)" -ForegroundColor Yellow
        Get-Content $_.FullName
    }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "3. SECURITY CLASSES" -ForegroundColor Cyan
Write-Host "============================================================"

Write-Host "`n--- JwtAuthFilter.java ---"
Get-ChildItem -Recurse -Filter "JwtAuthFilter.java" |
    ForEach-Object {
        Get-Content $_.FullName
    }

Write-Host "`n--- JwtService.java ---"
Get-ChildItem -Recurse -Filter "JwtService.java" |
    ForEach-Object {
        Get-Content $_.FullName
    }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "4. POM / TESTCONTAINERS CONFIGURATION" -ForegroundColor Cyan
Write-Host "============================================================"

Write-Host "`n--- pom.xml ---"
Get-Content ".\pom.xml"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "5. CURRENT MAVEN TEST RESULT" -ForegroundColor Cyan
Write-Host "============================================================"

mvn test

$MavenExit = $LASTEXITCODE

Write-Host ""
Write-Host "Maven exit code: $MavenExit" -ForegroundColor Yellow

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "6. SUREFIRE FAILURE SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================"

if (Test-Path ".\target\surefire-reports") {

    Get-ChildItem ".\target\surefire-reports" -File |
        Sort-Object Name |
        ForEach-Object {

            Write-Host ""
            Write-Host "===== $($_.Name) =====" -ForegroundColor Yellow

            $content = Get-Content $_.FullName -Raw

            if (
                $content -match "Failures: [1-9]" -or
                $content -match "Errors: [1-9]" -or
                $content -match "ERROR" -or
                $content -match "FAILURE"
            ) {
                Write-Host $content
            }
        }

} else {
    Write-Host "No surefire-reports directory found." -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "7. TESTCONTAINERS / DOCKER ENVIRONMENT" -ForegroundColor Cyan
Write-Host "============================================================"

Write-Host "`n--- docker info ---"
docker info

Write-Host "`n--- environment variables ---"
Get-ChildItem Env: |
    Where-Object {
        $_.Name -match "DOCKER|TESTCONTAINERS"
    } |
    Sort-Object Name |
    Format-Table -AutoSize

Write-Host "`n--- Docker named pipes ---"
Get-ChildItem "\\.\pipe\" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match "docker"
    } |
    Select-Object Name

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "8. DATABASE / REDIS HEALTH" -ForegroundColor Cyan
Write-Host "============================================================"

Write-Host "`n--- PostgreSQL ---"
docker compose exec postgres pg_isready -U fefo -d fefo

Write-Host "`n--- Redis ---"
docker compose exec redis redis-cli ping

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "9. FLYWAY STATE" -ForegroundColor Cyan
Write-Host "============================================================"

docker compose exec postgres psql -U fefo -d fefo -c "
SELECT installed_rank,
       version,
       description,
       checksum,
       success
FROM flyway_schema_history
ORDER BY installed_rank;
"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "10. BUILD WITHOUT TESTS" -ForegroundColor Cyan
Write-Host "============================================================"

mvn clean package -DskipTests

$BuildExit = $LASTEXITCODE

Write-Host ""
Write-Host "Build exit code: $BuildExit" -ForegroundColor Yellow

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "11. REBUILD BACKEND CONTAINER" -ForegroundColor Cyan
Write-Host "============================================================"

Set-Location $Root

docker compose build backend

$DockerBuildExit = $LASTEXITCODE

Write-Host ""
Write-Host "Docker backend build exit code: $DockerBuildExit" -ForegroundColor Yellow

docker compose up -d backend

Write-Host ""
Write-Host "Waiting for backend..."
Start-Sleep -Seconds 10

docker compose ps

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "12. FINAL API SMOKE TEST" -ForegroundColor Cyan
Write-Host "============================================================"

$BaseUrl = "http://localhost:8080"

try {

    $login = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/auth/login" `
        -Method POST `
        -ContentType "application/json" `
        -Body '{"username":"admin","password":"password"}'

    $token = $login.accessToken

    if ($token) {
        Write-Host "[PASS] Login" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] Login did not return accessToken" -ForegroundColor Red
    }

    $Headers = @{
        Authorization = "Bearer $token"
    }

    $products = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/products" `
        -Headers $Headers

    Write-Host "[PASS] Products API" -ForegroundColor Green

    $batches = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/batches" `
        -Headers $Headers

    Write-Host "[PASS] Batches API" -ForegroundColor Green

    $dashboard = Invoke-RestMethod `
        -Uri "$BaseUrl/api/v1/dashboard/summary" `
        -Headers $Headers

    Write-Host "[PASS] Dashboard API" -ForegroundColor Green

    $openapi = Invoke-RestMethod `
        -Uri "$BaseUrl/v3/api-docs"

    Write-Host "[PASS] OpenAPI" -ForegroundColor Green

}
catch {
    Write-Host "[FAIL] API smoke test: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "13. DATABASE INVARIANTS" -ForegroundColor Cyan
Write-Host "============================================================"

docker compose exec postgres psql -U fefo -d fefo -c "
SELECT
    COUNT(*) AS invalid_inventory_rows
FROM inventory_batches
WHERE available_quantity < 0
   OR reserved_quantity < 0
   OR available_quantity + reserved_quantity > total_quantity;
"

docker compose exec postgres psql -U fefo -d fefo -c "
SELECT
    idempotency_key,
    endpoint,
    COUNT(*)
FROM idempotency_keys
GROUP BY idempotency_key, endpoint
HAVING COUNT(*) > 1;
"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "14. REDIS LOCK CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================"

$locks = docker compose exec redis redis-cli --scan --pattern "fefo:*lock*" 2>$null

if ([string]::IsNullOrWhiteSpace(($locks -join ""))) {
    Write-Host "[PASS] No leftover FEFO Redis locks" -ForegroundColor Green
}
else {
    Write-Host "[WARN] Redis lock keys found:" -ForegroundColor Yellow
    $locks
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "15. FINAL DOCKER STATUS" -ForegroundColor Cyan
Write-Host "============================================================"

docker compose ps

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "16. FINAL RESULT" -ForegroundColor Cyan
Write-Host "============================================================"

if ($MavenExit -eq 0) {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "             ALL MAVEN TESTS PASSED" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""

}
else {

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "MAVEN TESTS STILL HAVE FAILURES/ERRORS" -ForegroundColor Yellow
    Write-Host "The complete Surefire output is printed above." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

}

Write-Host "Maven exit code : $MavenExit"
Write-Host "Build exit code  : $BuildExit"
Write-Host "Docker build     : $DockerBuildExit"

Write-Host ""
Write-Host "DONE." -ForegroundColor Cyan
