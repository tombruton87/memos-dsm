# Memos's hooks for the chassis core (sourced by run-core.sh). The core gives:
# say, env_get/env_set, rand, compose, in_volume, cname, svc_up, leave_secret,
# fresh, now, qr_png_b64, MSG, VAR, APP, LOG, PKG_NAME, PKG_TITLE, HOST_UID/GID.
#
# Memos's own API does the work. Your account is made at the first start with
# a password shown once; the window then acts through an administrator of the
# package's own ("dsm"), with an access token kept in the root-only .env. The
# window's numbers come from Memos's SQLite database, read read-only. Files
# people attach live in attachments/ in the shared folder (Memos's "local"
# storage). Your password is never stored.

MM=""
PKG_ADMIN=dsm
MEMOS_PIN=neosmemo/memos:0.31   # this package's Memos: 0.31.x patches come through the Updates tab, a newer Memos with a package update
DB=/vol/memos_prod.db
ATTACH=attachments              # in the shared folder; Memos's assets/

app_validate() {   # key value → 0 if the value has the key's shape
  case "$1" in
    ADMIN_USER|MUSER) [[ "$2" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,34}[A-Za-z0-9])?$ && "$2" != "$PKG_ADMIN" ]] ;;
    ROLE)     [[ "$2" =~ ^(user|admin)$ ]] ;;
    LIMIT_MB) [[ "$2" =~ ^(30|100|250|1000)$ ]] ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------ talking to Memos
