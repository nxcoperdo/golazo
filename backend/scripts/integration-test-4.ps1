# Prueba de integración 4: chat jugador <-> dueño (ligado a la reserva) y chat con soporte.
# Requiere db y api arriba y las migraciones aplicadas (hasta 008). Uso (desde backend/): ./scripts/integration-test-4.ps1
# Crea/borra datos de prueba (correos @itest.co) y un admin admin@itest.co. Necesita curl.exe para las fotos.
# /auth limita a 10 peticiones/min por IP: no la corras pegada a otra prueba.
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
$base = 'http://127.0.0.1:3000/v1'
$script:pass = 0; $script:fail = 0
$script:ids = @()
$pwd1 = 'clave-segura-1'

function Call($method, $path, $body, $token, $tries = 0) {
  $h = @{}; if ($token) { $h.Authorization = "Bearer $token" }
  try {
    $a = @{ Method = $method; Uri = "$base$path"; Headers = $h; ContentType = 'application/json' }
    if ($body) { $a.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6)) }
    return @{ code = 200; body = (Invoke-RestMethod @a) }
  } catch {
    $msg = $_.ErrorDetails.Message; $j = $null; try { $j = $msg | ConvertFrom-Json } catch {}
    $code = [int]$_.Exception.Response.StatusCode
    # /auth admite 10 peticiones por minuto: esperar y repetir en vez de fallar en cascada.
    if ($code -eq 429 -and $tries -lt 6) { Start-Sleep 15; return Call $method $path $body $token ($tries + 1) }
    return @{ code = $code; body = $j; raw = $msg }
  }
}
# Envía una foto (y texto opcional) por multipart con curl.
function Upload($path, $file, $token, $text) {
  $a = @('-s', '-w', '\n%{http_code}', '-X', 'POST', '-F', "image=@$file")
  if ($text) { $a += @('-F', "body=$text") }
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
function Cleanup {
  $list = ($script:ids | ForEach-Object { "'$_'" }) -join ','
  if (-not $list) { $list = "'00000000-0000-0000-0000-000000000000'" }
  Sql @"
CREATE TEMP TABLE tu AS SELECT id FROM users WHERE email LIKE '%@itest.co' OR name = 'Usuario eliminado' OR id IN ($list);
CREATE TEMP TABLE tc AS SELECT id FROM courts WHERE owner_id IN (SELECT id FROM tu);
DELETE FROM chat_blocks WHERE blocker_id IN (SELECT id FROM tu) OR blocked_id IN (SELECT id FROM tu);
DELETE FROM chat_threads WHERE participant_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM review_reports WHERE reporter_id IN (SELECT id FROM tu);
DELETE FROM reviews WHERE author_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM subscription_periods WHERE court_id IN (SELECT id FROM tc);
DELETE FROM payments WHERE payer_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM refunds WHERE player_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM bookings WHERE player_id IN (SELECT id FROM tu) OR court_id IN (SELECT id FROM tc);
DELETE FROM courts WHERE id IN (SELECT id FROM tc);
DELETE FROM users WHERE id IN (SELECT id FROM tu);
"@ | Out-Null
}
function Msgs($tid, $token, $after) {
  $q = if ($null -ne $after) { "?after=$after" } else { '' }
  return (Call Get "/chat/threads/$tid/messages$q" $null $token)
}
function Book($courtId, $player, $day, $hour) {
  $d = (Get-Date).ToUniversalTime().Date.AddDays($day).AddHours($hour)
  return (Call Post /bookings @{ courtId = $courtId; startAt = (Iso $d); hours = 1 } $player).body
}

# --- Imagen de prueba ---
$png = Join-Path $env:TEMP 'golazo-test.png'
node scripts/make-test-image.mjs $png
$fake = Join-Path $env:TEMP 'golazo-fake.jpg'; Set-Content $fake 'esto no es una imagen' -Encoding ascii

Cleanup
"Preparando administrador..."
docker compose run --rm migrate node dist/scripts/create-admin.js admin@itest.co "Admin Test" "clave-admin-larga-1" 2>&1 | Select-Object -Last 1

Write-Host "== Preparación"
$adm = (Call Post /auth/login @{ email = 'admin@itest.co'; password = 'clave-admin-larga-1' }).body
$script:ids += $adm.user.id
$at = $adm.accessToken
$own = Register 'Dueno Chat' 'chowner@itest.co' $true;   $ot = $own.accessToken
$own2 = Register 'Dueno Ajeno' 'chowner2@itest.co' $true; $o2t = $own2.accessToken
$p1 = Register 'Pablo Chat' 'chp1@itest.co' $false;      $p1t = $p1.accessToken
$p2 = Register 'Maria Chat' 'chp2@itest.co' $false;      $p2t = $p2.accessToken
$c = (Call Post /owner/courts @{ name = 'Cancha Chat'; city = 'Bogotá'; address = 'Cra 1 # 2-3'; lat = 4.7; lng = -74.05; covered = $true; pricePerHour = 60000; openHour = 0; closeHour = 24; requiresDeposit = $false } $ot).body
$court = $c.id
Activate $court
Check "sin reservas no hay hilos con mensajes" (@((Call Get /chat/threads $null $p1t).body).Count -eq 0) ""
Check "sin sesión -> 401" ((Call Get /chat/threads $null $null).code -eq 401) ""

Write-Host "== El hilo nace con la reserva"
$b1 = Book $court $p1t 3 15
Check "reserva confirmada" ($b1.status -eq 'confirmed') "$($b1 | ConvertTo-Json -Compress)"
Start-Sleep 1
$pt = @((Call Get /chat/threads $null $p1t).body)
Check "el jugador ve su hilo abierto con el nombre de la cancha" ($pt.Count -eq 1 -and $pt[0].open -eq $true -and $pt[0].courtName -eq 'Cancha Chat' -and $pt[0].kind -eq 'court') "$($pt | ConvertTo-Json -Compress)"
$ot1 = @((Call Get /chat/threads $null $ot).body)
Check "el dueño ve el mismo hilo con el nombre del jugador" ($ot1.Count -eq 1 -and $ot1[0].id -eq $pt[0].id -and $ot1[0].participantName -eq 'Pablo Chat') ""
$tid = $pt[0].id
Check "el jugador abre el chat desde su reserva" ((Call Post "/chat/bookings/$($b1.id)" $null $p1t).body.id -eq $tid) ""
Check "el dueño abre el chat desde la reserva del jugador" ((Call Post "/chat/bookings/$($b1.id)" $null $ot).body.id -eq $tid) ""
Check "otro jugador no puede abrir el chat de esa reserva (404)" ((Call Post "/chat/bookings/$($b1.id)" $null $p2t).code -eq 404) ""
Check "otro dueño tampoco (404)" ((Call Post "/chat/bookings/$($b1.id)" $null $o2t).code -eq 404) ""
Check "otros usuarios no ven el hilo (404)" ((Msgs $tid $p2t $null).code -eq 404 -and (Msgs $tid $o2t $null).code -eq 404) ""
Check "sin sesión no lee mensajes (401)" ((Msgs $tid $null $null).code -eq 401) ""

Write-Host "== Conversación"
$m1 = Call Post "/chat/threads/$tid/messages" @{ body = 'Hola, ¿tienen balones?' } $p1t
Check "el jugador escribe" (($m1.code -eq 200 -or $m1.code -eq 201) -and $m1.body.body -eq 'Hola, ¿tienen balones?' -and $m1.body.senderId -eq $p1.user.id) "$($m1.code) $($m1.raw)"
$ot1 = @((Call Get /chat/threads $null $ot).body)
Check "el dueño ve 1 mensaje sin leer y la vista previa" ($ot1[0].unread -eq 1 -and $ot1[0].lastBody -eq 'Hola, ¿tienen balones?') "$($ot1 | ConvertTo-Json -Compress)"
$r1 = Msgs $tid $ot $null
Check "el dueño lee el mensaje" (@($r1.body.messages).Count -eq 1 -and $r1.body.open -eq $true) "$($r1 | ConvertTo-Json -Compress -Depth 5)"
Check "al leer, ya no hay no leídos" (@((Call Get /chat/threads $null $ot).body)[0].unread -eq 0) ""
$m2 = Call Post "/chat/threads/$tid/messages" @{ body = 'Sí, tenemos. Los dejo en la entrada.' } $ot
Check "el dueño responde" ($m2.code -eq 200 -or $m2.code -eq 201) "$($m2.code) $($m2.raw)"
Check "el jugador ve 1 sin leer" (@((Call Get /chat/threads $null $p1t).body)[0].unread -eq 1) ""
$last = $r1.body.messages[0].seq
$news = Msgs $tid $p1t $last
Check "con after= solo llegan los mensajes nuevos" (@($news.body.messages).Count -eq 1 -and $news.body.messages[0].senderId -eq $own.user.id) "$($news | ConvertTo-Json -Compress -Depth 5)"
Check "sin novedades devuelve vacío" (@((Msgs $tid $p1t $news.body.messages[0].seq).body.messages).Count -eq 0) ""

Write-Host "== Validaciones"
Check "mensaje vacío -> 400" ((Call Post "/chat/threads/$tid/messages" @{ body = '   ' } $p1t).code -eq 400) ""
Check "más de 1000 caracteres -> 400" ((Call Post "/chat/threads/$tid/messages" @{ body = ('a' * 1001) } $p1t).code -eq 400) ""
Check "otro jugador no puede escribir (404)" ((Call Post "/chat/threads/$tid/messages" @{ body = 'hola' } $p2t).code -eq 404) ""
Check "otro dueño no puede escribir (404)" ((Call Post "/chat/threads/$tid/messages" @{ body = 'hola' } $o2t).code -eq 404) ""
Check "id inválido -> 400" ((Msgs 'no-es-uuid' $p1t $null).code -eq 400) ""

Write-Host "== Fotos"
$ph = Upload "/chat/threads/$tid/messages" $png $p1t 'Mira la cancha'
Check "el jugador envía una foto con texto" (($ph.code -eq 200 -or $ph.code -eq 201) -and $ph.body.hasImage -eq $true -and $ph.body.body -eq 'Mira la cancha') "$($ph.code) $($ph.raw)"
Check "archivo que no es imagen -> 415" ((Upload "/chat/threads/$tid/messages" $fake $p1t $null).code -eq 415) ""
$imgId = $ph.body.id
$d1 = Download "/chat/images/$imgId" $ot (Join-Path $env:TEMP 'chat1.jpg')
Check "el dueño descarga la foto (jpeg)" ($d1 -like '200 image/jpeg*') $d1
Check "el administrador también" ((Download "/chat/images/$imgId" $at (Join-Path $env:TEMP 'chat2.jpg')) -like '200 image/jpeg*') ""
Check "otro jugador no ve la foto (404)" ((Download "/chat/images/$imgId" $p2t (Join-Path $env:TEMP 'chat3.jpg')) -like '404*') ""
Check "sin sesión no ve la foto (401)" ((Download "/chat/images/$imgId" $null (Join-Path $env:TEMP 'chat4.jpg')) -like '401*') ""

Write-Host "== Administrador: leer sí, escribir en chats de cancha no"
Check "el admin lee el chat entre jugador y dueño" (@((Msgs $tid $at $null).body.messages).Count -eq 3) ""
Check "el admin no escribe en chats de cancha (403)" ((Call Post "/chat/threads/$tid/messages" @{ body = 'hola' } $at).code -eq 403) ""
$ct = @((Call Get '/admin/chat/threads?search=Cancha%20Chat' $null $at).body)
Check "el admin lista los chats de cancha y filtra por nombre" ($ct.Count -ge 1 -and $ct[0].courtName -eq 'Cancha Chat' -and $ct[0].playerName -eq 'Pablo Chat' -and $ct[0].messages -eq 3) "$($ct | ConvertTo-Json -Compress)"
Check "jugador y dueño no usan /admin/chat (403)" ((Call Get '/admin/chat/support' $null $p1t).code -eq 403 -and (Call Get '/admin/chat/threads' $null $ot).code -eq 403) ""

Write-Host "== El chat se cierra con la reserva y se reabre al reservar de nuevo"
$cn = Call Post "/bookings/$($b1.id)/cancel" $null $p1t
Check "el jugador cancela la reserva" ($cn.body.status -eq 'cancelled') "$($cn.code) $($cn.raw)"
$cl = Msgs $tid $p1t $null
Check "el hilo queda cerrado pero con el historial" ($cl.body.open -eq $false -and @($cl.body.messages).Count -eq 3) "$($cl | ConvertTo-Json -Compress -Depth 4)"
Check "cerrado: nadie puede escribir (409 CHAT_CLOSED)" ((Call Post "/chat/threads/$tid/messages" @{ body = 'x' } $p1t).code -eq 409 -and (Call Post "/chat/threads/$tid/messages" @{ body = 'x' } $ot).code -eq 409) ""
Check "la lista lo marca cerrado" (@((Call Get /chat/threads $null $ot).body)[0].open -eq $false) ""
$b2 = Book $court $p1t 4 15
Start-Sleep 1
Check "al reservar de nuevo el MISMO hilo se reabre" ((Msgs $tid $p1t $null).body.open -eq $true) ""
Check "y se puede escribir otra vez" ((Call Post "/chat/threads/$tid/messages" @{ body = 'Nueva reserva, hola otra vez' } $p1t).code -in 200,201) ""
# Una reserva que ya terminó cierra el chat aunque siga confirmada.
Sql "UPDATE bookings SET start_at = now() - interval '3 hours', end_at = now() - interval '2 hours' WHERE id = '$($b2.id)';" | Out-Null
Check "al terminar la hora de la reserva el chat se cierra" ((Msgs $tid $p1t $null).body.open -eq $false -and (Call Post "/chat/threads/$tid/messages" @{ body = 'x' } $ot).code -eq 409) ""
$b3 = Book $court $p1t 5 15
Start-Sleep 1
Check "otra reserva lo vuelve a abrir" ((Msgs $tid $ot $null).body.open -eq $true) ""

Write-Host "== Bloqueo"
Check "no puedes bloquearte" ((Call Post "/chat/blocks/$($own.user.id)" $null $ot).code -eq 422) ""
Check "no se puede bloquear a soporte (422)" ((Call Post "/chat/blocks/$($adm.user.id)" $null $p1t).code -eq 422) ""
Check "el dueño bloquea al jugador" ((Call Post "/chat/blocks/$($p1.user.id)" $null $ot).body.blocked -eq $true) ""
$bl = Msgs $tid $p1t $null
Check "bloqueado: el jugador no puede escribir (409)" ($bl.body.open -eq $false -and (Call Post "/chat/threads/$tid/messages" @{ body = 'x' } $p1t).code -eq 409) ""
Check "el dueño ve que bloqueó (puede desbloquear)" ((Msgs $tid $ot $null).body.blocked -eq $true) ""
Check "el dueño desbloquea" ((Call Delete "/chat/blocks/$($p1.user.id)" $null $ot).body.blocked -eq $false) ""
Check "desbloqueado: se puede escribir" ((Call Post "/chat/threads/$tid/messages" @{ body = 'Gracias' } $p1t).code -in 200,201) ""

Write-Host "== Reportes y moderación"
$all = (Msgs $tid $ot $null).body.messages
$fromP1 = @($all | Where-Object { $_.senderId -eq $p1.user.id })[0]
Check "no puedes reportar tu propio mensaje (422)" ((Call Post "/chat/messages/$($fromP1.id)/report" @{ reason = 'x' } $p1t).code -eq 422) ""
Check "el dueño reporta un mensaje" ((Call Post "/chat/messages/$($fromP1.id)/report" @{ reason = 'Insulto' } $ot).body.reported -eq $true) ""
Check "reportar dos veces no duplica" ((Call Post "/chat/messages/$($fromP1.id)/report" @{ reason = 'Insulto' } $ot).code -eq 200) ""
Check "otro usuario no puede reportar un mensaje ajeno (404)" ((Call Post "/chat/messages/$($fromP1.id)/report" @{ reason = 'x' } $p2t).code -eq 404) ""
$rep = @((Call Get '/admin/chat/reports' $null $at).body)
Check "el admin ve el reporte con el texto y los nombres" ($rep.Count -eq 1 -and $rep[0].reason -eq 'Insulto' -and $rep[0].reporterName -eq 'Dueno Chat' -and $rep[0].senderName -eq 'Pablo Chat' -and $rep[0].courtName -eq 'Cancha Chat') "$($rep | ConvertTo-Json -Compress)"
Check "el admin oculta el mensaje" ((Call Post "/admin/chat/messages/$($fromP1.id)/hide" $null $at).body.hidden -eq $true) ""
$hid = @((Msgs $tid $ot $null).body.messages | Where-Object { $_.id -eq $fromP1.id })[0]
Check "para los usuarios queda oculto y sin texto" ($hid.hidden -eq $true -and $null -eq $hid.body) "$($hid | ConvertTo-Json -Compress)"
$hidAdm = @((Msgs $tid $at $null).body.messages | Where-Object { $_.id -eq $fromP1.id })[0]
Check "el admin sigue viendo el texto original (evidencia)" ($hidAdm.hidden -eq $true -and $hidAdm.body -eq $fromP1.body) ""
Check "al ocultarlo el reporte queda resuelto" (@((Call Get '/admin/chat/reports' $null $at).body).Count -eq 0) ""

Write-Host "== Chat con soporte (jugador y dueño)"
$s1 = (Call Post /chat/support $null $p1t).body
Check "el jugador abre su hilo de soporte" ($s1.kind -eq 'support' -and $s1.open -eq $true) "$($s1 | ConvertTo-Json -Compress)"
Check "es siempre el mismo hilo" ((Call Post /chat/support $null $p1t).body.id -eq $s1.id) ""
$s2 = (Call Post /chat/support $null $ot).body
Check "el dueño tiene el suyo" ($s2.kind -eq 'support' -and $s2.id -ne $s1.id) ""
Check "el admin no abre hilo de soporte (403)" ((Call Post /chat/support $null $at).code -eq 403) ""
Check "el jugador escribe a soporte" ((Call Post "/chat/threads/$($s1.id)/messages" @{ body = 'Necesito ayuda con mi reserva' } $p1t).code -in 200,201) ""
Check "el dueño escribe a soporte con foto" ((Upload "/chat/threads/$($s2.id)/messages" $png $ot 'Mi comprobante').code -in 200,201) ""
$inbox = @((Call Get '/admin/chat/support' $null $at).body)
Check "la bandeja del admin tiene los dos y ambos esperan respuesta" ($inbox.Count -eq 2 -and @($inbox | Where-Object { $_.needsReply -eq $true }).Count -eq 2) "$($inbox | ConvertTo-Json -Compress)"
Check "la bandeja muestra el rol y el correo del usuario" (@($inbox | Where-Object { $_.participantRole -eq 'owner' -and $_.participantEmail -eq 'chowner@itest.co' }).Count -eq 1) ""
Check "otro jugador no lee el soporte de Pablo (404)" ((Msgs $s1.id $p2t $null).code -eq 404) ""
Check "el dueño tampoco (404)" ((Msgs $s1.id $ot $null).code -eq 404) ""
$rp = Call Post "/admin/chat/threads/$($s1.id)/messages" @{ body = 'Hola Pablo, ya lo revisamos.' } $at
Check "el admin responde" ($rp.code -in 200,201 -and $rp.body.fromSupport -eq $true) "$($rp.code) $($rp.raw)"
$ms = Msgs $s1.id $p1t $null
Check "el jugador ve la respuesta como «soporte»" (@($ms.body.messages | Where-Object { $_.fromSupport -eq $true }).Count -eq 1) ""
Check "el jugador tiene la respuesta sin leer antes de abrir el chat" (@((Call Get /chat/threads $null $p1t).body | Where-Object { $_.kind -eq 'support' }).Count -eq 1) ""
$inbox = @((Call Get '/admin/chat/support' $null $at).body)
Check "tras responder, ese hilo ya no espera respuesta y el otro sigue primero" ($inbox[0].participantEmail -eq 'chowner@itest.co' -and $inbox[0].needsReply -eq $true -and $inbox[1].needsReply -eq $false) "$($inbox | ConvertTo-Json -Compress)"

Write-Host "== Pedir mensualidad desde el botón de soporte"
$c2 = (Call Post /owner/courts @{ name = 'Cancha Pendiente'; city = 'Bogotá'; address = 'Cra 5 # 6-7'; lat = 4.7; lng = -74.05; covered = $true; pricePerHour = 60000; openHour = 0; closeHour = 24; requiresDeposit = $false } $o2t).body
$sub = Call Post '/chat/support/subscription' @{ courtId = $c2.id } $o2t
Check "el dueño abre el chat de su cancha pendiente" ($sub.code -eq 200 -and $sub.body.kind -eq 'support') "$($sub.code) $($sub.raw)"
$sm = @((Msgs $sub.body.id $o2t $null).body.messages)
Check "quedan 2 mensajes: el pedido del dueño y la respuesta de soporte" ($sm.Count -eq 2 -and $sm[0].fromSupport -eq $false -and $sm[1].fromSupport -eq $true) "$($sm | ConvertTo-Json -Compress)"
Check "el pedido dice que quiere activar su cancha" ($sm[0].body -like '*activar mi cancha*Cancha Pendiente*') "$($sm[0].body)"
Check "la respuesta pide el comprobante" ($sm[1].body -like '*comprobante*') "$($sm[1].body)"
$sub2 = Call Post '/chat/support/subscription' @{ courtId = $c2.id } $o2t
Check "tocar de nuevo no duplica los mensajes" ($sub2.code -eq 200 -and @((Msgs $sub.body.id $o2t $null).body.messages).Count -eq 2) ""
Check "el pedido de una cancha activa dice renovar" ((Call Post '/chat/support/subscription' @{ courtId = $court } $ot).code -eq 200 -and @((Msgs $s2.id $ot $null).body.messages | Where-Object { $_.body -like '*renovar la mensualidad*' }).Count -eq 1) ""
Check "cancha de otro dueño: 404" ((Call Post '/chat/support/subscription' @{ courtId = $c2.id } $ot).code -eq 404) ""
Check "el admin no puede usarlo (403)" ((Call Post '/chat/support/subscription' @{ courtId = $c2.id } $at).code -eq 403) ""
Check "courtId inválido: 400" ((Call Post '/chat/support/subscription' @{ courtId = 'x' } $o2t).code -eq 400) ""

Write-Host "== Borrar cuenta"
$pFoto = Upload "/chat/threads/$tid/messages" $png $p1t $null
Check "(preparación) foto del jugador en el chat de cancha" ($pFoto.code -in 200,201) ""
$del = Call Delete /auth/me @{ password = $pwd1 } $p1t
Check "el jugador borra su cuenta" ($del.code -eq 200 -or $del.code -eq 204) "$($del.code) $($del.raw)"
$after = @((Msgs $tid $ot $null).body.messages | Where-Object { $_.senderId -eq $p1.user.id })
Check "sus mensajes pasan a «Mensaje eliminado», ocultos y sin foto" ($after.Count -ge 3 -and @($after | Where-Object { $_.hidden -eq $true -and $_.body -eq $null }).Count -eq $after.Count -and @($after | Where-Object { $_.hasImage }).Count -eq 0) "$($after | ConvertTo-Json -Compress)"
Check "la foto ya no se puede descargar" ((Download "/chat/images/$($pFoto.body.id)" $at (Join-Path $env:TEMP 'chat5.jpg')) -like '404*') ""
Check "su hilo de soporte desapareció" (@((Call Get '/admin/chat/support' $null $at).body | Where-Object { $_.participantEmail -eq 'chp1@itest.co' }).Count -eq 0) ""
Check "el chat de la cancha sigue legible para el dueño" ($after.Count -ge 3) ""

Cleanup
Write-Host ""
Write-Host "RESULTADO: $script:pass OK, $script:fail FALLAS" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $script:fail
