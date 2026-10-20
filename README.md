# claude-notifications

[![CI](https://github.com/hallanneves/claude-notifications/actions/workflows/ci.yml/badge.svg)](https://github.com/hallanneves/claude-notifications/actions/workflows/ci.yml)

*English version: [README.en.md](README.en.md)*

> **Idioma**: a interface fala **português e inglês**. O idioma vem do locale do macOS
> (Ajustes → Idioma e Região) e você força com `NOTIFY_LANG="pt"` ou `"en"` no `notify.conf`.
> Os exemplos deste README mostram os textos em português.

Notificações nativas do macOS (estilo Slack) para o **Claude Code**: uma skill `/notify` +
três hooks que avisam com **banner com o ícone do Claude e um som próprio para cada tipo de
evento** — inclusive um **dialog com botão de Aprovar/Negar** quando o Claude precisa de
permissão e você está longe do editor.

## O que você ganha

| Evento | Título | Som | Como acontece |
|---|---|---|---|
| Claude precisa de aprovação | Aprovação necessária | Submarine (sonar) | hook `Notification` + dialog `PermissionRequest` |
| Notificação que você pediu | Claude Code | Glass (ding) | skill `/notify` |
| Turno concluído (você fora) | `<projeto> · pronto` | Glass (ding) | hook `Stop` |
| Job que você pediu para avisar | Trabalho concluído | Hero (fanfarra) | `/notify` em jobs |
| Algo falhou | Algo falhou | Basso (baque grave) | `/notify` em jobs |

Sem emojis nas mensagens: a identificação visual vem do **ícone do Claude** no banner
(ver `set-claude-icon.sh`) e a semântica vem do som + título.

Comportamentos inteligentes:

- **Janela de aprovação**: quando o Claude Code vai pedir permissão e você **não está
  olhando** (editor/terminal fora do primeiro plano, ou ninguém no teclado há mais de 60 s),
  aparece um painel flutuante por cima de tudo, com o ícone do Claude, o **projeto e a
  branch** que pedem, e as ações. O painel **não rouba o teclado**: você continua digitando
  onde estava, e decide com um clique.

  | Botão | Atalho | O que faz |
  |---|---|---|
  | Aprovar | **só clique** | devolve `allow` ao Claude Code |
  | Aprovar sempre: `<regra>` | **só clique** | aprova e grava a regra que o próprio Claude Code sugere (o "don't ask again" do terminal); só aparece quando há sugestão |
  | **N**egar | `N` | devolve `deny` |
  | **I**r para a sessão | `I` | volta para a aba ou janela da sessão e deixa você decidir lá |
  | Fechar (Esc) | `Esc` | fecha e ignora, sem decidir nada |

  Fechar/Esc, timeout (50s, ajustável em `NOTIFY_DIALOG_TIMEOUT`), erro ou "Ir para a sessão"
  caem no prompt normal do terminal — fail-safe. **Nenhuma tecla aprova**, e os atalhos dos
  outros botões só valem depois que você clica dentro do painel. Voltou para a sessão com o
  painel aberto? Ele fecha sozinho e o prompt dela assume. Várias sessões pedindo ao mesmo
  tempo esperam a vez, uma janela por vez. O comando aparece **inteiro e exatamente como vai
  rodar**, numa caixa rolável; caracteres invisíveis (controle, largura zero, bidi) aparecem
  como `⟨U+202E⟩` em vez de esconder ou reordenar o texto.
  Perguntas do próprio Claude e o plano pronto para revisão não geram janela: viram um banner
  "sua vez" quando você está fora.
- **"Pronto" só quando vale**: o banner de fim de turno fica quieto enquanto você está olhando
  **para aquela sessão**: o app que a mostra em primeiro plano (o Terminal de uma sessão no
  Terminal; VSCode na frente não conta), alguém no teclado e, no herdr, o pane dela na tela.
  Saiu pro Slack, está em outro pane, ou deixou tudo na frente e foi tomar café
  (`NOTIFY_AWAY_SECS`, padrão 60 s)? Ele dispara. Turnos curtos (menos de 30 s,
  `NOTIFY_MIN_TURN_SECS`) não fazem barulho.
- **O banner diz o que aconteceu**: título com o projeto (`claude-notifications · pronto`),
  subtítulo com a branch e, no herdr, o título da sessão, e no corpo a primeira linha da
  resposta do Claude. `NOTIFY_PREVIEW=off` tira a resposta do banner.
- **Uma notificação por sessão**: cada aviso substitui o anterior da mesma sessão, e quando
  você responde a sessão os avisos dela saem da Central de Notificações.
- **Clique volta para onde você estava, nunca para outro app**: no **herdr**, o clique foca o
  **pane exato** da sessão (achado pelo id da sessão, mesmo que o pane tenha mudado de lugar) e
  traz para a frente a aba do Terminal ou do iTerm2 em que o herdr está aberto. Num terminal, o
  clique seleciona a **aba exata** que gerou a notificação (iTerm2 pelo id de sessão,
  Terminal.app pelo tty). No **VSCode** (e no Cursor), com a extensão ponte que o instalador
  coloca, o clique abre a **aba exata do Claude** daquela sessão ou o **terminal integrado**
  em que ela roda, na janela dona da sessão. Sem a ponte, foca a janela do projeto pela raiz
  do workspace (abrir uma subpasta criaria uma janela nova).
  Aba que sumiu cai no app que hospeda a sessão: uma sessão no Terminal ou no herdr nunca abre
  o VSCode. Se o macOS negar a permissão de Automação, chega **um** aviso com um clique para os
  Ajustes. `NOTIFY_ACTIVATE_PATH=never` volta a só focar o app.
- **Silenciar para focar**: `mute.sh 30m` cala tudo por meia hora — banners, lembretes, aviso
  de atualização e **também a janela de aprovação**, que é a interrupção mais agressiva de
  todas. Enquanto silenciado, a permissão cai no prompt normal do terminal, que espera
  quietinho. O Focus do macOS esconde banners, mas não segura um dialog modal.
- **Nada de segredo na tela de bloqueio**: o banner de aprovação diz qual ferramenta o
  Claude quer usar e a descrição que ele mesmo escreveu do comando, nunca o comando. O comando completo fica na janela, que exige sessão desbloqueada — o
  macOS mostra prévia de notificação com a tela travada. `NOTIFY_BANNER_DETAIL=full` volta ao
  comportamento antigo.
- **Lembretes periódicos**: `repeat.sh` roda detached e sobrevive ao fim da sessão.
- **Aviso de versão nova**: uma vez por dia, o fim de turno checa se há uma tag mais recente
  no repositório. Se houver, chega um banner **clicável** que abre uma janela com
  **I̲nstalar / Ver no G̲itHub / Cancelar (Esc)** — clicar nunca instala nada sozinho: isto é
  código aberto e você tem o direito de ler o que vai rodar antes. Silencioso quando já está
  atualizado, e desligável com `NOTIFY_UPDATE_CHECK=0`.

## Instalação

Requisitos: macOS, [Claude Code](https://claude.com/claude-code), `jq` (incluso no macOS 15+).

```bash
git clone git@github.com:hallanneves/claude-notifications.git
cd claude-notifications
brew install terminal-notifier   # recomendado (ícone + clique útil)
./install.sh
```

O instalador:

1. Copia a skill para `~/.claude/skills/notify/` (vale para **todos** os projetos).
2. Adiciona os hooks `Notification`, `Stop`, `PermissionRequest` e `UserPromptSubmit` (este
   assíncrono: limpa os avisos da sessão que você respondeu e mede o turno) ao
   `~/.claude/settings.json`,
   **evento por evento**: eventos livres são adicionados, eventos que já apontam para a skill
   são reconhecidos e deixados como estão (re-rodar o instalador é seguro — é assim que se
   atualiza), e eventos com hooks **de outras ferramentas** nunca são sobrescritos — ele pede
   merge manual com o [`hooks.json`](hooks.json) só para esses. Antes de qualquer alteração,
   faz um backup timestampado (`settings.json.bak.<data>`).
3. Se o terminal-notifier estiver instalado, cria o app **"Claude Code"** em `~/Applications`
   com o ícone do Claude (roda o `install-notifier-app.sh`) e o abre uma vez, para o macOS
   pedir a permissão de notificação (só na criação — atualizações não re-abrem o app).
4. Se o `code` (ou o `cursor`) estiver no PATH, instala a **extensão ponte**
   ([`vscode-bridge/`](vscode-bridge)), que leva o clique até a aba do Claude ou o terminal
   integrado certo. Recarregue as janelas já abertas (*Developer: Reload Window*).
   `NOTIFY_BRIDGE=0` pula esta etapa.

Depois:

1. **Reinicie o Claude Code** (ou abra `/hooks`) para carregar os hooks.
2. Clique em **Permitir** no prompt "Notificações de *Claude Code*".
3. Dispare um teste: `~/.claude/skills/notify/notify.sh --done "Instalação concluída"`.
   Se o banner não aparecer: **Ajustes do Sistema → Notificações → Claude Code**, ligue
   "Permitir notificações" e deixe o estilo em **Banners** ou **Alertas**.

> Sem o terminal-notifier o fallback é `osascript`: funciona, mas o banner sai em nome do
> Script Editor e clicar nele abre uma janela vazia do Script Editor (quirk do macOS para
> notificações de CLI).

### O app "Claude Code" — por que ele existe

Duas razões, e a primeira é o que decide se você recebe notificação **alguma**:

**1. Permissão.** Rodando direto do keg do Homebrew, o macOS (confirmado no 26.x) nunca
registra o terminal-notifier como app apto a notificar: nunca mostra o prompt de permissão,
aceita todas as notificações — elas aparecem no `terminal-notifier -list ALL` — e **descarta
o banner em silêncio**. Todo comando sai com `exit 0`, nenhum erro em lugar nenhum, e nada na
tela. Um bundle com identidade própria em `~/Applications`, **lançado uma vez**, recebe o
prompt normalmente.

**2. Ícone.** O macOS mostra o ícone do *app que posta* a notificação e não deixa customizá-lo
por notificação (`-appIcon` é aceito e ignorado; `-sender` **pendura o processo** e nunca
entrega — não use nenhum dos dois). Trocar o ícone do `terminal-notifier.app` compartilhado
funciona, mas marca com o logo do Claude **toda** notificação de qualquer outro programa que
use o terminal-notifier — e `brew upgrade` desfaz. Com o app dedicado, o logo fica só nele.

De brinde, ele ganha uma entrada própria em Ajustes → Notificações ("Claude Code"), com som,
estilo e Foco independentes.

```bash
./install-notifier-app.sh            # cria (preserva o existente e sua autorização)
./install-notifier-app.sh --force    # recria do zero — o macOS vai pedir permissão de novo
./set-claude-icon.sh                 # só re-aplica o ícone
```

O `set-claude-icon.sh` aplica no app dedicado quando ele existe; sem ele, cai no
`terminal-notifier.app` do Homebrew — e aí sim um `brew upgrade` restaura o ícone original e
o script precisa ser re-rodado.

## Uso no Claude Code

- `/notify deploy terminou` — banner imediato.
- *"roda a suíte e me avisa quando terminar"* — o Claude roda o job em background e notifica
  sucesso ou falha **conforme o resultado real** (a skill proíbe notificar sucesso sem checar
  o exit code).
- *"me lembra a cada 30 minutos de alongar"* — lembrete periódico detached.
- `/notify list` / `/notify stop` — gerencia lembretes ativos.
- *"silencia por 1 hora"* / *"pode voltar a notificar"* — modo foco.
- *"tem versão nova?"* — checa na hora e atualiza se você quiser.

Direto no shell (fora do Claude):

```bash
~/.claude/skills/notify/notify.sh --done "build ok"
~/.claude/skills/notify/notify.sh --fail "build quebrou"
~/.claude/skills/notify/notify.sh "mensagem" "Título" "subtítulo" "Ping"
~/.claude/skills/notify/repeat.sh 1800 "alongar!"     # a cada 30 min
~/.claude/skills/notify/repeat.sh stop
~/.claude/skills/notify/mute.sh 30m                   # silêncio por 30 min
~/.claude/skills/notify/mute.sh off                   # religa
~/.claude/skills/notify/mute.sh status                # como está agora
~/.claude/skills/notify/doctor.sh                     # por que avisou (ou não), e para onde o clique vai
~/.claude/skills/notify/doctor.sh --test              # posta um banner; clique e veja o que o clique fez
~/.claude/skills/notify/check-update.sh --force       # tem versão nova?
~/.claude/skills/notify/update.sh                     # atualiza agora
```

### Atualização

O hook `Stop` roda `check-update.sh` detached, no máximo uma vez por dia (a consulta é um
`git ls-remote` nas tags — sem clone, sem autenticação, sem API). Quando o remoto tem uma tag
maior que o `VERSION` instalado, chega um banner clicável.

O clique **não instala nada**: abre uma janela com três saídas — **I̲nstalar**, **Ver no
G̲itHub** (abre a página de releases no navegador e sai sem tocar em nada) e **Cancelar**,
ligado ao `Esc`. Esse desvio é proposital: é software livre rodando um instalador na sua
máquina, então ler o diff antes tem que ser um clique, não uma escavação. `update.sh --yes`
pula a janela para quem quer automatizar.

Ao instalar, ele clona **exatamente a tag anunciada** (`--branch`) num diretório temporário e
roda o instalador de lá. Seu clone de trabalho nunca é tocado: puxar um branch entregaria
commits ainda não lançados, e dar checkout numa tag dentro do repositório onde você trabalha
te deixaria em detached HEAD. Depois de atualizar, **reinicie o Claude Code** para os hooks
recarregarem.

## Como funciona

```
claude-notifications/
├── install.sh              # instala skill + hooks (+ app, se possível); idempotente, com backup
├── uninstall.sh            # remove skill, app, ponte e SÓ os hooks da skill (preserva os alheios)
├── vscode-bridge/          # extensão ponte do VSCode: aba exata do Claude e terminal integrado
├── install-notifier-app.sh # cria o app "Claude Code" em ~/Applications (permissão + ícone isolado)
├── set-claude-icon.sh      # aplica o ícone do Claude no app dedicado (ou no terminal-notifier)
├── hooks.json              # snippet dos hooks p/ merge manual no settings.json
├── VERSION                 # versão instalada, comparada com as tags do remoto
├── assets/
│   ├── claude-logo.png     # ícone 1024×1024 (gerado do SVG ao lado)
│   └── claude-logo.svg     # fonte vetorial do ícone
├── skill/
│   ├── SKILL.md            # instruções que o Claude Code carrega (/notify)
│   ├── lang/               # catálogos de strings (en.sh, pt.sh)
│   ├── notify-lib.sh       # constantes + helpers compartilhados (bundle, foreground, idioma)
│   ├── notify.sh           # banner nativo (terminal-notifier ou osascript)
│   ├── repeat.sh           # lembretes periódicos detached (start/list/stop)
│   ├── mute.sh             # modo foco: silencia banners e o dialog de aprovação
│   ├── notify.conf.example # config opcional (idioma, app do clique, timeouts, update)
│   ├── notify-hook.sh      # hook Notification → roteia por notification_type
│   ├── stop-hook.sh        # hook Stop → banner "pronto" (quieto se você olha a sessão)
│   ├── prompt-hook.sh      # hook UserPromptSubmit → limpa avisos da sessão, mede o turno
│   ├── doctor.sh           # diagnóstico: origem, gate, clique, notificador, herdr
│   ├── approval-hook.sh    # hook PermissionRequest → dialog Aprovar/Negar
│   ├── dialog.js           # painel flutuante que não rouba o teclado (aprovação, update)
│   ├── check-update.sh     # há versão nova? (rate-limited, banner clicável)
│   └── update.sh           # baixa e reinstala — é o que o clique do banner roda
└── tests/                  # suíte bats (roda no CI em macOS + shellcheck)
```

Notas de segurança do design:

- `repeat.sh stop` só mata processos comprovadamente dele (verifica um marker no `ps` antes do
  `kill` — PID reciclado pós-reboot nunca é alvo) e rejeita intervalos inválidos ou menores
  que 5s (um `sleep` quebrado viraria um loop de spam de notificações).
- O `install.sh` faz backup timestampado (`settings.json.bak.<data>`) antes de mexer nos seus
  hooks e nunca sobrescreve hooks de outras ferramentas; o `uninstall.sh` remove **apenas** as
  entradas de hook que apontam para a skill, preservando qualquer outra intacta.
- O hook `Notification` roteia pelo campo `notification_type` do Claude Code (permissão,
  espera, agente concluído…), com fallback por palavra-chave para versões antigas. Um pedido de
  permissão dispara os dois eventos: quem o anuncia (banner + janela) deixa um marcador por
  sessão e o outro fica calado, então é um banner e um sonar por pedido. Se a janela não
  apareceu (você estava olhando e depois saiu), o `permission_prompt` é a única voz do pedido e
  fala. Tipo desconhecido vira banner informativo, nunca sonar de aprovação.
- O banner de aprovação não inclui o comando por padrão — prévia de notificação aparece na
  tela de bloqueio, e comando carrega segredo. A janela mostra tudo, e ela exige desbloqueio.

O gate de primeiro plano usa `lsappinfo` (sem permissões extras). A decisão sai como
`hookSpecificOutput.decision.behavior: "allow" | "deny"`; qualquer caminho inesperado sai com
código 0 e sem output, o que faz o Claude Code mostrar o prompt interativo normal.

O dialog é um **`NSPanel` não-ativante** (JXA), não um NSAlert nem o `display dialog` do
AppleScript. O NSAlert ativa o app e vira a janela-chave, então o que você estava digitando
no Slack caía nele, e uma letra perdida apertava um botão; o `display dialog` aceita no
máximo 3 botões. Detalhes que só aparecem quando se tenta:

- O painel é mostrado com `orderFrontRegardless` e **sem `runModal`**: uma sessão modal
  torna o painel a janela-chave. Os eventos são bombeados à mão até um clique. O resultado
  foi medido: o app da frente continua o mesmo, o osascript nunca fica ativo e o painel
  nunca vira janela-chave.
- O timeout mora no **shell**, que mata o processo quando ele vence; o mesmo vigia fecha o
  painel quando você volta a olhar a sessão.
- O watchdog do timeout roda com stdout redirecionado. Sem isso ele segura o pipe do
  chamador, e a decisão só chega ao Claude Code quando o timeout inteiro termina — mesmo você
  tendo respondido em 2 segundos.
- "Aprovar sempre" devolve **literalmente** a sugestão que veio em `permission_suggestions`:
  a própria extensão do Claude só aceita `updatedPermissions` que batam com uma sugestão
  oferecida.

> **Nota**: o formato de resposta usado (`hookSpecificOutput.decision.behavior`) é o formato
> documentado atual do hook `PermissionRequest`, e os caminhos allow e deny também foram
> testados ao vivo nesta configuração.

## Personalização

Crie `~/.claude/skills/notify/notify.conf` (há um `notify.conf.example` instalado junto):

```bash
# Idioma da interface: "en" ou "pt". Sem isto, segue o locale do macOS.
NOTIFY_LANG="pt"

# App focado ao clicar na notificação. Padrão: o app que hospeda a sessão
# (Terminal, iTerm2, VSCode, Cursor…), detectado sozinho.
# Descubra o bundle id de um app: osascript -e 'id of app "Cursor"'
NOTIFY_ACTIVATE="com.todesktop.230313mzl4w4u92"

# Segundos sem teclado nem mouse para contar como ausente (padrão: 60).
NOTIFY_AWAY_SECS=60

# Turnos mais curtos que isto não geram banner de "pronto" (padrão: 30; 0 = sempre).
NOTIFY_MIN_TURN_SECS=30

# "off" tira do banner a primeira linha da resposta do Claude (tela de bloqueio).
NOTIFY_PREVIEW=on

# Som de cada evento. "none" silencia. Fim de turno: Glass. Presets: Submarine,
# Hero, Basso, Glass.
NOTIFY_SOUND_TURN=Glass
NOTIFY_SOUND_DONE=Hero

# Apps extras que suprimem o banner de "pronto" e o dialog quando em foco
NOTIFY_FRONT_APPS="MeuEditor,OutroTerminal"

# Binário usado para notificar. Por padrão o app dedicado quando existe, senão o
# terminal-notifier do PATH. Só mexa se quiser apontar para outro bundle.
NOTIFY_TN="$HOME/Applications/Claude Code Notifier.app/Contents/MacOS/terminal-notifier"

# Segundos que o dialog de aprovação espera antes de desistir (padrão: 50).
NOTIFY_DIALOG_TIMEOUT=50

# O que o banner de aprovação mostra: "tool" (padrão) ou "full" (inclui o comando).
NOTIFY_BANNER_DETAIL=tool

# Uma linha por chamada de hook em .debug.log — os hooks falham em silêncio por design.
NOTIFY_DEBUG=1

# Checagem de versão nova (banner clicável). 0 desliga.
NOTIFY_UPDATE_CHECK=0
# Intervalo mínimo entre checagens, em segundos (padrão: 86400 = 1 dia).
NOTIFY_UPDATE_INTERVAL=86400
# Repositório consultado — troque para acompanhar um fork.
NOTIFY_UPDATE_REPO="https://github.com/hallanneves/claude-notifications.git"
```

Outros ajustes:

- **Sons**: qualquer nome de `ls /System/Library/Sounds` (Glass, Hero, Basso, Submarine, Ping…),
  passado como 4º argumento do `notify.sh` — nome inexistente gera um aviso no stderr (o banner
  sairia mudo em silêncio).
- **Ícone**: troque `assets/claude-logo.png` (quadrado, 1024×1024, com alpha) e re-rode
  `set-claude-icon.sh`. O PNG é gerado do `assets/claude-logo.svg` com
  `resvg --width 1024 --height 1024 assets/claude-logo.svg assets/claude-logo.png`.
- **Lembretes**: intervalo mínimo do `repeat.sh` é 5s (proteção contra loop de spam).

## Desinstalar

```bash
./uninstall.sh
```

Remove a skill, o app dedicado, a extensão ponte e as entradas de hook **da skill** no
`~/.claude/settings.json`
(hooks de outras ferramentas ficam intactos; um backup timestampado é criado antes). Se você
tinha aplicado o ícone no terminal-notifier compartilhado do Homebrew:
`brew reinstall terminal-notifier` restaura o original.

## Desenvolvimento

```bash
brew install shellcheck bats-core
shellcheck -x -P SCRIPTDIR -S style install.sh uninstall.sh install-notifier-app.sh set-claude-icon.sh skill/*.sh skill/lang/*.sh
bats tests
```

A mesma dupla roda no CI (GitHub Actions): shellcheck no Ubuntu, bats num runner macOS. Os
testes usam `HOME` descartável e stubs de `terminal-notifier`/`osascript`/`lsappinfo` — nenhum
teste dispara notificação real nem toca no seu `settings.json`.

### Adicionar um idioma

Copie `skill/lang/en.sh` para `skill/lang/<código>.sh` (o código de duas letras, como `es`
ou `fr`), traduza os valores e pronto — nenhum script muda, e quem tiver o macOS nesse idioma
passa a ser atendido automaticamente. Dois testes protegem o resto: os catálogos precisam ter
exatamente as mesmas chaves, e todo `$L_*` usado nos scripts precisa existir em todos eles.
Isso importa porque uma chave faltando **não** gera erro — a string simplesmente sai vazia.

Ao traduzir os botões, mantenha o atalho como a inicial da palavra traduzida (o formato é
`Rótulo:tecla:token`), que é o que faz a letra sublinhada bater com a tecla.

## Licença

Código sob [MIT](LICENSE). O logo (`assets/claude-logo.png`) é marca da Anthropic, usado
apenas para identificar notificações do Claude Code — não é coberto pela MIT.
