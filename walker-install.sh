#!/bin/bash

echo "======================================="
echo " Instalando Walker + Elephant no Arch "
echo "======================================="
echo

# PASSO 1 - Instalar pacotes
echo "[1/6] Instalando pacotes..."

paru -S --noconfirm walker elephant elephant-clipboard elephant-desktopapplications elephant-files elephant-menus elephant-providerlist elephant-websearch

echo
echo "Pacotes instalados."
echo

# PASSO 2 - Ativar Elephant service
echo "[2/6] Ativando Elephant service..."

elephant service enable

echo
echo "Elephant service ativado."
echo

# PASSO 3 - Criar config do Walker
echo "[3/6] Criando configuração do Walker..."

mkdir -p ~/.config/walker

cat > ~/.config/walker/config.toml << 'EOF'
# Tema
theme = "minimal"

[window]
anchor = "center"
width = 600
height = 400

# comportamento
force_keyboard_focus = true
close_when_open = true

[providers]

default = [
  "desktopapplications",
  "menus",
  "runner",
  "files",
  "calc",
  "websearch"
]

empty = [
  "desktopapplications"
]

max_results = 30

runner = ">"
files = "/"
calc = "="
websearch = "?"
EOF

echo "Configuração criada."
echo

# PASSO 4 - Criar tema minimal
echo "[4/6] Criando tema minimal..."

mkdir -p ~/.config/walker/themes/minimal

cat > ~/.config/walker/themes/minimal/style.css << 'EOF'
/* Color definitions */
@define-color window_bg_color #1f1f28;
@define-color accent_bg_color #54546d;
@define-color theme_fg_color #f2ecbc;
@define-color error_bg_color #C34043;
@define-color error_fg_color #DCD7BA;

/* Reset */
* {
  all: unset;
}

/* 🔥 REMOVE FUNDO DA JANELA REAL */
window {
  background: transparent;
  border-radius: 20px;
}

/* 🔥 CONTAINER PRINCIPAL (GLASS + FIX BORDA) */
.box-wrapper {
  box-shadow:
    0 25px 25px rgba(0, 0, 0, 0.35),
    0 10px 10px rgba(0, 0, 0, 0.20);

  background: alpha(@window_bg_color, 0.75);
  padding: 20px;
  border-radius: 20px;

  /* 👇 evita artefatos visuais */
  background-clip: padding-box;

  /* borda glass */
  border: 1px solid alpha(@accent_bg_color, 0.20);

  /* 👇 CORREÇÃO FINAL DO “BICO” */
  overflow: hidden;
  
  /* 💎 CONTORNO PREMIUM (glass elegante) */
  border: 2px solid rgba(255, 255, 255, 0.12);

  overflow: hidden;
}

/* INPUT */
.input {
  caret-color: @theme_fg_color;
  background: alpha(@window_bg_color, 0.6);
  padding: 10px;
  color: @theme_fg_color;
  border-radius: 10px;
}

.input placeholder {
  opacity: 0.5;
}

/* LISTA */
.list {
  color: @theme_fg_color;
  background: transparent;
}

/* ITENS */
.item-box {
  border-radius: 10px;
  padding: 10px;
  background: transparent;
}

/* HOVER / SELEÇÃO */
child:hover .item-box,
child:selected .item-box {
  background: alpha(@accent_bg_color, 0.20);
}

/* TEXTOS */
.item-text {
  font-size: 14px;
}

.item-subtext {
  font-size: 12px;
  opacity: 0.5;
}

/* ÍCONES */
.item-image,
.item-image-text {
  margin-right: 10px;
}

/* QUICK ACTION */
.item-quick-activation {
  margin-left: 10px;
  background: alpha(@accent_bg_color, 0.20);
  border-radius: 5px;
  padding: 10px;
}

/* PLACEHOLDERS */
.placeholder,
.elephant-hint {
  color: @theme_fg_color;
  opacity: 0.5;
}

/* KEYBINDS */
.keybinds-wrapper {
  border-top: 1px solid alpha(@window_bg_color, 0.5);
  font-size: 12px;
  opacity: 0.5;
  color: @theme_fg_color;
}

.keybind-bind {
  font-weight: bold;
  text-transform: lowercase;
}

/* ERRO */
.error {
  padding: 10px;
  background: @error_bg_color;
  color: @error_fg_color;
  border-radius: 5px;
}

/* PREVIEW */
.preview {
  border: 1px solid alpha(@accent_bg_color, 0.25);
  padding: 10px;
  border-radius: 10px;
  color: @theme_fg_color;
}

/* ÍCONES */
.normal-icons {
  -gtk-icon-size: 16px;
}

.large-icons {
  -gtk-icon-size: 32px;
}

/* SCROLL */
scrollbar {
  opacity: 0;
}
EOF

echo "Tema minimal criado."
echo

# PASSO 5 - Criar autostart
echo "[5/6] Criando autostart..."

mkdir -p ~/.config/autostart

cat > ~/.config/autostart/walker.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Walker Service
Exec=/usr/bin/env GDK_BACKEND=wayland walker --gapplication-service
X-GNOME-Autostart-enabled=true
EOF

echo "Autostart criado."
echo

# PASSO 6 - Final
echo "======================================="
echo " Instalação concluída com sucesso!"
echo "======================================="
echo
echo "Use SUPER + SPACE para abrir o Walker."
echo "Tema minimal com glass ativado automaticamente."
echo
