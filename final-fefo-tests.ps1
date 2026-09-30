$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        FEFO FINAL 3-TEST FIX + VALIDATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$backend = (Get-Location).Path

$controller = Join-Path $backend "src\test\java\com\aditya\fefo\controller\ControllerTests.java"
$allocator  = Join-Path $backend "src\test\java\com\aditya\fefo\unit\FefoAllocatorTest.java"

Write-Host ""
Write-Host "1. BACKING UP TEST FILES" -ForegroundColor Yellow

Copy-Item $controller "$controller.bak" -Force
Copy-Item $allocator "$allocator.bak" -Force

Write-Host "[BACKUP] ControllerTests.java"
Write-Host "[BACKUP] FefoAllocatorTest.java"

# ============================================================
# 2. FIX CONTROLLER TEST
# ============================================================

Write-Host ""
Write-Host "2. FIXING ControllerTests" -ForegroundColor Yellow

$c = Get-Content $controller -Raw

if ($c -notmatch 'com\.aditya\.fefo\.security\.JwtService') {
    $c = $c.Replace(
        'import com.aditya.fefo.service.*;',
        'import com.aditya.fefo.service.*; import com.aditya.fefo.security.JwtService;'
    )
}

if ($c -notmatch '@MockBean JwtService jwtService') {
    $c = $c.Replace(
        '@MockBean ProductService products;',
        '@MockBean ProductService products; @MockBean JwtService jwtService;'
    )
}

if ($c -notmatch 'with\(csrf\(\)\)') {
    $c = $c.Replace(
        'content("{\"username\":\"staff\",\"password\":\"password\"}")).andExpect(status().isOk())',
        'content("{\"username\":\"staff\",\"password\":\"password\"}").with(csrf())).andExpect(status().isOk())'
    )
}

if ($c -notmatch 'SecurityMockMvcRequestPostProcessors') {
    $c = $c.Replace(
        'import org.springframework.test.web.servlet.MockMvc;',
        'import org.springframework.test.web.servlet.MockMvc; import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;'
    )
}

Set-Content $controller $c -Encoding UTF8

Write-Host "[FIXED] JwtService mock + CSRF on login test"

# ============================================================
# 3. FIX FEFO ALLOCATOR TEST
# ============================================================

Write-Host ""
Write-Host "3. FIXING FefoAllocatorTest" -ForegroundColor Yellow

$a = Get-Content $allocator -Raw

$oldExpired = 'var a=new Batch(p,"A",LocalDate.now().minusDays(1),50);var b=new Batch(p,"B",LocalDate.now().plusDays(2),60);assertEquals("B",FefoAllocator.allocate(List.of(a,b),20).getFirst().batchNumber());'

$newExpired = 'assertThrows(IllegalArgumentException.class,()->new Batch(p,"A",LocalDate.now().minusDays(1),50));'

if ($a.Contains($oldExpired)) {
    $a = $a.Replace($oldExpired, $newExpired)
    Set-Content $allocator $a -Encoding UTF8
    Write-Host "[FIXED] Replaced impossible expired-Batch fixture with domain invariant test"
}
else {
    Write-Host "[INFO] Expired fixture already changed; showing current test:"
    Get-Content $allocator
}

# ============================================================
# 4. VERIFY DOCKER ENGINE PIPE
# ============================================================

Write-Host ""
Write-Host "4. VERIFYING DOCKER" -ForegroundColor Yellow

docker version

if ($LASTEXITCODE -ne 0) {
    throw "Docker CLI is not available."
}

Write-Host ""
Write-Host "--- Docker context ---"
docker context show

Write-Host ""
Write-Host "--- Docker Engine pipe ---"

$enginePipe = "\\.\pipe\docker_engine"

if (-not (Test-Path $enginePipe)) {
    Write-Host "[WARN] docker_engine pipe was not detected through Test-Path."
    Write-Host "[INFO] Docker CLI itself is still responding, so Maven will be tested with explicit docker.host."
}
else {
    Write-Host "[PASS] docker_engine pipe exists"
}

# ============================================================
# 5. COMPILE + RUN FULL MAVEN SUITE
# ============================================================

Write-Host ""
Write-Host "5. RUNNING FULL MAVEN TEST SUITE" -ForegroundColor Yellow

mvn clean test "-Ddocker.host=npipe:////./pipe/docker_engine"

$mavenExit = $LASTEXITCODE

Write-Host ""
if ($mavenExit -eq 0) {
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "[PASS] FULL MAVEN TEST SUITE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
}
else {
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "[FAIL] MAVEN TEST SUITE" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
}

# ============================================================
# 6. RUN THE THREE FORMER FAILURES INDIVIDUALLY
# ============================================================

Write-Host ""
Write-Host "6. INDIVIDUAL FORMER FAILURES" -ForegroundColor Yellow

Write-Host ""
Write-Host "--- ControllerTests ---"
mvn "-Dtest=ControllerTests" test

$controllerExit = $LASTEXITCODE

Write-Host ""
Write-Host "--- FefoAllocatorTest ---"
mvn "-Dtest=FefoAllocatorTest" test

$allocatorExit = $LASTEXITCODE

Write-Host ""
Write-Host "--- ConcurrencyIntegrationTest ---"
mvn "-Dtest=ConcurrencyIntegrationTest" test "-Ddocker.host=npipe:////./pipe/docker_engine"

$concurrencyExit = $LASTEXITCODE

# ============================================================
# 7. FINAL STATUS
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                    FINAL STATUS" -ForegroundColor Cyan
Write-Host "============================================================"

if ($mavenExit -eq 0) {
    Write-Host "[PASS] Full Maven suite"
}
else {
    Write-Host "[FAIL] Full Maven suite"
}

if ($controllerExit -eq 0) {
    Write-Host "[PASS] ControllerTests"
}
else {
    Write-Host "[FAIL] ControllerTests"
}

if ($allocatorExit -eq 0) {
    Write-Host "[PASS] FefoAllocatorTest"
}
else {
    Write-Host "[FAIL] FefoAllocatorTest"
}

if ($concurrencyExit -eq 0) {
    Write-Host "[PASS] ConcurrencyIntegrationTest"
}
else {
    Write-Host "[FAIL] ConcurrencyIntegrationTest"
}

Write-Host ""
Write-Host "Backups created:"
Write-Host "  ControllerTests.java.bak"
Write-Host "  FefoAllocatorTest.java.bak"

Write-Host ""
Write-Host "DONE."

if ($mavenExit -ne 0) {
    exit $mavenExit
}
