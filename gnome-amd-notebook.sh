#!/bin/bash
# =====================================================================
# Pós-instalação Arch Linux
# Rodar como usuário normal (NÃO como root). O script pede sudo quando precisa.
# =====================================================================
set -e

# ---------------------------------------------------------------------
# 0. Verificações iniciais
# ---------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  echo "!!! Não rode este script como root. Use seu usuário normal."
  echo "!!! O makepkg (Paru) não funciona como root."
  exit 1
fi

# Pede a senha uma vez e mantém o sudo ativo até o fim do script
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &

# Guarda cópia de segurança antes de editar qualquer arquivo
backup() {
  local arquivo="$1"
  if [[ -f "$arquivo" ]]; then
    sudo cp -a "$arquivo" "${arquivo}.bak-$(date +%Y%m%d-%H%M%S)"
  fi
}

# ---------------------------------------------------------------------
# 1. Atualização do sistema
# ---------------------------------------------------------------------
echo ">>> Atualizando pacotes do sistema..."
sudo pacman -Syu --noconfirm

# ---------------------------------------------------------------------
# 2. Pacotes oficiais
# ---------------------------------------------------------------------
echo ">>> Instalando pacotes oficiais..."

echo ">>> Ferramentas básicas..."
sudo pacman -S --needed --noconfirm \
  git zsh systemd-ukify pacman-contrib \
  file-roller p7zip unrar unzip \
  fwupd mesa-utils ibus base-devel

echo ">>> Mídia e multimídia..."
sudo pacman -S --needed --noconfirm \
  ffmpeg \
  gstreamer gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-plugins-ugly gst-libav \
  libdvdread libdvdnav libdvdcss \
  ffmpegthumbnailer

echo ">>> Fontes..."
sudo pacman -S --needed --noconfirm \
  ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd \
  inter-font noto-fonts noto-fonts-emoji \
  ttf-opensans ttf-roboto noto-fonts-cjk

echo ">>> Outros..."
sudo pacman -S --needed --noconfirm \
  gufw thunderbird-i18n-pt-br playerctl \
  expac fastfetch power-profiles-daemon \
  plymouth speedtest-cli \
  bluez bluez-utils zram-generator

echo ">>> Ferramentas de backup..."
sudo pacman -S --needed --noconfirm \
  btrfs-assistant btrfsmaintenance snapper

# ---------------------------------------------------------------------
# 3. Paru e pacotes do AUR
# ---------------------------------------------------------------------
echo ">>> Instalando Paru (AUR helper)..."
if ! command -v paru &>/dev/null; then
  rm -rf /tmp/paru
  git clone https://aur.archlinux.org/paru.git /tmp/paru
  (cd /tmp/paru && makepkg -si --noconfirm)
  rm -rf /tmp/paru
else
  echo "Paru já está instalado."
fi

echo ">>> Instalando pacotes do AUR com paru..."
paru -S --needed --noconfirm \
  google-chrome phinger-cursors ttf-ms-fonts

# ---------------------------------------------------------------------
# 4. Serviços
# ---------------------------------------------------------------------
echo ">>> Habilitando serviços..."
sudo systemctl enable --now fwupd-refresh.timer
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now power-profiles-daemon
sudo systemctl enable --now systemd-oomd

# ---------------------------------------------------------------------
# 5. ZRAM
# ---------------------------------------------------------------------
echo ">>> Configurando ZRAM..."
backup /etc/systemd/zram-generator.conf
sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

sudo systemctl daemon-reload
if ! sudo systemctl restart systemd-zram-setup@zram0.service; then
  echo "!!! Não foi possível reiniciar o zram agora. A nova configuração vale após reiniciar o PC."
fi

# ---------------------------------------------------------------------
# 6. Parâmetros do kernel para ZRAM (sysctl)
# ---------------------------------------------------------------------
echo ">>> Aplicando parâmetros de memória para ZRAM..."
sudo tee /etc/sysctl.d/99-vm-zram-parameters.conf >/dev/null <<'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
sudo sysctl --system >/dev/null

