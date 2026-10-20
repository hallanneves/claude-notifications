#!/bin/bash
# build-vsix.sh — packages the bridge as a .vsix, without node or vsce: a
# .vsix is a zip holding the extension under extension/, a manifest and a
# content-types file. Name, publisher and version come from package.json.
#
# usage: build-vsix.sh <out.vsix>
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?usage: build-vsix.sh <out.vsix>}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac

field() { jq -r ".$1" "$SRC/package.json"; }
NAME="$(field name)"
PUBLISHER="$(field publisher)"
VERSION="$(field version)"
DISPLAY_NAME="$(field displayName)"
DESCRIPTION="$(field description)"
ENGINE="$(field engines.vscode)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/extension"
cp "$SRC/package.json" "$SRC/extension.js" "$WORK/extension/"

cat > "$WORK/extension.vsixmanifest" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="$NAME" Version="$VERSION" Publisher="$PUBLISHER" />
    <DisplayName>$DISPLAY_NAME</DisplayName>
    <Description xml:space="preserve">$DESCRIPTION</Description>
    <Categories>Other</Categories>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="$ENGINE" />
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="ui" />
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
EOF

cat > "$WORK/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json" />
  <Default Extension=".js" ContentType="application/javascript" />
  <Default Extension=".vsixmanifest" ContentType="text/xml" />
</Types>
EOF

rm -f "$OUT"
(cd "$WORK" && zip -q -X -r "$OUT" '[Content_Types].xml' extension.vsixmanifest extension)
