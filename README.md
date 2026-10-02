# Clipp

Histórico de clipboard para macOS, feito em Swift. Fica na barra de menus: clique no ícone para ver textos e imagens com data e hora, buscar, copiar novamente, excluir itens ou pausar a captura. A engrenagem abre as configurações em uma janela própria. O atalho global abre o histórico na posição do mouse e permite colar no aplicativo anterior.

## Instalar pelo DMG

Requer **macOS 13 ou superior**, em Mac **Apple Silicon ou Intel**.

Baixe o instalador e seu arquivo de verificação na [página de versões](https://github.com/lucasdomonte/clipp/releases). O DMG pronto usa a assinatura local fixa do mantenedor; quem instala não precisa compilar nem gerar uma chave.

1. Abra o arquivo `Clipp-<versão>-universal.dmg`.
2. Arraste `Clipp.app` para a pasta **Applications (Aplicativos)** da janela. Encerre uma versão anterior do Clipp antes de substituí-la.
3. Ejete o disco Clipp no Finder e abra o app pela pasta **Aplicativos**.
4. O ícone aparece na barra superior. Clique nele ou use **⌘⇧V** para abrir o histórico.

Esta versão usa um **certificado local autossinado fixo**, adequado para testes, sem certificado Developer ID e sem notarização da Apple. Essa assinatura não torna o aplicativo confiável para o Gatekeeper; o macOS pode bloquear a primeira abertura. Se confiar na origem do arquivo, tente abrir o app instalado e então acesse **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**. Confirme **Abrir**. [Orientações oficiais da Apple](https://support.apple.com/pt-br/102445).

Autorize as notificações se quiser avisos ao copiar. A permissão de Acessibilidade é opcional e serve para a colagem automática: use **Autorizar colagem automática** nas configurações. Sem ela, copie pelo histórico e cole manualmente com **⌘V**. O histórico é local; o DMG inclui apenas o aplicativo e as instruções, sem dados ou preferências de quem gerou o instalador.

**Ao atualizar de uma versão anterior à 0.5.1:** encerre o Clipp, remova a entrada antiga em **Ajustes do Sistema → Privacidade e Segurança → Acessibilidade**, adicione `/Applications/Clipp.app`, habilite e reabra o aplicativo. Essa troca de identidade exige renovar a autorização uma vez. A versão 0.5.2 reutiliza o certificado da 0.5.1; confira a preservação da permissão no Mac após a atualização, testando a colagem em um campo de texto.

Quem recebe o instalador não precisa importar certificados, receber a chave privada nem alterar a confiança em certificados raiz.

## Novidades da versão 0.5.2

- Menos trabalho em segundo plano: com as janelas fechadas, novas cópias não recarregam a lista nem consultam contagem e espaço em disco.
- Linhas e miniaturas são liberadas ao fechar o histórico, inclusive quando uma busca ou página ainda está sendo carregada.
- O ícone e o atalho compartilham a mesma janela nativa, preservando as ações de copiar pelo ícone e colar pelo atalho.
- Consultas sem busca evitam filtros desnecessários; a paginação usa data/ID e a retenção exclui os itens antigos por faixa.
- Captura de texto sem criar tarefa extra; imagens continuam sendo preparadas fora da interface. A fila de gravação evita deslocar todos os itens e mantém a tentativa após falhas.
- Estados duplicados e rascunhos de ícones descartados foram removidos. Nenhuma dependência nova ou migração de banco.
- Instalador universal com a mesma identidade de assinatura local e arquivo SHA-256. Cada compilação monta um bundle limpo antes de substituir o anterior.

Para conferir a atualização: copie texto e imagem, abra o histórico pelo ícone e por **⌘⇧V**, busque um item antigo, role para carregar mais e feche/reabra a janela. Teste a colagem em um campo de texto com Acessibilidade autorizada. Confira também notificações, som e uso de disco nas configurações. A suíte automatizada cobre armazenamento, paginação, captura e manutenção; a autorização do macOS precisa ser conferida no próprio Mac.

## Gerar o instalador para compartilhar

```sh
./scripts/build-dmg.sh
```

Gera `dist/Clipp-<versão>-universal.dmg` com binário para Apple Silicon e Intel, o atalho para Aplicativos e o arquivo `LEIA-ME.txt`. O script verifica a integridade do DMG e grava seu SHA-256 em um arquivo `.dmg.sha256` ao lado. A montagem usa uma pasta temporária exclusiva e copia somente o aplicativo e as instruções; histórico, banco de dados e preferências locais não entram no pacote. Distribua o DMG e o checksum como anexos de uma versão no GitHub Releases; a pasta `dist/` fica fora dos commits.

Com os dois arquivos baixados na mesma pasta, confira a integridade:

```sh
shasum -a 256 -c Clipp-0.5.2-universal.dmg.sha256
```

O resultado esperado é `Clipp-0.5.2-universal.dmg: OK`. O checksum confere o arquivo baixado; não substitui a confiança na origem do instalador.

## Executar

Requer macOS 13 ou superior e as ferramentas de desenvolvimento Swift do Xcode ou Command Line Tools.

```sh
./scripts/build-app.sh
open dist/Clipp.app
```

O script compila em modo release e gera `dist/Clipp.app` com a identidade local fixa `Clipp Local Code Signing`. Para desenvolver no Xcode:

```sh
open Package.swift
```

Para instalar em uma pasta permanente, encerre o Clipp pelo menu e execute:

```sh
./scripts/install-app.sh
```

Se o Clipp já estiver na pasta Aplicativos principal, atualize o mesmo local com `./scripts/install-app.sh /Applications/Clipp.app`.

O instalador compila, copia para `~/Applications/Clipp.app` e abre o aplicativo. Na primeira abertura, “Iniciar com o Mac” vem ativado: o Clipp se registra pelo `SMAppService` para abrir na barra de menus ao entrar na sua conta. É possível desligar essa opção nas configurações. Uma escolha posterior de desativação, no Clipp ou no macOS, é respeitada. Se o sistema pedir aprovação, a janela informa a pendência e oferece abrir os itens de início.

Para executar as verificações automatizadas:

```sh
swift test --disable-sandbox
```

O macOS pode solicitar acesso ao clipboard. Se a captura estiver bloqueada, permita o acesso do Clipp nos Ajustes do Sistema.

## Assinatura local

A identidade `Clipp Local Code Signing` é criada uma única vez na máquina de desenvolvimento. Sua chave privada fica apenas no **Chaveiro login**; o arquivo `Resources/Signing/ClippLocal.cer` contém somente o certificado público. Os scripts reutilizam essa identidade e não recriam o certificado em cada compilação. Se ela estiver ausente, a compilação falha em vez de voltar automaticamente à assinatura ad-hoc.

O certificado público sozinho não permite assinar. Para compilar em outro Mac, crie sua própria identidade de assinatura de código no Acesso às Chaves e informe-a em `CLIPP_SIGNING_IDENTITY`; ela será diferente da usada nos DMGs do mantenedor. Para apenas usar o Clipp, baixe o DMG pronto.

Para verificar a assinatura e a estabilidade da identidade entre binários diferentes:

```sh
./scripts/verify-signing.sh
```

Essa verificação não substitui o teste da permissão de Acessibilidade no macOS. Não compartilhe a chave privada com quem recebe o DMG nem a inclua no repositório ou instalador. Perder a chave impede assinar novas versões com a mesma identidade.

Quando houver um certificado Apple Developer ID instalado, a identidade pode ser indicada explicitamente, sem mudar os scripts:

```sh
CLIPP_SIGNING_IDENTITY='Developer ID Application: Nome (TEAMID)' ./scripts/build-dmg.sh
```

A troca para Developer ID também muda a identidade. Notarização e publicação na loja continuam sendo etapas separadas; o certificado local não as substitui.

## Funcionamento

- NSStatusItem para o ícone da barra, um NSPanel com SwiftUI compartilhado entre o ícone e o atalho, NSPasteboard para o clipboard e SQLite do sistema para armazenamento. Sem bibliotecas externas ou nuvem.
- Textos e imagens nativas ficam em `~/Library/Application Support/Clipp/history.sqlite3`, inclusive depois de fechar o app.
- O histórico abre com 30 itens e carrega automaticamente os próximos 30 ao chegar perto do fim da rolagem. Cada página parte da data/ID do último item exibido, sem consultar novamente os itens anteriores. A lista usa prévias de texto e miniaturas; os originais são lidos apenas ao copiar/colar. Abrir novamente ou mudar a busca reinicia no primeiro lote.
- Com as janelas fechadas, uma nova cópia apenas é gravada e notificada: não recarrega a lista, a contagem nem o tamanho dos arquivos. O histórico libera as linhas e miniaturas ao fechar; as estatísticas de disco são consultadas nas configurações.
- A captura funciona enquanto o app está aberto e não está pausado. A consulta ocorre a cada 0,5 segundo; cópias intermediárias muito rápidas podem não ser capturadas.
- Suporta texto e imagens disponibilizadas diretamente no clipboard, incluindo PNG, TIFF e JPEG. Não arquiva arquivos arbitrários copiados pelo Finder.
- Se uma gravação falhar, mantém as cópias pendentes em memória e tenta novamente enquanto o app continuar aberto.
- O histórico começa sem limite. Nas configurações, escolha qualquer quantidade inteira a partir de 1, como 10 ou 1.000, ou mantenha sem limite. Com limite ativo, os itens mais antigos são excluídos automaticamente. Reduzir o limite abaixo da quantidade atual pede confirmação; essa retenção não cria backups.
- Os dados locais não são criptografados. Conteúdos marcados como confidenciais pelo aplicativo de origem são ignorados; textos sensíveis sem essa marcação podem ser registrados.

## Configurações

- O atalho padrão é **⌘⇧V**. Em “Atalho de teclado”, clique na combinação atual e pressione uma nova combinação com ⌘ ou ⌃. Esc cancela a gravação. “Remover” desativa o atalho, e a escolha permanece salva.
- O atalho abre o histórico na posição do mouse. A posição e o tamanho são ajustados para manter a janela inteira na área útil do monitor, com margem da barra de menus e do Dock. Em telas menores, a lista continua rolável. Esc, um clique fora ou repetir o atalho fecha o histórico.
- Clicar em um item da janela aberta pelo atalho copia seu conteúdo, fecha a janela, devolve o foco ao aplicativo anterior e envia **⌘V**. Funciona para textos e imagens nos campos que aceitam esses formatos. O Clipp não lê nem altera diretamente o texto do campo.
- A colagem automática exige permissão de Acessibilidade do macOS. Em configurações, use “Autorizar colagem automática”. Sem a permissão, o conteúdo continua copiado e pode ser colado manualmente com ⌘V. O posicionamento da janela permanece no mouse.
- O menu de contexto oferece “Copiar” sem colar. No histórico aberto pelo ícone da barra, o clique também mantém a ação de apenas copiar.
- O app verifica se o aplicativo original está ativo e se o clipboard ainda contém a cópia selecionada antes de enviar ⌘V; se o destino fechar, o foco não voltar ou o clipboard mudar, a colagem é cancelada.

- Notificações locais mostram “Texto copiado” ou “Imagem copiada” e dependem da autorização do macOS. O som nativo Tink tem controle independente. Ambos começam ligados e funcionam nas novas capturas e ao copiar pelo histórico; as escolhas ficam salvas.
- “Mostrar texto copiado na notificação” aparece logo abaixo da opção de notificações quando ela está ligada. Começa ativada e mostra uma prévia de até 300 caracteres do texto copiado; desligada, mantém somente o aviso genérico. A escolha permanece salva mesmo ao desligar e religar as notificações.
- Quando a permissão das notificações foi negada, o botão abre os Ajustes do Sistema. O app não repete o pedido bloqueado e atualiza o estado ao voltar dos ajustes.
- O painel mostra o uso real do disco pelo histórico (banco, miniaturas e arquivos auxiliares). Quanto mais itens, especialmente imagens, maior o espaço necessário.
- “Limpar todo o histórico” pede confirmação e exclui os registros imediatamente, sem backup e sem desfazer. Não existe mais rotina de criação ou expiração de backups. Arquivos eventualmente criados por versões anteriores não são modificados automaticamente.

Referências: [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard), [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem), [permissão de notificações](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications), [início com o Mac](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) e [posição do cursor de texto](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute).
