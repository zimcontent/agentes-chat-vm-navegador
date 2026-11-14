# agentes.chat: VM dos agentes e navegador rápido

Tudo o que fizemos na nossa instalação do [agentes.chat](https://github.com/agentes-chat/agentes-chat) para cada agente trabalhar numa tela própria (a "VM") e para o navegador responder em menos de um segundo, com o código e os scripts para repetir do começo ao fim.

| O que tem aqui | Para quê |
| --- | --- |
| [`scripts/instalar-vm.sh`](scripts/instalar-vm.sh) | Diz o que falta para a VM, instala e liga |
| [`patches/`](patches) | Os seis consertos do navegador, prontos para `git am` |
| [`scripts/aplicar-navegador.sh`](scripts/aplicar-navegador.sh) | Aplica os consertos, monta o runner e troca o deste computador |
| [`repro/medir.ts`](repro/medir.ts) | Reproduz os defeitos e mede o antes e o depois num Chrome de verdade |
| [`scripts/conferir.sh`](scripts/conferir.sh) | Lê o log do runner e diz se os agentes ainda travam |
| [`docs/como-funciona.md`](docs/como-funciona.md) | O que cada conserto muda e por quê |

São duas partes independentes. A VM já vem no agentes.chat: é instalar e ligar, sem mudar código. O navegador rápido são seis consertos nossos no runner, propostos ao projeto no [PR #437](https://github.com/agentes-chat/agentes-chat/pull/437); enquanto ele não entra, este repositório aplica por conta própria.

**Onde isso foi testado:** Ubuntu 24.04, o próprio servidor como computador dos agentes, em modo simples (todos os agentes como um usuário só), Google Chrome 156, `agent-browser` 0.39.1, Bun 1.4.4. Os patches foram feitos sobre o `main` do agentes.chat de 14/11/2026 (commit `59e1ed178`).

**Não testado:** modo `--system`, Mac, Windows, Chromium em ARM, `instalar-vm.sh --instalar` (aqui os pacotes já estavam instalados e não temos sudo nesse usuário; o modo que só confere foi testado).

```sh
git clone https://github.com/zimcontent/agentes-chat-vm-navegador.git
cd agentes-chat-vm-navegador
```

## Parte 1: ligar a VM dos agentes

A VM é uma tela Linux por agente (Xtigervnc com XFCE). O navegador do agente abre nela, você assiste ao vivo pela página do agente e assume o controle para fazer um login por ele. Só existe no Linux; em Mac e Windows o navegador do agente roda sem janela.

### 1.1 Ter um computador conectado

Escolha um:

**a) Servidor novo.** O instalador do agentes.chat pergunta se o servidor também vai ser o computador dos agentes e o que instalar nele (navegador, telas, Claude Code, Codex). Responda sim a tudo e pule para o passo 1.3.

**b) Servidor que já roda, usando ele mesmo como computador.** Como root, na pasta onde está o `.env` (troque 3000 pela sua porta, se mudou):

```sh
(umask 077 && openssl rand -base64 48 | tr -d '\n' > /root/host-computer-token)
echo "HOST_COMPUTER_TOKEN=$(cat /root/host-computer-token)" >> .env
docker compose up -d
curl -fsSL http://127.0.0.1:3000/api/machines/install.sh | sh -s -- --system --desktop \
  --server http://127.0.0.1:3000 --host-token-file /root/host-computer-token
```

Em menos de um minuto ele aparece como "This server's computer" na organização. Não funciona com cadastro aberto (`ALLOW_SIGNUP=true`). No Ubuntu o systemd não tem o que o `--system` precisa, e a instalação oferece o **modo simples** (todos os agentes como o usuário `agentes`). É o que usamos.

**c) Outro computador Linux.** No app, em Configurações › Dispositivos, conecte o computador com o comando que a tela mostra. Depois siga para o 1.2.

### 1.2 Instalar os pacotes e ligar (caso c, ou um computador conectado antes)

```sh
scripts/instalar-vm.sh              # só diz o que falta
scripts/instalar-vm.sh --instalar   # instala (pede sudo) e liga a tela e o terminal
```

O que o script faz, se preferir à mão:

```sh
sudo apt install --no-install-recommends tigervnc-standalone-server xauth dbus-x11 xfce4-session \
  xfwm4 xfce4-panel xfdesktop4 xfce4-settings thunar xfce4-terminal adwaita-icon-theme \
  elementary-xfce-icon-theme fonts-noto-core fonts-noto-cjk
agentes-runner tools enable desktop terminal
```

