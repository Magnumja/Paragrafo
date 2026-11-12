import Foundation
import Translation

let model = ReaderModel()
model.document = DocumentState([Paragraph(page: 1, original: "The document explains how to translate each paragraph.")])
model.detectedSource = "en"
model.startTranslation()
let initial = model.configuration!
model.phase = .idle // Completed callback, no live system session in this state test.
model.source = "en"
model.changeTarget()
model.startTranslation()
let retried = model.configuration!
precondition(retried.source == initial.source && retried.target == initial.target)
precondition(retried.version > initial.version, "Same language pair must invalidate the previous session on retry")
print("PASS: nova tentativa com o mesmo par invalida a sessão anterior")
model.stop()
precondition(!model.busy, "Stopping before callback must leave preparing state")
print("PASS: pausa antes do início da sessão libera a interface")
