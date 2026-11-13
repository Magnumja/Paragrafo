# Parágrafo

[Read in English](README.md)

App nativo em SwiftUI para macOS 15+: leia um PDF com a tradução ao lado do original e faça perguntas ao documento. Tudo roda no Mac.

## Executar

```sh
./build-app.sh
open "dist/Parágrafo.app"
```

Requer Swift 6 (Xcode 16+ ou Command Line Tools). O script gera o app para a arquitetura do Mac, com assinatura local. Distribuição pública ainda requer Developer ID e notarização.

Para o assistente de perguntas, instale o [Ollama](https://ollama.com/download) e baixe os dois modelos uma única vez:

```sh
ollama pull llama3.2:3b
```

```sh
ollama pull bge-m3
```

O app inicia o `ollama serve` sozinho quando o painel é aberto e oferece o download se algum modelo faltar. Sem o Ollama, a leitura e a tradução funcionam normalmente.

## O que o app faz

**Ler e traduzir**

- Abra um PDF com ⌘O, arrastando para a janela, pelo "Abrir com" do Finder ou pela lista de recentes.
- Três modos de leitura na barra de ferramentas: **Lado a lado** (original e tradução em colunas), **Tradução** (texto corrido) e **PDF original**.
- A tradução usa o framework Translation da Apple e começa pela página que você está lendo. Pause e continue quando quiser.
- O trabalho fica salvo por arquivo: ao reabrir o mesmo PDF, a tradução, o índice de busca e a síntese voltam na hora.
- Navegue pelas páginas na barra lateral (com o progresso de cada uma) ou com ⌘[ e ⌘]. Tamanho do texto com ⌘+ e ⌘-.
- Exporte como PDF traduzido, Markdown bilíngue ou texto bilíngue.

**Perguntar ao documento** (⌘K)

- Pergunte em português sobre um documento em qualquer idioma. A resposta é escrita por um modelo Llama local a partir de trechos recuperados do próprio PDF.
- Cada afirmação traz uma citação. Clique na citação ou no cartão da fonte para ir à página e ver o trecho marcado; no modo PDF original, a marcação aparece sobre a página real.
- **Síntese geral** resume o documento inteiro com os pontos principais, cada um ligado ao trecho de origem. Documentos longos são lidos em partes.
- Passe o mouse sobre um parágrafo para copiar, pedir uma explicação daquele trecho ou localizá-lo no PDF.
- O modelo de conversa pode ser trocado no menu do painel por qualquer modelo instalado no Ollama.

## Como o assistente funciona

1. Os parágrafos são agrupados por página em trechos de cerca de 900 caracteres.
2. Cada trecho vira um vetor com `bge-m3` (multilíngue, 1024 dimensões). Os vetores ficam salvos em `~/Library/Application Support/Paragrafo/`.
3. A pergunta é comparada aos trechos por similaridade de vetores e por palavras (BM25, incluindo a tradução quando existe); as duas listas são combinadas.
4. Os seis melhores trechos, numerados, vão para o modelo com a instrução de responder só com base neles e citar o número de cada um.
5. A interface transforma as citações em links para os parágrafos de origem.

Nada é enviado para fora do computador: a tradução é do macOS e os modelos rodam no Ollama local (`127.0.0.1:11434`).

## Verificação

```sh
./check.sh            # extração, OCR, persistência, exportação, links das respostas
./check-model.sh      # ciclo da sessão de tradução
./check-rag.sh        # divisão em trechos, busca híbrida, cliente Ollama
./check-assistant.sh  # ponta a ponta: PDF real, índice, perguntas, síntese, parar, restaurar
./benchmark.sh        # custo de atualização dos metadados da interface
```

As verificações usam uma pasta temporária e não tocam no trabalho salvo. As duas últimas de RAG usam o Ollama real quando ele está em execução e pulam essa parte quando não está. `swift test` requer Xcode com XCTest.

Veja [PERF.md](PERF.md) para as medições.

## Limites

- **Tradução:** os idiomas dependem do framework Translation da Apple. A velocidade é a do motor do sistema, cerca de 0,6 s por parágrafo neste Mac; lotes e sessões paralelas não aceleram (medido em PERF.md). Tradução automática pode errar: compare termos, números e referências.
- **Respostas:** o modelo padrão tem 3 bilhões de parâmetros. Ele responde bem a perguntas factuais sobre o texto, mas pode resumir de forma imprecisa ou citar o trecho errado. Confira sempre na fonte indicada. Um modelo maior no Ollama melhora a qualidade ao custo de memória e tempo.
- **Síntese de documentos muito longos:** acima de 24 partes, a síntese é feita por amostragem distribuída do início ao fim, e o app avisa quando isso acontece.
- **Extração:** parágrafos são separados por distância, recuo, tamanho de fonte e ordem das linhas. Colunas, tabelas e escrita vertical podem exigir revisão. Palavras hifenizadas no fim da linha são reunidas, o que pode juntar compostos legítimos. Texto dentro de imagens em páginas que também têm texto não é capturado.
- **OCR:** usado nas páginas sem texto extraível; depende da qualidade da digitalização.
- **PDFs protegidos** precisam ser desbloqueados antes. A conversa com o assistente vale para a sessão; só a síntese fica salva.

## Código

| Arquivo | Papel |
|---|---|
| `App.swift` | Janela, barra de ferramentas, ligação entre leitura e assistente |
| `Sidebar.swift` | Documento, idiomas, progresso e lista de páginas |
| `ReaderViews.swift` | Tela inicial, leitura bilíngue, linha de parágrafo |
| `ChatViews.swift` | Painel de perguntas, respostas e fontes |
| `PDFPane.swift` | PDF original com marcação do trecho |
| `ReaderModel.swift` | Importação, tradução, navegação e exportação |
| `Assistant.swift` | Disponibilidade do Ollama, índice, perguntas e síntese |
| `RAG.swift` | Divisão em trechos, índice vetorial, busca híbrida, prompt |
| `Ollama.swift` | Cliente HTTP do Ollama |
| `Library.swift` | Trabalho salvo por arquivo e recentes |
| `Extraction.swift` | PDFKit, OCR Vision e agrupamento de linhas |
| `Exporter.swift` | PDF, Markdown e texto |

Sem dependências de terceiros no app. Referências: [Translation — Apple](https://developer.apple.com/documentation/translation), [API do Ollama](https://github.com/ollama/ollama/blob/main/docs/api.md).
