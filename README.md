# agentes.chat: VM dos agentes e navegador rápido

Como deixamos a nossa instalação do [agentes.chat](https://github.com/agentes-chat/agentes-chat) com cada agente trabalhando numa tela própria (a "VM") e com o navegador respondendo em menos de um segundo.

São duas partes independentes:

1. **A VM dos agentes** já vem no agentes.chat. É só instalar os pacotes e ligar. Não muda código.
2. **O navegador rápido** são seis consertos nossos no runner. Estão propostos ao projeto no [PR #437](https://github.com/agentes-chat/agentes-chat/pull/437). Enquanto ele não entra, dá para aplicar por conta própria.

Onde isso roda aqui: Ubuntu 24.04, o próprio servidor como computador dos agentes, em modo simples (todos os agentes como um usuário só, `agentes`), Google Chrome 156 e `agent-browser` 0.39.1. O que não testamos está dito em cada parte.

## 1. Ligar a VM dos agentes

O guia oficial cobre tudo em [`SELF_HOSTING.md`](https://github.com/agentes-chat/agentes-chat/blob/main/SELF_HOSTING.md), nas seções "This server as the agents' computer" e "Desktops and terminal (Linux)". O caminho curto:

**Requisitos:** Linux com systemd. Mac e Windows não têm VM: lá o navegador do agente roda sem janela.

**Servidor novo.** O instalador pergunta se o servidor também vai ser o computador dos agentes e o que instalar nele (navegador, telas, Claude Code, Codex). Responda sim.

**Servidor que já existe.** Como root, na pasta onde está o `.env` (troque 3000 pela sua porta, se mudou):

```sh
(umask 077 && openssl rand -base64 48 | tr -d '\n' > /root/host-computer-token)
echo "HOST_COMPUTER_TOKEN=$(cat /root/host-computer-token)" >> .env
docker compose up -d
curl -fsSL http://127.0.0.1:3000/api/machines/install.sh | sh -s -- --system --desktop \
  --server http://127.0.0.1:3000 --host-token-file /root/host-computer-token
```

Em menos de um minuto ele aparece como "This server's computer" na organização. `HOST_COMPUTER_TOKEN` não funciona com cadastro aberto (`ALLOW_SIGNUP=true`).

No Ubuntu o systemd não tem o que o modo `--system` precisa, e o instalador oferece o modo simples. É o que usamos.

**Num computador já conectado**, só os pacotes e a chave:

```sh
sudo apt install --no-install-recommends tigervnc-standalone-server xauth dbus-x11 xfce4-session \
  xfwm4 xfce4-panel xfdesktop4 xfce4-settings thunar xfce4-terminal adwaita-icon-theme \
  elementary-xfce-icon-theme fonts-noto-core fonts-noto-cjk
agentes-runner tools enable desktop terminal
```

Mantenha o `--no-install-recommends`: sem ele cada tela ganha um bloqueio de tela que ninguém consegue destravar.

**No app:**

- O agente precisa da permissão **Use its desktop** (agentes novos já têm).
- Na página do agente, abra a tela dele para assistir ao vivo e use "assumir o controle" para fazer um login por ele. O login fica salvo no navegador do agente.
- Para o agente usar programas da tela sozinho (clicar, digitar, ler), o guia oficial pede o modo `--system`, mais pacotes e a permissão **Run code**: seção "Agents using apps on their desktops". Não usamos isso aqui.

**Conferir:** `agentes-runner status` diz se a tela e o terminal podem rodar e o que falta. `agentes-runner desktop-check --agent <nome>` (com o runner parado) liga a tela do agente, entra nela e desliga.

**Memória:** cerca de 0,2 GB por tela, 0,8 GB com o navegador aberto nela. A tela liga no primeiro uso e fica ligada.

## 2. Navegador rápido

### O que estava errado

| O que se via | Causa |
| --- | --- |
| 17% dos cliques e 41% dos preenchimentos dos agentes davam "The browser didn't answer within 33 s" | O Chrome restaura as abas antigas e o agente pode ficar ligado a uma aba em segundo plano. Aba escondida não responde ao mouse. |
| Clique que abre janela nova ("Continuar com Google") falhava depois de 30 s, embora tivesse funcionado | O contador de tráfego do runner pedia ao Chrome para se ligar sozinho a toda aba nova, e isso segura a resposta do clique. |
| Pessoa no controle: "isso não chegou à página" num desafio do Cloudflare | A entrada dela passava por uma fila que o próprio navegador mantém ocupada. |
| Pessoa no controle conseguia digitar mas não clicar; a página parecia ampliada | Toda imagem saía rotulada como 1280×720, qualquer que fosse o tamanho da página. |
| Assumir o controle não parava o agente | Só o clique era interrompido; leituras e esperas seguiam. |

### Antes e depois

Medido com Chrome 156 de verdade:

| Ação | Antes | Depois |
| --- | --- | --- |
| Clique em botão, lista, link de download, botão de arquivo | 33 s, falha | 0,7 a 0,9 s |
| Preencher 30 letras, digitando como pessoa | 33 s, falha | 3,3 s |
| Clique que abre janela nova | 30 s, falha | 0,8 s |

Vale para o navegador sem janela e para o que roda na VM do agente.

O ganho não vem de modelo de IA. A parte que encontra o botão na página (Jev) é a do próprio agentes.chat e não mudou. O tempo se perdia abaixo dela, entre o runner e o Chrome.

### Aplicar

Os seis commits estão no nosso fork público, no branch [`fix/agent-browser-clicks`](https://github.com/zimcontent/agentes-chat/tree/fix/agent-browser-clicks), em cima do `main` do agentes.chat de 14/11/2026. Mexem só no runner (e em quatro arquivos pequenos do servidor para a parte de "pessoa no controle").

**Se você roda de um fork seu** (é o nosso caso): traga os commits para o seu `main` e monte a imagem como sempre. O app passa a entregar o runner novo.

```sh
git remote add zim https://github.com/zimcontent/agentes-chat.git
git fetch zim fix/agent-browser-clicks
git cherry-pick 49f25d028^..e0280e284
```

**Se você só quer o runner agora**, num computador em modo simples. Precisa do [Bun](https://bun.sh) e do código da mesma versão que o seu servidor roda:

```sh
# no checkout do agentes.chat, na versão do seu servidor
git remote add zim https://github.com/zimcontent/agentes-chat.git
git fetch zim fix/agent-browser-clicks
git cherry-pick 49f25d028^..e0280e284
bun install --frozen-lockfile
bun build apps/server/runner/main.ts --target=node --banner '#!/usr/bin/env node' \
  --outfile /tmp/agentes-runner.mjs

# como o usuário que roda o runner
cp ~/.agentes-runner/agentes-runner.mjs ~/agentes-runner.anterior.mjs
cp /tmp/agentes-runner.mjs ~/.agentes-runner/agentes-runner.mjs
systemctl --user restart agentes-runner.service
```

Cuidados:

- **Use a versão do seu servidor.** Runner e servidor falam um protocolo com número; um runner montado de outra versão pode ser recusado.
- **`agentes-runner update` desfaz a troca**, e a atualização do servidor também: os dois baixam o runner que o app entrega. Por isso o caminho do fork é o que dura.
- Reiniciar o runner não fecha as telas dos agentes, mas corta o que eles estiverem fazendo. Faça com eles parados.
- Para voltar: copie o `agentes-runner.anterior.mjs` de volta e reinicie.
- No modo `--system` o runner fica em `/opt/agentes-runner` e é do root. Não testamos a troca manual lá.

**Conferir que pegou:** depois do primeiro comando de navegador de um agente, o log do runner (`journalctl --user -u agentes-runner.service`) mostra `the browser of <agente> brought its tab to the front` quando a aba estava escondida, e os erros de 33 s somem.

### O que testamos e o que não

- Testes do runner e do navegador passam (206 mais 133), com tipos e lint.
- Roda em produção aqui desde 14/11/2026, em modo simples no Ubuntu 24.04.
- Não testado: modo `--system`, Mac, Windows, Chromium em ARM, outras versões do `agent-browser`.

## Licença

Os commits seguem a licença do agentes.chat (AGPL-3.0-only). Este texto pode ser copiado à vontade.
