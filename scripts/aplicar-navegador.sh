#!/usr/bin/env bash
# Aplica os seis consertos do navegador num checkout do agentes.chat, monta o runner e, se pedido,
# troca o runner deste computador (modo simples: o runner roda como o usuário que chama o script).
#
#   scripts/aplicar-navegador.sh <checkout do agentes.chat> [opções]
#
#   --servidor URL     confere antes que o checkout é a versão que o servidor roda (ex. http://127.0.0.1:3000)
#   --trocar           troca o runner deste computador e reinicia o serviço (sem isso, só monta)
#   --runner-home DIR  pasta do runner (padrão: ~/.agentes-runner)
#   --saida ARQUIVO    onde gravar o runner montado (padrão: ./agentes-runner.mjs)
#
# Precisa de git, bun e node. Não usa sudo. Para desfazer a troca: copie o arquivo
# agentes-runner.anterior.mjs de volta e reinicie o serviço.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo="" server="" swap=0 home_dir="$HOME/.agentes-runner" out="$PWD/agentes-runner.mjs"
while [[ $# -gt 0 ]]; do
  case $1 in
    --servidor) server=${2:?} && shift 2 ;;
    --trocar) swap=1 && shift ;;
    --runner-home) home_dir=${2:?} && shift 2 ;;
    --saida) out=${2:?} && shift 2 ;;
    -h | --help) sed -n 2,14p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' && exit 0 ;;
    *) [[ -z $repo ]] && repo=$1 && shift || { echo "argumento a mais: $1" >&2; exit 2; } ;;
  esac
done
[[ -n $repo ]] || { echo "uso: scripts/aplicar-navegador.sh <checkout do agentes.chat> [--servidor URL] [--trocar]" >&2; exit 2; }
for tool in git bun node; do
  command -v "$tool" >/dev/null || { echo "falta o $tool no PATH" >&2; exit 1; }
done
repo=$(cd "$repo" && pwd)
entry=apps/server/runner/main.ts
[[ -f $repo/$entry ]] || { echo "$repo não parece um checkout do agentes.chat (falta $entry)" >&2; exit 1; }
cd "$repo"

build() { bun build "$entry" --target=node --banner '#!/usr/bin/env node' --outfile "$1" >/dev/null; }
sum() { sha256sum "$1" | cut -d' ' -f1; }
marker='brought its tab to the front'

echo "1/5 dependências (bun install)"
bun install --frozen-lockfile >/dev/null 2>&1 || { echo "bun install falhou; rode-o à mão para ver o erro" >&2; exit 1; }

if grep -q "$marker" apps/server/runner/browser.ts; then
  echo "2/5 os consertos já estão neste checkout"
  echo "3/5 nada a aplicar"
else
  [[ -z $(git status --porcelain --untracked-files=no) ]] || { echo "o checkout tem mudanças não commitadas; guarde-as antes" >&2; exit 1; }
  if [[ -n $server ]]; then
    echo "2/5 conferindo a versão contra $server"
    tmp=$(mktemp -d)
    build "$tmp/base.mjs"
    curl -fsS -o "$tmp/servido.mjs" "$server/runner/agentes-runner.mjs"
    if [[ $(sum "$tmp/base.mjs") == $(sum "$tmp/servido.mjs") ]]; then
      echo "    igual: este checkout é a versão que o servidor roda"
    else
      echo "    DIFERENTE: o runner que o servidor entrega não é o deste checkout." >&2
      echo "    Pode ser outra versão do código ou outra versão do bun (aqui: $(bun --version))." >&2
      echo "    Um runner de outra versão pode ser recusado pelo servidor. Para seguir assim mesmo: SEGUIR=1" >&2
      [[ ${SEGUIR:-} == 1 ]] || exit 1
    fi
    rm -rf "$tmp"
  else
    echo "2/5 versão não conferida (use --servidor URL para conferir)"
  fi
  echo "3/5 aplicando os seis consertos (git am)"
  git config user.email >/dev/null || export GIT_COMMITTER_EMAIL=aplicar@localhost GIT_COMMITTER_NAME=aplicar-navegador
  if ! git am --3way "$here"/patches/*.patch >/dev/null; then
    git am --abort || true
    echo "os consertos não aplicam limpo neste código. Ele pode já ter parte deles, ou ser de uma versão distante." >&2
    exit 1
  fi
fi

echo "4/5 montando o runner"
build "$out"
node --check "$out"
grep -q "$marker" "$out" || { echo "o runner montado não tem os consertos" >&2; exit 1; }
echo "    $out ($(sum "$out" | cut -c1-12))"

if [[ $swap == 0 ]]; then
  echo "5/5 pronto. Nada foi trocado. Para trocar o runner deste computador, rode de novo com --trocar."
  exit 0
fi
target=$home_dir/agentes-runner.mjs
[[ -f $target ]] || { echo "não achei $target (modo --system? o runner fica em /opt/agentes-runner e é do root)" >&2; exit 1; }
unit=agentes-runner.service
systemctl --user cat "$unit" >/dev/null 2>&1 || { echo "não achei o serviço de usuário $unit" >&2; exit 1; }
echo "5/5 trocando o runner"
cp -p "$target" "$home_dir/agentes-runner.anterior.mjs"
cp "$out" "$target.novo" && chmod 644 "$target.novo" && mv "$target.novo" "$target"
systemctl --user restart "$unit"
sleep 8
systemctl --user is-active --quiet "$unit" || {
  echo "o serviço não subiu; voltando ao runner anterior" >&2
  cp -p "$home_dir/agentes-runner.anterior.mjs" "$target"
  systemctl --user restart "$unit"
  exit 1
}
echo "    no ar. O anterior ficou em $home_dir/agentes-runner.anterior.mjs"
echo "    Confira com: scripts/conferir.sh"
