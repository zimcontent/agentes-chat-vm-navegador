#!/usr/bin/env bash
# Instala o que a VM (tela) dos agentes precisa num computador Linux com apt (Debian ou Ubuntu) que já
# está conectado ao agentes.chat, e liga a tela e o terminal no runner.
#
#   scripts/instalar-vm.sh            diz o que falta, sem instalar nada
#   scripts/instalar-vm.sh --instalar instala os pacotes (pede sudo) e liga a tela e o terminal
#   scripts/instalar-vm.sh --instalar --apps   também o que o agente precisa para usar programas da tela
#
# Os nomes dos pacotes são os do guia oficial (SELF_HOSTING.md, "Desktops and terminal (Linux)").
set -euo pipefail

install=0 apps=0
for arg in "$@"; do
  case $arg in
    --instalar) install=1 ;;
    --apps) apps=1 ;;
    -h | --help) sed -n 2,9p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' && exit 0 ;;
    *) echo "opção desconhecida: $arg" >&2 && exit 2 ;;
  esac
done
[[ $(uname -s) == Linux ]] || { echo "a VM dos agentes só existe no Linux" >&2; exit 1; }
command -v dpkg-query >/dev/null || { echo "este script é para Debian e Ubuntu (apt)" >&2; exit 1; }

packages=(tigervnc-standalone-server xauth dbus-x11 xfce4-session xfwm4 xfce4-panel xfdesktop4
  xfce4-settings thunar xfce4-terminal adwaita-icon-theme elementary-xfce-icon-theme fonts-noto-core
  fonts-noto-cjk)
[[ $apps == 1 ]] && packages+=(python3 python3-gi python3-xlib xdotool scrot at-spi2-core)

missing=()
for package in "${packages[@]}"; do
  [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) == "install ok installed" ]] || missing+=("$package")
done
if [[ ${#missing[@]} -eq 0 ]]; then
  echo "pacotes: todos instalados"
else
  echo "pacotes que faltam: ${missing[*]}"
fi
if command -v google-chrome >/dev/null || command -v chromium >/dev/null || command -v chromium-browser >/dev/null; then
  echo "navegador: instalado"
else
  echo "navegador: falta o Google Chrome (em ARM, o Chromium). Baixe o .deb em google.com/chrome"
fi
free_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
echo "memória livre: $((free_kb / 1024 / 1024)) GB (cada tela usa cerca de 0,2 GB; 0,8 GB com o navegador nela; o runner exige 1,5 GB livres para ligar uma)"

runner=$(command -v agentes-runner || true)
[[ -n $runner ]] || for candidate in "$HOME/.agentes-runner/bin/agentes-runner" /opt/agentes-runner/bin/agentes-runner; do
  [[ -x $candidate ]] && runner=$candidate && break
done
if [[ -z $runner ]]; then
  echo "runner: não achei o agentes-runner. Conecte este computador primeiro (Configurações › Dispositivos no app)."
else
  echo "runner: $runner"
  "$runner" status 2>&1 | grep -iE "desktop|terminal" || true
  echo "  (no computador do próprio servidor esse status pode dizer \"off\" com a tela funcionando: vale o que o app mostra)"
fi

if [[ $install == 0 ]]; then
  echo
  echo "Nada foi instalado. Para instalar e ligar: scripts/instalar-vm.sh --instalar"
  exit 0
fi
if [[ ${#missing[@]} -gt 0 ]]; then
  # Sem os recomendados: com eles cada tela ganha um bloqueio de tela que ninguém consegue destravar.
  sudo apt-get update
  sudo apt-get install --yes --no-install-recommends "${missing[@]}"
fi
[[ -n $runner ]] || { echo "pacotes instalados. Falta conectar o computador e rodar: agentes-runner tools enable desktop terminal" >&2; exit 1; }
if ! "$runner" tools enable desktop terminal; then
  # No computador do próprio servidor ("This server's computer") quem liga é a instalação do servidor.
  echo "o runner recusou a chave. Se este é o computador do próprio servidor, rode de novo a instalação do agentes.chat: ela liga a tela."
fi
"$runner" status
