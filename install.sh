#!/bin/bash
# Installer for the /notify skill + notification hooks (Claude Code, macOS).
set -euo pipefail

cd "$(dirname "$0")"

if [ "$(uname)" != "Darwin" ]; then
  echo "❌ Esta skill usa notificações nativas do macOS (osascript) — macOS obrigatório."
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "❌ jq não encontrado (vem no macOS 15+; senão: brew install jq)"; exit 1; }

DEST="$HOME/.claude/skills/notify"
mkdir -p "$DEST"
cp -f skill/SKILL.md skill/notify.conf.example skill/*.sh "$DEST/"
chmod +x "$DEST"/*.sh
echo "✅ skill instalada em $DEST"
echo "   (config opcional: copie $DEST/notify.conf.example para notify.conf e edite)"

SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

if jq -e '.hooks.Notification, .hooks.Stop, .hooks.PermissionRequest | select(. != null)' "$SETTINGS" >/dev/null 2>&1; then
  echo "⚠️  $SETTINGS já tem hooks em Notification/Stop/PermissionRequest."
  echo "    Faça o merge manual usando o conteúdo de hooks.json (não vou sobrescrever)."
else
  cp "$SETTINGS" "${SETTINGS}.bak"
  tmp="$(mktemp)"
  jq -s '.[0].hooks = ((.[0].hooks // {}) + .[1].hooks) | .[0]' "$SETTINGS" hooks.json > "$tmp"
  jq -e . "$tmp" >/dev/null
  mv "$tmp" "$SETTINGS"
  echo "✅ hooks adicionados em $SETTINGS"
fi

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
