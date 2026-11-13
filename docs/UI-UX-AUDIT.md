# Auditoria de UI/UX — Parágrafo

**Data:** 13/11/2026 · **Versão auditada:** `main` @ `1a6bec7` · **Plataforma:** macOS 15+ (SwiftUI, Liquid Glass no macOS 26)

**Fontes:** leitura completa de `App.swift`, `ReaderViews.swift`, `Sidebar.swift`, `ChatViews.swift`, `GlassDesign.swift` e `PDFPane.swift`; capturas `Assets/screens/leitura.png` e `pdf-original.png`; tela inicial capturada do build em `dist/`.

**Referências:** Aceternity UI, React Bits, Kokonut UI, Skiper UI, Unlumen UI e Behance. As referências estão traduzidas para SwiftUI nativo, **sem WebView e sem dependências**. Os links `share.google` (Skiper, Unlumen, Behance) não foram abertos: deles usei só os padrões gerais que essas bibliotecas são conhecidas por oferecer.

---

## Veredito

A base é **acima da média**. A hierarquia é clara (sidebar → leitura → assistente), a tipografia serifada é de leitor de verdade, o verde-sálvia dá identidade, e o app já trata *Reduce Motion*, *Reduce Transparency* e *Increase Contrast*. Isso é raro.

Os problemas não são de "feiura". São de **atrito e de descoberta**: há ações escondidas no hover, uma toolbar com muitos ícones sem rótulo, estados que parecem erro (botão desabilitado = "concluído") e uma navegação que tira o usuário do lugar. Na aparência, falta **vida nos momentos de transição**: a tradução chegando, a fonte sendo aberta, o app esperando um PDF. É nesses momentos que as referências web ajudam.

**Ressalva importante.** Aurora, beams, partículas e *spotlight* foram feitos para landing pages. Num leitor de documentos, efeito atrás do texto atrapalha a leitura. A regra que proponho: **movimento só nas bordas e nas transições, nunca atrás do texto lido.**

| Área | Nota | Comentário |
|---|---|---|
| Hierarquia e layout | 8/10 | Três colunas bem resolvidas; leitura lado a lado excelente |
| Tipografia | 8/10 | Serif + versalete com tracking; falta escala no modo stacked |
| Descoberta de ações | 5/10 | Hover-only, ícones sem rótulo, ⌘+ quebrado |
| Feedback e estados | 6/10 | Estado "concluído" parece desabilitado; placeholder "redacted" é cinza morto |
| Navegação | 6/10 | Leitura paginada; "Mostrar no PDF" troca o modo global sem volta |
| Acessibilidade | 7/10 | Boa base; ações do parágrafo ficam ocultas para o VoiceOver |
| Aparência / polimento | 7/10 | Coerente, mas estática; o modo escuro fica achatado |

---

## P0 — Corrigir (bugs de usabilidade)

### 1. `⌘+` não funciona como o usuário espera
`App.swift:117` usa `.keyboardShortcut("+")`. No teclado US/ABNT, `+` exige Shift, e o usuário de Mac aperta `⌘=` para ampliar, como no Safari, no Pages e no Books.
```swift
Button("Aumentar texto", systemImage: "textformat.size.larger") { … }
    .keyboardShortcut("=", modifiers: .command)   // ⌘= (exibido como ⌘+ nos menus do sistema)
// e adicione ⌘0 para restaurar o tamanho padrão (17)
```

### 2. As ações do parágrafo são invisíveis para teclado e VoiceOver
`ReaderViews.swift:577`: o overlay *Copiar / Perguntar / Mostrar no PDF* só aparece no hover e tem `.accessibilityHidden(true)`. O menu de contexto existe, mas pouca gente descobre. Solução nativa:
```swift
.accessibilityActions {
    Button("Copiar tradução") { copy(paragraph.translated) }
    Button("Perguntar sobre este trecho", action: ask)
    Button("Mostrar no PDF original", action: showInPDF)
}
```
Mostre também a barra de ações quando o parágrafo estiver **focado** (`.focusable()` + `@FocusState`), não só no hover.

