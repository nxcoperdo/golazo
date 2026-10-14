# Prueba de integración de la API contra el Postgres de docker-compose (db y api deben estar arriba).
# Uso (PowerShell, desde backend/):  ./scripts/integration-test.ps1
# Notas:
#  - Crea y borra datos con correos @itest.co.
#  - /auth tiene límite de 10 peticiones/min por IP: no la corras varias veces seguidas.
#  - Activa las canchas con SQL (pago aprobado + periodo vigente); el flujo real con admin está en integration-test-2.ps1.
#  - Envía el cuerpo en bytes UTF-8 (PowerShell 5.1 usaría Latin-1 y rompería las tildes).
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
$base = 'http://127.0.0.1:3000/v1'
$script:pass = 0; $script:fail = 0

function Call($method, $path, $body, $token) {
  $h = @{}; if ($token) { $h.Authorization = "Bearer $token" }
  try {
    $args2 = @{ Method = $method; Uri = "$base$path"; Headers = $h; ContentType = 'application/json' }
    if ($body) { $args2.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6)) }
    $r = Invoke-RestMethod @args2
    return @{ code = 200; body = $r }
  } catch {
    $code = [int]$_.Exception.Response.StatusCode
    $msg = $_.ErrorDetails.Message
    $j = $null; try { $j = $msg | ConvertFrom-Json } catch {}
    return @{ code = $code; body = $j; raw = $msg }
  }
}
function Check($name, $cond, $detail) {
  if ($cond) { $script:pass++; Write-Host "  OK   $name" } else { $script:fail++; Write-Host "  FAIL $name  -> $detail" -ForegroundColor Red }
}
function Sql($q) { $q | docker compose exec -T db psql -U golazo -d golazo -t -A 2>&1 }
function Activate($id) {
  Sql @"
WITH p AS (
  INSERT INTO payments (kind, court_id, payer_id, amount, proof_path, status, reviewed_at)
  SELECT 'subscription', c.id, c.owner_id, 100000, 'seed', 'approved', now() FROM courts c WHERE c.id = '$id'
  RETURNING id, court_id)
INSERT INTO subscription_periods (court_id, payment_id, starts_on, ends_on)
SELECT court_id, id, current_date, current_date + 30 FROM p;
UPDATE courts SET status = 'active' WHERE id = '$id';
"@ | Out-Null
}
function Iso($d) { $d.ToUniversalTime().ToString("yyyy-MM-ddTHH:00:00Z") }

# Limpieza previa de datos de prueba
Sql "DELETE FROM notifications WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co'); DELETE FROM subscription_periods WHERE court_id IN (SELECT id FROM courts WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co')); DELETE FROM payments WHERE court_id IN (SELECT id FROM courts WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co')); DELETE FROM bookings WHERE player_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co') OR court_id IN (SELECT id FROM courts WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co')); DELETE FROM courts WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co'); DELETE FROM users WHERE email LIKE '%@itest.co';" | Out-Null

Write-Host "== Registro"
$own = (Call Post /auth/register @{name='Dueno Test';email='dueno@itest.co';password='clave-segura-1';phone='3001112233';asOwner=$true}).body
$a = (Call Post /auth/register @{name='Jugador A';email='a@itest.co';password='clave-segura-1';phone='3002223344'}).body
$b = (Call Post /auth/register @{name='Jugador B';email='b@itest.co';password='clave-segura-1';phone='3003334455'}).body
Check "dueño con rol owner" ($own.user.role -eq 'owner') $own.user.role
Check "jugador con rol player" ($a.user.role -eq 'player') $a.user.role
$ot = $own.accessToken; $at = $a.accessToken; $bt = $b.accessToken

