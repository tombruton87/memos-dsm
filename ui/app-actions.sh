# Memos's actions, validated by the CGI before they become a request file.
app_cgi_post() {   # action body → sets $lines, or error
  local a=$1 body=$2 u role v
  case "$a" in
    useradd|userpw|setadmin|userdel)
      u=$(param user "$body")
      [[ "$u" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,34}[A-Za-z0-9])?$ && "$u" != dsm ]] || error "400 Bad Request" "A username: letters, digits and dashes, up to 36, starting and ending with a letter or digit (not dsm)."
      lines="ACTION='$a'
MUSER='$u'"
      if [[ "$a" == useradd || "$a" == setadmin ]]; then role=$(param role "$body"); [[ "$role" =~ ^(user|admin)$ ]] || error "400 Bad Request" "Member or administrator."; lines="$lines
ROLE='$role'"; fi ;;
    signups) v=$(param on "$body"); [[ "$v" =~ ^[01]$ ]] || error "400 Bad Request" "On or off."; lines="ACTION='signups'
ON='$v'" ;;
    uploadlimit) v=$(param mb "$body"); [[ "$v" =~ ^(30|100|250|1000)$ ]] || error "400 Bad Request" "Pick a size."; lines="ACTION='uploadlimit'
LIMIT_MB='$v'" ;;
  esac
}
