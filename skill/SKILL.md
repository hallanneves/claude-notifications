---
name: notify
description: Notificação nativa do macOS (banner + som, estilo Slack). Use quando o usuário pedir /notify, "me avisa/notifica quando X terminar" (build, testes, deploy, CI, job longo), lembretes periódicos ("me lembra a cada 30 min"), ou para parar lembretes ativos (/notify stop, /notify list). Sons e emojis semânticos por tipo de evento (aprovação/info/pronto/falha).
---

# notify — notificações nativas do macOS

Scripts neste diretório (`~/.claude/skills/notify/`):

- `notify.sh [--approval|--info|--done|--fail] "mensagem" ["título"] ["subtítulo"] ["som"]` —
  banner nativo agora. O tipo preseta título com emoji + som; título/som explícitos sobrepõem.
- `repeat.sh <segundos> "mensagem" ["título"]` — lembrete periódico detached (sobrevive à
  sessão). `repeat.sh stop` mata todos; `repeat.sh list` lista.
- `notify-hook.sh` / `stop-hook.sh` / `approval-hook.sh` — adaptadores de hook (Notification /
  Stop / PermissionRequest), ligados em `~/.claude/settings.json`. Não são chamados pela skill.

## Sistema de sons e ícones (SEMPRE respeitar)

| Tipo | Flag | Título default | Som | Quando usar |
|---|---|---|---|---|
| Aprovação | `--approval` | 🔐 Aprovação necessária | Submarine | reservado aos hooks |
| Informativo | `--info` (default) | 🔔 Claude Code | Glass | notificação que o usuário pediu |
| Pronto | `--done` | ✅ Trabalho concluído | Hero | job terminou com sucesso |
| Falha | `--fail` | ❌ Algo falhou | Basso | job quebrou |

Pode-se trocar o emoji do título por um mais contextual (⏰ lembrete, 🚀 deploy, 🧪 testes),
mas **nunca** misturar som de um tipo com semântica de outro (Hero é só sucesso, Basso é só falha).

## Modos de uso

### 1. Agora — `/notify <mensagem>`

```bash
bash ~/.claude/skills/notify/notify.sh "<mensagem>"
```

### 2. Quando um job terminar — "me avisa quando X acabar"

1. Rode o comando com Bash `run_in_background: true` (você é re-invocado quando ele termina).
2. **Cheque o exit code / output real** e só então notifique com o desfecho verdadeiro:
   - sucesso: `notify.sh --done "suíte web passou (752 testes, 4m)"`
   - falha:   `notify.sh --fail "build quebrou: <resumo de 1 linha do erro>"`
   Nunca notificar `--done` sem verificar.
3. Condição externa (CI, deploy, arquivo aparecer): poll com intervalo proporcional ao processo
   (job de ~10 min → checar a cada 3–5 min; use ScheduleWakeup/Monitor se disponíveis) e
   notifique na mudança de estado.

### 3. De tempos em tempos — "me lembra a cada X"

```bash
bash ~/.claude/skills/notify/repeat.sh <intervalo_em_segundos> "<mensagem>"
```

- Processo detached: continua depois que a sessão fechar. Informe o PID e como parar.
- `/notify stop` → `repeat.sh stop` · `/notify list` → `repeat.sh list`

## Hooks (automático, sem invocação)

Configurados em `~/.claude/settings.json`:
- **Notification** → `notify-hook.sh`: banner 🔐/💬 quando o Claude Code pede permissão ou espera input.
- **Stop** → `stop-hook.sh`: banner ✅ "trabalho pronto" ao fim do turno — **suprimido** quando
  VSCode/terminal está em primeiro plano (senão toca a cada resposta). `NOTIFY_FORCE=1` ignora o gate.
- **PermissionRequest** → `approval-hook.sh`: quando você está fora do editor, dialog nativo com
  **Aprovar / Abrir no editor / Negar** que devolve a decisão ao Claude Code; timeout/erro cai no
  prompt normal do terminal (fail-safe).

## Gotchas

- Sem `terminal-notifier`, o banner sai em nome do "Script Editor" e o ícone real do app não é
  customizável — a identidade visual vem do emoji no título. Se nada aparecer: Ajustes do
  Sistema → Notificações → Script Editor → permitir. Modo Foco/Não Perturbe silencia.
- Aspas e emoji na mensagem são seguros — os scripts escapam antes do AppleScript.
- Fonte canônica/instalação: repo `hallanneves/claude-notifications` (GitHub). Ao mudar algo
  aqui, refletir lá.
- Utilitário pessoal do Hallan (macOS) — não referenciar em código/docs de repositório de trabalho.
