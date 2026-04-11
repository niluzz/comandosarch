#!/bin/bash

echo "======================================="
echo " Instalando Walker + Elephant no Arch "
echo "======================================="
echo

# PASSO 1 - Instalar pacotes
echo "[1/5] Instalando pacotes..."

paru -S --noconfirm walker elephant elephant-clipboard elephant-desktopapplications elephant-files elephant-menus elephant-providerlist elephant-websearch

echo
echo "Pacotes instalados."
echo

# PASSO 2 - Ativar Elephant service
echo "[2/5] Ativando Elephant service..."

elephant service enable

echo
echo "Elephant service ativado."
echo

# PASSO 3 - Criar config do Walker
echo "[3/5] Criando configuração do Walker..."

mkdir -p ~/.config/walker

cat > ~/.config/walker/config.toml << 'EOF'
# Tema
theme = "default"

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
  "runner",
  "files",
  "calc",
  "websearch"
]

empty = [
  "desktopapplications"
]

max_results = 30

# rodar comandos
runner = ">"

# arquivos
files = "/"

# calculadora
calc = "="

# busca web
websearch = "?"
EOF

echo "Configuração criada em ~/.config/walker/config.toml"
echo

# PASSO 4 - Criar autostart
echo "[4/5] Criando autostart..."

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

# PASSO 5 - Mensagem final
echo "======================================="
echo " Instalação concluída com sucesso!"
echo "======================================="
echo
echo "Agora configure um atalho no GNOME:"
echo
echo "Configurações → Teclado → Atalhos personalizados"
echo
echo "Comando:"
echo
echo "/usr/bin/walker"
echo
echo "Sugestão de atalho:"
echo
echo "SUPER + SPACE"
echo
echo "Após reiniciar a sessão, o Walker iniciará automaticamente."
echo
