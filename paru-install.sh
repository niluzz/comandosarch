# Verifica se o paru já está instalado
if ! command -v paru &>/dev/null; then
    echo "📥 Instalando o paru (AUR helper)..."
    
    # Instala dependências necessárias antes de compilar o paru
    pacman -S --needed --noconfirm base-devel git || handle_error "Falha ao instalar dependências do Paru."

    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    git clone https://aur.archlinux.org/paru.git "$temp_dir/paru" || handle_error "Falha ao clonar o repositório do paru."
    
    cd "$temp_dir/paru"
    makepkg -si --noconfirm || handle_error "Falha ao instalar o paru."
    cd ~  # Retorna ao diretório inicial
else
    echo "✅ Paru já está instalado. Pulando instalação."
fi

# Confirma que o paru foi instalado corretamente antes de continuar
if ! command -v paru &>/dev/null; then
    handle_error "Paru não foi encontrado. Verifique a instalação e tente novamente."
fi

aur_packages=(
    google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware 
    onlyoffice-bin teamviewer extension-manager coolercontrol
)

for package in "${aur_packages[@]}"; do
    echo "📦 Instalando pacote do AUR: $package..."
    
    # Força aceitação de licença para pacotes que exigem
    paru -S --needed --noconfirm --skipreview "$package" || echo "⚠️  Aviso: Falha ao instalar $package"
done

# Habilita e inicia serviços
services=(
    fwupd-refresh.timer
    bluetooth.service
    teamviewerd.service
)

for service in "${services[@]}"; do
    if ! systemctl is-enabled --quiet "$service"; then
        echo "🔧 Ativando serviço: $service..."
        systemctl enable --now "$service" || handle_error "Falha ao ativar o serviço $service"
    else
        echo "✅ Serviço $service já está ativo."
    fi
done