Mantenha o `--no-install-recommends`: sem ele cada tela ganha um bloqueio de tela que ninguém consegue destravar. O navegador é o Google Chrome (o `.deb` de google.com/chrome); em ARM, o Chromium.

### 1.3 No app

1. Abra o agente e confira a permissão **Use its desktop** (agentes novos já têm).
2. Na página do agente, abra a tela dele. Ela liga no primeiro uso e fica ligada.
3. Para fazer um login pelo agente: assuma o controle, entre no site e devolva. O login fica no navegador do agente.

Para o agente usar programas da tela sozinho (clicar, digitar, ler), o agentes.chat exige o modo `--system`, mais pacotes (`scripts/instalar-vm.sh --instalar --apps`) e a permissão **Run code**. Não usamos isso aqui.

### 1.4 Conferir

```sh
agentes-runner status                          # diz se tela e terminal podem rodar e o que falta
agentes-runner desktop-check --agent <nome>    # com o runner parado: liga a tela, entra e desliga
```

No computador do próprio servidor, o `status` pode dizer "Desktops: off" com a tela funcionando (acontece aqui); vale o que o app mostra.

**Memória:** cerca de 0,2 GB por tela, 0,8 GB com o navegador aberto nela. O runner só liga uma tela com 1,5 GB livres.

