# Clipp

## GitHub e autenticação

- Repositório: `https://github.com/lucasdomonte/clipp`.
- Conta esperada para operações Git: `lucasdomonte`.
- Este checkout usa uma chave SSH exclusiva em `~/.ssh/id_ed25519_clipp`, selecionada por `core.sshCommand` na configuração local do Git.
- Preserve essa configuração local; não troque para a identidade global de outra conta/projeto.
- A chave é gerada no Mac e somente o arquivo `.pub` deve ser cadastrado na conta GitHub. Nunca leia, imprima ou versione a chave privada.
- Antes do primeiro push com uma nova configuração, confirme que a autenticação SSH responde `Hi lucasdomonte!`. Não considere a configuração validada apenas porque o remoto público pode ser lido.
- A conta autenticada no `gh` é independente da chave usada pelo Git. Confira a conta e as permissões antes de usar o CLI para gravar no GitHub.
- `user.name` e `user.email` definem a autoria dos commits, não a autenticação SSH. Não invente o e-mail do usuário.

## Arquivos locais

- Não publicar `.build/`, `dist/`, histórico SQLite, preferências ou chaves privadas.
- `Resources/Signing/ClippLocal.cer` é o certificado público de assinatura do aplicativo; a chave privada correspondente permanece no Chaveiro do macOS.
