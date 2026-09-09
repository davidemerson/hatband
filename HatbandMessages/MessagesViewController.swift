import HatbandCore
import Messages
import SwiftUI
import UIKit

/// Hatband in the Messages `+` menu. It offers the cards the app signed and
/// left in the App Group, and hands a received one back to the app.
///
/// It signs nothing: the seed belongs to the app, and a second process able
/// to read it would be a far larger key than this feature is worth.
@MainActor final class MessagesViewController: MSMessagesAppViewController {
    private var host: UIHostingController<CardPickerView>?

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        present(ShareFeed.read()?.cards ?? [])
    }

    /// A recipient who also has Hatband taps the bubble and lands here rather
    /// than in a browser. Hand the card to the app, which shows the review
    /// sheet a scan or a tapped link would: one way to receive a card,
    /// however it arrived.
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        guard let card = message.url else { return }
        extensionContext?.open(card, completionHandler: nil)
    }

    private func present(_ cards: [ShareFeed.Card]) {
        let view = CardPickerView(cards: cards) { [weak self] card in
            self?.send(card)
        }
        if let host {
            host.rootView = view
            return
        }
        let controller = UIHostingController(rootView: view)
        addChild(controller)
        controller.view.frame = self.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(controller.view)
        controller.didMove(toParent: self)
        host = controller
    }

    /// The whole card when a message will carry it, else the one without the
    /// photo. Apple does not document the limit, only that passing it fails,
    /// so the length is a guess and the error is not: a refusal retries.
    private func send(_ card: ShareFeed.Card) {
        guard let conversation = activeConversation else { return }
        insert(card, url: card.sendable(), into: conversation) { [weak self] failed in
            guard failed, card.sendable() != card.fullQRURL else { return }
            self?.insert(card, url: card.fullQRURL, into: conversation) { _ in }
        }
    }

    private func insert(_ card: ShareFeed.Card, url: String, into conversation: MSConversation,
                        then finished: @escaping @MainActor (Bool) -> Void) {
        guard let link = URL(string: url) else {
            finished(false)
            return
        }
        let message = MSMessage()
        message.url = link
        message.layout = MessagesViewController.layout(for: card, url: url)
        conversation.insert(message) { error in
            let tooBig = (error as? NSError)?.code == MSMessageErrorCode.urlExceedsMaxSize.rawValue
            Task { @MainActor in finished(tooBig) }
        }
    }

    /// Caption, company and the code itself. The image is left off rather
    /// than shown wrong when the card is too big to draw as a QR — a card
    /// carrying a photo is past what any symbol holds.
    nonisolated static func layout(for card: ShareFeed.Card, url: String) -> MSMessageTemplateLayout {
        let layout = MSMessageTemplateLayout()
        layout.caption = card.name ?? card.label
        layout.subcaption = card.company
        layout.trailingCaption = "Hatband"
        if let code = CardQR.code(for: url, form: .fullQR),
           let image = BrandedQRImage.cgImage(code, pixelsPerModule: 8) {
            layout.image = UIImage(cgImage: image)
        }
        return layout
    }
}
