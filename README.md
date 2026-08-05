# claude-notifications

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
  aparece um dialog nativo em primeiro plano com **Aprovar / Abrir no editor / Negar**. A
  escolha volta pro Claude Code como decisão real (allow e deny testados). Timeout (50s),
  erro ou "Abrir no editor" caem no prompt normal do terminal — fail-safe. Comandos longos
  aparecem truncados **com aviso explícito** (nunca corte silencioso — use "Abrir no editor"
  para ver tudo), e ferramentas de interação (perguntas do próprio Claude) não geram dialog.
- **"Trabalho pronto" sem spam**: o banner de fim de turno é suprimido enquanto o
  editor/terminal está em primeiro plano (você já está vendo o resultado). Saiu pro Slack ou
  navegador? Ele dispara.
- **Clique útil**: clicar em qualquer notificação foca o VSCode (configurável via
  `NOTIFY_ACTIVATE=<bundle-id>`).
- **Lembretes periódicos**: `repeat.sh` roda detached e sobrevive ao fim da sessão.

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
2. Adiciona os hooks `Notification`, `Stop` e `PermissionRequest` ao `~/.claude/settings.json`
   — **sem sobrescrever**: se você já tem hooks nesses eventos, ele pede merge manual com o
   [`hooks.json`](hooks.json).
3. Se o terminal-notifier estiver instalado, cria o app **"Claude Code"** em `~/Applications`
   com o ícone do Claude (roda o `install-notifier-app.sh`) e o abre uma vez, para o macOS
   pedir a permissão de notificação.

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

Direto no shell (fora do Claude):

```bash
~/.claude/skills/notify/notify.sh --done "build ok"
~/.claude/skills/notify/notify.sh --fail "build quebrou"
~/.claude/skills/notify/notify.sh "mensagem" "Título" "subtítulo" "Ping"
~/.claude/skills/notify/repeat.sh 1800 "alongar!"     # a cada 30 min
~/.claude/skills/notify/repeat.sh stop
```

## Como funciona

```
claude-notifications/
├── install.sh              # instala skill + hooks (+ app, se possível); faz backup do settings.json
├── install-notifier-app.sh # cria o app "Claude Code" em ~/Applications (permissão + ícone isolado)
├── set-claude-icon.sh      # aplica o ícone do Claude no app dedicado (ou no terminal-notifier)
├── bundle-lib.sh           # resolução de bundle compartilhada pelos dois scripts acima
├── hooks.json              # snippet dos hooks p/ merge manual no settings.json
├── assets/claude-logo.png
└── skill/
    ├── SKILL.md            # instruções que o Claude Code carrega (/notify)
    ├── notify.sh           # banner nativo (terminal-notifier ou osascript)
    ├── repeat.sh           # lembretes periódicos detached (start/list/stop)
    ├── notify.conf.example # config opcional (app do clique, apps que suprimem)
    ├── notify-hook.sh      # hook Notification → banner "precisa de você"
    ├── stop-hook.sh        # hook Stop → banner "pronto" (suprimido c/ editor em foco)
    └── approval-hook.sh    # hook PermissionRequest → dialog Aprovar/Negar
```

Notas de segurança do design:

- `repeat.sh stop` só mata processos comprovadamente dele (verifica um marker no `ps` antes do
  `kill` — PID reciclado pós-reboot nunca é alvo) e rejeita intervalos inválidos ou menores
  que 5s (um `sleep` quebrado viraria um loop de spam de notificações).
- O `install.sh` faz backup (`settings.json.bak`) antes de mexer nos seus hooks e nunca
  sobrescreve hooks existentes.

O gate de primeiro plano usa `lsappinfo` (sem permissões extras). O dialog de aprovação faz
`activate` antes do `display dialog` — sem isso a janela nasce **atrás** do app em foco. A
decisão sai como `hookSpecificOutput.decision.behavior: "allow" | "deny"`; qualquer caminho
inesperado sai com código 0 e sem output, o que faz o Claude Code mostrar o prompt interativo
normal.

> **Nota**: o formato de resposta do hook `PermissionRequest` ainda tem lacunas na documentação
> oficial ([anthropics/claude-code#11891](https://github.com/anthropics/claude-code/issues/11891)),
> mas os caminhos allow e deny foram testados ao vivo nesta configuração.

## Personalização

Crie `~/.claude/skills/notify/notify.conf` (há um `notify.conf.example` instalado junto):

```bash
# App focado ao clicar na notificação (padrão: VSCode).
# Descubra o bundle id do seu editor: osascript -e 'id of app "Cursor"'
NOTIFY_ACTIVATE="com.todesktop.230313mzl4w4u92"

# Apps extras que suprimem o banner de "pronto" e o dialog quando em foco
NOTIFY_FRONT_APPS="MeuEditor,OutroTerminal"

# Binário usado para notificar. Por padrão o app dedicado quando existe, senão o
# terminal-notifier do PATH. Só mexa se quiser apontar para outro bundle.
NOTIFY_TN="$HOME/Applications/Claude Code Notifier.app/Contents/MacOS/terminal-notifier"
```

Outros ajustes:

- **Sons**: qualquer nome de `ls /System/Library/Sounds` (Glass, Hero, Basso, Submarine, Ping…),
  passado como 4º argumento do `notify.sh`.
- **Ícone**: troque `assets/claude-logo.png` (quadrado, com alpha) e re-rode `set-claude-icon.sh`.
- **Lembretes**: intervalo mínimo do `repeat.sh` é 5s (proteção contra loop de spam).

## Desinstalar

```bash
rm -rf ~/.claude/skills/notify
rm -rf ~/Applications/"Claude Code Notifier.app"
brew reinstall terminal-notifier   # só se você tinha usado o ícone no bundle compartilhado
```

E remova as chaves `Notification`, `Stop` e `PermissionRequest` de `hooks` no
`~/.claude/settings.json` (ou restaure o `settings.json.bak` criado na instalação).

## Licença

Código sob [MIT](LICENSE). O logo (`assets/claude-logo.png`) é marca da Anthropic, usado
apenas para identificar notificações do Claude Code — não é coberto pela MIT.
