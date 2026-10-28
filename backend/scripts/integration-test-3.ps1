# Prueba de integración 3: ciudades, config de mensualidad, reservas del dueño, bloqueos, avisos al dueño,
# recordatorios, pausar/reanudar cancha y verificación de correo.
# Uso (desde backend/):  ./scripts/integration-test-3.ps1            (verificación NO exigida)
#                        ./scripts/integration-test-3.ps1 -Enforced  (con la API levantada con REQUIRE_EMAIL_VERIFICATION=1)
param([switch]$Enforced)
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
$base = 'http://127.0.0.1:3000/v1'
$script:pass = 0; $script:fail = 0
$script:ids = @()
$pwd1 = 'clave-segura-1'

function Call($method, $path, $body, $token) {
  $h = @{}; if ($token) { $h.Authorization = "Bearer $token" }
  try {
    $a = @{ Method = $method; Uri = "$base$path"; Headers = $h; ContentType = 'application/json' }
    if ($body) { $a.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6)) }
    return @{ code = 200; body = (Invoke-RestMethod @a) }
  } catch {
    $msg = $_.ErrorDetails.Message; $j = $null; try { $j = $msg | ConvertFrom-Json } catch {}
    return @{ code = [int]$_.Exception.Response.StatusCode; body = $j; raw = $msg }
  }
}
function Check($name, $cond, $detail) {
  if ($cond) { $script:pass++; Write-Host "  OK   $name" } else { $script:fail++; Write-Host "  FAIL $name  -> $detail" -ForegroundColor Red }
}
function Sql($q) { $q | docker compose exec -T db psql -U golazo -d golazo -t -A 2>&1 }
function Iso($d) { $d.ToUniversalTime().ToString("yyyy-MM-ddTHH:00:00Z") }
function Has($list, $id) { @($list | Where-Object { $_.id -eq $id }).Count -ge 1 }
function Titles($token) { @((Call Get /notifications $null $token).body.items | ForEach-Object { $_.title }) }
function Register($name, $email, $owner) {
  $r = (Call Post /auth/register @{acceptTerms=$true; name = $name; email = $email; password = $pwd1; phone = '3001112233'; asOwner = $owner }).body
  $script:ids += $r.user.id
  return $r
}
function Activate($id) {
  Sql @"
WITH p AS (
  INSERT INTO payments (kind, court_id, payer_id, amount, proof_path, status, reviewed_at)
  SELECT 'subscription', c.id, c.owner_id, 100000, 'seed', 'approved', now() FROM courts c WHERE c.id = '$id'
  RETURNING id, court_id)
INSERT INTO subscription_periods (court_id, payment_id, starts_on, ends_on)
SELECT court_id, id, (now() AT TIME ZONE 'America/Bogota')::date, (now() AT TIME ZONE 'America/Bogota')::date + 30 FROM p;
UPDATE courts SET status = 'active' WHERE id = '$id';
"@ | Out-Null
}
function MailToken($pattern) {
  Start-Sleep 1
  $log = docker compose logs --no-log-prefix --since 2m api 2>&1 | Out-String
  $m = [regex]::Matches($log, $pattern)
  if ($m.Count) { return $m[$m.Count - 1].Groups[1].Value } else { return '' }
}
function Cleanup {
  $list = ($script:ids | ForEach-Object { "'$_'" }) -join ','
  if (-not $list) { $list = "'00000000-0000-0000-0000-000000000000'" }
  Sql @"
CREATE TEMP TABLE tu AS SELECT id FROM users WHERE email LIKE '%@itest.co' OR id IN ($list);
CREATE TEMP TABLE tc AS SELECT id FROM courts WHERE owner_id IN (SELECT id FROM tu);
DELETE FROM review_reports WHERE reporter_id IN (SELECT id FROM tu) OR review_id IN (SELECT id FROM reviews WHERE author_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc));
DELETE FROM reviews WHERE author_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM subscription_periods WHERE court_id IN (SELECT id FROM tc);
DELETE FROM payments WHERE payer_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM refunds WHERE player_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM bookings WHERE player_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM courts WHERE id IN (SELECT id FROM tc);
DELETE FROM users WHERE id IN (SELECT id FROM tu);
"@ | Out-Null
}
function NewCourt($token, $name, $city, $deposit) {
  (Call Post /owner/courts @{ name = $name; city = $city; address = 'Cra 9 # 9-9'; lat = 4.7; lng = -74.05; covered = $true; pricePerHour = 100000; openHour = 0; closeHour = 24; requiresDeposit = $deposit } $token).body
}

