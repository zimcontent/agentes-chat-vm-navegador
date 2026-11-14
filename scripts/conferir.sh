#!/usr/bin/env bash
# Lê o log do runner deste computador (serviço de usuário, modo simples) e diz como o navegador dos
# agentes está respondendo: quantos cliques e preenchimentos houve e quantos passaram de 30 s.
#
#   scripts/conferir.sh [período]     período no formato do journalctl (padrão: "24 hours ago")
set -euo pipefail
since=${1:-24 hours ago}
unit=agentes-runner.service
log=$(journalctl --user -u "$unit" --since "$since" --no-pager 2>/dev/null || true)
[[ -n $log ]] || { echo "sem log do $unit desde \"$since\" (no modo --system: sudo journalctl -u agentes-runner)" >&2; exit 1; }

count() { grep -cE "$1" <<<"$log" || true; }
slow() { grep -E "$1" <<<"$log" | grep -cE ' [3-9][0-9]{4}ms' || true; }
for kind in click fill; do
  pattern="browser\.(act|batch) [a-z, ]*\b$kind\b"
  echo "$kind: $(count "$pattern") comandos, $(slow "$pattern") com 30 s ou mais"
done
echo "aba trazida para a frente: $(count 'brought its tab to the front') vezes"
if grep -q 'brought its tab to the front' "$HOME/.agentes-runner/agentes-runner.mjs" 2>/dev/null; then
  echo "runner instalado: com os consertos"
else
  echo "runner instalado: SEM os consertos (ou em outra pasta)"
fi
