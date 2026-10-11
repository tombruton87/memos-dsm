# Memos's steps for the chassis harness (chassis/tests/e2e.sh <appdir> act).
# Memos and attachments are made through Memos's own API, as its web app does.
app_e2e_answers() { printf "ADMIN_USER='alice'\n"; }
wait_for() { local i; for i in $(seq 1 "$2"); do touch "$VAR/watching"; jq -e "$1" "$VAR/status.json" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
secret() { local s; s=$(jq -r 'select(.kind == "users") | .password' "$VAR/secret.json" 2>/dev/null); rm -f "$VAR/secret.json"; printf '%s' "$s"; }
U="http://127.0.0.1:$PORT"
signin() { curl -s -H 'Content-Type: application/json' -d "$(jq -cn --arg u "$1" --arg p "$2" '{passwordCredentials: {username: $u, password: $p}}')" "$U/api/v1/auth/signin" | jq -r '.accessToken // empty'; }
api() { curl -s -X "$1" -H "Authorization: Bearer $2" -H 'Content-Type: application/json' ${4:+-d "$4"} "$U/api/v1/$3"; }
code() { curl -s -o /dev/null -w '%{http_code}' -X "$1" ${2:+-H "Authorization: Bearer $2"} -H 'Content-Type: application/json' ${4:+-d "$4"} "$U/api/v1/$3"; }
memo() { api POST "$1" memos "$(jq -cn --arg c "$2" '{content: $c, visibility: "PRIVATE"}')" | jq -r '.name // empty'; }
attach() {   # token memo-name filename text → the attachment's name
  api POST "$1" attachments "$(jq -cn --arg m "$2" --arg f "$3" --arg c "$(printf '%s' "$4" | base64 -w0)" '{filename: $f, type: "text/plain", content: $c, memo: $m}')" | jq -r '.name // empty'
}
in_share() { local f; f=$(find "$APP/attachments" -type f -name "*_$1" 2>/dev/null | head -1); [[ -n "$f" && "$(cat "$f")" == "$2" ]]; }
app_e2e_act() {
  local fail=0 pw tok m1 a1 pwb pwb2 tokb name before after
  log "memos"
  echo "  (healthz: HTTP $(curl -s -o /dev/null -w '%{http_code}' "$U/healthz"), version $(jq -r .version "$VAR/status.json"))"
  # Your account: made at the first start, shown once; the package's administrator beside it; sign-ups off.
  pw=$(secret)
  [[ ${#pw} -ge 20 ]] && echo "  ok   a one-time password was left for the window" || { echo "  FAIL no password secret"; fail=1; }
  tok=$(signin alice "$pw"); [[ -n "$tok" ]] && echo "  ok   alice signs in to Memos" || { echo "  FAIL sign-in"; fail=1; }
  [[ "$(api GET "$tok" auth/me | jq -r .user.role)" == ADMIN ]] && echo "  ok   …as an administrator" || { echo "  FAIL alice's role"; fail=1; }
  wait_for '.app.api == true and (.app.users | map(.user) | index("alice") and index("dsm")) and .app.signups == false' 30 \
    && echo "  ok   the window: alice and the package's dsm, its token works, sign-ups off" || { echo "  FAIL status: $(jq -c '{api: .app.api, users: [.app.users[]?.user], signups: .app.signups}' "$VAR/status.json")"; fail=1; }
  [[ "$(code POST "" users '{"username":"mallory","password":"x-y-z-1234567"}')" == 403 ]] && echo "  ok   a stranger can't sign up" || { echo "  FAIL anonymous sign-up wasn't refused"; fail=1; }
  [[ "$(curl -s "$U/api/v1/instance/profile" | jq -r '.instanceUrl')" == "http://127.0.0.1:$PORT" ]] && echo "  ok   Memos knows its address (MEMOS_INSTANCE_URL)" || { echo "  FAIL instance url: $(curl -s "$U/api/v1/instance/profile" | jq -c .)"; fail=1; }
  jq -e '.app.qr | length > 100' "$VAR/status.json" >/dev/null && echo "  ok   a QR code of the address for phones" || { echo "  FAIL no qr"; fail=1; }
  # Memos and an attachment, through Memos's API; the file lands in attachments/ in the shared folder.
  m1=$(memo "$tok" "Shopping: milk, bread #home"); memo "$tok" "Call the plumber on Monday #todo" >/dev/null; memo "$tok" "Idea: a shelf for the hall" >/dev/null
  [[ "$m1" == memos/* ]] && echo "  ok   three memos made" || { echo "  FAIL memo: $m1"; fail=1; }
  a1=$(attach "$tok" "$m1" "receipt.txt" "Receipt: 3.20 for milk and bread")
  [[ "$a1" == attachments/* ]] && echo "  ok   a file attached to a memo" || { echo "  FAIL attachment: $a1"; fail=1; }
  in_share receipt.txt "Receipt: 3.20 for milk and bread" && echo "  ok   …and it's an ordinary file in the share's attachments/ ($(basename "$(find "$APP/attachments" -type f -name '*_receipt.txt' | head -1)"))" || { echo "  FAIL not in the share: $(find "$APP/attachments" | head)"; fail=1; }
  [[ "$(stat -c %u "$(find "$APP/attachments" -type f -name '*_receipt.txt' | head -1)" 2>/dev/null)" == "$(id -u)" ]] && echo "  ok   …owned by the package's user (HOST_UID)" || { echo "  FAIL owner $(find "$APP/attachments" -type f -name '*_receipt.txt' -exec stat -c %u:%g {} \;)"; fail=1; }
  [[ "$(curl -s -H "Authorization: Bearer $tok" "$U/file/$a1/receipt.txt")" == "Receipt: 3.20 for milk and bread" ]] && echo "  ok   Memos serves it back" || { echo "  FAIL serving the file"; fail=1; }
  wait_for '.app.memos == 3 and (.app.attachments.by_storage | map(select(.storage == "LOCAL")) | .[0].n == 1) and .app.storage.type == "LOCAL" and (.app.users[] | select(.user == "alice") | .memos == 3 and .files == 1)' 60 \
    && echo "  ok   the window counts 3 memos and 1 file in the shared folder, by person" || { echo "  FAIL counts: $(jq -c '{memos: .app.memos, a: .app.attachments, s: .app.storage}' "$VAR/status.json")"; fail=1; }
  # Sign-ups on and off.
  request "ACTION='signups'" "ON='1'" || fail=1
  [[ "$(code POST "" users '{"username":"carol","password":"c-a-r-o-l-12345"}')" == 200 ]] && echo "  ok   sign-ups on: carol made her own account" || { echo "  FAIL self sign-up"; fail=1; }
  request "ACTION='signups'" "ON='0'" || fail=1
  [[ "$(code POST "" users '{"username":"mallory","password":"x-y-z-1234567"}')" == 403 ]] && echo "  ok   sign-ups off again: refused" || { echo "  FAIL sign-ups off"; fail=1; }
  # People.
  request "ACTION='useradd'" "MUSER='bob'" "ROLE='user'" || fail=1; pwb=$(secret)
  tokb=$(signin bob "$pwb"); [[ -n "$tokb" && "$(api GET "$tokb" auth/me | jq -r .user.role)" == USER ]] && echo "  ok   bob was added as a member and signs in" || { echo "  FAIL bob"; fail=1; }
  memo "$tokb" "Bob's first note" >/dev/null
  request "ACTION='setadmin'" "MUSER='bob'" "ROLE='admin'" || fail=1
  [[ "$(api GET "$tokb" auth/me | jq -r .user.role)" == ADMIN ]] && wait_for '.app.users[] | select(.user == "bob") | .role == "ADMIN"' 20 && echo "  ok   bob made an administrator" || { echo "  FAIL setadmin"; fail=1; }
  request "ACTION='setadmin'" "MUSER='bob'" "ROLE='user'" || fail=1
  request "ACTION='userpw'" "MUSER='bob'" || fail=1; pwb2=$(secret)
  [[ -n "$(signin bob "$pwb2")" && -z "$(signin bob "$pwb")" ]] && echo "  ok   bob's new password works, the old one doesn't" || { echo "  FAIL password change"; fail=1; }
  request "ACTION='setadmin'" "MUSER='alice'" "ROLE='user'" >/dev/null && { echo "  FAIL alice demoted herself"; fail=1; } || echo "  ok   your own account stays an administrator"
  request "ACTION='userdel'" "MUSER='alice'" >/dev/null && { echo "  FAIL removed your own account"; fail=1; } || echo "  ok   …and can't be removed from here"
  # The file size limit.
  request "ACTION='uploadlimit'" "LIMIT_MB='100'" || fail=1
  [[ "$(api GET "$tok" instance/settings/STORAGE | jq -r .storageSetting.uploadSizeLimitMb)" == 100 ]] && wait_for '.app.storage.limit_mb == 100' 20 && echo "  ok   attachments up to 100 MB" || { echo "  FAIL upload limit: $(api GET "$tok" instance/settings/STORAGE | jq -c .)"; fail=1; }
  # The window's token: lost or broken, it is made again.
  docker exec "$NAME" sed -i "s/^DSM_TOKEN=.*/DSM_TOKEN=memos_pat_broken/" "$APP/.env"
  request "ACTION='signups'" "ON='0'" || fail=1
  docker exec "$NAME" grep -qE '^DSM_TOKEN=memos_pat_[A-Za-z0-9_-]{20,}$' "$APP/.env" && echo "  ok   a broken access token is made again" || { echo "  FAIL token renewal"; fail=1; }
  # A backup, then changes, then the restore: the database and attachments/ go back together.
  request "ACTION='backup'" || fail=1; name=$(jq -r '.backups[0].name // ""' "$VAR/status.json")
  grep -q '^attachments/.*_receipt.txt$' < <(tar -xOf "$APP/backups/$name" "${name%.tar}/attachments.tar.gz" | tar -tzf -) && echo "  ok   the backup holds attachments/ (and the database)" || { echo "  FAIL attachments not in the backup"; fail=1; }
  request "ACTION='userdel'" "MUSER='bob'" || fail=1
  memo "$tok" "Written after the backup" >/dev/null; attach "$tok" "$m1" "later.txt" "only after the backup" >/dev/null
  in_share later.txt "only after the backup" && wait_for '.app.memos == 4 and (.app.users | map(.user) | index("bob") | not)' 60 && echo "  ok   after the backup: bob removed, a 4th memo and a 2nd file" || { echo "  FAIL changes after backup: $(jq -c '.app.memos' "$VAR/status.json")"; fail=1; }
  request "ACTION='restore'" "BACKUP='$name'" || fail=1
  wait_for '.app.memos == 4 and (.app.users | map(.user) | index("bob")) and (.app.attachments.by_storage | map(select(.storage == "LOCAL")) | .[0].n == 1)' 60 \
    && echo "  ok   restored: bob is back, 4 memos (alice 3, bob 1), 1 file" || { echo "  FAIL restore: $(jq -c '{m: .app.memos, u: [.app.users[]?.user], a: .app.attachments.by_storage}' "$VAR/status.json")"; fail=1; }
  in_share receipt.txt "Receipt: 3.20 for milk and bread" && ! find "$APP/attachments" -name '*_later.txt' | grep -q . && echo "  ok   attachments/ is as it was: the receipt there, the later file gone" || { echo "  FAIL attachments after restore: $(ls "$APP/attachments")"; fail=1; }
  tok=$(signin alice "$pw"); [[ -n "$tok" && "$(curl -s -H "Authorization: Bearer $tok" "$U/file/$a1/receipt.txt")" == "Receipt: 3.20 for milk and bread" ]] && echo "  ok   alice signs in and opens the restored file" || { echo "  FAIL after restore"; fail=1; }
  wait_for '.app.api == true' 20 && echo "  ok   the window still works through Memos's API" || { echo "  FAIL api after restore"; fail=1; }
  request "ACTION='userdel'" "MUSER='bob'" || fail=1
  wait_for '.app.users | map(.user) | index("bob") | not' 20 && [[ -z "$(signin bob "$pwb2")" ]] && echo "  ok   bob removed" || { echo "  FAIL userdel"; fail=1; }
  (( fail == 0 )) && echo "  memos: all passed" || echo "  memos: something FAILED"
  return $fail
}