Cleanup
$admExists = docker compose run --rm migrate node dist/scripts/create-admin.js admin@itest.co "Admin Test" "clave-admin-larga-1" 2>&1 | Select-Object -Last 1
$adm = (Call Post /auth/login @{ email = 'admin@itest.co'; password = 'clave-admin-larga-1' }).body
$script:ids += $adm.user.id
$at = $adm.accessToken
$day = (Get-Date).ToUniversalTime().Date.AddDays(2).AddHours(15)   # 10:00 a. m. Colombia

if ($Enforced) {
  Write-Host "== Verificación de correo EXIGIDA"
  $own = Register 'Dueno Verif' 'dueno1@itest.co' $true
  $u = Register 'Jugador Verif' 'p1@itest.co' $false
  Check "recién registrado: emailVerified = false" ($u.user.emailVerified -eq $false) ""
  $court = (NewCourt $own.accessToken 'Cancha V' 'Bogotá' $false)
  Check "dueño sin verificar no publica canchas (403)" ((Call Post /owner/courts @{ name = 'X Y Z'; city = 'Bogotá'; address = 'Cra 1 # 1-1'; lat = 4; lng = -74; covered = $true; pricePerHour = 5000; openHour = 1; closeHour = 2; requiresDeposit = $false } $own.accessToken).body.code -eq 'EMAIL_NOT_VERIFIED') ""
  # Para probar la reserva se necesita una cancha activa: la crea un dueño verificado por SQL.
  Sql "UPDATE users SET email_verified_at = now() WHERE email = 'dueno1@itest.co';" | Out-Null
  $court = NewCourt $own.accessToken 'Cancha V' 'Bogotá' $false
  Activate $court.id
  $r = Call Post /bookings @{ courtId = $court.id; startAt = (Iso $day); hours = 1 } $u.accessToken
  Check "jugador sin verificar no reserva (403 EMAIL_NOT_VERIFIED)" ($r.code -eq 403 -and $r.body.code -eq 'EMAIL_NOT_VERIFIED') "$($r.code) $($r.raw)"
  $tok = MailToken 'verify-email\?token=([A-Za-z0-9_-]+)'
  Check "se envió el correo de confirmación" ($tok.Length -gt 20) "sin token"
  Check "confirmar el correo" ((Call Post /auth/verify-email @{ token = $tok } $null).code -eq 200) ""
  $r = Call Post /bookings @{ courtId = $court.id; startAt = (Iso $day); hours = 1 } $u.accessToken
  Check "ya verificado puede reservar" ($r.code -eq 200 -and $r.body.status -eq 'confirmed') "$($r.code) $($r.raw)"
  Check "exigencia no afecta lecturas (listado público)" ((Call Get '/courts' $null $null).code -eq 200) ""
  Cleanup
  Write-Host ""; Write-Host "RESULTADO (verificación exigida): $script:pass OK, $script:fail FALLAS"
  return
}

Write-Host "== Ciudades y configuración"
$own = Register 'Dueno Uno' 'dueno1@itest.co' $true; $ot = $own.accessToken
$own2 = Register 'Dueno Dos' 'dueno2@itest.co' $true; $ot2 = $own2.accessToken
$p1 = Register 'Pablo Perez' 'p1@itest.co' $false; $p1t = $p1.accessToken
$p2 = Register 'Maria Gomez' 'p2@itest.co' $false; $p2t = $p2.accessToken
$c1 = NewCourt $ot 'Cancha Libre' 'Bogotá' $false
$c2 = NewCourt $ot 'Cancha Pendiente' 'Cali' $false
Activate $c1.id
$cities = (Call Get /cities $null $null).body
Check "ciudades solo incluye las activas (Bogotá sí, Cali no)" ((@($cities | Where-Object { $_.city -eq 'Bogotá' }).Count -eq 1) -and (@($cities | Where-Object { $_.city -eq 'Cali' }).Count -eq 0)) ($cities | ConvertTo-Json -Compress)
$cfg = Call Get /config/subscription $null $ot
Check "dueño ve precio y cuentas de la plataforma" ($cfg.body.price -eq 100000 -and $cfg.body.periodDays -eq 30 -and @($cfg.body.accounts).Count -ge 1) "$($cfg.code) $($cfg.raw)"
Check "jugador no ve la config (403)" ((Call Get /config/subscription $null $p1t).code -eq 403) ""
Check "sin sesión (401)" ((Call Get /config/subscription $null $null).code -eq 401) ""

