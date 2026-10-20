# claude-notifications

[![CI](https://github.com/hallanneves/claude-notifications/actions/workflows/ci.yml/badge.svg)](https://github.com/hallanneves/claude-notifications/actions/workflows/ci.yml)

*English version: [README.en.md](README.en.md)*

> **Idioma**: a interface fala **português e inglês**. O idioma vem do locale do macOS
> (Ajustes → Idioma e Região) e você força com `NOTIFY_LANG="pt"` ou `"en"` no `notify.conf`.
> Os exemplos deste README mostram os textos em português.

Notificações nativas do macOS (estilo Slack) para o **Claude Code**, como **plugin**: uma
skill `/notify` + hooks que avisam com **banner com o ícone do Claude e um som próprio para
cada tipo de evento** — inclusive um **painel com Aprovar/Negar** quando o Claude precisa de
permissão e você não está olhando — e um clique que volta para a **sessão exata**.

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
- **Silenciar para focar**: `mute.sh 30m` cala tudo por meia hora — banners, lembretes e
  **também a janela de aprovação**, que é a interrupção mais agressiva de todas. Enquanto silenciado, a permissão cai no prompt normal do terminal, que espera
  quietinho. O Focus do macOS esconde banners, mas não segura um dialog modal.
- **Nada de segredo na tela de bloqueio**: o banner de aprovação diz qual ferramenta o
  Claude quer usar e a descrição que ele mesmo escreveu do comando, nunca o comando. O comando completo fica na janela, que exige sessão desbloqueada — o
  macOS mostra prévia de notificação com a tela travada. `NOTIFY_BANNER_DETAIL=full` volta ao
  comportamento antigo.
- **Lembretes periódicos**: `repeat.sh` roda detached e sobrevive ao fim da sessão.
- **Atualização pelo sistema de plugins** do Claude Code (veja [Atualizações](#atualizações)).

## Instalação

Requisitos: macOS, [Claude Code](https://claude.com/claude-code) 2.1.275 ou mais novo e `jq`
(incluso no macOS 15+). Recomendado: `brew install terminal-notifier` (ícone do Claude e
clique útil).

No Claude Code:

```
/plugin install notify --marketplace hallanneves/claude-notifications
```

Ou no terminal, `claude plugin install notify --marketplace hallanneves/claude-notifications`,
ou ainda clonando o repo e rodando `./install.sh`, que faz o mesmo e já migra uma instalação
1.x.

Na primeira sessão depois de instalar, o plugin se prepara **em segundo plano**, uma vez por
versão, e avisa numa mensagem:

1. Se o terminal-notifier estiver instalado, cria o app **"Claude Code"** em `~/Applications`
   com o ícone do Claude (`install-notifier-app.sh`) e o abre uma vez, para o macOS pedir a
   permissão de notificação (só na criação: atualizações não reabrem o app).
2. Se o `code` (ou o `cursor`) estiver no PATH, instala a **extensão ponte**
   ([`vscode-bridge/`](vscode-bridge)), que leva o clique até a aba do Claude ou o terminal
   integrado certo. `NOTIFY_BRIDGE=0` no `notify.conf` pula esta etapa.

Depois:

1. Clique em **Permitir** no prompt "Notificações de *Claude Code*".
2. Teste: `/notify instalação concluída`. Se o banner não aparecer: **Ajustes do Sistema →
   Notificações → Claude Code**, ligue "Permitir notificações" e deixe o estilo em **Banners**
   ou **Alertas**. `/notify doctor` diz o que falta.

> Sem o terminal-notifier o fallback é `osascript`: funciona, mas o banner sai em nome do
> Script Editor e clicar nele abre uma janela vazia do Script Editor (quirk do macOS para
> notificações de CLI).

### Atualizações

O Claude Code adiciona marketplaces de terceiros com a **atualização automática desligada**.
Para ligar: `/plugin` → **Marketplaces** → `claude-notifications` → **Enable auto-update**. A
primeira sessão lembra disso uma vez, e o `/notify doctor` mostra o estado. Sem ligar, atualize
quando quiser com `/plugin update notify@claude-notifications`. A versão nova vale a partir da
próxima sessão (ou de `/reload-plugins`).

### Vindo da 1.x

A 1.x copiava a skill para `~/.claude/skills/notify` e escrevia os hooks no
`~/.claude/settings.json`. O Claude Code roda os hooks de um plugin **ao lado** dos do
`settings.json`, sem deduplicar; então, enquanto a 1.x estiver ligada, o plugin fica em espera
(nada toca duas vezes) e cada sessão pede:

```
/notify migrate
```

Ele tira do `settings.json` **só** os hooks da 1.x (com backup timestampado; hooks de outras
ferramentas ficam), move o `notify.conf` e o estado para
`~/Library/Application Support/claude-notifications`, para os lembretes da cópia antiga e
apaga `~/.claude/skills/notify`. Depois, **reinicie as sessões abertas**: elas começaram com
os hooks antigos.

O `./install.sh` da 2.0 faz instalação e migração de uma vez, e é ele que o aviso de
atualização da 1.x roda: quem clicar em **Instalar** chega na 2.0 já migrado.

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

Num clone do repo:

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
- `/notify doctor` — por que avisou (ou não) e para onde o clique vai.
- `/notify migrate` — conclui a troca da 1.x pelo plugin.

Direto no shell (fora do Claude), a partir de um clone do repo:

```bash
skills/notify/notify.sh --done "build ok"
skills/notify/notify.sh --fail "build quebrou"
skills/notify/notify.sh "mensagem" "Título" "subtítulo" "Ping"
skills/notify/repeat.sh 1800 "alongar!"     # a cada 30 min
skills/notify/repeat.sh stop
skills/notify/mute.sh 30m                   # silêncio por 30 min
skills/notify/mute.sh off                   # religa
skills/notify/mute.sh status                # como está agora
skills/notify/doctor.sh                     # por que avisou (ou não), e para onde o clique vai
skills/notify/doctor.sh --test              # posta um banner; clique e veja o que o clique fez
```

## Como funciona

```
claude-notifications/
├── .claude-plugin/
│   ├── plugin.json         # o plugin "notify" (nome, versão)
│   └── marketplace.json    # o repo é o próprio marketplace "claude-notifications"
├── hooks/hooks.json        # SessionStart, Notification, Stop, PermissionRequest, UserPromptSubmit
├── install.sh              # instala o plugin pelo CLI do Claude Code e migra a 1.x
├── uninstall.sh            # remove plugin, app, ponte, estado e o que sobrou da 1.x
├── vscode-bridge/          # extensão ponte do VSCode: aba exata do Claude e terminal integrado
├── install-notifier-app.sh # cria o app "Claude Code" em ~/Applications (permissão + ícone isolado)
├── set-claude-icon.sh      # aplica o ícone do Claude no app dedicado (ou no terminal-notifier)
├── VERSION                 # igual ao "version" do plugin.json (um teste confere)
├── assets/
│   ├── claude-logo.png     # ícone 1024×1024 (gerado do SVG ao lado)
│   └── claude-logo.svg     # fonte vetorial do ícone
├── skills/notify/
│   ├── SKILL.md            # instruções que o Claude Code carrega (/notify)
│   ├── lang/               # catálogos de strings (en.sh, pt.sh)
│   ├── notify-lib.sh       # constantes + helpers compartilhados (origem, gate, idioma, plugin)
│   ├── notify.sh           # banner nativo (terminal-notifier ou osascript)
│   ├── repeat.sh           # lembretes periódicos detached (start/list/stop)
│   ├── mute.sh             # modo foco: silencia banners e o dialog de aprovação
│   ├── notify.conf.example # config opcional (idioma, app do clique, sons, timeouts)
│   ├── session-hook.sh     # hook SessionStart → prepara a versão, pede a migração da 1.x
│   ├── setup.sh            # app de notificação + extensão ponte, uma vez por versão
│   ├── migrate.sh          # /notify migrate: aposenta a instalação 1.x
│   ├── notify-hook.sh      # hook Notification → roteia por notification_type
│   ├── stop-hook.sh        # hook Stop → banner "pronto" (quieto se você olha a sessão)
│   ├── prompt-hook.sh      # hook UserPromptSubmit → limpa avisos da sessão, mede o turno
│   ├── doctor.sh           # diagnóstico: origem, gate, clique, notificador, plugin, herdr
│   ├── approval-hook.sh    # hook PermissionRequest → dialog Aprovar/Negar
│   ├── focus.sh            # o clique: pane do herdr, aba do terminal, aba do Claude no VSCode
│   └── dialog.js           # painel flutuante que não rouba o teclado
└── tests/                  # suíte bats (roda no CI em macOS + shellcheck)
```

Notas de segurança do design:

- `repeat.sh stop` só mata processos comprovadamente dele (verifica um marker no `ps` antes do
  `kill` — PID reciclado pós-reboot nunca é alvo) e rejeita intervalos inválidos ou menores
  que 5s (um `sleep` quebrado viraria um loop de spam de notificações).
- O `/notify migrate` e o `uninstall.sh` fazem backup timestampado (`settings.json.bak.<data>`)
  antes de mexer nos seus hooks e removem **apenas** as entradas que apontam para a cópia 1.x,
  preservando qualquer outra intacta. A migração só roda com o plugin instalado: sem ele, você
  ficaria sem notificação nenhuma.
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
  torna o painel a janela-chave. Os eventos são bombeados à mão, e o painel só pega o teclado
  quando você clica nele. A máscara do laço é `-1`, não `NSEventMaskAny`: esse vale
  `NSUIntegerMax`, que o JXA arredonda para 2^63, e nenhum evento casa (na 1.9.0 o painel
  ignorava todo clique). Os atalhos são lidos no próprio laço, antes de a caixa do comando
  engolir a letra.
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

Crie `~/Library/Application Support/claude-notifications/notify.conf` (fora do plugin, então
as atualizações não o tocam; modelo em
[`skills/notify/notify.conf.example`](skills/notify/notify.conf.example)):

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

# Não instalar a extensão ponte no VSCode/Cursor.
NOTIFY_BRIDGE=0
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

```
/plugin uninstall notify@claude-notifications
```

remove o plugin. Para levar junto o app dedicado, a extensão ponte, o estado e o que tiver
sobrado de uma 1.x, rode num clone do repo:

```bash
./uninstall.sh
```

Hooks de outras ferramentas no `settings.json` ficam intactos (um backup timestampado é criado
antes). Se você tinha aplicado o ícone no terminal-notifier compartilhado do Homebrew:
`brew reinstall terminal-notifier` restaura o original.

## Desenvolvimento

```bash
brew install shellcheck bats-core
shellcheck -x -P SCRIPTDIR -S style install.sh uninstall.sh install-notifier-app.sh set-claude-icon.sh vscode-bridge/build-vsix.sh skills/notify/*.sh skills/notify/lang/*.sh tests/helpers.bash
bats tests
claude plugin validate .
```

O CI (GitHub Actions) roda shellcheck e `claude plugin validate` no Ubuntu e o bats num
runner macOS. Os testes usam `HOME` descartável e stubs de `claude`, `terminal-notifier`,
`osascript` e `lsappinfo`: nenhum teste dispara notificação real, instala plugin ou toca no seu
`settings.json`.

Para testar mudanças locais como plugin: `./install.sh --local` instala a partir do clone, que
o Claude Code carrega no lugar (edições valem na próxima sessão ou com `/reload-plugins`). Ou,
só numa sessão: `claude --plugin-dir .`.

**Release**: suba juntos o `VERSION` e o `version` do `.claude-plugin/plugin.json` (um teste
confere); é a mudança desse número que faz o Claude Code oferecer a atualização. Crie a tag
`v<versão>` no mesmo commit.

### Adicionar um idioma

Copie `skills/notify/lang/en.sh` para `skills/notify/lang/<código>.sh` (o código de duas letras, como `es`
ou `fr`), traduza os valores e pronto — nenhum script muda, e quem tiver o macOS nesse idioma
passa a ser atendido automaticamente. Dois testes protegem o resto: os catálogos precisam ter
exatamente as mesmas chaves, e todo `$L_*` usado nos scripts precisa existir em todos eles.
Isso importa porque uma chave faltando **não** gera erro — a string simplesmente sai vazia.

Ao traduzir os botões, mantenha o atalho como a inicial da palavra traduzida (o formato é
`Rótulo:tecla:token`), que é o que faz a letra sublinhada bater com a tecla.

## Licença

Código sob [MIT](LICENSE). O logo (`assets/claude-logo.png`) é marca da Anthropic, usado
apenas para identificar notificações do Claude Code — não é coberto pela MIT.
