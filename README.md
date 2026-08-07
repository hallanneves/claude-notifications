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
| Trabalho pronto | Trabalho concluído | Hero (fanfarra) | hook `Stop` + `/notify` em jobs |
| Algo falhou | Algo falhou | Basso (baque grave) | `/notify` em jobs |

Sem emojis nas mensagens: a identificação visual vem do **ícone do Claude** no banner
(ver `set-claude-icon.sh`) e a semântica vem do som + título.

Comportamentos inteligentes:

- **Botão de aprovação**: quando o Claude Code vai pedir permissão e o seu editor/terminal
  **não** está em primeiro plano (VSCode, Cursor, Zed, Windsurf, iTerm2, Warp, Ghostty…),
  aparece um dialog nativo em primeiro plano, com o ícone do Claude e quatro ações — cada uma
  com **atalho de teclado na letra sublinhada**:

  | Botão | Atalho | O que faz |
  |---|---|---|
  | **A**provar | `A` | devolve `allow` ao Claude Code |
  | **N**egar | `N` | devolve `deny` |
  | Abrir no **e**ditor | `E` | foca o editor e deixa você decidir lá |
  | Fechar (Esc) | `Esc` | fecha e ignora, sem decidir nada |

  Fechar/Esc, timeout (50s, ajustável em `NOTIFY_DIALOG_TIMEOUT`), erro ou "Abrir no editor"
  caem no prompt normal do terminal — fail-safe. **Enter não faz nada**: aprovar exige um
  clique ou a tecla `A`, nunca um toque distraído. Comandos longos aparecem truncados **com
  aviso explícito** (nunca corte silencioso — use "Abrir no editor" para ver tudo), e
  ferramentas de interação (perguntas do próprio Claude) não geram dialog.
- **"Trabalho pronto" sem spam**: o banner de fim de turno é suprimido enquanto o
  editor/terminal está em primeiro plano (você já está vendo o resultado). Saiu pro Slack ou
  navegador? Ele dispara.
- **Clique útil**: clicar em qualquer notificação foca o VSCode (configurável via
  `NOTIFY_ACTIVATE=<bundle-id>`).
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
2. Adiciona os hooks `Notification`, `Stop` e `PermissionRequest` ao `~/.claude/settings.json`,
   **evento por evento**: eventos livres são adicionados, eventos que já apontam para a skill
   são reconhecidos e deixados como estão (re-rodar o instalador é seguro — é assim que se
   atualiza), e eventos com hooks **de outras ferramentas** nunca são sobrescritos — ele pede
   merge manual com o [`hooks.json`](hooks.json) só para esses. Antes de qualquer alteração,
   faz um backup timestampado (`settings.json.bak.<data>`).
3. Se o terminal-notifier estiver instalado, cria o app **"Claude Code"** em `~/Applications`
   com o ícone do Claude (roda o `install-notifier-app.sh`) e o abre uma vez, para o macOS
   pedir a permissão de notificação (só na criação — atualizações não re-abrem o app).

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
- *"tem versão nova?"* — checa na hora e atualiza se você quiser.

Direto no shell (fora do Claude):

```bash
~/.claude/skills/notify/notify.sh --done "build ok"
~/.claude/skills/notify/notify.sh --fail "build quebrou"
~/.claude/skills/notify/notify.sh "mensagem" "Título" "subtítulo" "Ping"
~/.claude/skills/notify/repeat.sh 1800 "alongar!"     # a cada 30 min
~/.claude/skills/notify/repeat.sh stop
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

Ao instalar, ele dá `git pull --ff-only` no clone de origem (registrado na instalação) e
reinstala; se o clone sumiu, clona o repositório canônico num diretório temporário. Nada é
forçado: um clone com commits locais ou mudanças não commitadas faz o fast-forward falhar, e
você recebe um banner de falha em vez de ter o histórico reescrito. Depois de atualizar,
**reinicie o Claude Code** para os hooks recarregarem.

## Como funciona

```
claude-notifications/
├── install.sh              # instala skill + hooks (+ app, se possível); idempotente, com backup
├── uninstall.sh            # remove skill, app e SÓ os hooks da skill (preserva os alheios)
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
│   ├── notify.conf.example # config opcional (app do clique, apps que suprimem)
│   ├── notify-hook.sh      # hook Notification → roteia por notification_type
│   ├── stop-hook.sh        # hook Stop → banner "pronto" (suprimido c/ editor em foco)
│   ├── approval-hook.sh    # hook PermissionRequest → dialog Aprovar/Negar
│   ├── dialog.js           # NSAlert genérico (atalhos sublinhados + ícone do Claude)
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
  espera, agente concluído…), com fallback por palavra-chave para versões antigas.

