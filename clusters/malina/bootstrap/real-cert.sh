#!/usr/bin/env bash
# Install (or renew) a REAL, bought certificate (home.pl) on the platform.
# The certificate and key NEVER enter git (Constitution III) — the operator
# supplies the files:
#
#   bash real-cert.sh DOMAIN /path/to/fullchain.pem /path/to/privkey.pem
#
# fullchain.pem = server certificate + intermediate chain (home.pl sends
# them as separate files: concatenate certificate.pem + intermediate.pem).
#
# Domain -> TLS Secret mapping (must match the ingresses in git):
#   kreciowo.pl -> demo/kreciowo-tls, jenkins/kreciowo-tls,
#                  argocd/argocd-server-tls (+ removes the dummy Certificate
#                  there so cert-manager does not fight the static secret),
#                  monitoring/kreciowo-tls (Grafana, spec 006)
#   bibop.pl    -> demo/bibop-tls   (demo-symfony ingress)
#
# Hosts NOT covered by the bought certs (no wildcard SAN) keep the
# self-signed dummy cert: demo.kreciowo.pl.
# Idempotent: safe to re-run at every renewal.
set -euo pipefail

DOMAIN="${1:?usage: real-cert.sh DOMAIN FULLCHAIN_PEM PRIVKEY_PEM}"
FULLCHAIN="${2:?usage: real-cert.sh DOMAIN FULLCHAIN_PEM PRIVKEY_PEM}"
PRIVKEY="${3:?usage: real-cert.sh DOMAIN FULLCHAIN_PEM PRIVKEY_PEM}"

case "$DOMAIN" in
  kreciowo.pl) TARGETS="demo:kreciowo-tls jenkins:kreciowo-tls argocd:argocd-server-tls monitoring:kreciowo-tls" ;;
  bibop.pl)    TARGETS="demo:bibop-tls" ;;
  *) echo "ERROR: unknown domain '$DOMAIN' — add it to the mapping in this script" >&2; exit 1 ;;
esac

echo "==> Sanity: key matches the leaf certificate, CN matches the domain"
[ "$(openssl x509 -in "$FULLCHAIN" -noout -pubkey)" = "$(openssl pkey -in "$PRIVKEY" -pubout)" ] \
  || { echo "ERROR: private key does not match the certificate" >&2; exit 1; }
openssl x509 -in "$FULLCHAIN" -noout -subject | grep -q "CN *= *$DOMAIN" \
  || { echo "ERROR: certificate CN is not $DOMAIN" >&2; exit 1; }
openssl x509 -in "$FULLCHAIN" -noout -subject -issuer -enddate | sed 's/^/    /'

for target in $TARGETS; do
  ns="${target%%:*}"; secret="${target##*:}"
  echo "==> Secret $secret ($ns)"
  if [ "$target" = "argocd:argocd-server-tls" ]; then
    # only there does a dummy Certificate own the same secret name —
    # cert-manager must not re-issue over the static secret
    kubectl -n argocd delete certificate kreciowo-dummy --ignore-not-found
  fi
  kubectl -n "$ns" create secret tls "$secret" \
    --cert="$FULLCHAIN" --key="$PRIVKEY" \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo "DONE — verify with:"
echo "  echo | openssl s_client -connect 192.168.68.52:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -issuer"
