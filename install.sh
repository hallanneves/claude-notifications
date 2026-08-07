#!/bin/bash
# Installer for the /notify skill + notification hooks (Claude Code, macOS).
# Safe to re-run: hooks already pointing at the skill are left alone, hooks
# from other tools are never overwritten (per-event manual-merge warning).
set -euo pipefail

cd "$(dirname "$0")"

if [ "$(uname)" != "Darwin" ]; then
  echo "❌ Esta skill usa notificações nativas do macOS (osascript) — macOS obrigatório."
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "❌ jq não encontrado (vem no macOS 15+; senão: brew install jq)"; exit 1; }

DEST="$HOME/.claude/skills/notify"
mkdir -p "$DEST"
cp -f skill/SKILL.md skill/notify.conf.example skill/*.sh skill/*.js "$DEST/"
# The approval dialog sets this as its NSAlert icon; without it the alert
# borrows osascript's generic document icon.
cp -f assets/claude-logo.png "$DEST/claude-logo.png"
cp -f VERSION "$DEST/VERSION"
# Lets update.sh pull into this working copy instead of cloning a fresh one.
if [ -d .git ]; then
  pwd > "$DEST/.source-repo"
else
  rm -f "$DEST/.source-repo"
fi
chmod +x "$DEST"/*.sh
echo "✅ skill instalada em $DEST"
echo "   (config opcional: copie $DEST/notify.conf.example para notify.conf e edite)"

SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# One timestamped backup per run, taken only if we are about to modify.
BACKUP=""
ensure_backup() {
  [ -n "$BACKUP" ] && return 0
  BACKUP="${SETTINGS}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
}

MANUAL=""
for EV in Notification Stop PermissionRequest; do
  if ! jq -e --arg ev "$EV" '.hooks[$ev]' "$SETTINGS" >/dev/null 2>&1; then
    ensure_backup
    tmp="$(mktemp)"
    jq -s --arg ev "$EV" \
      '.[0].hooks = ((.[0].hooks // {}) + {($ev): .[1].hooks[$ev]}) | .[0]' \
      "$SETTINGS" hooks.json > "$tmp"
    jq -e . "$tmp" >/dev/null
    mv "$tmp" "$SETTINGS"
    echo "✅ hook $EV adicionado em $SETTINGS"
  elif jq -e --arg ev "$EV" '.hooks[$ev] | tostring | contains("/skills/notify/")' "$SETTINGS" >/dev/null 2>&1; then
    echo "✅ hook $EV já configurado — nada a fazer"
  else
    MANUAL="$MANUAL $EV"
  fi
done
if [ -n "$MANUAL" ]; then
  echo "⚠️  Você já tem hooks seus em:$MANUAL — não vou sobrescrever."
  echo "    Faça o merge manual desses eventos usando o conteúdo de hooks.json."
fi
[ -n "$BACKUP" ] && echo "   (backup do settings.json em $BACKUP)"

if command -v terminal-notifier >/dev/null 2>&1; then
  ./install-notifier-app.sh || echo "⚠️  não consegui criar o app de notificação (rode ./install-notifier-app.sh depois)"
else
  echo "ℹ️  Recomendado: brew install terminal-notifier && ./install-notifier-app.sh"
  echo "   (sem ele o fallback é o osascript: o banner sai em nome do Script Editor)"
fi

echo
echo "🔔 Teste agora:  $DEST/notify.sh --done \"Instalação concluída\""
echo "➡️  Reinicie o Claude Code (ou abra /hooks) para os hooks carregarem."
echo "➡️  Se o banner não aparecer: Ajustes do Sistema → Notificações → permitir o app"
echo "   (\"Claude Code\", ou \"Script Editor\" quando estiver no fallback)."
