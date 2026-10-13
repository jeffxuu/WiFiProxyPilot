> **Documentation version: v3.2.0-beta.1.** This translated guide describes the older release. Current UI and installer documentation: [English](README.md), [简体中文](README.zh-CN.md), [v3.3 Setup EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/WiFiProxyPilot-Setup-x64.exe). The application UI supports en-US and zh-CN; README translation does not imply another UI language.

<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Troca inteligente de proxy por Wi-Fi no Windows</h3>
  <p>Um utilitário leve e moderno para Windows que alterna automaticamente o proxy do sistema conforme os SSIDs de Wi-Fi, os endereços de gateway e as regras definidas por você.</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot?include_prereleases)](https://github.com/jeffxuu/WiFiProxyPilot/releases)
  [![Licença MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Seu Wi-Fi muda. Seu proxy acompanha.** Use um proxy hospedado no gateway das redes Wi-Fi comuns e conexão direta nas redes que você escolher. Gerencie tudo por uma interface WPF moderna ou pela bandeja do sistema.

> **A v3.2.0-beta.1 está publicada como Beta/Prerelease, não como versão estável.** As capturas mostram o aplicativo WPF real com dados de rede simulados. A validação com rede real, login/suspensão, instalação e desinstalação continua separada dos testes de regressão isolados. A interface atual está em chinês simplificado; as traduções do README não significam que a interface esteja traduzida. O repositório é Public, com confirmação do proprietário.

## Capturas de tela

![Visão geral: aplicativo WPF real, rede simulada](docs/images/dashboard.png)

| Regras de Wi-Fi | Configurações |
| --- | --- |
| ![Prévia das regras de Wi-Fi](docs/images/rules.png) | ![Prévia das configurações](docs/images/settings.png) |

![Bandeja do sistema: menu real com dados simulados](docs/images/tray.png)

<details>
<summary>Prévia do tema escuro</summary>

![Tema escuro: layout anterior da visão geral WPF](docs/images/dashboard-dark.png)

</details>

Todas as imagens são capturas reais do aplicativo em um ambiente isolado, **não comprovação de uma conexão de proxy real**. A captura do tema escuro usa um layout anterior da visão geral. A captura da bandeja mostra o menu real do aplicativo com os mesmos dados simulados.

## Principais recursos

- Identifica o Wi-Fi conectado e compara suas regras com o SSID completo, sem diferenciar maiúsculas de minúsculas.
- Obtém o **gateway IPv4 padrão** da interface Wi-Fi física atual e aplica a porta de proxy configurada, `7890` por padrão.
- Permite conexão direta nas redes selecionadas. Novas instalações começam **sem regras de Wi-Fi predefinidas**; todas as regras podem ser editadas ou excluídas.
- Oferece interface WPF inspirada no macOS, temas claro/escuro e bandeja do sistema com um monitor independente em segundo plano.
- Separa o gerenciamento automático, o estado do proxy manual do Windows e os diagnósticos opcionais TCP/HTTP. Um proxy ativado não comprova acesso à internet.
- Salva a configuração de forma atômica e distingue «salvo» de «aplicado pelo monitor».
- Preserva o backup do proxy manual original e protege alterações posteriores feitas por você ou outro aplicativo.
- Disponibiliza o código sob a licença MIT para inspeção e contribuição.

## Download e instalação

**[Baixar v3.2.0-beta.1 — Beta/Prerelease](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)** · **[EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.exe)** · **[ZIP](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.zip)** · **[SHA256.txt](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/SHA256.txt)** · **[Ver versões](https://github.com/jeffxuu/WiFiProxyPilot/releases)** · **[Artefatos de compilação v3.2](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)**

A versão publicada v3.2.0-beta.1 contém a interface WPF mostrada acima e está marcada como **Beta/Prerelease**. Ela não é uma versão estável. Confira a versão, as notas e o SHA256 antes de instalar. Os artefatos de compilação são uma opção separada de download e expiram. O badge Release inclui as pré-versões.

A plataforma prevista é **Windows 11 x64**, com Windows PowerShell 5.1, serviço WLAN e Windows Script Host. O EXE autocontido dispensa instalação separada de .NET, Python, Node.js ou WebView2. Não se afirma compatibilidade com outras versões do Windows. Políticas da organização podem restringir informações WLAN, configurações de proxy ou tarefas agendadas. As compilações atuais não têm assinatura digital; mantenha as proteções de segurança do Windows ativadas.

Baixe o EXE ou extraia o ZIP e compare o hash com o arquivo `SHA256.txt` incluído:

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

O executável continua se chamando `WiFiProxySwitcher.exe` para manter a compatibilidade das atualizações. Execute com seu usuário interativo normal do Windows. Abrir a janela v3.2, por si só, não ativa o gerenciamento do proxy. Não instale para sua conta habitual usando a conta de outro administrador.

## Início rápido

1. **Baixe** uma compilação e confira a versão e o hash.
2. **Configure** a porta de um proxy que já exista no gateway do seu Wi-Fi e adicione os nomes das redes que devem usar conexão direta.
3. **Ative a troca automática** depois de revisar as configurações que o aplicativo irá gerenciar.

**O gateway precisa realmente executar um serviço de proxy. O WiFi Proxy Pilot não fornece servidor proxy nem nós VPN.** Ao usar um hotspot Android, o gateway IPv4 atual é obtido automaticamente. Configure a porta de escuta do aplicativo de proxy no celular e permita conexões do dispositivo Windows conectado. Um hotspot sozinho não é um proxy.

## Como funciona

```text
Wi-Fi conectado → Ler um estado estável de SSID/interface → Comparar regras do usuário
  ├─ Regra de conexão direta encontrada → Desativar o proxy manual do Windows
  └─ Nenhuma regra de conexão direta    → Obter o gateway IPv4 do Wi-Fi atual
                                         → Aplicar gateway + porta configurada
```

O monitor verifica a rede atual antes de aplicar uma alteração, para evitar reutilizar um gateway antigo após a troca de Wi-Fi. SSID desconhecido, rotas ausentes ou interfaces ambíguas mantêm a configuração existente, mostram o motivo e levam a novas tentativas. Uma desconexão confirmada desativa o proxy manual. PAC e detecção automática mantêm seus valores e ainda podem influenciar o tráfego dos aplicativos.

## Gerenciamento de regras de Wi-Fi

Abra **Regras de Wi-Fi** para adicionar, renomear, excluir ou adicionar a rede atual quando ela for identificada com segurança. Listas vazias são permitidas. A comparação usa o nome completo com `OrdinalIgnoreCase`, não um prefixo ou trecho. Espaços válidos são preservados; os nomes devem ter de 1 a 32 bytes UTF-8 e não conter caracteres de controle.

**Salvar e aplicar** verifica edições simultâneas e grava de forma atômica. «Salvo» confirma a gravação; «Aplicado» exige um sinal recente e compatível do monitor, com a mesma revisão e uma rede estável. Caso contrário, o aplicativo informa que a aplicação em segundo plano está pendente. Cancelar descarta as alterações não salvas. Regras excluídas não são reinseridas silenciosamente.

## Bandeja do sistema e modos de proxy

| Ação | Efeito |
| --- | --- |
| Ativar troca automática | Observar a rede novamente e gerenciar o proxy manual conforme suas regras |
| Pausar | Interromper as gravações automáticas; manter o proxy atual |
| Conexão direta | Pausar o gerenciamento e desativar apenas o proxy manual do Windows |
| Verificar agora | Solicitar nova observação da rede e avaliação de um estado estável |
| Fechar a janela | Ocultar na bandeja por padrão; o monitor continua |
| Sair da interface | Fechar a interface e a bandeja; o monitor independente continua |
| Restaurar configuração original | Encerrar o gerenciamento e restaurar o backup original com verificação de conflitos |

A intenção de pausa ou conexão direta persiste após reiniciar a interface e nos próximos logins. O início do monitor no login e o início da bandeja são configurações separadas.

**Strict** aplica a regra selecionada e informa falhas de diagnóstico sem desativar o proxy silenciosamente. **Safe** pode mudar para conexão direta após a quantidade configurada de falhas consecutivas, permitindo que parte do tráfego passe fora do proxy. Um diagnóstico desconhecido não conta como recuperação. O diagnóstico TCP comprova apenas que é possível conectar a uma porta; o diagnóstico HTTP faz uma requisição real pelo proxy para a URL HTTP configurada. Nenhum garante o funcionamento de todos os sites ou aplicativos.

## Recuperação e desinstalação

O backup do proxy manual original fica em `state/proxy-before-install.json`, dentro do diretório de instalação. As atualizações preservam esse backup e suas regras; não criam um novo backup «original». Mudanças na configuração conservam o arquivo válido anterior. Mantenha esses arquivos locais privados.

Para uma instalação existente, abra o EXE candidato e use **Configurações → Operações avançadas → Reparar instalação / Atualizar**. Não desinstale primeiro nem substitua sua configuração pelos padrões do repositório. Veja a [migração de configuração](docs/CONFIG_MIGRATION.md).

Use **Restaurar configuração original**, **Configurações → Operações avançadas → Desinstalar** ou Aplicativos instalados do Windows. A restauração e a desinstalação comparam os valores atuais com os originais e os últimos gravados pela ferramenta. Alterações externas posteriores geram um conflito em vez de serem sobrescritas. Forçar a restauração é uma escolha explícita; também é possível desinstalar mantendo o proxy atual. A remoção se limita a tarefas e registros de inicialização do próprio produto e a arquivos verificados, protegendo arquivos alheios ou modificados pelo usuário. O modo direto mantém o backup original.

## Segurança e privacidade

- SSIDs, configuração do proxy, estado e logs são processados localmente; não é necessária conta na nuvem nem serviço de análise de uso.
- O aplicativo não coleta senhas de Wi-Fi. Os diagnósticos opcionais se conectam ao proxy escolhido e, no modo HTTP, à URL configurada por você.
- O backup do proxy original é mantido. As operações de instalação e tarefas respeitam a identidade do usuário atual e as verificações de permissão.
- O aplicativo gerencia o **proxy manual** do usuário atual do Windows; não altera DNS, rotas nem regras de firewall.
- Logs e diagnósticos podem incluir identificadores de rede. Revise e anonimize antes de compartilhar.

Para problemas de segurança, consulte [SECURITY.md](SECURITY.md).

## Perguntas frequentes

**Como trocar automaticamente o proxy conforme o Wi-Fi no Windows 11?** Configure a porta do proxy no gateway, adicione SSIDs de conexão direta e ative a troca automática. O monitor avalia mudanças estáveis de Wi-Fi e aplica o proxy manual do Windows para o usuário atual.

**Como usar o gateway de um hotspot Android como proxy do Windows?** Execute um serviço de proxy separado no celular, permita acesso dos dispositivos conectados e informe sua porta no Pilot. O gateway é detectado na interface Wi-Fi atual. Se não estiver acessível, verifique o serviço e o firewall do celular.

**O WiFi Proxy Pilot inclui uma VPN?** Não. Ele gerencia a configuração do proxy manual do Windows; você fornece o serviço. Aplicativos com proxy próprio ou que ignoram as configurações do Windows podem se comportar de outra forma.

**Por que o proxy está ativado, mas a internet não funciona?** O gateway pode não hospedar um proxy, a porta pode estar errada, o serviço pode estar parado ou o destino pode falhar. Confira os diagnósticos TCP/HTTP separadamente. Pausa mantém a configuração; Direto desativa o proxy manual. PAC ainda pode influenciar o tráfego.

**Como evitar o proxy em redes Wi-Fi específicas?** Adicione os SSIDs completos às Regras de Wi-Fi e salve/aplique. Todas as regras podem ser editadas ou excluídas; uma lista vazia é válida.

**Como restaurar as configurações de proxy do Windows?** Escolha Restaurar configuração original e examine qualquer conflito causado por alterações externas. Direto apenas desativa o proxy manual; não restaura o servidor original nem a lista de exceções.

**O aplicativo continua funcionando após fechar a janela?** Sim. X oculta a janela na bandeja por padrão. Sair da interface também mantém o monitor independente ativo; use Pausa ou Restaurar para alterar o gerenciamento em segundo plano.

**Por que não é possível ler a rede atual?** Permissões WLAN/localização, políticas da organização, rotas ausentes, monitor parado ou um sinal antigo podem impedir um estado confiável. A interface mostra o motivo e a última observação válida sem apresentar dados antigos como atuais.

**O que foi testado?** Veja os [resultados v3.2](docs/TEST_RESULTS_V3_2.md), as [evidências de desempenho](docs/PERFORMANCE_V3_2.md) e o [checklist de publicação](docs/RELEASE_CHECKLIST.md). Verificações isoladas não são validação de rede ou instalação real; uma meta de desempenho não é um resultado medido.

## Star History

Se o WiFi Proxy Pilot facilita seu trabalho, considere dar uma estrela ao projeto.

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

O SVG oficial ao vivo usa os dados reais deste repositório no GitHub. Verificado em 14 de outubro de 2026: **0 estrelas** e resposta **HTTP 200** para os SVGs dos temas claro e escuro. Com zero estrelas, o histórico vazio é esperado; não inventamos estrelas nem crescimento, e esse histórico não é substituído por dados fictícios. Veja o [guia oficial de incorporação](https://www.star-history.com/blog/how-to-use-github-star-history/).

## Contribuições e próximos passos

Usuários com acesso ao repositório podem enviar issues e pull requests. Informe a compilação, o comportamento esperado e observado e as evidências anonimizadas. Veja [CONTRIBUTING.md](CONTRIBUTING.md) para o processo de compilação e revisão no Windows. Não inclua configurações pessoais, backups de proxy, credenciais nem logs sem anonimização.

Trabalho planejado: validação real de atualização, login, suspensão e desinstalação; verificações restantes de acessibilidade e layout WPF; melhorias no desempenho de inicialização; e tradução da interface. São planos, não recursos já entregues; a atualização automática não está implementada.

Compile com o SDK definido em `global.json` e Windows PowerShell:

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

A compilação cria um EXE autocontido `win-x64` sem instalá-lo nem alterar o proxy do computador. As identidades existentes `WiFiProxySwitcher` de instalação, registro, mutex e tarefas são preservadas por compatibilidade.

## Licença

O código do projeto usa a licença [MIT](LICENSE). Materiais de terceiros mantêm seus próprios termos; veja os [avisos de terceiros](docs/THIRD_PARTY_NOTICES.md). As fontes são usadas a partir do Windows e não são redistribuídas.
