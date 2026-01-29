#!/bin/bash

set -e

FONTCONFIG_DIR="$HOME/.config/fontconfig"
FONTCONFIG_FILE="$FONTCONFIG_DIR/fonts.conf"
ENV_FILE="/etc/environment"
FREETYPE_LINE='FREETYPE_PROPERTIES="cff:no-stem-darkening=0 autofitter:no-stem-darkening=0"'

echo "🔧 Melhorando renderização de fontes no Linux"
echo "---------------------------------------------"

### Parte 1 — Fontconfig (usuário)
echo "📝 Configurando subpixel rendering (fontconfig)..."

mkdir -p "$FONTCONFIG_DIR"

cat << 'EOF' > "$FONTCONFIG_FILE"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="rgba" mode="assign">
      <const>rgb</const>
    </edit>
    <edit name="hinting" mode="assign">
      <bool>true</bool>
    </edit>
    <edit name="hintstyle" mode="assign">
      <const>hintslight</const>
    </edit>
    <edit name="antialias" mode="assign">
      <bool>true</bool>
    </edit>
  </match>
</fontconfig>
EOF

echo "✅ Fontconfig configurado"

### Parte 2 — FreeType (sistema)
echo "🧠 Configurando FreeType (stem darkening)..."

if grep -q "FREETYPE_PROPERTIES" "$ENV_FILE"; then
  echo "⚠️ FREETYPE_PROPERTIES já existe em $ENV_FILE"
  echo "ℹ️ Nenhuma alteração feita para evitar duplicação"
else
  echo "🔐 Necessário sudo para editar $ENV_FILE"
  echo "$FREETYPE_LINE" | sudo tee -a "$ENV_FILE" > /dev/null
  echo "✅ FREETYPE_PROPERTIES adicionada"
fi

### Parte 3 — Atualizar cache
echo "♻️ Atualizando cache de fontes..."
fc-cache -fv > /dev/null

echo
echo "🎉 Concluído com sucesso!"
echo "➡️ Faça LOGOUT/LOGIN ou REINICIE o sistema para aplicar tudo."

