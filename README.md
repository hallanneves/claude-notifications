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

- **Botão de aprovação**: quando o Claude Code vai pedir permissão e o VSCode/terminal **não**
  está em primeiro plano, aparece um dialog nativo em primeiro plano com **Aprovar / Abrir no
  editor / Negar**. A escolha volta pro Claude Code como decisão real (allow e deny testados).
  Timeout (50s), erro ou "Abrir no editor" caem no prompt normal do terminal — fail-safe.
  Ferramentas de interação (perguntas do próprio Claude) não geram dialog.
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
3. Se o terminal-notifier estiver instalado, aplica o **ícone do Claude** nas notificações
   (roda o `set-claude-icon.sh`).

Depois:

1. **Reinicie o Claude Code** (ou abra `/hooks`) para carregar os hooks.
2. Dispare um teste: `~/.claude/skills/notify/notify.sh --done "Instalação concluída"`.
3. Na primeira notificação o macOS pede permissão (para "terminal-notifier" ou "Script
   Editor") — clique em Permitir. Se o banner não aparecer depois disso: **Ajustes do
   Sistema → Notificações → permitir o app**.

> Sem o terminal-notifier o fallback é `osascript`: funciona, mas o banner sai em nome do
> Script Editor e clicar nele abre uma janela vazia do Script Editor (quirk do macOS para
> notificações de CLI).

### Ícone do Claude

O macOS mostra o ícone do **app que posta** a notificação e não permite customizá-lo por
notificação. O `set-claude-icon.sh` resolve trocando o ícone do próprio
`terminal-notifier.app` (gera o `.icns` a partir de `assets/claude-logo.png`, re-assina o
bundle ad-hoc e recarrega o Notification Center).

**`brew upgrade terminal-notifier` restaura o ícone original** — é só rodar o script de novo:

```bash
./set-claude-icon.sh
```

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
├── install.sh            # instala skill + hooks (+ ícone, se possível)
├── set-claude-icon.sh    # aplica o ícone do Claude no terminal-notifier.app
├── hooks.json            # snippet dos hooks p/ merge manual no settings.json
├── assets/claude-logo.png
└── skill/
    ├── SKILL.md          # instruções que o Claude Code carrega (/notify)
    ├── notify.sh         # banner nativo (terminal-notifier ou osascript)
    ├── repeat.sh         # lembretes periódicos detached (start/list/stop)
    ├── notify-hook.sh    # hook Notification → banner "precisa de você"
    ├── stop-hook.sh      # hook Stop → banner "pronto" (suprimido c/ editor em foco)
    └── approval-hook.sh  # hook PermissionRequest → dialog Aprovar/Negar
```

O gate de primeiro plano usa `lsappinfo` (sem permissões extras). O dialog de aprovação faz
`activate` antes do `display dialog` — sem isso a janela nasce **atrás** do app em foco. A
decisão sai como `hookSpecificOutput.decision.behavior: "allow" | "deny"`; qualquer caminho
inesperado sai com código 0 e sem output, o que faz o Claude Code mostrar o prompt interativo
normal.

> **Nota**: o formato de resposta do hook `PermissionRequest` ainda tem lacunas na documentação
> oficial ([anthropics/claude-code#11891](https://github.com/anthropics/claude-code/issues/11891)),
> mas os caminhos allow e deny foram testados ao vivo nesta configuração.

## Personalização

- **Sons**: qualquer nome de `ls /System/Library/Sounds` (Glass, Hero, Basso, Submarine, Ping…).
- **App aberto no clique**: padrão é o VSCode; defina `NOTIFY_ACTIVATE=<bundle-id>`
  (ex.: `com.googlecode.iterm2`).
- **Ícone**: troque `assets/claude-logo.png` (quadrado, com alpha) e re-rode `set-claude-icon.sh`.
- **Apps que suprimem o banner de "pronto"**: edite a lista `case "$FRONT"` em `stop-hook.sh`.

## Desinstalar

```bash
rm -rf ~/.claude/skills/notify
brew reinstall terminal-notifier   # restaura o ícone original
```

E remova as chaves `Notification`, `Stop` e `PermissionRequest` de `hooks` no
`~/.claude/settings.json`.
