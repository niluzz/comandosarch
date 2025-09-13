#!/bin/bash
set -e

echo ">>> Instalando Zsh..."
sudo pacman -S --needed --noconfirm zsh curl git

echo ">>> Instalando Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh já está instalado."
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

echo ">>> Instalando tema Powerlevel10k..."
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
  git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
else
  echo "Powerlevel10k já está instalado."
fi

echo ">>> Instalando plugins..."
# Autosuggestions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
fi

# Syntax Highlighting
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
fi

# History Substring Search
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-history-substring-search" ]; then
  git clone https://github.com/zsh-users/zsh-history-substring-search $ZSH_CUSTOM/plugins/zsh-history-substring-search
fi

# FZF
if [ ! -d "$HOME/.fzf" ]; then
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  yes | ~/.fzf/install --all
fi

echo ">>> Configurando ~/.zshrc..."
ZSHRC="$HOME/.zshrc"

# Garantir que o tema esteja configurado
if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

# Garantir que os plugins estejam configurados
PLUGINS_LINE='plugins=(git zsh-syntax-highlighting zsh-autosuggestions fzf zsh-history-substring-search)'
if grep -q '^plugins=' "$ZSHRC"; then
  sed -i "s|^plugins=.*|$PLUGINS_LINE|" "$ZSHRC"
else
  echo "$PLUGINS_LINE" >> "$ZSHRC"
fi

echo ">>> Definindo Zsh como shell padrão..."
chsh -s /bin/zsh "$USER"

echo ">>> Recarregando configurações do Zsh..."
# o "source" só funciona dentro do zsh, então criamos um aviso
echo "Para aplicar imediatamente, rode: source ~/.zshrc"

echo ">>> Zsh + Oh My Zsh configurado com sucesso! 🚀"
