# Prueba de integración 2: pagos, comprobantes, mensualidades, admin, reseñas, jobs y cuenta.
# Requiere db y api arriba y las migraciones aplicadas. Uso (desde backend/): ./scripts/integration-test-2.ps1
# Crea/borra datos de prueba (correos @itest.co) y un admin admin@itest.co.
# Necesita curl.exe (viene con Windows 10+) para las subidas multipart.
# Ojo: la API ejecuta sus tareas programadas cada minuto; en muy raras ocasiones pueden adelantarse a una
# comprobación de 'tareas programadas'. Si falla solo esa, repite (esperando 1 minuto por el límite de /auth).
$ErrorActionPreference = 'Continue'   # docker compose escribe progreso en stderr
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
function Upload($path, $field, $file, $token) {
  $a = @('-s', '-w', '\n%{http_code}', '-X', 'POST', '-F', "$field=@$file")
  if ($token) { $a += @('-H', "Authorization: Bearer $token") }
  $a += "$base$path"
  $out = (& curl.exe @a) -join "`n"
  $lines = @($out -split "`n")
  $code = [int]$lines[-1]
  $json = if ($lines.Count -gt 1) { ($lines[0..($lines.Count - 2)] -join "`n") } else { '' }
  $body = $null; try { $body = $json | ConvertFrom-Json } catch {}
  return @{ code = $code; body = $body; raw = $json }
}
function Download($path, $token, $out) {
  $a = @('-s', '-o', $out, '-w', '%{http_code} %{content_type}')
  if ($token) { $a += @('-H', "Authorization: Bearer $token") }
  $a += "$base$path"
  return (& curl.exe @a)
}
function Check($name, $cond, $detail) {
  if ($cond) { $script:pass++; Write-Host "  OK   $name" } else { $script:fail++; Write-Host "  FAIL $name  -> $detail" -ForegroundColor Red }
}
function Sql($q) { $q | docker compose exec -T db psql -U golazo -d golazo -t -A 2>&1 }
function Iso($d) { $d.ToUniversalTime().ToString("yyyy-MM-ddTHH:00:00Z") }
function Has($list, $id) { @($list | Where-Object { $_.id -eq $id }).Count -ge 1 }
function Register($name, $email, $owner) {
  $r = (Call Post /auth/register @{acceptTerms=$true; name = $name; email = $email; password = $pwd1; phone = '3001112233'; asOwner = $owner }).body
  $script:ids += $r.user.id
  return $r
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

# --- Archivos de prueba ---
$png = Join-Path $env:TEMP 'golazo-test.png'
node scripts/make-test-image.mjs $png
$fake = Join-Path $env:TEMP 'golazo-fake.jpg'; Set-Content $fake 'esto no es una imagen' -Encoding ascii
$big = Join-Path $env:TEMP 'golazo-big.png'; [IO.File]::WriteAllBytes($big, (New-Object byte[] (6MB)))

Cleanup
"Preparando administrador..."
docker compose run --rm migrate node dist/scripts/create-admin.js admin@itest.co "Admin Test" "clave-admin-larga-1" 2>&1 | Select-Object -Last 1

Write-Host "== Roles y accesos"
$adm = (Call Post /auth/login @{ email = 'admin@itest.co'; password = 'clave-admin-larga-1' }).body
$script:ids += $adm.user.id
$at = $adm.accessToken
Check "admin inicia sesión con rol admin" ($adm.user.role -eq 'admin') $adm.user.role
$own = Register 'Dueno Uno' 'dueno1@itest.co' $true;   $ot = $own.accessToken
$p1 = Register 'Pablo Perez' 'p1@itest.co' $false;     $p1t = $p1.accessToken
$p2 = Register 'Maria Gomez' 'p2@itest.co' $false;     $p2t = $p2.accessToken
Check "jugador no entra a /admin (403)" ((Call Get /admin/metrics $null $p1t).code -eq 403) ""
Check "dueño no entra a /admin (403)" ((Call Get /admin/metrics $null $ot).code -eq 403) ""
Check "sin sesión no entra a /admin (401)" ((Call Get /admin/metrics $null $null).code -eq 401) ""

Write-Host "== Mensualidad y activación"
$c = (Call Post /owner/courts @{ name = 'Cancha Pagos'; city = 'Bogotá'; address = 'Cra 9 # 9-9'; lat = 4.7; lng = -74.05; covered = $true; pricePerHour = 100000; openHour = 0; closeHour = 24; requiresDeposit = $true; depositPercent = 40 } $ot).body
$court = $c.id
Check "la cancha nace pendiente" ($c.status -eq 'pending') $c.status
Check "sin sesión -> 401" ((Upload "/owner/courts/$court/subscription-payment" proof $png $null).code -eq 401) ""
Check "sin archivo -> 400" ((Call Post "/owner/courts/$court/subscription-payment" $null $ot).code -eq 400) ""
$r = Upload "/owner/courts/$court/subscription-payment" proof $fake $ot
Check "archivo que no es imagen -> 415" ($r.code -eq 415) "$($r.code) $($r.raw)"
$r = Upload "/owner/courts/$court/subscription-payment" proof $big $ot
Check "archivo de 6 MB -> 413" ($r.code -eq 413) "$($r.code) $($r.raw)"
$r = Upload "/owner/courts/$court/subscription-payment" proof $png $p1t
Check "jugador no sube mensualidad (403)" ($r.code -eq 403) "$($r.code)"
$sub = Upload "/owner/courts/$court/subscription-payment" proof $png $ot
Check "dueño sube comprobante de mensualidad" (($sub.code -eq 200 -or $sub.code -eq 201) -and $sub.body.amount -eq 100000) "$($sub.code) $($sub.raw)"
Check "segundo comprobante pendiente -> 409" ((Upload "/owner/courts/$court/subscription-payment" proof $png $ot).code -eq 409) ""
$d = (Call Get "/owner/courts/$court" $null $ot).body
Check "detalle del dueño marca pago en revisión" ($d.subscription.pendingReview -eq $true) ""
$list = (Call Get '/admin/payments?kind=subscription&status=pending' $null $at).body
Check "admin ve el pago pendiente" (Has $list $sub.body.paymentId) ""
$notiAdm = (Call Get /notifications $null $at).body
Check "admin recibió aviso" (@($notiAdm.items | Where-Object { $_.title -like 'Pago de mensualidad*' }).Count -ge 1) ""
$img = Download "/payments/$($sub.body.paymentId)/proof" $at (Join-Path $env:TEMP 'out1.jpg')
Check "admin descarga el comprobante (jpeg)" ($img -like '200 image/jpeg*') $img
Check "otro dueño/jugador no ve el comprobante (404)" ((Download "/payments/$($sub.body.paymentId)/proof" $p1t (Join-Path $env:TEMP 'out2.jpg')) -like '404*') ""
Check "sin sesión no ve el comprobante (401)" ((Download "/payments/$($sub.body.paymentId)/proof" $null (Join-Path $env:TEMP 'out3.jpg')) -like '401*') ""
$ap = Call Post "/admin/payments/$($sub.body.paymentId)/approve" $null $at
Check "admin aprueba la mensualidad" ($ap.code -eq 200 -and $ap.body.status -eq 'approved') "$($ap.code) $($ap.raw)"
Check "ya aprobada: repetir -> 409" ((Call Post "/admin/payments/$($sub.body.paymentId)/approve" $null $at).code -eq 409) ""
$d = (Call Get "/owner/courts/$court" $null $ot).body
Check "cancha activa" ($d.status -eq 'active') $d.status
Check "vigencia de 30 días" (([datetime]$d.subscription.activeUntil - (Get-Date).Date).Days -in 29..31) $d.subscription.activeUntil
Check "ya visible en el buscador" (Has (Call Get '/courts?city=Bogot%C3%A1' $null $null).body $court) ""
Check "el dueño recibió el aviso de aprobación" (@((Call Get /notifications $null $ot).body.items | Where-Object { $_.title -eq 'Mensualidad aprobada' }).Count -eq 1) ""

Write-Host "== Mensualidad registrada por el admin (cobro fuera de la app)"
$cm = (Call Post /owner/courts @{ name = 'Cancha Manual'; city = 'Bogotá'; address = 'Cra 8 # 8-8'; lat = 4.7; lng = -74.05; covered = $true; pricePerHour = 80000; openHour = 0; closeHour = 24; requiresDeposit = $false } $ot).body
Check "cancha nueva nace pendiente" ($cm.status -eq 'pending') $cm.status
Check "dueño no registra mensualidad (403)" ((Call Post "/admin/courts/$($cm.id)/subscription-payment" @{} $ot).code -eq 403) ""
Check "cancha inexistente -> 404" ((Call Post "/admin/courts/00000000-0000-0000-0000-000000000000/subscription-payment" @{} $at).code -eq 404) ""
$mp = Call Post "/admin/courts/$($cm.id)/subscription-payment" @{ amount = 100000; note = 'Nequi 25 oct' } $at
Check "admin registra la mensualidad" ($mp.code -eq 200 -and $mp.body.status -eq 'approved') "$($mp.code) $($mp.raw)"
$dm = (Call Get "/owner/courts/$($cm.id)" $null $ot).body
Check "la cancha queda activa" ($dm.status -eq 'active') $dm.status
Check "vigencia de 30 días" (([datetime]$dm.subscription.activeUntil - (Get-Date).Date).Days -in 29..31) $dm.subscription.activeUntil
$mp2 = Call Post "/admin/courts/$($cm.id)/subscription-payment" @{} $at
Check "renovar continúa el periodo (60 días)" (([datetime](Call Get "/owner/courts/$($cm.id)" $null $ot).body.subscription.activeUntil - (Get-Date).Date).Days -in 59..61) "$($mp2.code)"

Write-Host "== Fotos de la cancha"
$ph = Upload "/owner/courts/$court/photos" photo $png $ot
Check "dueño sube una foto" (($ph.code -eq 200 -or $ph.code -eq 201) -and $ph.body.photos.Count -eq 1) "$($ph.code) $($ph.raw)"
Check "otro dueño no sube fotos (404)" ((Upload "/owner/courts/$court/photos" photo $png ((Register 'Dueno Dos' 'dueno2@itest.co' $true).accessToken)).code -eq 404) ""
Check "foto no válida -> 415" ((Upload "/owner/courts/$court/photos" photo $fake $ot).code -eq 415) ""
$pub = (Call Get "/courts/$court" $null $null).body
Check "detalle público trae la URL de la foto" ($pub.photos.Count -eq 1 -and $pub.photos[0] -like '/v1/files/courts/*.jpg') ""
$fileOut = Download ($pub.photos[0] -replace '^/v1', '') $null (Join-Path $env:TEMP 'foto.jpg')
Check "la foto se sirve pública como jpeg" ($fileOut -like '200 image/jpeg*') $fileOut
Check "ruta con path traversal -> 404" ((Download '/files/courts/..%2F..%2Fetc%2Fpasswd' $null (Join-Path $env:TEMP 'x.jpg')) -like '404*') ""
$del = Call Delete "/owner/courts/$court/photos/$($ph.body.photos[0].id)" $null $ot
Check "dueño borra la foto" ($del.body.photos.Count -eq 0) "$($del.code) $($del.raw)"

Write-Host "== Reserva con anticipo y comprobante"
$day = (Get-Date).ToUniversalTime().Date.AddDays(3).AddHours(15)
$b = (Call Post /bookings @{ courtId = $court; startAt = (Iso $day); hours = 2 } $p1t).body
Check "reserva pendiente de pago (anticipo 80000)" ($b.status -eq 'pending_payment' -and $b.deposit -eq 80000) "$($b.status) $($b.deposit)"
Check "otro jugador no puede subir su comprobante (404)" ((Upload "/bookings/$($b.id)/payment" proof $png $p2t).code -eq 404) ""
Check "comprobante inválido -> 415" ((Upload "/bookings/$($b.id)/payment" proof $fake $p1t).code -eq 415) ""
$up = Upload "/bookings/$($b.id)/payment" proof $png $p1t
Check "jugador sube el comprobante" (($up.code -eq 200 -or $up.code -eq 201) -and $up.body.bookingStatus -eq 'pending_review') "$($up.code) $($up.raw)"
Check "segundo comprobante mientras revisan -> 409" ((Upload "/bookings/$($b.id)/payment" proof $png $p1t).code -eq 409) ""
Check "la reserva queda en revisión" ((Call Get "/bookings/$($b.id)" $null $p1t).body.status -eq 'pending_review') ""
$pend = (Call Get '/owner/payments?status=pending' $null $ot).body
$mine = @($pend | Where-Object { $_.id -eq $up.body.paymentId })
Check "dueño ve el pago con datos de contacto del jugador" ($mine.Count -eq 1 -and $mine[0].payerPhone -eq '3001112233' -and $mine[0].amount -eq 80000) ""
Check "dueño recibió aviso de comprobante" (@((Call Get /notifications $null $ot).body.items | Where-Object { $_.title -eq 'Nuevo comprobante de pago' }).Count -ge 1) ""
$img = Download "/payments/$($up.body.paymentId)/proof" $ot (Join-Path $env:TEMP 'out4.jpg')
Check "dueño descarga el comprobante" ($img -like '200 image/jpeg*') $img
Check "otro dueño no puede aprobarlo (404)" ((Call Post "/owner/payments/$($up.body.paymentId)/approve" $null (Register 'Dueno Tres' 'dueno3@itest.co' $true).accessToken).code -eq 404) ""
$rej = Call Post "/owner/payments/$($up.body.paymentId)/reject" @{ reason = 'Monto incorrecto' } $ot
Check "dueño rechaza con motivo" ($rej.body.status -eq 'rejected') "$($rej.code) $($rej.raw)"
Check "la reserva queda rechazada (conserva la hora)" ((Call Get "/bookings/$($b.id)" $null $p1t).body.status -eq 'rejected') ""
$nt = (Call Get /notifications $null $p1t).body
Check "jugador recibió el motivo del rechazo" (@($nt.items | Where-Object { $_.body -like '*Monto incorrecto*' }).Count -eq 1 -and $nt.unread -ge 1) ""
$up2 = Upload "/bookings/$($b.id)/payment" proof $png $p1t
Check "jugador vuelve a subir tras el rechazo" ($up2.code -eq 200 -or $up2.code -eq 201) "$($up2.code) $($up2.raw)"
$ok = Call Post "/owner/payments/$($up2.body.paymentId)/approve" $null $ot
Check "dueño aprueba" ($ok.body.status -eq 'approved') "$($ok.code) $($ok.raw)"
Check "reserva confirmada" ((Call Get "/bookings/$($b.id)" $null $p1t).body.status -eq 'confirmed') ""
$nt = (Call Get /notifications $null $p1t).body
Check "aviso de pago aprobado" (@($nt.items | Where-Object { $_.title -eq 'Pago aprobado' }).Count -eq 1) ""
$first = $nt.items[0].id
Check "marcar una notificación como leída" ((Call Post "/notifications/$first/read" $null $p1t).code -eq 200) ""
Call Post /notifications/read-all $null $p1t | Out-Null
Check "todas leídas" ((Call Get /notifications $null $p1t).body.unread -eq 0) ""
Check "registrar token de dispositivo" ((Call Post /devices @{ platform = 'android'; token = ('t' * 40) } $p1t).code -eq 200) ""

Write-Host "== Cancelar con comprobante en revisión"
$day2 = $day.AddDays(1)
$bb = (Call Post /bookings @{ courtId = $court; startAt = (Iso $day2); hours = 1 } $p2t).body
Upload "/bookings/$($bb.id)/payment" proof $png $p2t | Out-Null
$cn = Call Post "/bookings/$($bb.id)/cancel" $null $p2t
Check "cancela (faltan >24 h) y el pago deja de estar pendiente" ($cn.body.status -eq 'cancelled' -and @((Call Get '/owner/payments?status=pending' $null $ot).body).Count -eq 0) "$($cn.code) $($cn.raw)"

Write-Host "== Devoluciones de anticipos (se devuelven fuera de la app)"
Check "cancelar con el pago en revisión no genera devolución" (@((Call Get '/owner/refunds' $null $ot).body).Count -eq 0) ""
$day3 = $day.AddDays(2)
$rb = (Call Post /bookings @{ courtId = $court; startAt = (Iso $day3); hours = 1 } $p2t).body
$rup = Upload "/bookings/$($rb.id)/payment" proof $png $p2t
$rap = Call Post "/owner/payments/$($rup.body.paymentId)/approve" $null $ot
Check "anticipo aprobado: reserva confirmada" ($rap.body.status -eq 'approved' -and (Call Get "/bookings/$($rb.id)" $null $p2t).body.status -eq 'confirmed') "$($rap.code) $($rap.raw)"
Check "cancelación gratis con anticipo aprobado" ((Call Post "/bookings/$($rb.id)/cancel" $null $p2t).body.status -eq 'cancelled') ""
$rf = @((Call Get '/owner/refunds?status=pending' $null $ot).body)
Check "el dueño ve la devolución pendiente (40000, jugador, celular)" ($rf.Count -eq 1 -and $rf[0].amount -eq 40000 -and $rf[0].playerName -eq 'Maria Gomez' -and $rf[0].playerPhone -eq '3001112233' -and $rf[0].status -eq 'pending') "$($rf | ConvertTo-Json -Compress)"
Check "el dueño recibió el aviso de devolución" (@((Call Get /notifications $null $ot).body.items | Where-Object { $_.body -like '*Debes devolverle*' }).Count -eq 1) ""
Check "jugador no entra a /owner/refunds (403)" ((Call Get '/owner/refunds' $null $p2t).code -eq 403) ""
Check "filtro de estado inválido -> 400" ((Call Get '/owner/refunds?status=otra' $null $ot).code -eq 400) ""
$other = Register 'Dueno Cinco' 'dueno5@itest.co' $true
Check "otro dueño no ve la devolución" (@((Call Get '/owner/refunds' $null $other.accessToken).body).Count -eq 0) ""
Check "otro dueño no puede marcarla (404)" ((Call Post "/owner/refunds/$($rf[0].id)/done" @{} $other.accessToken).code -eq 404) ""
$dn = Call Post "/owner/refunds/$($rf[0].id)/done" @{ note = 'Nequi 25 oct' } $ot
Check "el dueño marca la devolución como hecha" ($dn.code -eq 200 -and $dn.body.status -eq 'done') "$($dn.code) $($dn.raw)"
Check "marcarla otra vez -> 409" ((Call Post "/owner/refunds/$($rf[0].id)/done" @{} $ot).code -eq 409) ""
Check "ya no está pendiente y queda en el historial con su nota" (@((Call Get '/owner/refunds?status=pending' $null $ot).body).Count -eq 0 -and (Call Get '/owner/refunds?status=done' $null $ot).body[0].note -eq 'Nequi 25 oct') ""
Check "el jugador recibió el aviso de devolución" (@((Call Get /notifications $null $p2t).body.items | Where-Object { $_.title -eq 'Devolución enviada' }).Count -eq 1) ""

Write-Host "== Reseñas"
$past = Sql "INSERT INTO bookings (court_id, player_id, start_at, hours, end_at, total, deposit, last_minute, status) VALUES ('$court','$($p1.user.id)', now() - interval '3 days', 1, now() - interval '3 days' + interval '1 hour', 100000, 0, false, 'confirmed') RETURNING id;" | Select-Object -First 1
Check "reserva futura no se puede reseñar (422)" ((Call Post "/bookings/$($b.id)/review" @{ stars = 5 } $p1t).code -eq 422) ""
Check "otro jugador no reseña mi reserva (404)" ((Call Post "/bookings/$past/review" @{ stars = 5 } $p2t).code -eq 404) ""
Check "estrellas fuera de rango -> 400" ((Call Post "/bookings/$past/review" @{ stars = 9 } $p1t).code -eq 400) ""
$rv = Call Post "/bookings/$past/review" @{ stars = 2; body = 'Muy mala atención' } $p1t
Check "jugador califica la reserva jugada" (($rv.code -eq 200 -or $rv.code -eq 201) -and $rv.body.stars -eq 2) "$($rv.code) $($rv.raw)"
Check "reseñar dos veces -> 409" ((Call Post "/bookings/$past/review" @{ stars = 5 } $p1t).code -eq 409) ""
$pubr = (Call Get "/courts/$court/reviews" $null $null).body
Check "reseñas públicas muestran solo el primer nombre" (@($pubr).Count -eq 1 -and $pubr[0].authorName -eq 'Pablo') ""
Check "la calificación promedio se actualiza" ((Call Get "/courts/$court" $null $null).body.rating -eq 2) ""
Check "no puede reportar su propia reseña (422)" ((Call Post "/reviews/$($rv.body.id)/report" @{} $p1t).code -eq 422) ""
Check "otro jugador reporta la reseña" ((Call Post "/reviews/$($rv.body.id)/report" @{ reason = 'Insultos' } $p2t).code -eq 200) ""
Call Post "/reviews/$($rv.body.id)/report" @{ reason = 'Insultos' } $p2t | Out-Null
$rep = (Call Get /admin/review-reports $null $at).body
Check "admin ve la reseña reportada una vez (reporte repetido no suma)" (@($rep).Count -eq 1 -and $rep[0].reports -eq 1) "n=$(@($rep).Count)"
$h = Call Post "/admin/reviews/$($rv.body.id)/hide" $null $at
Check "admin oculta la reseña" ($h.body.hidden -eq $true) ""
Check "oculta: ya no sale en lo público" (@((Call Get "/courts/$court/reviews" $null $null).body).Count -eq 0) ""
Check "oculta: ya no cuenta en la calificación" ((Call Get "/courts/$court" $null $null).body.rating -eq 0) ""
Check "los reportes quedan resueltos" (@((Call Get /admin/review-reports $null $at).body).Count -eq 0) ""

Write-Host "== Estadísticas del dueño"
$st = (Call Get '/owner/stats?from=2020-01-01&to=2030-12-31' $null $ot)
Check "rango demasiado grande -> 400" ($st.code -eq 400) ""
$from = (Get-Date).AddDays(-10).ToString('yyyy-MM-dd'); $to = (Get-Date).AddDays(10).ToString('yyyy-MM-dd')
$st = (Call Get "/owner/stats?from=$from&to=$to" $null $ot).body
Check "estadísticas: 1 confirmada futura + 1 pasada" ($st.bookings.confirmed -eq 2 -and $st.income -eq 300000) "conf=$($st.bookings.confirmed) ingreso=$($st.income)"
Check "ocupación calculada" ($st.occupancyPercent -gt 0 -and $st.bookedHours -eq 3) "$($st.occupancyPercent) $($st.bookedHours)"
Check "jugador no ve estadísticas (403)" ((Call Get /owner/stats $null $p1t).code -eq 403) ""

Write-Host "== Tareas programadas"
$bx = (Call Post /bookings @{ courtId = $court; startAt = (Iso $day.AddDays(5)); hours = 1 } $p2t).body
Sql "UPDATE bookings SET created_at = now() - interval '2 hours' WHERE id = '$($bx.id)';" | Out-Null
$j = (Call Post /admin/jobs/run $null $at).body
Check "libera reserva sin comprobante tras 30 min" ($j.expiredUnpaid -ge 1 -and (Call Get "/bookings/$($bx.id)" $null $p2t).body.status -eq 'cancelled') "$($j | ConvertTo-Json -Compress)"
Check "el jugador fue avisado" (@((Call Get /notifications $null $p2t).body.items | Where-Object { $_.title -eq 'Reserva cancelada' }).Count -eq 1) ""
Sql "UPDATE subscription_periods SET starts_on = (now() AT TIME ZONE 'America/Bogota')::date - 28, ends_on = (now() AT TIME ZONE 'America/Bogota')::date + 2, reminded_at = NULL WHERE court_id = '$court';" | Out-Null
$j = (Call Post /admin/jobs/run $null $at).body
Check "avisa 3 días antes del vencimiento" ($j.subscriptionReminders -ge 1) ($j | ConvertTo-Json -Compress)
Check "el aviso se envía una sola vez" ((Call Post /admin/jobs/run $null $at).body.subscriptionReminders -eq 0) ""
Sql "UPDATE subscription_periods SET starts_on = (now() AT TIME ZONE 'America/Bogota')::date - 40, ends_on = (now() AT TIME ZONE 'America/Bogota')::date - 10 WHERE court_id = '$court';" | Out-Null
$j = (Call Post /admin/jobs/run $null $at).body
Check "mensualidad vencida: suspende la cancha" ($j.suspendedCourts -ge 1 -and -not (Has (Call Get '/courts?city=Bogot%C3%A1' $null $null).body $court)) ($j | ConvertTo-Json -Compress)
Check "el dueño fue avisado" (@((Call Get /notifications $null $ot).body.items | Where-Object { $_.title -like 'Tu cancha dejó de ser visible*' }).Count -eq 1) ""
Check "admin no puede reactivar sin mensualidad (409)" ((Call Post "/admin/courts/$court/reactivate" $null $at).code -eq 409) ""
$sub2 = Upload "/owner/courts/$court/subscription-payment" proof $png $ot
Call Post "/admin/payments/$($sub2.body.paymentId)/approve" $null $at | Out-Null
Check "al pagar de nuevo vuelve a estar visible" (Has (Call Get '/courts?city=Bogot%C3%A1' $null $null).body $court) ""

Write-Host "== Administración"
Check "listar usuarios con búsqueda" (@((Call Get '/admin/users?search=pablo' $null $at).body).Count -eq 1) ""
Check "no se puede suspender a un admin (403)" ((Call Post "/admin/users/$($adm.user.id)/suspend" $null $at).code -eq 403) ""
Check "suspender jugador" ((Call Post "/admin/users/$($p2.user.id)/suspend" $null $at).body.suspended -eq $true) ""
$lg = Call Post /auth/login @{ email = 'p2@itest.co'; password = $pwd1 } $null
Check "suspendido no puede iniciar sesión (403)" ($lg.code -eq 403 -and $lg.body.code -eq 'SUSPENDED') "$($lg.code)"
Check "su sesión activa deja de servir de inmediato (403)" ((Call Get /auth/me $null $p2t).code -eq 403) ""
Call Post "/admin/users/$($p2.user.id)/restore" $null $at | Out-Null
Check "restaurado vuelve a entrar" ((Call Post /auth/login @{ email = 'p2@itest.co'; password = $pwd1 } $null).code -eq 200) ""
Check "suspender cancha la oculta" ((Call Post "/admin/courts/$court/suspend" $null $at).body.status -eq 'suspended' -and -not (Has (Call Get '/courts?city=Bogot%C3%A1' $null $null).body $court)) ""
Check "reactivar con mensualidad vigente" ((Call Post "/admin/courts/$court/reactivate" $null $at).body.status -eq 'active') ""
$tx = (Call Get '/admin/transactions' $null $at).body
Check "historial: mensualidades y reservas aprobadas" ($tx.count -ge 3 -and (@($tx.items | Where-Object { $_.kind -eq 'subscription' }).Count -ge 2) -and (@($tx.items | Where-Object { $_.kind -eq 'booking' }).Count -ge 1)) "n=$($tx.count)"
Check "total de transacciones" ($tx.totalAmount -ge 280000) $tx.totalAmount
Check "filtro de fechas inválido -> 400" ((Call Get '/admin/transactions?from=2026-02-30' $null $at).code -eq 400) ""
$m = (Call Get /admin/metrics $null $at).body
Check "métricas generales" ($m.users.admin -ge 1 -and $m.courts.active -ge 1 -and $m.revenue.subscriptionsTotal -ge 200000) ($m | ConvertTo-Json -Compress -Depth 5)
Check "admin lista canchas con dueño y vigencia" (@((Call Get "/admin/courts?status=active" $null $at).body | Where-Object { $_.id -eq $court -and $_.ownerName -eq 'Dueno Uno' -and $_.activeUntil }).Count -eq 1) ""

Write-Host "== Cuenta: perfil, contraseña y borrado"
$me = (Call Patch /auth/me @{ phone = '3109998877'; name = 'Pablo Perez Ruiz' } $p1t).body
Check "actualizar celular y nombre" ($me.phone -eq '3109998877' -and $me.name -eq 'Pablo Perez Ruiz') ""
Check "celular inválido -> 400" ((Call Patch /auth/me @{ phone = '12345' } $p1t).code -eq 400) ""
$cp = Call Post /auth/change-password @{ current = 'incorrecta-123'; next = 'otra-clave-nueva-1' } $p1t
Check "cambiar contraseña con la actual mala -> 401" ($cp.code -eq 401) ""
$cp = Call Post /auth/change-password @{ current = $pwd1; next = 'otra-clave-nueva-1' } $p1t
Check "cambiar contraseña devuelve sesión nueva" ($cp.code -eq 200 -and $cp.body.accessToken) ""
Check "la sesión anterior se cerró" ((Call Post /auth/refresh @{ refreshToken = $p1.refreshToken } $null).code -eq 401) ""
Check "la clave vieja ya no sirve" ((Call Post /auth/login @{ email = 'p1@itest.co'; password = $pwd1 } $null).code -eq 401) ""

Call Post /auth/forgot-password @{ email = 'dueno1@itest.co' } $null | Out-Null
Check "olvidé contraseña responde igual con correo inexistente" ((Call Post /auth/forgot-password @{ email = 'nadie@itest.co' } $null).code -eq 200) ""
Start-Sleep 1
$log = docker compose logs --no-log-prefix --since 2m api 2>&1 | Out-String
$mt = [regex]::Matches($log, 'token=([A-Za-z0-9_-]+)')
$tok = if ($mt.Count) { $mt[$mt.Count - 1].Groups[1].Value } else { '' }
Check "el correo de recuperación salió (en el log) con enlace" ($tok.Length -gt 20) "sin token en el log"
Check "token inventado -> 422" ((Call Post /auth/reset-password @{ token = ('x' * 43); next = 'nueva-clave-segura-1' } $null).code -eq 422) ""
Check "restablecer contraseña con el enlace" ((Call Post /auth/reset-password @{ token = $tok; next = 'nueva-clave-segura-1' } $null).code -eq 200) ""
Check "el enlace no se puede usar dos veces (422)" ((Call Post /auth/reset-password @{ token = $tok; next = 'otra-mas-segura-1' } $null).code -eq 422) ""
Check "entra con la contraseña nueva" ((Call Post /auth/login @{ email = 'dueno1@itest.co'; password = 'nueva-clave-segura-1' } $null).code -eq 200) ""

$o2 = Register 'Dueno Cuatro' 'dueno4@itest.co' $true
$c2 = (Call Post /owner/courts @{ name = 'Cancha Que Se Borra'; city = 'Cali'; address = 'Av 1 # 2-3'; lat = 3.45; lng = -76.5; covered = $false; pricePerHour = 50000; openHour = 0; closeHour = 24; requiresDeposit = $false } $o2.accessToken).body
$v = Register 'Victima Borrado' 'victima@itest.co' $false
$vb = (Call Post /bookings @{ courtId = $court; startAt = (Iso $day.AddDays(8)); hours = 1 } $v.accessToken).body
Check "la reserva de la víctima existe" ($vb.status -eq 'pending_payment') "$($vb | ConvertTo-Json -Compress)"
Check "borrar cuenta con contraseña errónea -> 401" ((Call Delete /auth/me @{ password = 'mala-clave-123' } $v.accessToken).code -eq 401) ""
Check "borrar la propia cuenta" ((Call Delete /auth/me @{ password = $pwd1 } $v.accessToken).code -eq 200) ""
Check "cuenta borrada no inicia sesión" ((Call Post /auth/login @{ email = 'victima@itest.co'; password = $pwd1 } $null).code -eq 401) ""
Check "su reserva futura se canceló" ((Sql "SELECT status FROM bookings WHERE id='$($vb.id)';" | Select-Object -First 1) -eq 'cancelled') ""
Check "datos personales anonimizados" ((Sql "SELECT name || '|' || COALESCE(email,'-') || '|' || COALESCE(phone,'-') FROM users WHERE id='$($v.user.id)';" | Select-Object -First 1) -eq 'Usuario eliminado|-|-') ""
Check "admin borra a un dueño y se suspenden sus canchas" ((Call Delete "/admin/users/$($o2.user.id)" $null $at).body.deleted -eq $true -and (Sql "SELECT status FROM courts WHERE id='$($c2.id)';" | Select-Object -First 1) -eq 'suspended') ""
Check "admin no se puede borrar (403)" ((Call Delete "/admin/users/$($adm.user.id)" $null $at).code -eq 403) ""

Cleanup
Write-Host ""
Write-Host "RESULTADO: $script:pass OK, $script:fail FALLAS"
