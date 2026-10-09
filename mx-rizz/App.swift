import SwiftUI
import UIKit
import FoundationModels

@main
struct MXRizzAIApp: App {
    var body: some Scene {
        WindowGroup { RizzHome().preferredColorScheme(.dark) }
    }
}

struct RizzHome: View {
    @State private var message = ""
    @State private var mode = "Reply"
    @State private var tone = "Charming"
    @State private var output = [String]()
    @State private var busy = false
    @State private var status = ""
    private let purple = Color(red: 0.65, green: 0.34, blue: 0.98)
    private let bg = Color(red: 0.06, green: 0.05, blue: 0.10)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: "heart.text.square.fill").foregroundStyle(.pink)
                        Text("MX RIZZ").font(.title2.bold())
                        Text("AI").foregroundStyle(purple)
                        Spacer()
                        Image(systemName: "circle.fill")
                            .foregroundStyle(SystemLanguageModel.default.isAvailable ? .green : .orange)
                            .font(.caption2)
                        Text("LOCAL").font(.caption2)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Better chats.\nYour own voice.")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Private AI on your iPhone. No tokens, account or subscription.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(LinearGradient(colors: [Color(red: 0.25, green: 0.12, blue: 0.34), bg], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    Picker("Mode", selection: $mode) {
                        Text("Reply").tag("Reply")
                        Text("Polish").tag("Polish")
                    }.pickerStyle(.segmented)
                    HStack {
                        Text(mode == "Reply" ? "Paste her message" : "Write your draft").font(.headline)
                        Spacer()
                        Button("Paste") { message = UIPasteboard.general.string ?? message }.tint(purple)
                    }
                    TextEditor(text: $message)
                        .frame(height: 145)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    Text("Your vibe").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(["Charming","Flirty","Romantic","Funny","Gentleman"],id:\.self) { item in
                                Button(item) { tone = item }
                                    .padding(.horizontal,14).padding(.vertical,10)
                                    .background(tone == item ? purple : Color.white.opacity(0.10))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(busy ? "Generating on iPhone..." : "Generate 3 replies")
                        }
                        .frame(maxWidth: .infinity).padding(16)
                        .background(purple)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                    .disabled(busy || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
                    ForEach(output, id:\.self) { suggestion in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(suggestion).textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = suggestion
                                status = "Copied. Open your chat and paste."
                            } label: {
                                Label("Copy reply", systemImage: "doc.on.doc")
                            }.tint(purple)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Divider()
                    Text("Enable MX Rizz Keyboard: Settings → General → Keyboard → Keyboards → Add New Keyboard.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Replies are suggestions. You always choose what to send.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(20)
            }
        }
    }
    @MainActor
    private func generate() async {
        guard SystemLanguageModel.default.isAvailable else {
            status = "Apple Intelligence model is unavailable right now. Check Settings."
            return
        }
        busy = true
        defer { busy = false }
        status = ""
        output = []
        let input = String(message.prefix(1200))
        let instruction = "You help with dating conversations. Write natural, warm, respectful, confident messages. Style: \(tone). Never invent facts or promises. Give exactly 3 different concise replies, each on a separate numbered line, with no introduction."
        let prompt = mode == "Reply" ? "Suggest my response to this incoming message:\n\(input)" : "Improve my own draft without changing its intended meaning:\n\(input)"
        do {
            let session = LanguageModelSession(instructions: instruction)
            let response = try await session.respond(to: prompt)
            let lines = response.content.components(separatedBy: .newlines)
                .map { $0.replacingOccurrences(of: #"^\s*\d+[.)]\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            output = Array(lines.prefix(3))
            if output.isEmpty { status = "No reply generated. Try a different message." }
        } catch {
            status = error.localizedDescription
        }
    }
}
