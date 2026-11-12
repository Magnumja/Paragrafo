# Revisão de desempenho — 2026-11-12

## Problema encontrado

A view calculava `completed` usando `filter` sobre todos os parágrafos em cada atualização. Cada cartão usava `firstIndex` sobre o documento inteiro para descobrir seu próprio número. O custo crescia com o documento mesmo quando poucos cartões estavam visíveis.

## Mudança mantida

`DocumentState` calcula intervalos de páginas na importação, mantém a contagem incremental de traduções e fornece índices diretamente aos cartões. A interface apresenta uma página por vez e continua usando `LazyVStack`. O contador não duplica resultados quando um trecho já traduzido recebe uma atualização.

## Medição reproduzível

Execute `./benchmark.sh`. Compilação otimizada, 10.000 parágrafos, 40 trechos visíveis da última página e 200 atualizações por rodada. Os dois caminhos calculam o mesmo resultado, validado por precondição. Cinco rodadas no mesmo processo/hardware:

| Rodada | Código anterior | Código novo |
|---|---:|---:|
| 1 | 76,649 ms | 0,004 ms |
| 2 | 61,531 ms | 0,002 ms |
| 3 | 57,249 ms | 0,003 ms |
| 4 | 61,252 ms | 0,003 ms |
| 5 | 60,780 ms | 0,002 ms |

Mediana: 61,252 ms → 0,003 ms. Os valores novos estão próximos do limite de medição do relógio; a conclusão útil é a remoção das varreduras, não um multiplicador de velocidade exato.

**Escopo da medição:** apenas a preparação de metadados usados pela interface. Não mede layout SwiftUI, tempo total de importação, OCR nem latência do motor de tradução. Não extrapolar esse resultado para a velocidade total do aplicativo.

## Outras decisões

- Tradução sequencial mantida. Não há evidência local de que lotes acelerem o motor e não foi introduzida concorrência sem medição.
- Removida a chamada redundante de preparação. `translate` pode identificar a origem e solicitar downloads. O fluxo foi observado na UI, mas não há medição de redução de latência.
- OCR continua em qualidade `accurate`; não foi trocado por um modo menos preciso para aparentar velocidade.
- Importação agora informa a página e permite cancelamento cooperativo, observado entre páginas e após o OCR da página atual. Melhoria de controle/responsividade, não de velocidade bruta.

## Revisão de correção

Testes cobrem intervalos de páginas, atualização repetida, respostas vazias, troca de destino e cancelamento. A inversão proposital da condição que incrementa o contador fez a verificação falhar; a implementação correta foi restaurada e os testes repetidos.

## Validação final da aplicação

Build de produção e 15 verificações concluídos. Na UI, um PDF de dois parágrafos em inglês foi importado, traduzido para português e exportado em TXT; o número 1250 e os dois pares de trechos permaneceram no resultado. Os modelos de inglês/português foram baixados pelo macOS durante a validação. Contraste no modo escuro, modo só tradução e ajuste de tamanho de texto foram conferidos.
