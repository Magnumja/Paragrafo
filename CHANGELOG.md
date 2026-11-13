# Histórico

## 0.3.0 — 2026-11-13

- Revisão de segurança: armazenamento contido na biblioteca, limites de vetores, conexões Ollama somente locais, bloqueio de links externos do modelo.
- Retenção dos modelos reduzida de 30 para 2 minutos; resposta limitada a 1.024 tokens e extração com liberação temporária por página.
- Primeira publicação no GitHub com CI macOS, política de segurança, documentação bilíngue e checksum da release.

- **Perguntar ao documento:** painel de perguntas com modelo Llama local (Ollama) e busca híbrida nos trechos do PDF. Respostas com citações clicáveis que levam ao parágrafo e o marcam, inclusive sobre o PDF original.
- **Síntese geral** do documento com pontos ligados aos trechos de origem; documentos longos são lidos em partes.
- **Trabalho salvo por arquivo:** tradução, índice de busca e síntese voltam ao reabrir o PDF. Tela inicial com recentes.
- **Nova interface:** barra lateral com páginas e progresso, leitura em colunas, modos Lado a lado / Tradução / PDF original, ações por parágrafo.
- A tradução começa pela página em leitura.
- Exportação em PDF traduzido e Markdown bilíngue, além do texto.
- Extração: títulos separados do corpo pelo tamanho da fonte; palavras hifenizadas no fim da linha reunidas.
- Abrir PDFs pelo Finder ("Abrir com") e pela linha de comando.

## Visual de vidro — 2026-11-12

- Liquid Glass nativo na barra lateral, navegação e status em macOS compatível.
- Materiais foscos no macOS 15, com respeito às preferências de transparência e contraste.
- Texto sobre superfície sólida e botões principais com estilo de vidro.

## Correção de tradução — 2026-11-12

- Corrigido reinício da sessão com o mesmo par de idiomas.
- Origem detectada a partir de uma amostra do documento e selecionável manualmente.
- Números e símbolos preservados sem depender de detecção de língua.
- Pausar durante a preparação libera os controles.
- Mensagens específicas para origem não identificada e idiomas incompatíveis.

## 0.2.0 — 2026-11-12

- Nova interface com logo, barra lateral, navegação por página e cores para tema claro/escuro.
- Modo só tradução, tamanho de texto ajustável, cópia por parágrafo e abertura por arrastar PDF.
- Removidas buscas repetidas no documento ao atualizar a interface; benchmark em PERF.md.
- Progresso por página e cancelamento cooperativo na importação.
- Cancelamento de tradução preserva o progresso.
- Ampliadas as verificações de documentos, progresso e cancelamento.

## 0.1.0 — 2026-11-12

- Interface nativa para comparar original e tradução por parágrafo.
- Extração de PDF, OCR de páginas sem texto e referência à página original.
- Idiomas de destino fornecidos pelo sistema, progresso, pausa e retomada na mesma sessão.
- Exportação bilíngue em TXT e geração de aplicativo macOS por script.
