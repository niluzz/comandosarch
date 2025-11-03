# ⚙️ Comandos Arch  

Scripts de configuração e automação para Arch Linux — criados para facilitar setups personalizados, otimizados e modulares.  

---

## 📦 Sobre o Projeto  

Este repositório reúne uma coleção de **scripts Bash** voltados à configuração completa do **Arch Linux**, incluindo ajustes de desempenho, otimização de energia, drivers gráficos, ambiente de desktop e utilitários essenciais.  

A ideia é **automatizar tarefas repetitivas**, manter tudo versionado e simplificar reinstalações ou novos ambientes.  

> 💡 Cada script é independente — você pode rodar apenas o que precisar.

---

## 🧩 Estrutura do Repositório  

| Arquivo / Script | Função Principal |
|------------------|------------------|
| `gnome-amd-N.sh` | Configuração completa do GNOME para sistemas com GPU AMD |
| `gnome-nvidia-D.sh` | Configuração otimizada do GNOME com drivers NVIDIA |
| `kde-nvidia.sh` | Setup completo do KDE Plasma com suporte NVIDIA |
| `hibernate-configure.sh` | Script para ajuste fino da hibernação no Arch |
| `tlp-configure.sh` | Configuração avançada de economia de energia (TLP) |
| `configurar_samba.sh` | Configuração automatizada de compartilhamento via Samba |
| `zram-install.sh` | Instalação e ajuste de zRAM para melhor uso de memória |
| `zsh-install.sh` | Instalação e personalização inicial do Zsh |
| `README.md` | Este arquivo de documentação |

---

## 🚀 Como Usar  

1. Clone o repositório:
   ```bash
   git clone https://github.com/niluzz/comandosarch.git
   cd comandosarch
