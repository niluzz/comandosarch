# Instala o Oh My Zsh
echo "Instalando o Oh My Zsh..."
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Instala o tema Powerlevel10k
echo "Instalando o tema Powerlevel10k..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k

# Configura o tema Powerlevel10k no ~/.zshrc
echo "Configurando o tema Powerlevel10k..."
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc

# Instala plugins para ZSH
echo "Instalando plugins para ZSH..."

# zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# zsh-history-substring-search
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

# fzf (Fuzzy Finder)
echo "Instalando o fzf..."
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --all --no-update-rc

# Configura os plugins no ~/.zshrc
echo "Configurando plugins no ~/.zshrc..."
sed -i 's/^plugins=.*/plugins=(git zsh-syntax-highlighting zsh-autosuggestions fzf zsh-history-substring-search)/' ~/.zshrc

# Define o ZSH como shell padrão
echo "Definindo o ZSH como shell padrão..."
chsh -s $(which zsh)

# Recarrega o ZSH
echo "Recarregando o ZSH..."
exec zsh

# Mensagem final
echo "Instalação e configuração concluídas!"