### 3. "Tradução concluída" aparece como botão desabilitado
`Sidebar.swift:279-284`: no fim da tradução, o CTA principal fica cinza e desabilitado (veja a captura). Visualmente, isso lê como "indisponível" ou "erro", não como sucesso. Troque o botão por um **estado**:
```swift
if model.document.isComplete {
    Label("Tradução concluída", systemImage: "checkmark.seal.fill")
        .font(.callout.weight(.medium)).foregroundStyle(ReaderStyle.accent)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(ReaderStyle.accent.opacity(0.12), in: .rect(cornerRadius: 8))
        .transition(.scale(0.9).combined(with: .opacity))
} else { /* botão Traduzir/Continuar */ }
```

### 4. "Mostrar no PDF" sequestra o modo de leitura
`App.swift:142-145` faz `mode = .original` globalmente. Quem estava lendo lado a lado perde o contexto e precisa achar o segmented control para voltar. Duas opções, em ordem de preferência:
- **Peek:** abrir o `PDFPane` num `.popover` ou `.sheet` ancorado no parágrafo (uns 520×640), com a marcação já posicionada. O usuário fecha com Esc e continua onde estava.
- **Breadcrumb:** se mantiver a troca de modo, mostre um chip flutuante "← Voltar à leitura" (`.safeAreaInset(edge: .bottom)`) que restaura o modo e o parágrafo anteriores.

---

## P1 — Melhorar (atrito real)

### 5. A toolbar está carregada: 9 controles só com ícone
À direita: `‹ › A A ⇪ 📁 ✦`. Os dois "A" são ambíguos e ficam desabilitados em silêncio no modo PDF.
- Agrupe o tamanho do texto num **popover "Aa"**, como no Books e no Safari Reader: tamanho, entrelinha e serif/sans. Isso libera dois slots.
- Torne o botão do assistente um `Toggle` (`.toggleStyle(.button)`) para mostrar visualmente se o painel está aberto.
- Mova "Abrir PDF" para o menu **Arquivo** (`CommandGroup(replacing: .newItem)`). Na toolbar, ele compete com Exportar.

> **Ref. Aceternity *Floating Dock* / Kokonut *toolbar*:** a ideia boa é agrupar e expandir sob demanda, não a animação de magnificação, que no Mac fica estranha fora do Dock.

### 6. Leitura paginada quebra o fluxo
`BilingualPage` mostra uma página por vez, e a única forma de avançar é ir até o "Próxima página" no fim. Para relatórios longos (37 págs.), prefira **rolagem contínua com cabeçalho fixo**:
```swift
LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
    ForEach(model.document.pages, id: \.self) { page in
        Section { /* parágrafos da página */ } header: { PageHeader(page) .background(.bar) }
    }
}
// sincronize model.selectedPage com onScrollTargetVisibilityChange / scrollPosition(id:)
```
Se preferir manter a paginação, adicione pelo menos ←/→ e Espaço/Shift-Espaço para trocar de página.

### 7. A sidebar não tem busca
Em um PDF de 37 páginas, achar "garantia" exige o assistente. Use `.searchable(text:placement: .sidebar)` filtrando páginas e parágrafos (original + tradução), e destaque o termo no texto.

### 8. Nomes longos de arquivo são cortados no fim
Na tela inicial, `A_Review_of_Vision-Based_Pothole_Detection_Meth...` perde a parte mais útil. Use `.truncationMode(.middle)` em `RecentRow` e no título da sidebar. Considere também limpar `_` → espaço só na exibição.

### 9. A escolha de modelo do assistente está escondida
O `Picker("Modelo")` fica dentro de um menu `⋯`. Coloque um **chip do modelo dentro do composer** (`llama3.2:3b ▾`), como fazem os inputs de IA modernos (**ref. Kokonut *AI Input***). E, depois da primeira resposta, mostre 2 ou 3 **sugestões de continuação** acima do composer, não só no estado vazio.

### 10. Citações `[1]` são pequenas demais para clicar
No texto da resposta, `[1]` é um link de 1 caractere de largura. No `AnswerFormatter`, renderize a citação como **pílula** (fundo `accent.opacity(0.16)`, padding horizontal com espaço fino) para aumentar a área de clique e combinar com o badge numerado do `SourceRow`.

### 11. O erro é genérico
`App.swift:73`: "Não foi possível concluir" e um OK. Diga **o que** falhou e **o que fazer**: "Este PDF é escaneado e não tem texto selecionável. Use um PDF com texto ou passe-o por OCR antes."

