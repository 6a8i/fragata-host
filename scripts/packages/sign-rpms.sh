#!/bin/sh
# Signs RPMs with the Fragata Host key and checks the signatures, inside the XCP-ng 8.3 build environment.
# usage (in the container): sign-rpms.sh <key dir> <RPM>...
#   key dir: RPM-GPG-KEY-fragata, fragata-signing.secret.asc, passphrase.txt
set -eu
KEYS=$1
shift
command -v rpmsign >/dev/null && command -v expect >/dev/null || yum -q -y install rpm-sign expect >/dev/null
GNUPGHOME=$(mktemp -d)
export GNUPGHOME
gpg2 --batch -q --import "$KEYS/fragata-signing.secret.asc"
FPR=$(gpg2 --list-secret-keys --with-colons --with-fingerprint | awk -F: '/^fpr/ {print $10; exit}')

# rpmsign reads the passphrase from the terminal
cat >"$GNUPGHOME/sign.exp" <<EOT
set timeout -1
spawn sh -c "rpmsign --define '_gpg_name $FPR' --define '_signature gpg' --define '__gpg /usr/bin/gpg2' --addsign $* >/dev/null"
expect "pass phrase:"
send -- "[exec cat $KEYS/passphrase.txt]\r"
expect eof
EOT
expect "$GNUPGHOME/sign.exp" >/dev/null

rpm --import "$KEYS/RPM-GPG-KEY-fragata"
KEY_ID=$(echo "$FPR" | tail -c 9 | tr 'A-F' 'a-f')
for file in "$@"; do
  rpm -Kv "$file" | grep -q "key ID $KEY_ID: OK" || { echo "not signed by Fragata: $file" >&2; exit 1; }
done
rm -rf "$GNUPGHOME"
echo "$# packages signed"