Write-Host "== Avisos al dueño y su lista de reservas"
$b1 = (Call Post /bookings @{ courtId = $c1.id; startAt = (Iso $day.AddDays(5)); hours = 2 } $p1t).body
Check "reserva sin anticipo queda confirmada" ($b1.status -eq 'confirmed') $b1.status
Start-Sleep 1
$n = (Call Get /notifications $null $ot).body.items | Where-Object { $_.title -eq 'Nueva reserva confirmada' }
Check "dueño recibe aviso de la reserva con nombre y hora AM/PM" (@($n).Count -eq 1 -and $n.body -like '*Pablo*' -and $n.body -match '(AM|PM)') ($n | ConvertTo-Json -Compress)
$from = (Get-Date).ToString('yyyy-MM-dd'); $to = (Get-Date).AddDays(10).ToString('yyyy-MM-dd')
$list = (Call Get "/owner/bookings?from=$from&to=$to" $null $ot).body
$row = @($list | Where-Object { $_.id -eq $b1.id })
Check "dueño ve la reserva con jugador y celular" ($row.Count -eq 1 -and $row[0].playerName -eq 'Pablo Perez' -and $row[0].playerPhone -eq '3001112233' -and -not $row[0].isBlock) ($list | ConvertTo-Json -Compress)
Check "otro dueño no ve esa reserva" (@((Call Get "/owner/bookings?from=$from&to=$to" $null $ot2).body).Count -eq 0) ""
Check "jugador no entra a la lista del dueño (403)" ((Call Get /owner/bookings $null $p1t).code -eq 403) ""
Check "rango inválido -> 422/400" ((Call Get '/owner/bookings?from=2026-02-30' $null $ot).code -in 400, 422) ""
Check "filtro por estado" (@((Call Get "/owner/bookings?from=$from&to=$to&status=pending_review" $null $ot).body).Count -eq 0) ""
$cn = Call Post "/bookings/$($b1.id)/cancel" $null $p1t
Check "jugador cancela (faltan >24 h)" ($cn.body.status -eq 'cancelled') "$($cn.code) $($cn.raw)"
Start-Sleep 1
Check "dueño recibe aviso de la cancelación" (@(Titles $ot) -contains 'Reserva cancelada') ""
Check "las canceladas no aparecen por defecto" (-not (Has (Call Get "/owner/bookings?from=$from&to=$to" $null $ot).body $b1.id)) ""
Check "pero sí si se pide ese estado" (Has (Call Get "/owner/bookings?from=$from&to=$to&status=cancelled" $null $ot).body $b1.id) ""

