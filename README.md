# Parágrafo

App nativo em SwiftUI para macOS 15+, com leitura e tradução de PDFs por parágrafo.

## Executar

Abra `dist/Parágrafo.app`. Para recompilar com Swift 6 / Xcode 16+:

```sh
./build-app.sh
open "dist/Parágrafo.app"
```

O projeto pode ser aberto no Xcode usando `Package.swift`. O script inclui a logo e gera um aplicativo para a arquitetura do Mac, com assinatura local. Distribuição pública ainda requer Developer ID e notarização.

## Interface

- Abra um PDF com ⌘O ou arraste-o para a janela.
- Escolha origem e destino na barra lateral. O modo Automático usa uma amostra do documento; para um PDF em inglês, você pode selecionar explicitamente Inglês → Português.
- Inicie a tradução e acompanhe o progresso. Pause após o trecho atual e continue mantendo o que já foi traduzido.
- Navegue por página, compare os dois idiomas ou ative **Só tradução**.
- Ajuste o tamanho de texto de 14 a 24 pontos e copie traduções individualmente.
- Exporte em TXT bilíngue com ⌘⇧E. Trechos pendentes ficam identificados.
- A importação mostra a página atual e permite cancelar. Se houver outro documento aberto, ele permanece disponível quando a nova importação falha ou é cancelada.
- Tema acompanha o macOS, com cores adaptadas a claro/escuro e logo integrada à tela inicial.

O progresso fica na janela durante a sessão. Fechá-la descarta os dados. Alterar o idioma de destino apaga as traduções anteriores. A tradução pode solicitar downloads de idiomas do sistema; eles são gerenciados pelo macOS e podem continuar em segundo plano.

## Desempenho e validação

Veja [PERF.md](PERF.md) para o benchmark antes/depois, seus limites e os achados da revisão.

```sh
./check.sh       # testes executáveis, incluindo PDF real, OCR e cancelamento
./benchmark.sh   # custo de atualização dos metadados da interface
./check-model.sh # regressões de reinício e pausa da sessão
swift test       # testes XCTest; requer Xcode com XCTest disponível
```

Não há dependências de terceiros, servidor, login ou chave de API. O ambiente desta entrega possui Command Line Tools sem XCTest; `check.sh` é a verificação executável usada aqui. As 21 verificações de extração/entrada e 2 verificações de ciclo da sessão passaram, incluindo OCR real de um PDF com imagem. Também foram conferidos manualmente importação, modo só tradução, tamanho de texto, contraste no modo escuro, tradução inglês → português e exportação.

## Limites

- Idiomas disponíveis dependem do framework Translation da Apple. Não há suporte universal. Uma sessão trabalha com um par de idiomas; PDFs com múltiplos idiomas precisam ser separados para resultados previsíveis.
- Tradução automática não garante fidelidade absoluta. Compare termos, números e referências com o original.
- A extração separa parágrafos por distância, recuo e ordem das linhas. Colunas, tabelas, escrita vertical, hifenização e parágrafos entre páginas podem exigir revisão. Não há reconstrução da diagramação original na exportação.
- OCR é usado nas páginas sem texto extraível. Texto dentro de imagens em páginas que também têm texto pode não ser capturado. O reconhecimento depende da qualidade da digitalização e dos idiomas do Vision.
- PDFs protegidos precisam ser desbloqueados antes da importação. Arquivos grandes ainda podem consumir memória. Cancelar aguarda a operação atual da página; pausar tradução aguarda o trecho atual ou o diálogo do sistema.
- O fluxo completo foi validado com um PDF de dois parágrafos em inglês: download dos modelos, tradução para português, comparação e exportação em TXT. Isso não garante resultados em todos os idiomas e layouts. Não foi comprovado ganho de velocidade no motor de tradução.

## Código

- `App.swift`: composição da janela, controles e navegação.
- `ReaderViews.swift`: tela inicial e cartões de leitura.
- `ReaderModel.swift`: importação, tradução e exportação.
- `DocumentState.swift`: parágrafos, intervalos de páginas e progresso.
- `Extraction.swift`: PDFKit, OCR Vision e agrupamento de linhas.

Referências: [Translation — Apple](https://developer.apple.com/documentation/translation) e [TranslationSession — Apple](https://developer.apple.com/documentation/translation/translationsession).

### Correção da tradução

Reproduzidas e corrigidas duas falhas: início com trecho apenas numérico e nova tentativa com o mesmo par de idiomas após limpar a configuração. A configuração agora é mantida e invalidada explicitamente ao reiniciar. Inglês → português foi validado na interface em duas execuções sucessivas, usando detecção automática e seleção manual. O teste de regressão de reinício falhou antes da correção e passou depois. O PDF específico do usuário não foi disponibilizado para validação.
