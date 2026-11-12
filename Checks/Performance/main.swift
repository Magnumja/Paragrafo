import Foundation

let paragraphs = (0..<10000).map { Paragraph(page: $0 / 40 + 1, original: "Parágrafo \($0)", translated: $0 % 2 == 0 ? "Tradução" : "") }
let document = DocumentState(paragraphs)
let visibleIDs = Array(paragraphs.suffix(40).map(\.id))

@inline(never) func before(_ paragraphs: [Paragraph], _ visibleIDs: [UUID]) -> Int {
    var total = paragraphs.filter { !$0.translated.isEmpty }.count
    for id in visibleIDs { total += paragraphs.firstIndex(where: { $0.id == id })! + 1 }
    return total
}
@inline(never) func after(_ document: DocumentState, _ page: Int) -> Int {
    var total = document.completed
    for index in document.pageRanges[page] ?? 0..<0 { total += index + 1 }
    return total
}
var checksum = 0
for run in 1...5 {
    let startOld = Date()
    for _ in 0..<200 { checksum += before(paragraphs, visibleIDs) }
    let old = Date().timeIntervalSince(startOld) * 1000
    let startNew = Date()
    for _ in 0..<200 { checksum += after(document, 250) }
    let new = Date().timeIntervalSince(startNew) * 1000
    print(String(format: "run %d | before %.3f ms | after %.3f ms", run, old, new))
}
precondition(before(paragraphs, visibleIDs) == after(document, 250))
print("checksum \(checksum)")