Write-Host "== Bloqueo manual de horas"
$bk = Call Post "/owner/courts/$($c1.id)/blocks" @{ startAt = (Iso $day); hours = 2; note = 'Reservado por WhatsApp' } $ot
Check "dueño bloquea 2 horas" (($bk.code -eq 200) -and $bk.body.isBlock) "$($bk.code) $($bk.raw)"
$dateStr = $day.AddHours(-5).ToString('yyyy-MM-dd')
$av = (Call Get "/courts/$($c1.id)/availability?date=$dateStr" $null $null).body
Check "el bloqueo ocupa las horas en la disponibilidad pública" ((@($av.hours | Where-Object { $_.hour -in 10, 11 -and -not $_.free }).Count -eq 2) -and (@($av.hours | Where-Object { $_.hour -eq 12 -and $_.free }).Count -eq 1)) ""
$r = Call Post /bookings @{ courtId = $c1.id; startAt = (Iso $day.AddHours(1)); hours = 1 } $p1t
Check "jugador no puede reservar sobre un bloqueo (409)" ($r.code -eq 409 -and $r.body.code -eq 'SLOT_TAKEN') "$($r.code)"
Check "bloquear sobre otro bloqueo (409)" ((Call Post "/owner/courts/$($c1.id)/blocks" @{ startAt = (Iso $day); hours = 1 } $ot).code -eq 409) ""
$lst = (Call Get "/owner/bookings?from=$from&to=$to" $null $ot).body
$blkRow = @($lst | Where-Object { $_.id -eq $bk.body.id })
Check "el bloqueo se lista sin datos de jugador y con su nota" ($blkRow.Count -eq 1 -and $blkRow[0].isBlock -and $null -eq $blkRow[0].playerName -and $blkRow[0].note -eq 'Reservado por WhatsApp') ($blkRow | ConvertTo-Json -Compress)
Check "el bloqueo no aparece en 'mis reservas' del dueño" (@((Call Get /bookings/mine $null $ot).body).Count -eq 0) ""
Check "bloqueo en el pasado -> 422" ((Call Post "/owner/courts/$($c1.id)/blocks" @{ startAt = (Iso (Get-Date).AddDays(-1)); hours = 1 } $ot).code -eq 422) ""
Check "más de 4 horas -> 400" ((Call Post "/owner/courts/$($c1.id)/blocks" @{ startAt = (Iso $day.AddDays(1)); hours = 5 } $ot).code -eq 400) ""
Check "otro dueño no bloquea mi cancha (404)" ((Call Post "/owner/courts/$($c1.id)/blocks" @{ startAt = (Iso $day.AddDays(1)); hours = 1 } $ot2).code -eq 404) ""
Check "jugador no bloquea (403)" ((Call Post "/owner/courts/$($c1.id)/blocks" @{ startAt = (Iso $day.AddDays(1)); hours = 1 } $p1t).code -eq 403) ""
$st = (Call Get "/owner/stats?from=$from&to=$to" $null $ot).body
Check "los bloqueos no cuentan como ingresos ni reservas" ($st.bookings.confirmed -eq 0 -and $st.income -eq 0) ($st | ConvertTo-Json -Compress -Depth 4)
$b2 = (Call Post /bookings @{ courtId = $c1.id; startAt = (Iso $day.AddDays(3)); hours = 1 } $p2t).body
Check "el dueño no puede 'desbloquear' una reserva real (404)" ((Call Delete "/owner/blocks/$($b2.id)" $null $ot).code -eq 404) ""
Check "desbloquear (204)" ((Call Delete "/owner/blocks/$($bk.body.id)" $null $ot).code -eq 200) ""
$av = (Call Get "/courts/$($c1.id)/availability?date=$dateStr" $null $null).body
Check "las horas vuelven a estar libres" (@($av.hours | Where-Object { $_.hour -in 10, 11 -and $_.free }).Count -eq 2) ""
Check "desbloquear dos veces -> 404" ((Call Delete "/owner/blocks/$($bk.body.id)" $null $ot).code -eq 404) ""

Write-Host "== Recordatorio de reserva"
# Se mueve la reserva de p2 a "dentro de una hora" para simular que ya toca recordarla.
Sql "UPDATE bookings SET start_at = date_trunc('hour', now()) + interval '1 hour', end_at = date_trunc('hour', now()) + interval '2 hours', reminded_at = NULL WHERE id = '$($b2.id)';" | Out-Null
$j = (Call Post /admin/jobs/run $null $at).body
$rem = @((Call Get /notifications $null $p2t).body.items | Where-Object { $_.title -eq 'Tu partido es pronto' })
Check "jugador recibe el recordatorio con hora AM/PM" ($rem.Count -eq 1 -and $rem[0].body -match '(AM|PM)' -and $rem[0].body -like '*Cancha Libre*') "$($j | ConvertTo-Json -Compress) $($rem | ConvertTo-Json -Compress)"
Call Post /admin/jobs/run $null $at | Out-Null
Check "el recordatorio no se repite" (@((Call Get /notifications $null $p2t).body.items | Where-Object { $_.title -eq 'Tu partido es pronto' }).Count -eq 1) ""
$soon = (Get-Date).ToUniversalTime().AddHours(1); $soon = $soon.Date.AddHours($soon.Hour + 1)
$b3 = (Call Post /bookings @{ courtId = $c1.id; startAt = (Iso $soon); hours = 1 } $p1t).body
Sql "UPDATE bookings SET status = 'confirmed' WHERE id = '$($b3.id)';" | Out-Null
Call Post /admin/jobs/run $null $at | Out-Null
Check "reservas creadas con <2 h de anticipación no generan recordatorio inmediato" (@((Call Get /notifications $null $p1t).body.items | Where-Object { $_.title -eq 'Tu partido es pronto' }).Count -eq 0) ""