---

## P2 — Aparência (onde as referências entram)

Cada item diz a origem web e a tradução SwiftUI. Todos devem respeitar `accessibilityReduceMotion`.

### A. A tradução "chegando" — React Bits *Blur Text* + Skiper/Unlumen *skeleton shimmer*
Hoje o parágrafo pendente mostra o original `.redacted` com 22% de opacidade (`ReaderViews.swift:608`), uma barra cinza parada. Proposta: um **shimmer** sutil enquanto `active` e a tradução entrando com **blur → nítido**.
```swift
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                    .scaleEffect(x: 0.4).offset(x: x * 400).blendMode(.plusLighter)
                    .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { x = 1 } }
            }
        }.mask(content)
    }
}

extension AnyTransition {
    static var blurIn: AnyTransition {
        .modifier(active: BlurFade(r: 8, o: 0), identity: BlurFade(r: 0, o: 1))
    }
}
private struct BlurFade: ViewModifier { let r: CGFloat; let o: Double
    func body(content: Content) -> some View { content.blur(radius: r).opacity(o) } }
// no ParagraphRow:  text(paragraph.translated).transition(.blurIn)  + .animation(.easeOut(duration: 0.45), value: pending)
```

### B. Números vivos — React Bits *Count Up*
Progresso (`22 de 22`, `100%`) e contadores do `PageRow` mudam com salto seco. Nativo e de graça:
```swift
Text("\(Int(progress * 100))%").monospacedDigit().contentTransition(.numericText(value: progress))
// e envolva a mutação em withAnimation(.snappy)
```

### C. Pulso ao chegar numa fonte — Aceternity *highlight*
Ao clicar numa fonte, o parágrafo recebe `accent.opacity(0.14)`, que no escuro fica cinza (na captura, os três blocos parecem só "cards cinza"). Faça um **pulso único** e depois assente num tom mais quente:
```swift
.background {
    RoundedRectangle(cornerRadius: 10).fill(ReaderStyle.accent.opacity(highlighted ? 0.18 : 0))
        .phaseAnimator([0, 1], trigger: model.revealToken) { v, phase in
            v.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ReaderStyle.accent.opacity(phase == 1 ? 0.0 : 0.6), lineWidth: 2))
        } animation: { _ in .easeOut(duration: 0.9) }
}
```
Adicione também uma **barra lateral de 3pt** em `accent` à esquerda do parágrafo destacado. Ela é visível mesmo para quem tem dificuldade com contraste de cor de fundo.

### D. Cards com spotlight no hover — Aceternity *Card Spotlight* / React Bits *Spotlight Card*
Só para **cards pequenos e clicáveis** (`RecentRow`, `SourceRow`, sugestões do assistente), nunca para o texto lido:
```swift
struct Spotlight: ViewModifier {
    @State private var p: CGPoint?
    func body(content: Content) -> some View {
        content
            .background {
                if let p {
                    RadialGradient(colors: [ReaderStyle.accent.opacity(0.16), .clear], center: .init(x: p.x, y: p.y),
                                   startRadius: 0, endRadius: 180)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                if case .active(let pt) = phase { p = pt } else { p = nil }
            }
    }
}
```
Atenção: `RadialGradient(center:)` usa `UnitPoint`, então normalize `pt` pela largura e altura via `onGeometryChange`.

### E. Tela inicial com profundidade — React Bits *Aurora/Silk*, Aceternity *Spotlight*, Behance (hero de apps editoriais)
A tela inicial é um fundo cinza chapado com muito espaço vazio. Ali **não há texto para ler**, então dá para ter atmosfera:
```swift
@available(macOS 15, *)
struct AuroraBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: reduceMotion)) { t in
            let s = Float(sin(t.date.timeIntervalSinceReferenceDate * 0.15)) * 0.15
            MeshGradient(width: 3, height: 3, points: [
                [0,0],[0.5,0],[1,0],
                [0,0.5],[0.5 + s, 0.5 - s],[1,0.5],
                [0,1],[0.5,1],[1,1]
            ], colors: [
                .clear, ReaderStyle.accent.opacity(0.10), .clear,
                .clear, ReaderStyle.accent.opacity(0.22), .clear,
                .clear, .clear, .clear
            ])
        }
        .blur(radius: 60).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
// EmptyReader(...).background { ZStack { ReaderBackdrop(); AuroraBackdrop() } }
```
Some apenas com *Reduce Transparency*, e pause com *Reduce Motion*, como o `ReaderBackdrop` já faz.

