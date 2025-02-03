# comandosarch
# Adicionando parâmetros ao kernel
if [ -f /etc/kernel/cmdline ]; then
    echo "Adicionando parâmetros NVIDIA ao kernel..."
    desired_param="nvidia-drm.modeset=1 nvidia_drm.fbdev=1 loglevel=3 quiet splash"
    
    if ! grep -q "nvidia-drm.modeset=1" /etc/kernel/cmdline; then
        echo "$desired_param" | sudo tee -a /etc/kernel/cmdline > /dev/null
    else
        echo "Parâmetros NVIDIA já configurados."
    fi
else
    echo "Aviso: /etc/kernel/cmdline não encontrado. Pulando configuração do kernel."
fi