Write-Host "== Pausar y reanudar la cancha"
Check "dueño pausa su cancha" ((Call Post "/owner/courts/$($c1.id)/pause" $null $ot).body.status -eq 'suspended') ""
Check "pausada: no aparece en el buscador" (-not (Has (Call Get '/courts?city=Bogot%C3%A1' $null $null).body $c1.id)) ""
Check "pausar de nuevo -> 409" ((Call Post "/owner/courts/$($c1.id)/pause" $null $ot).code -eq 409) ""
Check "reanuda (mensualidad vigente)" ((Call Post "/owner/courts/$($c1.id)/resume" $null $ot).body.status -eq 'active') ""
Check "otro dueño no la pausa (404)" ((Call Post "/owner/courts/$($c1.id)/pause" $null $ot2).code -eq 404) ""
Call Post "/admin/courts/$($c1.id)/suspend" $null $at | Out-Null
$rs = Call Post "/owner/courts/$($c1.id)/resume" $null $ot
Check "suspendida por el admin: el dueño no la reanuda (403)" ($rs.code -eq 403 -and $rs.body.code -eq 'SUSPENDED_BY_ADMIN') "$($rs.code)"
Call Post "/admin/courts/$($c1.id)/reactivate" $null $at | Out-Null
Check "sin mensualidad no se puede reanudar (409)" ((Call Post "/owner/courts/$($c2.id)/resume" $null $ot).body.code -eq 'NO_ACTIVE_SUBSCRIPTION') ""
Check "una cancha pendiente no se 'pausa' (409)" ((Call Post "/owner/courts/$($c2.id)/pause" $null $ot).body.code -eq 'NOT_ACTIVE') ""

Write-Host "== Verificación de correo"
$nu = Register 'Nuevo Usuario' 'p3@itest.co' $false
Check "registro: emailVerified = false" ($nu.user.emailVerified -eq $false) ""
Check "/auth/me informa emailVerified" ((Call Get /auth/me $null $nu.accessToken).body.emailVerified -eq $false) ""
$vt = MailToken 'verify-email\?token=([A-Za-z0-9_-]+)'
Check "se envió el correo de confirmación con enlace" ($vt.Length -gt 20) "sin token en el log"
Check "token inventado -> 422" ((Call Post /auth/verify-email @{ token = ('x' * 43) } $null).code -eq 422) ""
Check "confirmar con el enlace" ((Call Post /auth/verify-email @{ token = $vt } $null).code -eq 200) ""
Check "ahora emailVerified = true" ((Call Get /auth/me $null $nu.accessToken).body.emailVerified -eq $true) ""
Check "el enlace no se reutiliza (422)" ((Call Post /auth/verify-email @{ token = $vt } $null).code -eq 422) ""
Check "reenviar estando verificado no falla" ((Call Post /auth/resend-verification $null $nu.accessToken).code -eq 200) ""
Check "sin sesión no reenvía (401)" ((Call Post /auth/resend-verification $null $null).code -eq 401) ""
Check "con la verificación apagada, un usuario sin verificar sí reserva" ((Call Post /bookings @{ courtId = $c1.id; startAt = (Iso $day.AddDays(6)); hours = 1 } $p1t).code -eq 200) ""

Cleanup
Write-Host ""
Write-Host "RESULTADO: $script:pass OK, $script:fail FALLAS"
