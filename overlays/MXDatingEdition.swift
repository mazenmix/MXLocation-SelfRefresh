import SwiftUI
import MapKit
import UIKit
import Translation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MX Dating Edition: deliberately only two top-level destinations.
// MapKit, the real location engine, and pairing remain part of the host app.
enum MXDatingArea: String, CaseIterable, Identifiable {
    case map = "Map"
    case radar = "Dating Radar"
    case location = "GPS Control"
    var id: String { rawValue }
}

struct MXDatingExploreHome: View {
    @EnvironmentObject private var navigation: MXPremiumNavigation
    @State private var area: MXDatingArea = .map

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "location.north.circle.fill")
                    .foregroundStyle(MXPremiumStyle.cyan)
                Text("MX LOCATION PRO").font(.subheadline.weight(.bold))
                Spacer()
                Text("DATING EDITION")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MXPremiumStyle.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            Picker("Explore mode", selection: $area) {
                ForEach(MXDatingArea.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Group {
                switch area {
                case .map:
                    MapHomeView()
                case .radar:
                    MXPremiumExploreScreen()
                case .location:
                    NavigationStack { MXPremiumLocationControl() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MXPremiumStyle.background)
        .onChange(of: navigation.openCategory) { _, open in
            if open { area = .radar }
        }
        .onChange(of: navigation.tab) { _, tab in
            if tab == 0 && navigation.openCategory { area = .radar }
        }
    }
}

enum MXWingmanTone: String, CaseIterable, Identifiable {
    case gentleman = "Gentleman"
    case playful = "Playful"
    case flirty = "Flirty"
    var id: String { rawValue }
}

enum MXWingmanLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case tagalog = "Tagalog"
    case indonesian = "Indonesian"
    case arabic = "Arabic"
    var id: String { rawValue }
    var code: String {
        switch self {
        case .english: return "en"
        case .tagalog: return "tl"
        case .indonesian: return "id"
        case .arabic: return "ar"
        }
    }
}

struct MXDatingWingmanScreen: View {
    @State private var incoming = ""
    @State private var tone: MXWingmanTone = .gentleman
    @State private var language: MXWingmanLanguage = .english
    @State private var replies: [String] = []
    @State private var why = ""
    @State private var nextStep = ""
    @State private var modelStatus = "Paste a message to begin"
    @State private var isAnalyzing = false
    @State private var translationInput = ""
    @State private var translated = ""
    @State private var translationStatus = ""
    @State private var translationConfig: TranslationSession.Configuration?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("MX WINGMAN", systemImage: "heart.text.square.fill")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(.white)
                        Text("Paste. Analyze. Copy. Your messages stay on this device.")
                            .font(.caption)
                            .foregroundStyle(MXPremiumStyle.muted)
                    }

                    MXPremiumPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Her message / conversation", systemImage: "bubble.left")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button {
                                    if let value = UIPasteboard.general.string {
                                        incoming = String(value.prefix(6000))
                                    }
                                } label: {
                                    Label("Paste", systemImage: "doc.on.clipboard")
                                        .font(.caption)
                                }
                            }
                            TextEditor(text: $incoming)
                                .frame(height: 138)
                                .padding(7)
                                .scrollContentBackground(.hidden)
                                .background(MXPremiumStyle.background,
                                            in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityIdentifier("mxWingmanInput")
                            HStack {
                                Text("\(incoming.count)/6000 characters")
                                    .font(.caption2)
                                    .foregroundStyle(MXPremiumStyle.muted)
                                Spacer()
                                Button("Clear") {
                                    incoming = ""
                                    replies = []
                                    why = ""
                                    nextStep = ""
                                    translated = ""
                                    translationInput = ""
                                }.font(.caption)
                            }
                        }
                    }

                    MXPremiumPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("REPLY STYLE")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MXPremiumStyle.muted)
                            Picker("Tone", selection: $tone) {
                                ForEach(MXWingmanTone.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            Button {
                                Task { await analyzeMessage() }
                            } label: {
                                HStack(spacing: 9) {
                                    if isAnalyzing { ProgressView().tint(.white) }
                                    else { Image(systemName: "sparkles") }
                                    Text(isAnalyzing ? "Analyzing…" : "Analyze & Suggest")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(13)
                                .foregroundStyle(.white)
                                .background(MXPremiumStyle.cyan,
                                            in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                            .disabled(incoming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
                            Text(modelStatus).font(.caption2)
                                .foregroundStyle(MXPremiumStyle.muted)
                        }
                    }

                    if !replies.isEmpty {
                        Text("SUGGESTED REPLIES")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MXPremiumStyle.muted)
                        ForEach(replies.indices, id: \.self) { index in
                            MXPremiumPanel {
                                VStack(alignment: .leading, spacing: 11) {
                                    HStack {
                                        Text("OPTION \(index + 1)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(MXPremiumStyle.cyan)
                                        Spacer()
                                        Button {
                                            UIPasteboard.general.string = replies[index]
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                                .font(.caption.weight(.semibold))
                                        }
                                    }
                                    Text(replies[index])
                                        .font(.subheadline)
                                        .textSelection(.enabled)
                                    Button {
                                        translationInput = replies[index]
                                        requestTranslation()
                                    } label: {
                                        Label("Translate this reply", systemImage: "character.bubble")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        MXPremiumPanel {
                            VStack(alignment: .leading, spacing: 9) {
                                Label("WHY THIS RESPONSE", systemImage: "lightbulb")
                                    .font(.caption.weight(.bold))
                                Text(why).font(.subheadline)
                                Label("NEXT BEST MOVE", systemImage: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                                    .padding(.top, 4)
                                Text(nextStep).font(.subheadline)
                            }
                        }
                    }

                    MXPremiumPanel {
                        VStack(alignment: .leading, spacing: 11) {
                            Label("DATING TRANSLATOR", systemImage: "character.bubble.fill")
                                .font(.headline)
                            Text("Paste English text or translate a suggested reply. Availability depends on downloaded Apple languages.")
                                .font(.caption)
                                .foregroundStyle(MXPremiumStyle.muted)
                            TextField("Text to translate", text: $translationInput, axis: .vertical)
                                .lineLimit(2...5)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Picker("Target", selection: $language) {
                                    ForEach(MXWingmanLanguage.allCases) { item in
                                        Text(item.rawValue).tag(item)
                                    }
                                }
                                .pickerStyle(.menu)
                                Spacer()
                                Button("Translate") { requestTranslation() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(translationInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            if !translated.isEmpty {
                                Text(translated).font(.subheadline)
                                    .textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = translated
                                } label: {
                                    Label("Copy translation", systemImage: "doc.on.doc")
                                }.font(.caption)
                            }
                            if !translationStatus.isEmpty {
                                Text(translationStatus)
                                    .font(.caption2)
                                    .foregroundStyle(MXPremiumStyle.muted)
                            }
                            Text("QUICK PHRASE · COFFEE INVITATION")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(MXPremiumStyle.muted)
                            let phrase = coffeePhrase
                            HStack {
                                Text(phrase).font(.caption)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = phrase
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }.accessibilityLabel("Copy quick phrase")
                            }
                        }
                    }
                    Text("Responses are suggestions, not measurements of another person's feelings. No messages are sent to dating apps automatically.")
                        .font(.caption2)
                        .foregroundStyle(MXPremiumStyle.muted)
                }
                .padding(15)
            }
            .background(MXPremiumStyle.background)
            .navigationTitle("Wingman")
            .navigationBarTitleDisplayMode(.inline)
            .translationTask(translationConfig) { session in
                do {
                    let result = try await session.translate(translationInput)
                    translated = result.targetText
                    translationStatus = "Translated by Apple Translation."
                } catch {
                    translated = ""
                    translationStatus = "This language pair may not be supported or downloaded: \(error.localizedDescription)"
                }
            }
        }
    }

    private var coffeePhrase: String {
        switch language {
        case .english: return "Would you like to grab coffee this week?"
        case .tagalog: return "Gusto mo bang magkape tayo ngayong linggo?"
        case .indonesian: return "Mau ngopi bareng minggu ini?"
        case .arabic: return "تحبين نطلع نشرب قهوة هالأسبوع؟"
        }
    }

    private func requestTranslation() {
        let input = translationInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if language == .english {
            translated = input
            translationStatus = "Original English text."
            return
        }
        translated = ""
        translationStatus = "Checking Apple Translation language availability…"
        if translationConfig == nil {
            translationConfig = .init(source: Locale.Language(identifier: "en"),
                                      target: Locale.Language(identifier: language.code))
        } else {
            translationConfig = .init(source: Locale.Language(identifier: "en"),
                                      target: Locale.Language(identifier: language.code))
            translationConfig?.invalidate()
        }
    }

    @MainActor
    private func analyzeMessage() async {
        let message = String(incoming.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6000))
        guard !message.isEmpty else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let instructions = """
                    You are an ethical, warm dating conversation coach.
                    Create authentic, concise, natural messages; respect consent and boundaries.
                    Never fabricate knowledge about another person's emotions or imply certainty.
                    Answer in English. Use exactly 5 lines, each beginning with its label:
                    ONE|<reply>
                    TWO|<reply>
                    THREE|<reply>
                    WHY|<short explanation>
                    NEXT|<one specific next step>
                    Do not add any other lines.
                    """
                let prompt = """
                    Conversation to respond to:
                    \(message)
                    Preferred style: \(tone.rawValue).
                    Suggest 3 distinct short messages for an authentic chat.
                    """
                let session = LanguageModelSession(instructions: instructions)
                let result = try await session.respond(to: prompt)
                let lines = result.content.components(separatedBy: .newlines)
                func extract(_ key: String) -> String? {
                    lines.first(where: { $0.hasPrefix(key + "|") })
                        .map { String($0.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces) }
                }
                if let a = extract("ONE"), let b = extract("TWO"), let c = extract("THREE"),
                   !a.isEmpty, !b.isEmpty, !c.isEmpty {
                    replies = [a, b, c]
                    why = extract("WHY") ?? "Shows interest and gives room for a genuine reply."
                    nextStep = extract("NEXT") ?? "Wait for a response before proposing a plan."
                    modelStatus = "Generated locally with Apple Intelligence."
                    return
                }
            } catch {
                modelStatus = "Local AI unavailable for this request; using quick suggestions."
            }
        }
        #endif
        let lower = message.lowercased()
        let tired = ["tired", "exhaust", "busy", "work", "stress"].contains { lower.contains($0) }
        let meeting = ["coffee", "meet", "date", "weekend", "tomorrow"].contains { lower.contains($0) }
        if tired {
            replies = [
                "That sounds like a full day. What usually helps you unwind? 😊",
                "You definitely deserve a relaxed evening after all that 😄",
                "I hope you get some downtime tonight. What's your favorite way to recharge?"
            ]
            why = "Acknowledge their day before changing the topic."
            nextStep = "Ask one easy follow-up, then give them space to reply."
        } else if meeting {
            replies = [
                "That sounds good! Would a relaxed coffee meet-up work for you?",
                "I like that idea 😄 What day tends to be easiest for you?",
                "Coffee and good conversation sounds like a great plan. No pressure, of course."
            ]
            why = "Offer a simple plan without putting pressure on the other person."
            nextStep = "If they show interest, suggest one specific public place and time."
        } else {
            replies = [
                "That sounds interesting! Tell me a little more 😊",
                "Now I'm curious 😄 What got you into that?",
                "I like hearing your perspective. What's your favorite part of it?"
            ]
            why = "Open-ended questions invite real conversation without pretending to know their feelings."
            nextStep = "Follow up on one detail from their reply instead of sending multiple messages."
        }
        if tone == .flirty {
            replies[1] = "You have an interesting way of telling stories 😉 I'd like to hear more."
        } else if tone == .playful {
            replies[1] = "Okay, now you've got my curiosity working overtime 😄 Tell me more!"
        }
        if modelStatus.isEmpty || !modelStatus.contains("unavailable") {
            modelStatus = "Offline quick suggestions · Apple Intelligence not ready."
        }
    }
}
