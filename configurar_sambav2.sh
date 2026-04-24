#!/bin/bash

# Script de configuração do Samba para Arch Linux (Interativo)

# =========================
# Verificação de root
# =========================
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root (sudo)."
  exit 1
fi

# =========================
# Função de erro
# =========================
verificar_erro() {
    if [ $? -ne 0 ]; then
        echo "Erro: $1 falhou!"
        exit 1
    fi
}

# =========================
# Detectar usuário correto
# =========================
USUARIO=${SUDO_USER:-$(whoami)}
echo "Usuário detectado: $USUARIO"

# =========================
# Escolha interativa
# =========================
echo ""
echo "Configuração de rede do Samba:"
read -p "Digite o nome do WORKGROUP (padrão: WORKGROUP): " WORKGROUP
WORKGROUP=${WORKGROUP:-WORKGROUP}

read -p "Digite o nome do servidor (padrão: ARCH-SERVER): " NETBIOS
NETBIOS=${NETBIOS:-ARCH-SERVER}

echo ""
echo "Resumo:"
echo "Workgroup: $WORKGROUP"
echo "Nome do servidor: $NETBIOS"
echo ""

# =========================
# Atualizar sistema
# =========================
echo "Atualizando o sistema..."
pacman -Syu --noconfirm
verificar_erro "Atualização do sistema"

# =========================
# Instalar pacotes
# =========================
echo "Instalando Samba e dependências..."
pacman -S --noconfirm samba wsdd avahi
verificar_erro "Instalação dos pacotes"

# =========================
# Criar diretório público
# =========================
echo "Criando diretório público..."
PASTA="/home/$USUARIO/Publico"
mkdir -p "$PASTA"
chmod 775 "$PASTA"
chown "$USUARIO:$USUARIO" "$PASTA"

# =========================
# Backup config antiga
# =========================
echo "Fazendo backup do smb.conf..."
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak 2>/dev/null

# =========================
# Criar smb.conf
# =========================
echo "Criando novo smb.conf..."

cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = $WORKGROUP
   netbios name = $NETBIOS
   server string = Samba Server
   server role = standalone server

   log file = /var/log/samba/log.%m
   max log size = 50

   dns proxy = no
   unix charset = UTF-8

[homes]
   comment = Home Directories
   browsable = no
   writable = yes

[ARCH-SHARE]
   comment = Pasta Compartilhada
   path = $PASTA
   browseable = yes
   writable = yes
   public = yes
   create mask = 0775
   directory mask = 0775
EOF

verificar_erro "Criação do smb.conf"

# =========================
# Validar config
# =========================
echo "Validando configuração..."
testparm -s
verificar_erro "Validação do smb.conf"

# =========================
# Criar senha samba
# =========================
echo "Configurando senha do Samba para $USUARIO..."
smbpasswd -a "$USUARIO"
verificar_erro "Senha do Samba"

# =========================
# Configurar WSDD
# =========================
echo "Configurando WSDD..."
echo "WSDD_PARAMS=\"--workgroup $WORKGROUP --hostname $NETBIOS\"" > /etc/conf.d/wsdd

# =========================
# Habilitar serviços
# =========================
echo "Habilitando serviços..."
systemctl enable smb wsdd avahi-daemon
systemctl restart smb wsdd avahi-daemon
verificar_erro "Inicialização dos serviços"

# =========================
# Firewall (ufw)
# =========================
if command -v ufw >/dev/null 2>&1; then
    echo "Configurando UFW..."
    ufw allow samba
fi

# =========================
# Firewall (firewalld)
# =========================
if command -v firewall-cmd >/dev/null 2>&1; then
    echo "Configurando firewalld..."
    firewall-cmd --permanent --add-service=samba
    firewall-cmd --reload
fi

# =========================
# Status dos serviços
# =========================
echo "Status dos serviços:"
systemctl status smb wsdd avahi-daemon --no-pager -l

# =========================
# Finalização
# =========================
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "======================================"
echo " Samba configurado com sucesso!"
echo "======================================"
echo "Usuário: $USUARIO"
echo "Workgroup: $WORKGROUP"
echo "Nome do servidor: $NETBIOS"
echo "Pasta compartilhada: $PASTA"
echo ""
echo "Acesse no Windows:"
echo "\\\\$NETBIOS"
echo "ou"
echo "\\\\$IP"
echo "======================================"