# ---------------------------------------------------------------------
# 7. Tampa do notebook: bloquear a tela ao fechar
# ---------------------------------------------------------------------
echo ">>> Configurando HandleLidSwitch=lock..."
LOGIND=/etc/systemd/logind.conf
backup "$LOGIND"
if sudo grep -qE '^#?HandleLidSwitch=' "$LOGIND"; then
  sudo sed -i -E 's/^#?HandleLidSwitch=.*/HandleLidSwitch=lock/' "$LOGIND"
else
  if ! sudo grep -q '^\[Login\]' "$LOGIND"; then
    echo "[Login]" | sudo tee -a "$LOGIND" >/dev/null
  fi
  echo "HandleLidSwitch=lock" | sudo tee -a "$LOGIND" >/dev/null
fi
# O logind não é reiniciado aqui para não derrubar a sessão gráfica.
# A mudança vale no próximo boot.

# ---------------------------------------------------------------------
# 8. Plymouth (ordem importa: editar tudo antes de gerar a imagem)
# ---------------------------------------------------------------------
echo ">>> Configurando Plymouth..."

# 8.1 Hook do plymouth logo após o udev no mkinitcpio.conf
MKINIT=/etc/mkinitcpio.conf
backup "$MKINIT"
if sudo grep -qE '^HOOKS=.*\bplymouth\b' "$MKINIT"; then
  echo "Hook plymouth já está presente."
elif sudo grep -qE '^HOOKS=.*\budev\b' "$MKINIT"; then
  sudo sed -i -E '/^HOOKS=/ s/\budev\b/udev plymouth/' "$MKINIT"
elif sudo grep -qE '^HOOKS=.*\bsystemd\b' "$MKINIT"; then
  # Se o initramfs usa o hook systemd no lugar do udev, o plymouth vai logo depois dele
  sudo sed -i -E '/^HOOKS=/ s/\bsystemd\b/systemd plymouth/' "$MKINIT"
else
  echo "!!! Não encontrei udev nem systemd em HOOKS. Adicione plymouth manualmente."
fi
echo "HOOKS atual:"
sudo grep -E '^HOOKS=' "$MKINIT"

# 8.2 quiet e splash na linha do kernel
CMDLINE=/etc/kernel/cmdline
if [[ -f "$CMDLINE" ]]; then
  backup "$CMDLINE"
  for param in quiet splash; do
    if ! sudo grep -qw "$param" "$CMDLINE"; then
      sudo sed -i "1 s/\$/ $param/" "$CMDLINE"
    fi
  done
  echo "Linha do kernel atual:"
  sudo cat "$CMDLINE"
else
  echo "!!! $CMDLINE não existe. Adicione quiet splash manualmente no seu bootloader."
fi

# 8.3 Comentar o splash do Arch no preset (senão ele aparece por cima do Plymouth)
PRESET=/etc/mkinitcpio.d/linux.preset
if [[ -f "$PRESET" ]]; then
  backup "$PRESET"
  sudo sed -i -E 's|^(default_options=.*--splash /usr/share/systemd/bootctl/splash-arch\.bmp.*)|#\1|' "$PRESET"
  echo "Linha no preset:"
  sudo grep -n 'splash-arch.bmp' "$PRESET" || echo "(linha do splash não encontrada)"
else
  echo "!!! $PRESET não encontrado."
fi

# 8.4 Definir tema bgrt e regenerar o initramfs/UKI (o -R já roda o mkinitcpio)
echo ">>> Aplicando tema bgrt e regenerando a imagem de boot..."
sudo plymouth-set-default-theme -R bgrt

# ---------------------------------------------------------------------
# 9. Final
# ---------------------------------------------------------------------
echo ""
echo ">>> Instalação concluída com sucesso! 🚀"
echo ">>> Reinicie o computador para ativar Plymouth, logind e ZRAM por completo."
echo ">>> Cópias de segurança dos arquivos editados ficaram com a extensão .bak-DATA."
