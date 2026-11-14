# O que cada conserto muda

Os seis patches mexem no runner do agentes.chat (`apps/server/runner/browser.ts` e `browser-traffic.ts`), com os testes de cada um. As decisões estão escritas no ADR 0040 do projeto, seções 17 a 20, que os próprios patches acrescentam.

Como o navegador do agente funciona, em uma linha: o runner inicia um Google Chrome por agente e fala com ele pelo `agent-browser` (um programa que recebe comandos como `click` e `fill` e os traduz para o protocolo DevTools do Chrome). Na VM, esse Chrome abre numa janela da tela do agente; sem VM, roda sem janela.

## 5. A aba do agente vem para a frente antes de cada comando

`patches/0005`. É o conserto que mais pesa.

**Defeito.** O runner inicia o Chrome com `--restore-last-session`, para o agente não perder as abas. O Chrome volta com todas elas e mostra uma; o `agent-browser` pode se ligar a outra, que ficou em segundo plano. Uma página escondida não responde a eventos de mouse. O clique "como pessoa" do runner é uma sequência de movimentos de mouse, e cada um esperava 5 s sem resposta, até o lote inteiro estourar o limite de 33 s.

**Conserto.** Antes de um comando que precisa da página, o runner pergunta à aba se ela está visível (`document.visibilityState`), no máximo uma vez por segundo. Se estiver escondida, traz para a frente com o comando de troca de aba do próprio `agent-browser` (`tab <id>`), para a aba que ele já segura. A função é `foreground`, em `browser.ts`.

- Nunca faz um comando falhar: se a pergunta não puder ser lida, ou a aba continuar escondida, tenta de novo só depois de 30 s.
- A visão ao vivo, quando abre, faz o mesmo.
- `tab`, `wait`, `dialog` e a leitura do tamanho da página não passam por isso.

## 6. O clique que abre uma janela nova

`patches/0006`.

**Defeito.** O runner mantém uma ligação própria com cada Chrome para contar tráfego (e para a proteção de senha digitada). Essa ligação pedia `Target.setAutoAttach` no nível do navegador. Enquanto algum cliente pede isso, o Chrome nunca confirma a soltura de um clique que chama `window.open`. O clique funcionava, mas o comando ficava 30 s esperando e voltava como erro: `CDP command timed out: Input.dispatchMouseEvent`.

**Conserto.** O contador passa a pedir só para ser avisado dos alvos (`Target.setDiscoverTargets`) e se liga ele mesmo a cada página, página de extensão e worker (`Target.attachToTarget`). Quadros e workers dedicados continuam ligados automaticamente por baixo da página, o que não segura nada. O que cada sessão recebe não mudou.

## 1 e 2. Assumir o controle de verdade

`patches/0001` e `0002`.

**Defeito.** Quando a pessoa assumia o controle, só o clique em andamento do agente era interrompido. Leituras, esperas e o resto do lote seguiam, e o `agent-browser` executa um comando por vez: a entrada da pessoa entrava na fila atrás deles e estourava em 5 s.

**Conserto.** Assumir o controle aborta todo comando do agente, inclusive os enfileirados. Enquanto a pessoa dirige, um comando que não seja dela não entra mais na fila: `get url` e `get title` são respondidos com o que a visão ao vivo já mostrou, e o resto volta na hora com `person_in_control`. Esta parte toca também o servidor (`packages/engine/src/browser/` e o protocolo em `packages/adapters`).

## 3. A entrada da pessoa vai direto pela aba

`patches/0003`.

**Defeito.** Cada clique ou tecla da pessoa passava pelo `agent-browser`, atrás da mesma trava dos comandos. Ele segura essa trava também para a própria manutenção, e numa página com desafio do Cloudflare isso podia durar 30 s. Resultado: "isso não chegou à página".

**Conserto.** Com a pessoa no controle, o runner abre a ligação DevTools da própria aba ativa e manda a entrada por ali, com as mesmas chamadas que o `agent-browser` faria. O caminho antigo fica como reserva quando essa ligação não abre.

## 4. A imagem diz o tamanho real da página

`patches/0004`.

**Defeito.** O `agent-browser` rotula toda imagem da visão ao vivo como 1280×720. Os apps usam esse rótulo para converter o clique na imagem em posição na página. Numa janela de login de 500 pixels de largura, o clique saía 2,5 vezes longe demais.

**Conserto.** Cada imagem sai com o tamanho dela mesma; com a pessoa no controle, a aba informa o próprio tamanho (`Page.getLayoutMetrics`).

## O que não mudou

- Como o agente encontra o alvo na página: planos `browser_do`, alvos em palavras e o Jev (ADR 0054 do projeto).
- A versão do `agent-browser` (0.39.1) e do Chrome.
- O que o contador de tráfego conta e a proteção de senha.
