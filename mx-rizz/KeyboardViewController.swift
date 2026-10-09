import UIKit
import FoundationModels

final class KeyboardViewController: UIInputViewController {
    private let purple = UIColor(red: 0.62, green: 0.35, blue: 0.93, alpha: 1)
    private let dark = UIColor(red: 0.09, green: 0.08, blue: 0.13, alpha: 1)
    private let light = UIColor(red: 0.22, green: 0.20, blue: 0.28, alpha: 1)
    private let status = UILabel()
    private let suggestion = UILabel()
    private var proposal: String?
    private var processing = false
    override func viewDidLoad() {
        super.viewDidLoad()
        render()
    }
    private func render() {
        view.backgroundColor = dark
        let height = view.heightAnchor.constraint(equalToConstant: 335)
        height.priority = .defaultHigh
        height.isActive = true
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -5)
        ])
        let header = UIStackView()
        header.axis = .horizontal
        let title = UILabel()
        title.text = "♥  MX RIZZ AI"
        title.textColor = .white
        title.font = .systemFont(ofSize: 14, weight: .bold)
        header.addArrangedSubview(title)
        status.text = "LOCAL AI"
        status.textColor = UIColor.systemGray2
        status.textAlignment = .right
        status.font = .systemFont(ofSize: 10)
        header.addArrangedSubview(status)
        stack.addArrangedSubview(header)
        header.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let actions = UIStackView()
        actions.axis = .horizontal
        actions.spacing = 5
        actions.distribution = .fillEqually
        for (title, tag) in [("✨ Polish", 1),("😏 Flirty",2),("😂 Funny",3)] {
            let b = key(title)
            b.tag = tag
            b.addTarget(self, action: #selector(improve(_:)), for: .touchUpInside)
            actions.addArrangedSubview(b)
        }
        stack.addArrangedSubview(actions)
        actions.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let result = UIStackView()
        result.axis = .horizontal
        result.spacing = 5
        suggestion.text = "Type a message, then choose a style."
        suggestion.textColor = .white
        suggestion.numberOfLines = 3
        suggestion.font = .systemFont(ofSize: 12)
        suggestion.backgroundColor = UIColor(red: 0.18, green: 0.14, blue: 0.24, alpha: 1)
        suggestion.layer.cornerRadius = 8
        suggestion.layer.masksToBounds = true
        result.addArrangedSubview(suggestion)
        let use = key("Use ↗")
        use.backgroundColor = purple
        use.widthAnchor.constraint(equalToConstant: 68).isActive = true
        use.addTarget(self, action: #selector(insertSuggestion), for: .touchUpInside)
        result.addArrangedSubview(use)
        stack.addArrangedSubview(result)
        result.heightAnchor.constraint(equalToConstant: 60).isActive = true

        for line in ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"] {
            let keys = line.map { String($0) }
            stack.addArrangedSubview(row(keys))
        }
        stack.addArrangedSubview(row(["🌐", ",", "space", ".", "⌫", "↵"]))
    }
    private func key(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        b.backgroundColor = light
        b.layer.cornerRadius = 6
        return b
    }
    private func row(_ keys: [String]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.distribution = .fillEqually
        for letter in keys {
            let b = key(letter == "space" ? "SPACE" : letter)
            b.accessibilityIdentifier = letter
            b.addTarget(self, action: #selector(press(_:)), for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        row.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return row
    }
    @objc private func press(_ b: UIButton) {
        guard let value = b.accessibilityIdentifier else { return }
        switch value {
        case "🌐": advanceToNextInputMode()
        case "⌫": textDocumentProxy.deleteBackward()
        case "↵": textDocumentProxy.insertText("\n")
        case "space": textDocumentProxy.insertText(" ")
        default: textDocumentProxy.insertText(value.lowercased())
        }
    }
    @objc private func improve(_ b: UIButton) {
        guard !processing else { return }
        let existing = (textDocumentProxy.documentContextBeforeInput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existing.isEmpty else {
            suggestion.text = "Type your draft before using AI."
            return
        }
        guard SystemLanguageModel.default.isAvailable else {
            suggestion.text = "Local Apple model not ready. Try main MX Rizz app."
            return
        }
        processing = true
        status.text = "THINKING..."
        suggestion.text = "Generating privately on iPhone..."
        proposal = nil
        let vibe = b.tag == 2 ? "playful and flirty" : b.tag == 3 ? "lighthearted and funny" : "natural and charming"
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.processing = false
                self.status.text = "LOCAL AI"
            }
            do {
                let session = LanguageModelSession(instructions: "Polish this user's own draft message, preserving meaning while making it \(vibe). Reply with only one concise message, no quotation marks or explanation.")
                let response = try await session.respond(to: existing)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    self.suggestion.text = "No suggestion returned."
                } else {
                    self.proposal = text
                    self.suggestion.text = text
                }
            } catch {
                self.suggestion.text = error.localizedDescription
            }
        }
    }
    @objc private func insertSuggestion() {
        guard let text = proposal else { return }
        textDocumentProxy.insertText(" " + text)
        proposal = nil
        suggestion.text = "Inserted. Review before sending."
    }
}