Write-Host "== Canchas (dueño)"
$c1 = Call Post /owner/courts @{name='Cancha Con Anticipo';city="Bogotá";address='Cra 7 # 10-20';lat=4.711;lng=-74.072;covered=$true;pricePerHour=90000;openHour=0;closeHour=24;requiresDeposit=$true;depositPercent=40} $ot
Check "crear cancha -> 201/200" ($c1.code -eq 200 -or $c1.code -eq 201) "$($c1.code) $($c1.raw)"
Check "nace en estado pending" ($c1.body.status -eq 'pending') $c1.body.status
$court1 = $c1.body.id
$c2 = Call Post /owner/courts @{name='Cancha Sin Anticipo';city='Medellín';address='Calle 10 # 5-5';lat=6.244;lng=-75.581;covered=$false;pricePerHour=70000;openHour=0;closeHour=24;requiresDeposit=$false} $ot
$court2 = $c2.body.id
Check "jugador NO puede crear cancha (403)" ((Call Post /owner/courts @{name='X';city='Y';address='Z';lat=1;lng=1;covered=$true;pricePerHour=5000;openHour=1;closeHour=2;requiresDeposit=$false} $at).code -eq 403) ""
Check "horario inválido -> 400" ((Call Post /owner/courts @{name='Mala';city="Bogotá";address='Cra 1 # 1-1';lat=4;lng=-74;covered=$true;pricePerHour=5000;openHour=10;closeHour=10;requiresDeposit=$false} $ot).code -eq 400) ""

$pm = Call Put "/owner/courts/$court1/payment-methods" @{methods=@(@{label='Nequi';account='300 111 2233';holder='Dueno Test'})} $ot
Check "cuentas de cobro guardadas" ($pm.body.paymentMethods.Count -eq 1) "$($pm.code) $($pm.raw)"

Write-Host "== Visibilidad (aún pendientes)"
$pub = Call Get '/courts?city=Bogot%C3%A1' $null $null
Check "cancha pendiente NO aparece en el listado" (@($pub.body | Where-Object { $_.id -eq $court1 }).Count -eq 0) ""
Check "detalle de cancha pendiente -> 404" ((Call Get "/courts/$court1" $null $null).code -eq 404) ""
Check "reservar cancha pendiente -> 404" ((Call Post /bookings @{courtId=$court1;startAt=(Iso (Get-Date).AddDays(2));hours=1} $at).code -eq 404) ""

Write-Host "== Activación (simula al admin) y listado"
Activate $court1; Activate $court2
$pub = Call Get '/courts?city=Bogot%C3%A1' $null $null
Check "ahora aparece en Bogotá" (@($pub.body | Where-Object { $_.id -eq $court1 }).Count -eq 1) ""
Check "filtro de ciudad excluye Medellín" (@($pub.body | Where-Object { $_.id -eq $court2 }).Count -eq 0) ""
$near = Call Get '/courts?lat=6.25&lng=-75.57&radiusKm=50' $null $null
Check "búsqueda por cercanía a Medellín trae solo la de Medellín" ($near.body.Count -eq 1 -and $near.body[0].id -eq $court2) "n=$($near.body.Count)"
Check "distancia calculada" ($near.body[0].distanceM -gt 0) ""
Check "filtro techada" (@((Call Get '/courts?covered=true' $null $null).body | Where-Object { $_.id -eq $court2 }).Count -eq 0) ""
Check "filtro precio máximo" (@((Call Get '/courts?maxPrice=80000' $null $null).body | Where-Object { $_.id -eq $court1 }).Count -eq 0) ""
Check "parámetro inválido -> 400" ((Call Get '/courts?maxPrice=abc' $null $null).code -eq 400) ""