O guia oficial tem o resto dos detalhes: [`SELF_HOSTING.md`](https://github.com/agentes-chat/agentes-chat/blob/main/SELF_HOSTING.md), seções "This server as the agents' computer" e "Desktops and terminal (Linux)".

## Parte 2: navegador rápido

### 2.1 O que estava errado

| O que se via | Causa |
| --- | --- |
| 17% dos cliques e 41% dos preenchimentos dos agentes: "The browser didn't answer within 33 s" | O Chrome restaura as abas antigas e o agente pode ficar ligado a uma aba em segundo plano. Aba escondida não responde ao mouse. |
| Clique que abre janela nova ("Continuar com Google") falhava depois de 30 s, embora tivesse funcionado | O contador de tráfego do runner pedia ao Chrome para se ligar sozinho a toda aba nova, e isso segura a resposta do clique. |
| Pessoa no controle: "isso não chegou à página" num desafio do Cloudflare | A entrada dela passava por uma fila que o próprio navegador mantém ocupada. |
| Pessoa no controle digitava mas não clicava; a página parecia ampliada | Toda imagem saía rotulada como 1280×720, qualquer que fosse o tamanho da página. |
| Assumir o controle não parava o agente | Só o clique era interrompido; leituras e esperas seguiam. |

O ganho não vem de modelo de IA. A parte que encontra o botão na página (Jev) é a do próprio agentes.chat e não mudou. O tempo se perdia abaixo dela, entre o runner e o Chrome. Os detalhes de cada conserto estão em [`docs/como-funciona.md`](docs/como-funciona.md).

### 2.2 Reproduzir o defeito (opcional, uns 5 minutos)

Precisa de [Bun](https://bun.sh), Google Chrome e um checkout do agentes.chat **sem** os consertos:

```sh
git clone https://github.com/agentes-chat/agentes-chat.git ../agentes-chat
(cd ../agentes-chat && git checkout 59e1ed178 && bun install --frozen-lockfile)
bun repro/medir.ts ../agentes-chat ./estado-antes
```

O script abre o navegador três vezes na mesma pasta, porque o defeito da aba escondida só aparece quando o Chrome volta com abas de antes. Saída que tivemos:

```
rodada 3: a aba do agente está hidden logo depois de abrir
│ rodada │ acao                        │ tempo  │ resultado                                               │
│ 1      │ clique num botão            │ 0.7 s  │ ok                                                      │
│ 1      │ preencher 30 letras         │ 3.1 s  │ ok                                                      │
│ 1      │ clique que abre janela nova │ 30.3 s │ falhou: CDP command timed out: Input.dispatchMouseEvent │
│ 3      │ clique num botão            │ 40.0 s │ falhou: The browser didn't answer within 40 s           │
│ 3      │ preencher 30 letras         │ 40.0 s │ falhou: The browser didn't answer within 40 s           │
```

Em qual rodada a aba fica escondida pode variar. `RODADAS=5` roda mais vezes; `VER_LOG=1` mostra o log do runner.

### 2.3 Aplicar os consertos

**Regra que vale para os dois caminhos:** use o código da **mesma versão que o seu servidor roda**. Runner e servidor falam um protocolo com número, e um runner de outra versão pode ser recusado.

#### Caminho A: você monta a sua imagem a partir de um fork (o que dura)

É o nosso caso. No seu fork:

```sh
git am /caminho/de/agentes-chat-vm-navegador/patches/*.patch
```

ou, pelo nosso fork público:

```sh
git remote add zim https://github.com/zimcontent/agentes-chat.git
git fetch zim fix/agent-browser-clicks
git cherry-pick 49f25d028^..e0280e284
```

Monte a imagem e suba como sempre. O app passa a entregar o runner novo, e `agentes-runner update` (ou a própria instalação, no computador do servidor) leva ele aos computadores.

#### Caminho B: trocar só o runner deste computador (rápido, provisório)

Para modo simples, em que o runner roda como o seu usuário:

```sh
# 1. o código do agentes.chat na versão do seu servidor
git clone https://github.com/agentes-chat/agentes-chat.git ../agentes-chat
(cd ../agentes-chat && git checkout <commit ou tag da sua instalação>)

# 2. aplica, monta e confere a versão contra o servidor; não troca nada
scripts/aplicar-navegador.sh ../agentes-chat --servidor http://127.0.0.1:3000

# 3. com os agentes parados, troca o runner e reinicia o serviço
scripts/aplicar-navegador.sh ../agentes-chat --trocar
```

O passo 2 monta o runner do checkout **antes** de aplicar e compara com o que o servidor entrega em `/runner/agentes-runner.mjs`. Se forem iguais, o checkout é a versão certa. Se disser `DIFERENTE`, é outra versão do código ou outro Bun (a comparação só bate com o mesmo Bun que montou a imagem; aqui, 1.4.4): ache a versão certa antes de trocar.

O passo 3 guarda o runner atual em `~/.agentes-runner/agentes-runner.anterior.mjs`, troca, reinicia o serviço de usuário `agentes-runner.service` e, se ele não subir, volta sozinho ao anterior.

Cuidados do caminho B:

- **É provisório.** `agentes-runner update` e a atualização do servidor baixam o runner que o app entrega e desfazem a troca. Para durar, caminho A.
- Reiniciar o runner não fecha as telas dos agentes, mas corta o que eles estiverem fazendo, e fecha o Chrome deles (reabre no próximo uso, com os logins).
- Um dos seis consertos toca também quatro arquivos do servidor (com a pessoa no controle, recusar os comandos do agente). Só com o runner trocado, os cliques e preenchimentos dos agentes já ficam rápidos, que é o principal; a parte completa de "pessoa no controle" precisa do caminho A.
- No modo `--system` o runner fica em `/opt/agentes-runner` e é do root. O script não cobre esse caso.

**Para desfazer:**

```sh
cp ~/.agentes-runner/agentes-runner.anterior.mjs ~/.agentes-runner/agentes-runner.mjs
systemctl --user restart agentes-runner.service
```

### 2.4 Medir o depois

```sh
bun repro/medir.ts ../agentes-chat ./estado-depois
```

Saída que tivemos, com os consertos:

```
│ rodada │ acao                        │ tempo │ resultado │
│ 1      │ clique num botão            │ 0.7 s │ ok        │
│ 1      │ preencher 30 letras         │ 3.1 s │ ok        │
│ 1      │ clique que abre janela nova │ 0.6 s │ ok        │
│ 3      │ clique num botão            │ 0.7 s │ ok        │
│ 3      │ preencher 30 letras         │ 2.8 s │ ok        │
│ 3      │ clique que abre janela nova │ 0.7 s │ ok        │
```

### 2.5 Conferir em produção

```sh
scripts/conferir.sh                 # últimas 24 horas
scripts/conferir.sh "7 days ago"
```

Ele conta, no log do runner, os cliques e preenchimentos dos agentes e quantos passaram de 30 s. No nosso servidor, de 13/11 até a troca do runner: 99 cliques, 31 com 30 s ou mais; 42 preenchimentos, 20 com 30 s ou mais. Depois, a linha `the browser of <agente> brought its tab to the front` aparece quando uma aba escondida é trazida de volta.

### 2.6 Os testes do próprio projeto

No checkout com os consertos:

```sh
bun test apps/server/test/runner/browser.test.ts apps/server/test/runner/browser-traffic.test.ts \
  packages/engine/test/browser-handoff.test.ts
```

Aqui: 206 passam, 0 falham.

## Licença

Os arquivos em `patches/` são mudanças no agentes.chat e seguem a licença dele, AGPL-3.0-only. O resto deste repositório (scripts, medição e textos) é MIT: veja [`LICENSE`](LICENSE).
