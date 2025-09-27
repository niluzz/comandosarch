# Verificar se pacotes SELinux foram instalados
pacman -Q | grep -i selinux

# Verificar se comandos existem
which sestatus getenforce setenforce semodule

# Verificar arquivos de configuração
ls -la /etc/selinux/

# Verificar parâmetros do kernel
cat /proc/cmdline | grep selinux

# Verificar módulo do kernel
lsmod | grep selinux