Write-Host "== Reservas: anticipo y doble reserva"
$day = (Get-Date).ToUniversalTime().Date.AddDays(2).AddHours(15)   # 10:00 a. m. Colombia
$r1 = Call Post /bookings @{courtId=$court1;startAt=(Iso $day);hours=2} $at
Check "reserva 2 h creada" ($r1.code -eq 200 -or $r1.code -eq 201) "$($r1.code) $($r1.raw)"
Check "total = precio x horas (180000)" ($r1.body.total -eq 180000) $r1.body.total
Check "anticipo 40% sobre el total (72000)" ($r1.body.deposit -eq 72000) $r1.body.deposit
Check "estado pending_payment" ($r1.body.status -eq 'pending_payment') $r1.body.status
Check "trae cuentas de pago" ($r1.body.paymentMethods.Count -eq 1) ""
Check "no es de última hora" ($r1.body.lastMinute -eq $false) ""

$r2 = Call Post /bookings @{courtId=$court1;startAt=(Iso $day.AddHours(1));hours=1} $bt
Check "traslape (otro jugador) -> 409 SLOT_TAKEN" ($r2.code -eq 409 -and $r2.body.code -eq 'SLOT_TAKEN') "$($r2.code) $($r2.raw)"
$r3 = Call Post /bookings @{courtId=$court1;startAt=(Iso $day.AddHours(2));hours=1} $bt
Check "bloque contiguo sí se permite" ($r3.code -eq 200 -or $r3.code -eq 201) "$($r3.code) $($r3.raw)"

$dateStr = $day.AddHours(-5).ToString('yyyy-MM-dd')
$av = Call Get "/courts/$court1/availability?date=$dateStr" $null $null
$h10 = $av.body.hours | Where-Object { $_.hour -eq 10 }; $h11 = $av.body.hours | Where-Object { $_.hour -eq 11 }
$h12 = $av.body.hours | Where-Object { $_.hour -eq 12 }; $h13 = $av.body.hours | Where-Object { $_.hour -eq 13 }
Check "disponibilidad: 10 y 11 ocupadas" ($h10.free -eq $false -and $h11.free -eq $false) ""
Check "disponibilidad: 12 ocupada (jugador B), 13 libre" ($h12.free -eq $false -and $h13.free -eq $true) ""
Check "fecha inválida -> 400" ((Call Get "/courts/$court1/availability?date=2026-02-30" $null $null).code -eq 400) ""

Write-Host "== Validaciones de reserva"
Check "5 horas -> 400" ((Call Post /bookings @{courtId=$court1;startAt=(Iso $day.AddHours(6));hours=5} $at).code -eq 400) ""
Check "hora en el pasado -> 422" ((Call Post /bookings @{courtId=$court1;startAt=(Iso (Get-Date).AddDays(-1));hours=1} $at).code -eq 422) ""
Check "sin sesión -> 401" ((Call Post /bookings @{courtId=$court1;startAt=(Iso $day);hours=1} $null).code -eq 401) ""
Check "monto enviado por el cliente se rechaza (400)" ((Call Post /bookings @{courtId=$court1;startAt=(Iso $day.AddHours(8));hours=1;total=1} $at).code -eq 400) ""

Write-Host "== Última hora (<8 h)"
$soon = (Get-Date).ToUniversalTime().AddHours(2); $soon = $soon.Date.AddHours($soon.Hour)
$ls = Call Post /bookings @{courtId=$court2;startAt=(Iso $soon);hours=1} $at
Check "reserva de última hora creada" ($ls.code -eq 200 -or $ls.code -eq 201) "$($ls.code) $($ls.raw)"
Check "marcada lastMinute" ($ls.body.lastMinute -eq $true) ""
Check "anticipo 30% aunque la cancha no lo exija (21000)" ($ls.body.deposit -eq 21000) $ls.body.deposit
Check "sin pago hecho se puede cancelar" ((Call Post "/bookings/$($ls.body.id)/cancel" $null $at).body.status -eq 'cancelled') ""

