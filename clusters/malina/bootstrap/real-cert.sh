#!/usr/bin/env bash
# Install (or renew) the REAL kreciowo.pl certificate (bought at home.pl).
# The certificate and key NEVER enter git (Constitution III) — the operator
# supplies the files:
#
#   bash real-cert.sh /path/to/fullchain.pem /path/to/privkey.pem
#
# fullchain.pem = server certificate + intermediate chain (home.pl sends
# them as separate files: concatenate certificate.pem + intermediate.pem).
#
# What it does:
#   1. creates/rotates secret `kreciowo-tls` in namespaces demo + jenkins
#      (kreciowo.pl, www.kreciowo.pl, /jenkins + webhook ingresses),
#   2. creates/rotates secret `argocd-server-tls` in namespace argocd and
#      deletes the dummy Certificate there, so cert-manager does not fight
#      the static secret,
#   3. leaves `kreciowo-dummy-tls` in demo alone — demo.kreciowo.pl is not
#      covered by the bought certificate (no wildcard SAN).
# Idempotent: safe to re-run at every renewal.
set -euo pipefail

FULLCHAIN="${1:?usage: real-cert.sh FULLCHAIN_PEM PRIVKEY_PEM}"
PRIVKEY="${2:?usage: real-cert.sh FULLCHAIN_PEM PRIVKEY_PEM}"

echo "==> Sanity: key matches the leaf certificate"
[ "$(openssl x509 -in "$FULLCHAIN" -noout -pubkey)" = "$(openssl pkey -in "$PRIVKEY" -pubout)" ] \
  || { echo "ERROR: private key does not match the certificate" >&2; exit 1; }
openssl x509 -in "$FULLCHAIN" -noout -subject -issuer -enddate | sed 's/^/    /'

echo "==> Secret kreciowo-tls (demo, jenkins)"
for ns in demo jenkins; do
  kubectl -n "$ns" create secret tls kreciowo-tls \
    --cert="$FULLCHAIN" --key="$PRIVKEY" \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> Secret argocd-server-tls (argocd)"
kubectl -n argocd delete certificate kreciowo-dummy --ignore-not-found
kubectl -n argocd create secret tls argocd-server-tls \
  --cert="$FULLCHAIN" --key="$PRIVKEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "DONE — verify with:"
echo '  echo | openssl s_client -connect 192.168.68.52:443 -servername kreciowo.pl 2>/dev/null | openssl x509 -noout -issuer'
