---
name: notify
description: Notificação nativa do macOS (banner + som, estilo Slack). Use quando o usuário pedir /notify, "me avisa/notifica quando X terminar" (build, testes, deploy, CI, job longo), lembretes periódicos ("me lembra a cada 30 min"), ou para parar lembretes ativos (/notify stop, /notify list). Sons semânticos por tipo de evento (aprovação/info/pronto/falha); ícone do Claude no banner; sem emojis nas mensagens.
---

# notify — notificações nativas do macOS

Scripts neste diretório (`~/.claude/skills/notify/`):

- `notify.sh [--approval|--info|--done|--fail] "mensagem" ["título"] ["subtítulo"] ["som"]` —
  banner nativo agora. O tipo preseta título + som; título/som explícitos sobrepõem.
- `repeat.sh <segundos> "mensagem" ["título"]` — lembrete periódico detached (sobrevive à
  sessão). `repeat.sh stop` mata todos; `repeat.sh list` lista.
- `notify-hook.sh` / `stop-hook.sh` / `approval-hook.sh` — adaptadores de hook (Notification /
  Stop / PermissionRequest), ligados em `~/.claude/settings.json`. Não são chamados pela skill.

## Identidade visual e sonora (SEMPRE respeitar)

- **SEM emojis** em títulos e mensagens de notificação — preferência explícita do Hallan.
  A identificação visual vem do **ícone do Claude** no banner (transplantado no
  terminal-notifier via `set-claude-icon.sh` do repo); a semântica vem do **som + título**.
- Sons nunca trocam de semântica: Hero é só sucesso, Basso é só falha.

| Tipo | Flag | Título default | Som | Quando usar |
|---|---|---|---|---|
| Aprovação | `--approval` | Aprovação necessária | Submarine | reservado aos hooks |
| Informativo | `--info` (default) | Claude Code | Glass | notificação que o usuário pediu |
| Pronto | `--done` | Trabalho concluído | Hero | job terminou com sucesso |
| Falha | `--fail` | Algo falhou | Basso | job quebrou |

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
- `repeat.sh` é SÓ para mensagem fixa (lembrete). Para status de trabalho, use o modo 4 —
  nunca congele um "status" dentro de um repeat.

### 4. Status do trabalho de tempos em tempos — "vai me mandando o status"

Quando o usuário pedir progresso periódico de uma tarefa em andamento, quem compõe cada
mensagem é VOCÊ, na hora, com o estado real — um `--info` curto por checagem:

```bash
bash ~/.claude/skills/notify/notify.sh "Migração: 3 de 7 arquivos prontos, testes passando" "Status do trabalho"
```

- **Você mesmo executando a tarefa**: dispare a cada marco concluído (fase, suíte, arquivo
  grande), mirando o intervalo pedido de forma aproximada. Mudou de rumo ou travou em algo?
  Isso É status — notifique.
- **Trabalho em background** (suíte longa, workflow, agente, CI): programe checagens
  periódicas (ScheduleWakeup/Monitor, intervalo proporcional ao job) e a cada acordada mande
  o resumo real do momento; ao final, feche com `--done`/`--fail` (modo 2).
- Conteúdo: 1 linha concreta (o que já foi, o que está rodando, % ou contagem se houver).
  Título "Status do trabalho". Nunca inventar progresso — se não houver novidade, diga isso
  ("ainda na suíte de integração, sem falhas até aqui").

## Hooks (automático, sem invocação)

Configurados em `~/.claude/settings.json`:
- **Notification** → `notify-hook.sh`: banner quando o Claude Code pede permissão ou espera input.
- **Stop** → `stop-hook.sh`: banner "trabalho pronto" ao fim do turno — **suprimido** quando
  VSCode/terminal está em primeiro plano (senão toca a cada resposta). `NOTIFY_FORCE=1` ignora o gate.
- **PermissionRequest** → `approval-hook.sh`: quando você está fora do editor, dialog nativo com
  **Aprovar / Abrir no editor / Negar** que devolve a decisão ao Claude Code (allow e deny
  confirmados ao vivo). Ferramentas de interação (AskUserQuestion etc.) são puladas. Timeout/erro
  cai no prompt normal do terminal (fail-safe). Comando já allowlistado não gera prompt → hook
  nem roda (não é bug).

## Gotchas

- O ícone do Claude vem de um swap do ícone do `terminal-notifier.app`
  (`set-claude-icon.sh` no repo). **`brew upgrade terminal-notifier` reverte** — re-rodar o
  script. Clicar na notificação foca o VSCode (`NOTIFY_ACTIVATE` muda o bundle id).
- Sem terminal-notifier, o fallback é `osascript`: banner sai como "Script Editor" e o
  clique/"Mostrar" abre uma janela vazia do Script Editor (quirk do macOS).
- O dialog de aprovação usa `activate` antes do `display dialog` — sem isso a janela nasce
  atrás do app em foco e ninguém vê.
- Se nada aparecer: Ajustes do Sistema → Notificações → permitir o app (terminal-notifier ou
  Script Editor). Modo Foco/Não Perturbe silencia.
- Aspas na mensagem são seguras — os scripts escapam antes do AppleScript.
- Fonte canônica/instalação: repo `hallanneves/claude-notifications` (GitHub). Ao mudar algo
  aqui, refletir lá.
- Utilitário pessoal do Hallan (macOS) — não referenciar em código/docs de repositório de trabalho.