mm_url() { echo "http://127.0.0.1:$(env_get HTTP_PORT)"; }
strong_password() { echo "$(rand 5)-$(rand 5)-$(rand 5)-$(rand 5)"; }
# One call to Memos's API: the body in MM_OUT, the HTTP code in MM_CODE (globals, so callers needn't use a subshell).
# JSON bodies travel on stdin (passwords never in argv); a 401 makes the package's token again, once.
mm_call() {   # method path token [json]
  local out
  out=$(curl -s --max-time 30 -X "$1" "$(mm_url)/api/v1/$2" ${3:+-H "Authorization: Bearer $3"} -H 'Content-Type: application/json' \
        ${4:+--data-binary @-} -w '\n%{http_code}' 2>/dev/null <<< "${4:-}")
  MM_CODE=${out##*$'\n'}; MM_OUT=${out%$'\n'*}
  [[ "$MM_CODE" =~ ^2 ]]
}
mm_api() {   # method path [json] — as the package's administrator
  mm_call "$1" "$2" "$(env_get DSM_TOKEN)" "${3:-}" && return 0
  [[ "$MM_CODE" == 401 ]] || return 1
  mm_new_token || { MM_CODE=401; return 1; }
  mm_call "$1" "$2" "$(env_get DSM_TOKEN)" "${3:-}"
}
mm_err() { local m; m=$(jq -r '.message // empty' <<< "${MM_OUT:-}" 2>/dev/null | tr -d '\000-\037' | head -c 200); echo "${m:-HTTP ${MM_CODE:-?}}"; }
mm_signin() {   # user password → a short-lived access token in MM_TOKEN
  MM_TOKEN=""
  mm_call POST auth/signin "" "$(jq -cn --arg u "$1" --arg p "$2" '{passwordCredentials: {username: $u, password: $p}}')" || return 1
  MM_TOKEN=$(jq -r '.accessToken // empty' <<< "$MM_OUT" | grep -E '^[A-Za-z0-9._-]+$'); [[ -n "$MM_TOKEN" ]]
}
mm_new_token() {   # the package's administrator signs in and makes a long-lived access token for the window
  local pat
  mm_signin "$PKG_ADMIN" "$(env_get DSM_PASS)" || { say "✗ the package's administrator (dsm) couldn't sign in to Memos: $(mm_err)"; return 1; }
  mm_call POST "users/$PKG_ADMIN/personalAccessTokens" "$MM_TOKEN" '{"description":"Memos window in DSM (the package)","expiresInDays":0}' || { say "✗ Memos didn't make the package's access token: $(mm_err)"; return 1; }
  pat=$(jq -r '.token // empty' <<< "$MM_OUT")
  [[ "$pat" =~ ^memos_pat_[A-Za-z0-9_-]+$ ]] || { say "✗ Memos's access token didn't look as expected"; return 1; }
  env_set DSM_TOKEN "$pat"; say "the package's access token for Memos was made"
}
setting_put() {   # KEY jq-filter — Memos replaces a setting whole: read it, change it, write it back
  mm_api GET "instance/settings/$1" || return 1
  local body; body=$(jq -c "$2" <<< "$MM_OUT") || return 1
  mm_api PATCH "instance/settings/$1" "$body"
}

# ------------------------------------------------------------ lifecycle hooks
app_first_env() {
  env_set MEMOS_IMAGE "$MEMOS_PIN"
  env_set ADMIN_USER "${ADMIN_USER:-admin}"; env_set DSM_USER "$PKG_ADMIN"; env_set DSM_PASS "$(strong_password)"; env_set DSM_TOKEN ""
  touch "$VAR/.needs-users"
}
app_load_env() {
  MM=$(cname server)
  # A package update can bring a newer Memos: move forward to this package's, never back.
  local img; img=$(env_get MEMOS_IMAGE)
  if [[ -z "$img" ]] || { [[ "$img" == neosmemo/memos:* && "$img" != "$MEMOS_PIN" ]] && [[ "$(printf '%s\n%s\n' "${img#*:}" "${MEMOS_PIN#*:}" | sort -V | tail -1)" == "${MEMOS_PIN#*:}" ]]; }; then
    [[ -n "$img" ]] && say "Memos's image: $img → $MEMOS_PIN (this package's)"; env_set MEMOS_IMAGE "$MEMOS_PIN"
  fi
}
app_before_up() {   # attachments/ in the shared folder, owned by the package's user (Memos writes it as that user)
  mkdir -p "$APP/$ATTACH" || return 1
  chown "$HOST_UID:$HOST_GID" "$APP/$ATTACH" 2>/dev/null || true
}
app_health() { [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$(mm_url)/healthz" 2>/dev/null)" == 200 ]]; }
app_version() {   # Memos's own version, kept a few minutes (status asks often)
  if ! fresh "$VAR/.version" 300 || [[ ! -s "$VAR/.version" ]]; then
    curl -s --max-time 5 "$(mm_url)/api/v1/instance/profile" 2>/dev/null | jq -r '.version // empty' 2>/dev/null | tr -cd '0-9A-Za-z.-' | head -c 30 > "$VAR/.version"
  fi
  cat "$VAR/.version" 2>/dev/null
}
app_after_up() { rm -f "$VAR/.version" "$VAR/.dbstats"; make_users 60; }
make_users() {   # [tries] — the first time: your account (Memos's first user, an administrator), then the package's own
  [[ -f "$VAR/.needs-users" ]] || return 0
  local i pw user; user=$(env_get ADMIN_USER)
  for i in $(seq 1 "${1:-1}"); do app_health && break; sleep 2; done
  app_health || { say "Memos isn't answering yet — your account is made when it does"; return 0; }
  if [[ ! -s "$VAR/.first-pass" ]]; then
    pw=$(strong_password)
    if mm_call POST users "" "$(jq -cn --arg u "$user" --arg p "$pw" '{username: $u, password: $p}')" && [[ "$(jq -r .role <<< "$MM_OUT")" == ADMIN ]]; then
      ( umask 077; printf '%s' "$pw" > "$VAR/.first-pass" )   # root-only, until the package's administrator exists
      leave_secret "Memos ($user)" "$pw" users; say "first start: your Memos account $user was made; the password is shown once in the window"
    elif mm_call GET instance/profile "" && [[ "$(jq -r '.needsSetup // false' <<< "$MM_OUT")" == false ]]; then
      say "Memos already has users — the package didn't make one, and can't make its own administrator without one (Users tab)"; rm -f "$VAR/.needs-users"; return 0
    else say "✗ your Memos account couldn't be made: $(mm_err) — trying again shortly"; return 0; fi
  fi
  mm_signin "$user" "$(cat "$VAR/.first-pass")" || { say "✗ your new account couldn't sign in to Memos: $(mm_err) — trying again shortly"; return 0; }
  if ! mm_call POST users "$MM_TOKEN" "$(jq -cn --arg u "$PKG_ADMIN" --arg p "$(env_get DSM_PASS)" '{username: $u, password: $p, role: "ADMIN", displayName: "DSM package (keep this one)"}')" \
     && [[ "$MM_CODE" != 409 ]] && ! grep -qi "exist" <<< "$MM_OUT"; then say "✗ the package's administrator couldn't be made: $(mm_err) — trying again shortly"; return 0; fi
  mm_new_token || return 0
  setting_put GENERAL '.generalSetting.disallowUserRegistration = true' && say "sign-ups are off: only an administrator adds people (Users tab)" || say "✗ sign-ups couldn't be turned off: $(mm_err)"
  rm -f "$VAR/.first-pass" "$VAR/.needs-users"
  say "the package's administrator (dsm) is ready"
}

# ------------------------------------------------------------ what the window shows
# Counts straight from the database (Memos's own API only counts what the asker may see), read-only, kept 30 s.
DB_SQL="SELECT json_object(
  'users', json((SELECT json_group_array(json_object('user', username, 'name', nickname, 'role', role, 'state', row_status, 'created', created_ts,
            'memos', (SELECT count(*) FROM memo m WHERE m.creator_id = u.id AND m.row_status = 'NORMAL'),
            'last_memo', (SELECT max(m.updated_ts) FROM memo m WHERE m.creator_id = u.id),
            'files', (SELECT count(*) FROM attachment a WHERE a.creator_id = u.id),
            'bytes', (SELECT coalesce(sum(a.size), 0) FROM attachment a WHERE a.creator_id = u.id))) FROM (SELECT * FROM user ORDER BY id) u)),
  'memos', (SELECT count(*) FROM memo WHERE row_status = 'NORMAL'),
  'archived', (SELECT count(*) FROM memo WHERE row_status = 'ARCHIVED'),
  'by_storage', json((SELECT json_group_array(json_object('storage', storage_type, 'n', n, 'bytes', b)) FROM (SELECT storage_type, count(*) n, coalesce(sum(size), 0) b FROM attachment GROUP BY storage_type))),
  'unattached', (SELECT count(*) FROM attachment WHERE memo_id IS NULL));"
db_stats() {
  if ! fresh "$VAR/.dbstats" 30 || [[ ! -s "$VAR/.dbstats" ]]; then
    printf '%s\n' "$DB_SQL" | in_volume data rw -- "[ -f $DB ] && sqlite3 -readonly $DB" 2>>"$LOG" | jq -c . > "$VAR/.dbstats.tmp" 2>/dev/null \
      && [[ -s "$VAR/.dbstats.tmp" ]] && mv "$VAR/.dbstats.tmp" "$VAR/.dbstats" || rm -f "$VAR/.dbstats.tmp"
  fi
  cat "$VAR/.dbstats" 2>/dev/null || echo null
}
folder_stats() {   # attachments/ on disk: files and MB, kept 10 minutes
  if ! fresh "$VAR/.folder" 600 || [[ ! -s "$VAR/.folder" ]]; then
    jq -n -c --arg n "$(find "$APP/$ATTACH" -type f 2>/dev/null | wc -l)" --arg mb "$(du -sm "$APP/$ATTACH" 2>/dev/null | cut -f1)" --argjson at "$(now)" \
      '{files: ($n | tonumber? // 0), mb: ($mb | tonumber? // 0), at: $at}' > "$VAR/.folder"
  fi
  cat "$VAR/.folder"
}
qr() {   # the address as a QR code, made again when the address changes
  local url; url=$(env_get APP_URL)
  [[ -s "$VAR/qr.b64" && "$(cat "$VAR/qr.url" 2>/dev/null)" == "$url" ]] || { qr_png_b64 "$url" > "$VAR/qr.b64"; printf '%s' "$url" > "$VAR/qr.url"; }
  cat "$VAR/qr.b64"
}
app_status() {
  svc_up server || { echo '{"up": false}'; return 0; }
  local db settings=null api=false
  db=$(db_stats)
  if mm_api POST instance/settings:batchGet '{"names":["instance/settings/GENERAL","instance/settings/STORAGE","instance/settings/ACCESS"]}'; then
    api=true; settings=$(jq -c '[.settings[]? | {(.name | sub("^instance/settings/"; "")): .}] | add // {}' <<< "$MM_OUT" 2>/dev/null) || settings=null
  fi
  jq -n -c --argjson db "${db:-null}" --argjson s "${settings:-null}" --argjson api "$api" --argjson folder "$(folder_stats)" \
     --arg url "$(env_get APP_URL)" --arg admin "$(env_get ADMIN_USER)" --arg pkg "$PKG_ADMIN" --arg qr "$(qr)" --arg dir "$ATTACH" \
     '($s.STORAGE.storageSetting // {}) as $st | (($st.storages // []) | map(select(.id == $st.defaultStorageId)) | .[0]) as $def
      | {up: true, api: $api, url: $url, admin_user: $admin, pkg_admin: $pkg, qr: $qr,
         users: ($db.users // []), memos: ($db.memos // 0), archived: ($db.archived // 0),
         attachments: {by_storage: ($db.by_storage // []), unattached: ($db.unattached // 0), dir: $dir, folder: $folder},
         signups: (if $s == null then null else (($s.GENERAL.generalSetting.disallowUserRegistration // false) | not) end),
         access: ($s.ACCESS.accessSetting.accessMode // null),
         storage: (if $s == null then null else {type: (($def.type // $st.storageType // "LOCAL") | sub("^STORAGE_TYPE_"; "")), name: ($def.name // ""), template: ($st.filepathTemplate // ""), limit_mb: ($st.uploadSizeLimitMb // 30 | tonumber)} end)}' 2>/dev/null || echo '{"up": true}'
}

# ------------------------------------------------------------ logs, storage, backups, report
app_tick() { make_users 1; return 0; }
app_logs() { :; }
app_storage() {
  in_volume data ro -- 'cd /vol && printf "database\t%s\n" "$(du -cm memos_prod.db* 2>/dev/null | tail -n 1 | cut -f1)"; printf "caches\t%s\n" "$(du -cm .thumbnail_cache .motion_cache 2>/dev/null | tail -n 1 | cut -f1)"; true' </dev/null 2>/dev/null \
    | jq -R -s -c --arg a "$(du -sm "$APP/$ATTACH" 2>/dev/null | cut -f1)" \
      'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] | tonumber? // 0)}) | from_entries | . + {attachments: ($a | tonumber? // 0)}' 2>/dev/null || echo "{}"
}
app_backup() {   # dir — a consistent copy of the database, Memos's other data (not its caches), and attachments/ from the shared folder
  in_volume data rw -- "sqlite3 $DB '.backup /tmp/memos_prod.db' && cat /tmp/memos_prod.db" > "$1/memos_prod.db" 2>>"$LOG" </dev/null && [[ -s "$1/memos_prod.db" ]] || { say "✗ the database copy didn't finish"; return 1; }
  in_volume data ro -- "tar -C /vol -czf - --exclude=./memos_prod.db --exclude='./memos_prod.db-*' --exclude='./assets/*' --exclude='./.thumbnail_cache/*' --exclude='./.motion_cache/*' ." > "$1/files.tar.gz" 2>>"$LOG" </dev/null \
    && tar -tzf "$1/files.tar.gz" >/dev/null 2>&1 || { say "✗ Memos's other files didn't tar"; return 1; }
  mkdir -p "$APP/$ATTACH"
  tar -C "$APP" -czf "$1/attachments.tar.gz" --exclude="./$ATTACH/.thumbnail_cache" "$ATTACH" 2>>"$LOG" || { say "✗ $ATTACH/ didn't tar"; return 1; }
  say "backed up: the database ($(du -h "$1/memos_prod.db" | cut -f1)) and $(find "$APP/$ATTACH" -type f 2>/dev/null | wc -l) attached files"
}
app_restore() {   # dir — the core has stopped the containers
  [[ -s "$1/memos_prod.db" && -f "$1/files.tar.gz" ]] || { MSG="That backup has no database copy."; return 1; }
  in_volume data rw -- 'find /vol -mindepth 1 -delete && tar -C /vol -xzf -' < "$1/files.tar.gz" 2>>"$LOG" || { MSG="Memos's files didn't unpack."; return 1; }
  in_volume data rw -- "cat > $DB" < "$1/memos_prod.db" 2>>"$LOG" || { MSG="The database didn't copy back."; return 1; }
  if [[ -f "$1/attachments.tar.gz" ]]; then
    mkdir -p "$APP/$ATTACH"; find "$APP/$ATTACH" -mindepth 1 -delete 2>>"$LOG" || true
    # The share's permissions are DSM's ACLs: even root can't set modes or times on its folders — those two complaints are expected.
    tar -C "$APP" --no-overwrite-dir --touch -xzf "$1/attachments.tar.gz" 2>"$VAR/.untar-err"; local rc=$?
    grep -vE 'Cannot (change mode|utime)|Exiting with failure status due to previous errors' "$VAR/.untar-err" >> "$LOG"
    if grep -qvE 'Cannot (change mode|utime)|Exiting with failure status due to previous errors' "$VAR/.untar-err" || { (( rc )) && [[ ! -s "$VAR/.untar-err" ]]; }; then rm -f "$VAR/.untar-err"; MSG="The attached files didn't unpack into $ATTACH/."; return 1; fi
    rm -f "$VAR/.untar-err"; chown -R "$HOST_UID:$HOST_GID" "$APP/$ATTACH" 2>/dev/null || true
  fi
  rm -f "$VAR/.dbstats" "$VAR/.folder" "$VAR/.version" "$VAR/.needs-users" "$VAR/.first-pass"
}
app_report() {
  local db; db=$(db_stats)
  echo "== memos: $(jq -r '.memos // "?"' <<< "$db") ($(jq -r '.archived // "?"' <<< "$db") archived)"
  echo "== users"; jq -r '.users[]? | "\(.user)  \(.role)  \(.state)  \(.memos) memos  \(.files) files"' <<< "$db" 2>/dev/null
  echo; echo "== attachments by storage"; jq -r '.by_storage[]? | "\(.storage)  \(.n) files  \(.bytes) bytes"' <<< "$db" 2>/dev/null
  echo "$ATTACH/ in the shared folder: $(folder_stats)"
  echo; echo "== settings"
  if mm_api POST instance/settings:batchGet '{"names":["instance/settings/GENERAL","instance/settings/STORAGE","instance/settings/ACCESS"]}'; then
    jq -c '.settings[]? | del(.generalSetting.additionalScript, .generalSetting.additionalStyle, .storageSetting.s3Config, .storageSetting.storages[]?.s3Config)' <<< "$MM_OUT" 2>/dev/null
  else echo "Memos's API didn't answer the package's administrator: $(mm_err)"; fi
  :
}

# ------------------------------------------------------------ actions
app_act() {   # action (request vars are set)
  local pw role
  rm -f "$VAR/.dbstats"
  case "$1" in
    useradd)
      pw=$(strong_password); role=$([[ "${ROLE:-user}" == admin ]] && echo ADMIN || echo USER)
      mm_api POST users "$(jq -cn --arg u "$MUSER" --arg p "$pw" --arg r "$role" '{username: $u, password: $p, role: $r}')" || { MSG="Memos didn't add $MUSER: $(mm_err)."; return 1; }
      leave_secret "Memos ($MUSER)" "$pw" users; MSG="$MUSER was added$([[ "$role" == ADMIN ]] && echo " as an administrator") — the password is shown once, below." ;;
    userpw|setadmin|userdel)
      mm_api GET "users/$MUSER" || { MSG="There's no user called $MUSER."; return 1; }
      case "$1" in
        userpw) pw=$(strong_password)
          mm_api PATCH "users/$MUSER?updateMask=password" "$(jq -cn --arg u "users/$MUSER" --arg p "$pw" '{name: $u, password: $p}')" || { MSG="Memos didn't take it: $(mm_err)."; return 1; }
          leave_secret "Memos ($MUSER)" "$pw" users; MSG="A new password for $MUSER is ready — it's shown once, below." ;;
        setadmin)
          [[ "$MUSER" == "$(env_get ADMIN_USER)" ]] && { MSG="That's your own account — it stays an administrator."; return 1; }
          role=$([[ "${ROLE:-user}" == admin ]] && echo ADMIN || echo USER)
          mm_api PATCH "users/$MUSER?updateMask=role" "$(jq -cn --arg u "users/$MUSER" --arg r "$role" '{name: $u, role: $r}')" || { MSG="Memos didn't take it: $(mm_err)."; return 1; }
          MSG="$MUSER is $([[ "$role" == ADMIN ]] && echo "now an administrator" || echo "no longer an administrator")." ;;
        userdel)
          [[ "$MUSER" == "$(env_get ADMIN_USER)" ]] && { MSG="That's your own account — remove it in Memos itself if you really mean to."; return 1; }
          mm_api DELETE "users/$MUSER" || { MSG="Memos didn't remove $MUSER: $(mm_err)."; return 1; }
          rm -f "$VAR/.folder"; MSG="$MUSER was removed, with their memos and attached files." ;;
      esac ;;
    signups)
      setting_put GENERAL ".generalSetting.disallowUserRegistration = $([[ "${ON:-0}" == 1 ]] && echo false || echo true)" || { MSG="Memos didn't take it: $(mm_err)."; return 1; }
      MSG=$([[ "${ON:-0}" == 1 ]] && echo "Sign-ups are on: anyone who can reach Memos can make an account." || echo "Sign-ups are off: only an administrator adds people.") ;;
    uploadlimit)
      setting_put STORAGE ".storageSetting.uploadSizeLimitMb = \"$LIMIT_MB\"" || { MSG="Memos didn't take it: $(mm_err)."; return 1; }
      MSG="Each attached file may now be up to $LIMIT_MB MB." ;;
    *) MSG="Unknown request."; return 1 ;;
  esac
  return 0   # each failure above returned 1 itself; a message's own test mustn't decide
}
