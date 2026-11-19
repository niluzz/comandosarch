#!/usr/bin/env zsh
# Zsh + Oh My Zsh + Powerlevel10k no macOS (Apple Silicon)
# Adaptado do opcao_zsh do gnome-amd-notebook.sh
set -e

# 1. Homebrew (se ainda não tiver)
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 2. Pacotes (zsh e curl já vêm no macOS)
brew install git fzf

# 3. Fonte Nerd para os ícones do tema
brew install --cask font-meslo-lg-nerd-font

# 4. Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# 5. Tema e plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clonar() { [ -d "$2" ] || git clone --depth 1 "$1" "$2"; }
clonar https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
clonar https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clonar https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clonar https://github.com/zsh-users/zsh-history-substring-search "$ZSH_CUSTOM/plugins/zsh-history-substring-search"

# 6. .zshrc
ZSHRC="$HOME/.zshrc"
[ -f "$ZSHRC" ] || cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$ZSHRC"
cp "$ZSHRC" "$ZSHRC.bak.$(date +%Y%m%d%H%M%S)"

# No macOS o sed é BSD: -i precisa do '' logo depois
if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i '' 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

PLUGINS_LINE='plugins=(git fzf zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search)'
if grep -q '^plugins=' "$ZSHRC"; then
  sed -i '' "s|^plugins=.*|$PLUGINS_LINE|" "$ZSHRC"
else
  echo "$PLUGINS_LINE" >> "$ZSHRC"
fi

if ! grep -q 'history-substring-search-up' "$ZSHRC"; then
  cat >> "$ZSHRC" <<'EOF'

# Busca no histórico com as setas
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
EOF
fi

echo
echo "Pronto. Agora:"
echo "1) Terminal > Ajustes > Perfis > Texto > Fonte: MesloLGS Nerd Font"
echo "2) Feche e abra o Terminal: o assistente do Powerlevel10k abre sozinho"
echo "   (para refazer depois: p10k configure)"
