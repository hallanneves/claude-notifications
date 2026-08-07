#!/bin/bash
# Strings em português. Carregado por load_lang(); veja en.sh para o outro
# catálogo. Todo L_* daqui precisa existir em todos os catálogos, com os
# mesmos placeholders de printf na mesma ordem.
# shellcheck disable=SC2034  # consumidas pelos scripts que dão source

# notify.sh — os quatro presets
L_TITLE_APPROVAL="Aprovação necessária"
L_TITLE_DONE="Trabalho concluído"
L_TITLE_FAIL="Algo falhou"
L_TITLE_INFO="Claude Code"
L_WARN_SOUND="aviso: som '%s' não existe (veja: ls /System/Library/Sounds) — o banner sai mudo\n"

# notify-hook.sh
L_NEEDS_YOU="Claude Code precisa de você"
L_WAITING_TITLE="Claude está esperando você"

# stop-hook.sh
L_STOP_DONE="Terminei — pode conferir"
L_STOP_DONE_IN="Terminei em %s — pode conferir"
L_STOP_SUBTITLE="projeto %s"

# approval-hook.sh
L_TOOL_FALLBACK="uma ferramenta"
L_USER_FALLBACK="usuário"
L_NO_DETAILS="sem detalhes"
L_TRUNCATED="[TRUNCADO — use Abrir no editor para ver o comando completo]"
L_APPROVAL_PROMPT="Claude quer usar: %s"
L_APPROVAL_TITLE="Claude Code — aprovação"
L_APPROVAL_BUTTONS="Aprovar:a:approve|Negar:n:deny|Abrir no editor:e:editor|Fechar (Esc):esc:ignore"
L_DENY_MESSAGE="Negado por %s via dialog de notificação"

# repeat.sh
L_REMINDER_TITLE="Lembrete"
L_REP_USAGE="uso: repeat.sh SEGUNDOS MENSAGEM [TÍTULO] | stop | list"
L_REP_BAD_INTERVAL="intervalo inválido: '%s' (use segundos, inteiro >= 5)\n"
L_REP_MIN_INTERVAL="intervalo mínimo é 5s (recebi %ss)\n"
L_REP_STOPPED="lembrete parado, pid %s\n"
L_REP_NONE="nenhum lembrete ativo"
L_REP_STARTED="lembrete iniciado: pid %s, a cada %ss — pare com: repeat.sh stop\n"

# check-update.sh
L_UPD_UNREACHABLE="não consegui consultar %s (offline? repo privado?)\n"
L_UPD_NO_TAGS="nenhuma tag de versão em %s\n"
L_UPD_CURRENT="já está atualizado (local %s, remoto %s)\n"
L_UPD_AVAILABLE="atualização disponível: %s -> %s\n"
L_UPD_BANNER_TITLE="Atualização disponível"
L_UPD_BANNER_MSG="Clique para atualizar da %s para a %s"
L_UPD_BANNER_SUB="claude-notifications %s"

# update.sh
L_UPD_NO_GIT="git não encontrado — não dá para atualizar"
L_UPD_DIALOG_TITLE="Atualização do claude-notifications"
L_UPD_DIALOG_BODY="Você tem a versão %s. Instalar a mais recente de %s? Veja o que mudou antes, se preferir."
L_UPD_DIALOG_BUTTONS="Instalar:i:install|Ver no GitHub:g:github|Cancelar (Esc):esc:cancel"
L_UPD_OPENED="abri %s — rode de novo quando quiser instalar\n"
L_UPD_CANCELLED="atualização cancelada"
L_UPD_PULL_FAIL="não consegui atualizar o clone em %s (commits locais ou mudanças não commitadas?)"
L_UPD_CLONE_FAIL="não consegui clonar %s"
L_UPD_INSTALL_FAIL="o instalador falhou — veja %s"
L_UPD_DETAILS="detalhes em %s"
L_UPD_SAME="Já estava na versão %s"
L_UPD_DONE="Atualizado da %s para a %s"
L_UPD_RESTART="%s — reinicie o Claude Code para recarregar os hooks"

# install.sh / uninstall.sh
L_INS_NEED_MACOS="Esta skill usa notificações nativas do macOS (osascript) — macOS obrigatório."
L_INS_NEED_JQ="jq não encontrado (vem no macOS 15+; senão: brew install jq)"
L_INS_SKILL_OK="skill instalada em %s\n"
L_INS_CONF_HINT="   (config opcional: copie %s para notify.conf e edite)\n"
L_INS_HOOK_ADDED="hook %s adicionado em %s\n"
L_INS_HOOK_PRESENT="hook %s já configurado — nada a fazer\n"
L_INS_HOOK_MANUAL="Você já tem hooks seus em:%s — não vou sobrescrever.\n"
L_INS_HOOK_MANUAL2="    Faça o merge manual desses eventos usando o conteúdo de hooks.json."
L_INS_BACKUP="   (backup do settings.json em %s)\n"
L_INS_APP_FAIL="não consegui criar o app de notificação (rode ./install-notifier-app.sh depois)"
L_INS_TN_HINT="Recomendado: brew install terminal-notifier && ./install-notifier-app.sh"
L_INS_TN_HINT2="   (sem ele o fallback é o osascript: o banner sai em nome do Script Editor)"
L_INS_TEST="Teste agora:  %s/notify.sh --done \"Instalação concluída\"\n"
L_INS_RESTART="Reinicie o Claude Code (ou abra /hooks) para os hooks carregarem."
L_INS_NO_BANNER="Se o banner não aparecer: Ajustes do Sistema → Notificações → permitir o app"
L_INS_NO_BANNER2="   (\"Claude Code\", ou \"Script Editor\" quando estiver no fallback)."
L_UNI_HOOKS_REMOVED="hooks removidos de %s (backup: %s)\n"
L_UNI_NO_HOOKS="nenhum hook da skill em %s — nada a remover\n"
L_UNI_SKILL_REMOVED="skill removida de ~/.claude/skills/notify"
L_UNI_APP_REMOVED="app '%s' removido de ~/Applications\n"
L_UNI_ICON_HINT="Se você tinha aplicado o ícone no terminal-notifier compartilhado do Homebrew:"
L_UNI_ICON_HINT2="    brew reinstall terminal-notifier   # restaura o ícone original"
L_UNI_RESTART="Reinicie o Claude Code para descarregar os hooks."

# install-notifier-app.sh / set-claude-icon.sh
L_APP_NO_TN="terminal-notifier não encontrado (brew install terminal-notifier)"
L_APP_EXISTS="%s já existe — mantendo (use --force para recriar).\n"
L_APP_EXISTS2="   Recriar zera a autorização: o macOS pergunta de novo."
L_APP_CREATED="bundle criado em %s\n"
L_APP_ICON_FAIL="não consegui aplicar o ícone (rode ./set-claude-icon.sh depois)"
L_APP_AUTHORIZE="Autorize as notificações para receber os avisos do Claude Code"
L_APP_ALLOW="O macOS deve mostrar 'Notificações de \"Claude Code\"' — clique em Permitir."
L_APP_ALLOW2="   Se não aparecer: Ajustes do Sistema → Notificações → Claude Code → ligue"
L_APP_ALLOW3="   'Permitir notificações' e deixe o estilo em Banners ou Alertas."
L_ICON_APPLIED="ícone do Claude aplicado em %s\n"
L_ICON_SHARED="   Este é o terminal-notifier compartilhado: re-rode após um 'brew upgrade'."
L_ICON_SHARED2="   Para isolar o ícone só nas notificações do Claude: ./install-notifier-app.sh"