Write-Host "== Cancelación"
$far = (Get-Date).ToUniversalTime().Date.AddDays(5).AddHours(15)
$ok = Call Post /bookings @{courtId=$court2;startAt=(Iso $far);hours=1} $at
Check "cancha sin anticipo y >8h: confirmada al instante" ($ok.body.status -eq 'confirmed' -and $ok.body.deposit -eq 0) "$($ok.raw)"
Check "confirmada con 5 días: cancelable" ($ok.body.cancellable -eq $true) ""
$can = Call Post "/bookings/$($ok.body.id)/cancel" $null $at
Check "cancelación gratis OK" ($can.body.status -eq 'cancelled') ""
$near2 = (Get-Date).ToUniversalTime().AddHours(12); $near2 = $near2.Date.AddHours($near2.Hour)
$mid = Call Post /bookings @{courtId=$court2;startAt=(Iso $near2);hours=1} $at
Check "reserva a 12 h sin anticipo: confirmada" ($mid.body.status -eq 'confirmed') "$($mid.raw)"
$no = Call Post "/bookings/$($mid.body.id)/cancel" $null $at
Check "confirmada con <24 h: NO cancelable (409)" ($no.code -eq 409 -and $no.body.code -eq 'NOT_CANCELLABLE') "$($no.code) $($no.raw)"
Check "ajena: otro jugador no la ve (404)" ((Call Get "/bookings/$($mid.body.id)" $null $bt).code -eq 404) ""
Check "ajena: otro jugador no la cancela (404)" ((Call Post "/bookings/$($mid.body.id)/cancel" $null $bt).code -eq 404) ""
$mine = Call Get /bookings/mine $null $at
Check "mis reservas lista las propias" ($mine.body.Count -ge 3) "n=$($mine.body.Count)"

Write-Host "== Límites y requisitos"
$u = Call Post /auth/register @{name='Jugador C';email='c@itest.co';password='clave-segura-1';phone='3004445566'}
$ct = $u.body.accessToken
Sql "UPDATE users SET phone=NULL WHERE email='c@itest.co';" | Out-Null
$np = Call Post /bookings @{courtId=$court1;startAt=(Iso $day.AddHours(10));hours=1} $ct
Check "sin celular -> 422 PHONE_REQUIRED" ($np.code -eq 422 -and $np.body.code -eq 'PHONE_REQUIRED') "$($np.code) $($np.raw)"
Sql "UPDATE users SET phone='3004445566' WHERE email='c@itest.co';" | Out-Null
1..3 | ForEach-Object { Call Post /bookings @{courtId=$court1;startAt=(Iso $day.AddHours(10 + $_ * 2));hours=1} $ct | Out-Null }
$many = Call Post /bookings @{courtId=$court1;startAt=(Iso $day.AddHours(20));hours=1} $ct
Check "4ª reserva sin pagar -> 409 TOO_MANY_UNPAID" ($many.code -eq 409 -and $many.body.code -eq 'TOO_MANY_UNPAID') "$($many.code) $($many.raw)"

Write-Host "== Propiedad de canchas"
$o2 = (Call Post /auth/register @{name='Otro Dueno';email='dueno2@itest.co';password='clave-segura-1';phone='3009998877';asOwner=$true}).body
Check "otro dueño no edita mi cancha (404)" ((Call Patch "/owner/courts/$court1" @{name='Hackeada'} $o2.accessToken).code -eq 404) ""
$upd = Call Patch "/owner/courts/$court1" @{pricePerHour=95000} $ot
Check "el dueño sí edita (precio 95000)" ($upd.body.pricePerHour -eq 95000) "$($upd.code) $($upd.raw)"

# Limpieza
Sql "DELETE FROM notifications WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co'); DELETE FROM subscription_periods WHERE court_id IN (SELECT id FROM courts WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co')); DELETE FROM payments WHERE court_id IN (SELECT id FROM courts WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co')); DELETE FROM bookings WHERE player_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co') OR court_id IN (SELECT id FROM courts WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co')); DELETE FROM courts WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@itest.co'); DELETE FROM users WHERE email LIKE '%@itest.co';" | Out-Null
Write-Host ""
Write-Host "RESULTADO: $script:pass OK, $script:fail FALLAS"
