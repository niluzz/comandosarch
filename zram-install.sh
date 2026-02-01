#!/bin/bash

# Verifica se o script está sendo executado como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root (use sudo)."
  exit 1
fi

# Caminho dos arquivos de configuração
SYSCTL_CONFIG="/etc/sysctl.d/99-vm-zram-parameters.conf"
ZRAM_CONFIG="/etc/systemd/zram-generator.conf"

# Criando o arquivo sysctl.d com os parâmetros
cat <<EOF > "$SYSCTL_CONFIG"
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF

# Criando o arquivo zram-generator.conf com os parâmetros
cat <<EOF > "$ZRAM_CONFIG"
[zram0]
zram-size = ram * 0.3
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# Aplicando as configurações imediatamente
sysctl --system

echo "Configuração aplicada com sucesso."

