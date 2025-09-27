# Instalar dependências
sudo pacman -S --needed base-devel git

# Clonar e instalar paru
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si

# Configurar paru (opcional)
sudo nano /etc/paru.conf