    echo "ADMIN_USER='$(printf '%s' "${wizard_admin_user:-admin}" | tr -cd 'A-Za-z0-9-' | head -c 36)'"
