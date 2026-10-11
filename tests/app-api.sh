# Memos's CGI checks (sourced by chassis/tests/test-api.sh).
expect "useradd good" 202 "$(post "$me" useradd 'action=useradd&user=alice&role=user')"; request_is "useradd request" "ACTION='useradd'
MUSER='alice'
ROLE='user'
BY='$me'"
expect "useradd dsm refused" 400 "$(post "$me" useradd 'action=useradd&user=dsm&role=user')"
expect "useradd dot refused (not a Memos username)" 400 "$(post "$me" useradd 'action=useradd&user=al.ice&role=user')"
expect "useradd trailing dash refused" 400 "$(post "$me" useradd 'action=useradd&user=alice-&role=user')"
expect "useradd injection refused" 400 "$(post "$me" useradd "action=useradd&user=a%27%24(id)&role=user")"
expect "useradd bad role" 400 "$(post "$me" useradd 'action=useradd&user=alice&role=root')"
expect "userpw" 202 "$(post "$me" userpw 'action=userpw&user=bob-2')"; request_is "userpw request" "ACTION='userpw'
MUSER='bob-2'
BY='$me'"
expect "setadmin" 202 "$(post "$me" setadmin 'action=setadmin&user=bob&role=admin')"; request_is "setadmin request" "ACTION='setadmin'
MUSER='bob'
ROLE='admin'
BY='$me'"
expect "setadmin no role" 400 "$(post "$me" setadmin 'action=setadmin&user=bob')"
expect "userdel" 202 "$(post "$me" userdel 'action=userdel&user=bob')"; rm -f "$CHASSIS_VAR/request"
expect "userdel too long" 400 "$(post "$me" userdel "action=userdel&user=$(printf 'a%.0s' {1..37})")"
expect "signups on" 202 "$(post "$me" signups 'action=signups&on=1')"; request_is "signups request" "ACTION='signups'
ON='1'
BY='$me'"
expect "signups bad" 400 "$(post "$me" signups 'action=signups&on=yes')"
expect "uploadlimit" 202 "$(post "$me" uploadlimit 'action=uploadlimit&mb=250')"; request_is "uploadlimit request" "ACTION='uploadlimit'
LIMIT_MB='250'
BY='$me'"
expect "uploadlimit bad" 400 "$(post "$me" uploadlimit 'action=uploadlimit&mb=5000')"
expect "viewer useradd → 403" 403 "$(CHASSIS_ADMINS=no-such-group post "$me" useradd 'action=useradd&user=alice&role=user')"