### F. Entrada da tela inicial — Aceternity *Text Generate Effect*
Uma entrada **escalonada** (logo → título → subtítulo → CTA → recentes), ~60ms entre itens, `y: 8 → 0` e opacidade. Use um `@State var appeared` e `.animation(.smooth.delay(Double(i) * 0.06), value: appeared)`. Rode só uma vez por abertura, nunca em loop.

### G. Zona de soltar visível — Kokonut / Aceternity *File Upload*
"ou arraste um PDF para esta janela" é texto de 11pt fácil de perder. Transforme o CTA numa **drop zone** (card tracejado de ~460×140, com o botão dentro) que reage ao `dropTarget` com escala 1.02 e borda em `accent`. O overlay que hoje cobre a janela inteira pode ficar como reforço.

### H. Status do assistente "pensando" — React Bits *Shiny Text* / Kokonut *AI Loading*
"Procurando no documento…" e "Lendo o documento · parte 2 de 5" podem usar o mesmo `Shimmer` do item A aplicado ao texto (gradiente varrendo as letras), em vez de `ProgressView` + texto cinza. Fica claro que é trabalho em andamento sem um spinner a mais.

### I. Composer do assistente — Kokonut *AI Input* / Aceternity *Placeholders and Vanish Input*
- Placeholder **rotativo** com perguntas reais ("Qual o prazo de devolução?", "Resuma a página 3…"), trocando a cada ~4s com `.contentTransition(.opacity)`. Pare a rotação com *Reduce Motion* ou se o campo tiver foco.
- No macOS 26, aplique `.glassEffect(.regular, in: .rect(cornerRadius: 14))` ao composer, com o fallback atual quando `reduceTransparency`. Isso completa a linguagem Liquid Glass já usada nos botões.

### J. Modo escuro achatado
`ReaderStyle.paper = textBackgroundColor` vira quase preto, e os cards destacados ficam cinza sobre cinza. Sugestões:
- Um **papel quente** próprio no escuro (≈ `#1C1D1B`, com um leve verde) e no claro (≈ `#FBFAF7`). Hoje o claro é branco puro, que cansa em sessões longas.
- O original a 72% de opacidade funciona. No modo **stacked**, diferencie mais: original em `.callout` sans e tradução em serif no tamanho cheio.
- Teste o contraste do verde `0.55/0.76/0.65` sobre o novo papel em texto pequeno, como `PORTUGUÊS` em 10pt. Fica perto do limite AA.

---

## O que NÃO trazer das referências

| Efeito web | Por que não |
|---|---|
| Partículas, beams e meteors atrás do texto | Competem com a leitura e gastam bateria num app de uso longo |
| Cursor customizado / *magnet buttons* | Quebram a expectativa do Mac; o cursor é do sistema |
| *Click spark* / confetti | Infantiliza um app de documentos; se quiser celebrar o fim da tradução, use só o selo do item 3 com `.symbolEffect(.bounce)` |
| Floating Dock com magnificação | Já existe um Dock no Mac; agrupe sem animar |
| Gradientes neon / glassmorphism pesado | O app já tem o Liquid Glass nativo; vidro falso por cima fica com cara de web |

---

## Plano sugerido

1. **Rápido, cerca de meio dia:** itens 1, 2, 3, 8, B e o selo de concluído. Baixo risco e ganho imediato.
2. **Navegação, 1–2 dias:** itens 4 (peek do PDF), 5 (toolbar e popover Aa) e 7 (busca).
3. **Polimento, 1–2 dias:** A (blur-in + shimmer), C (pulso), E/F/G (tela inicial) e I (composer).
4. **Estrutural, opcional:** item 6 (rolagem contínua). Muda o modelo de seleção de página e precisa de testes.

Cada etapa deve ser validada em claro e escuro e com *Reduce Motion*, *Reduce Transparency* e *Increase Contrast* ligados, além do VoiceOver nas ações do parágrafo.
