# Parágrafo

Aplicativo minimalista nativo em SwiftUI para macOS 15 ou posterior. Abra um PDF, escolha o idioma e leia original e tradução lado a lado, separados por parágrafos.

## Executar

Com Xcode 16+ ou Command Line Tools com Swift 6 instalados:

```sh
./build-app.sh
open "dist/Parágrafo.app"
```

O script gera um aplicativo para a arquitetura do Mac que o compila, com assinatura local. Para distribuição pública, ainda é necessário assinar com Developer ID e notarizar. Também é possível abrir `Package.swift` no Xcode. Execute o `.app` gerado para usar o fluxo nativo de tradução.

## Uso

1. Clique em **Abrir PDF** (⌘O).
2. Confira os trechos extraídos. Páginas sem camada de texto passam por OCR.
3. Escolha o idioma de destino, inicialmente português.
4. Clique em **Traduzir**. O macOS pode solicitar o download de idiomas.
5. Use **Parar** para pausar após o trecho atual e **Continuar** para retomar.
6. **Exportar** salva um TXT UTF-8 com original, tradução e referência à página. Trechos pendentes são identificados.

O progresso permanece na janela durante a sessão; fechar a janela descarta os dados. Trocar o destino limpa as traduções anteriores. Não há conta, chave de API, servidor próprio ou dependências externas.

## Limites desta primeira versão

- O motor é o framework Translation da Apple; a lista de destinos vem do sistema. Nem todos os idiomas do mundo são suportados. A origem é detectada pelo motor e a sessão trabalha com um par de idiomas; documentos que misturam idiomas precisam ser separados por idioma para resultados previsíveis.
- A tradução não resume deliberadamente o texto, mas tradução automática não garante fidelidade absoluta. Revise termos técnicos, números, referências e textos importantes comparando com o original.
- PDFs frequentemente não armazenam parágrafos semanticamente. A separação usa distância vertical, recuo e ordem das linhas do PDFKit/Vision. Colunas, tabelas, cabeçalhos, notas, hifenização, parágrafos que atravessam páginas e escrita vertical podem ser extraídos incorretamente.
- OCR depende da qualidade da imagem e dos idiomas reconhecidos pelo Vision. Páginas que já possuem texto não passam por OCR adicional; imagens com texto embutidas nessas páginas podem não ser capturadas.
- PDF protegido precisa ser desbloqueado antes da importação. A exportação é textual, sem recriar a diagramação original.
- A extração ocorre fora da interface; documentos muito grandes podem consumir memória e levar tempo. A importação ainda não possui cancelamento.

## Estrutura

- `App.swift`: interface, sessão de tradução, importação e exportação.
- `Extraction.swift`: PDFKit, OCR Vision e agrupamento de linhas.
- `ParagraphTests.swift`: testes da separação e preservação do texto.

```sh
swift test
```

## Referências

- [TranslationSession — Apple](https://developer.apple.com/documentation/translation/translationsession)
- [Translation — Apple](https://developer.apple.com/documentation/translation)

O conteúdo é processado no dispositivo pelo framework nativo. Downloads de idiomas podem exigir internet; consulte a documentação da Apple sobre métricas do sistema.

## Validação desta entrega

- Build de produção concluído e `.app` com assinatura local gerado em Apple Silicon.
- Abertura da janela verificada no macOS.
- Sete verificações passaram em `./check.sh`, incluindo extração de um PDF real com dois parágrafos, preservação de números, Unicode e listas.
- `swift test` requer XCTest do Xcode completo, ausente no ambiente desta entrega. `./check.sh` funciona com Command Line Tools.
- A tradução completa com download dos modelos e a qualidade do OCR ainda precisam de validação manual com documentos representativos. Não são cobertas pelas sete verificações acima.
