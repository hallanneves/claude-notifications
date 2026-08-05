# claude-notifications

Notificações nativas do macOS (estilo Slack) para o **Claude Code**: uma skill `/notify` +
três hooks que avisam com **banner, som e emoji certos para cada tipo de evento** — inclusive
um **dialog com botão de Aprovar/Negar** quando o Claude precisa de permissão e você está
longe do editor.

## O que você ganha

| Evento | Notificação | Som | Como acontece |
|---|---|---|---|
| Claude precisa de aprovação | 🔐 Aprovação necessária | Submarine (sonar) | hook `Notification` + dialog `PermissionRequest` |
| Notificação que você pediu | 🔔 (ou emoji contextual) | Glass (ding) | skill `/notify` |
| Trabalho pronto | ✅ Trabalho concluído | Hero (fanfarra) | hook `Stop` + `/notify` em jobs |
| Algo falhou | ❌ Algo falhou | Basso (baque grave) | `/notify` em jobs |

Comportamentos inteligentes:

- **Botão de aprovação**: quando o Claude Code vai pedir permissão e o VSCode/terminal **não**
  está em primeiro plano, aparece um dialog nativo com **Aprovar / Abrir no editor / Negar**.
  A escolha volta pro Claude Code como decisão real. Timeout (50s), erro ou "Abrir no editor"
  caem no prompt normal do terminal — fail-safe.
- **"Trabalho pronto" sem spam**: o banner ✅ de fim de turno é suprimido enquanto o
  editor/terminal está em primeiro plano (você já está vendo o resultado). Saiu pro Slack ou
  navegador? Ele dispara.
- **Lembretes periódicos**: `repeat.sh` roda detached e sobrevive ao fim da sessão.

## Instalação

Requisitos: macOS, [Claude Code](https://claude.com/claude-code), `jq` (incluso no macOS 15+).

```bash
git clone git@github.com:hallanneves/claude-notifications.git
cd claude-notifications
./install.sh
```

O instalador:

1. Copia a skill para `~/.claude/skills/notify/` (vale para **todos** os projetos).
2. Adiciona os hooks `Notification`, `Stop` e `PermissionRequest` ao `~/.claude/settings.json`
   — **sem sobrescrever**: se você já tem hooks nesses eventos, ele pede merge manual com o
   [`hooks.json`](hooks.json).

Depois:

1. **Recomendado:** `brew install terminal-notifier` — sem ele o fallback é `osascript`, e aí
   clicar na notificação (ou em "Mostrar") abre uma janela vazia do Script Editor, um quirk do
   macOS para notificações de CLI. Com ele, **o clique foca o VSCode** (troque o app-alvo com a
   env `NOTIFY_ACTIVATE=<bundle-id>`).
2. **Reinicie o Claude Code** (ou abra `/hooks`) para carregar os hooks.
3. Dispare um teste: `~/.claude/skills/notify/notify.sh --done "Instalação concluída"`.
4. Na primeira notificação o macOS pede permissão (para "terminal-notifier" ou "Script
   Editor") — clique em Permitir. Se o banner não aparecer depois disso: **Ajustes do
   Sistema → Notificações → permitir o app**.

### Instalação manual

Copie `skill/` para `~/.claude/skills/notify/`, dê `chmod +x` nos `.sh`, e faça merge do
conteúdo de `hooks.json` dentro do seu `~/.claude/settings.json`.

## Uso no Claude Code

- `/notify deploy terminou` — banner imediato.
- *"roda a suíte e me avisa quando terminar"* — o Claude roda o job em background e notifica
  com ✅/❌ **conforme o resultado real** (a skill proíbe notificar sucesso sem checar exit code).
- *"me lembra a cada 30 minutos de alongar"* — lembrete periódico detached.
- `/notify list` / `/notify stop` — gerencia lembretes ativos.

Direto no shell (fora do Claude):

```bash
~/.claude/skills/notify/notify.sh --done "build ok"
~/.claude/skills/notify/notify.sh --fail "build quebrou" 
~/.claude/skills/notify/notify.sh "mensagem" "🚀 Título" "subtítulo" "Ping"
~/.claude/skills/notify/repeat.sh 1800 "alongar!"     # a cada 30 min
~/.claude/skills/notify/repeat.sh stop
```

## Como funciona

```
skill/
├── SKILL.md           # instruções que o Claude Code carrega (/notify)
├── notify.sh          # banner nativo via osascript (ou terminal-notifier, se instalado)
├── repeat.sh          # lembretes periódicos detached (start/list/stop)
├── notify-hook.sh     # hook Notification → banner 🔐/💬 "precisa de você"
├── stop-hook.sh       # hook Stop → banner ✅ "pronto" (suprimido com editor em foco)
└── approval-hook.sh   # hook PermissionRequest → dialog Aprovar/Negar com decisão real
```

O gate de primeiro plano usa `lsappinfo` (sem permissões extras). O dialog de aprovação emite
`hookSpecificOutput.decision.behavior: "allow" | "deny"`; qualquer caminho inesperado sai com
código 0 e sem output, o que faz o Claude Code mostrar o prompt interativo normal.

> **Nota**: o formato de resposta do hook `PermissionRequest` ainda tem lacunas na documentação
> oficial ([anthropics/claude-code#11891](https://github.com/anthropics/claude-code/issues/11891)).
> O caminho "allow" foi testado; se o "deny" não surtir efeito em alguma versão, o pior caso é
> o prompt normal aparecer.

## Personalização

- **Sons**: qualquer nome de `ls /System/Library/Sounds` (Glass, Hero, Basso, Submarine, Ping…).
- **App aberto no clique**: com terminal-notifier, o padrão é focar o VSCode; defina
  `NOTIFY_ACTIVATE=<bundle-id>` (ex.: `com.googlecode.iterm2`) para outro app.
- **Apps que suprimem o banner de "pronto"**: edite a lista `case "$FRONT"` em `stop-hook.sh`.

## Desinstalar

```bash
rm -rf ~/.claude/skills/notify
```

E remova as chaves `Notification`, `Stop` e `PermissionRequest` de `hooks` no
`~/.claude/settings.json`.