O gate de primeiro plano usa `lsappinfo` (sem permissões extras). A decisão sai como
`hookSpecificOutput.decision.behavior: "allow" | "deny"`; qualquer caminho inesperado sai com
código 0 e sem output, o que faz o Claude Code mostrar o prompt interativo normal.

O dialog é um **NSAlert** (JXA), não o `display dialog` do AppleScript — este aceita no
máximo 3 botões (precisamos de 4) e não tem atalho por botão nem letra sublinhada. Três
detalhes que só aparecem quando se tenta:

- O timeout mora no **shell**, não no JavaScript: um `NSTimer` agendado nunca dispara durante
  `runModal`, porque o modal roda em `NSModalPanelRunLoopMode` e o timer entra no modo default.
- O watchdog do timeout roda com stdout redirecionado. Sem isso ele segura o pipe do
  chamador, e a decisão só chega ao Claude Code quando o timeout inteiro termina — mesmo você
  tendo respondido em 2 segundos.
- Os títulos sublinhados são aplicados **depois** de `alert.layout`: o NSAlert reconstrói os
  títulos dos botões ao fazer layout e descartaria um `attributedTitle` definido antes.

> **Nota**: o formato de resposta usado (`hookSpecificOutput.decision.behavior`) é o formato
> documentado atual do hook `PermissionRequest`, e os caminhos allow e deny também foram
> testados ao vivo nesta configuração.

## Personalização

Crie `~/.claude/skills/notify/notify.conf` (há um `notify.conf.example` instalado junto):

```bash
# Idioma da interface: "en" ou "pt". Sem isto, segue o locale do macOS.
NOTIFY_LANG="pt"

# App focado ao clicar na notificação (padrão: VSCode).
# Descubra o bundle id do seu editor: osascript -e 'id of app "Cursor"'
NOTIFY_ACTIVATE="com.todesktop.230313mzl4w4u92"

# Apps extras que suprimem o banner de "pronto" e o dialog quando em foco
NOTIFY_FRONT_APPS="MeuEditor,OutroTerminal"

# Binário usado para notificar. Por padrão o app dedicado quando existe, senão o
# terminal-notifier do PATH. Só mexa se quiser apontar para outro bundle.
NOTIFY_TN="$HOME/Applications/Claude Code Notifier.app/Contents/MacOS/terminal-notifier"

# Segundos que o dialog de aprovação espera antes de desistir (padrão: 50).
NOTIFY_DIALOG_TIMEOUT=50
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

Remove a skill, o app dedicado e as entradas de hook **da skill** no `~/.claude/settings.json`
(hooks de outras ferramentas ficam intactos; um backup timestampado é criado antes). Se você
tinha aplicado o ícone no terminal-notifier compartilhado do Homebrew:
`brew reinstall terminal-notifier` restaura o original.

## Desenvolvimento

```bash
brew install shellcheck bats-core
shellcheck -x -P SCRIPTDIR -S style install.sh uninstall.sh install-notifier-app.sh set-claude-icon.sh skill/*.sh
bats tests
```

A mesma dupla roda no CI (GitHub Actions): shellcheck no Ubuntu, bats num runner macOS. Os
testes usam `HOME` descartável e stubs de `terminal-notifier`/`osascript`/`lsappinfo` — nenhum
teste dispara notificação real nem toca no seu `settings.json`.

## Licença

Código sob [MIT](LICENSE). O logo (`assets/claude-logo.png`) é marca da Anthropic, usado
apenas para identificar notificações do Claude Code — não é coberto pela MIT.
