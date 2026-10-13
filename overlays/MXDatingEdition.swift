import SwiftUI
import MapKit
import UIKit
import Translation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MX Dating Edition: deliberately only two top-level destinations.
// MapKit, the real location engine, and pairing remain part of the host app.
// One map-first destination. The category chips are real navigation controls;
// location spoofing remains in the existing map's lower control bar.
struct MXDatingExploreHome: View {
    @EnvironmentObject private var navigation: MXPremiumNavigation
    @AppStorage("mxDatingAdultAccessConfirmed") private var adultConfirmed = false
    @State private var showAdultConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                MapHomeView()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MXPremiumCategory.allCases) { category in
                            Button {
                                if category == .adultVenues && !adultConfirmed {
                                    showAdultConfirmation = true
                                } else {
                                    open(category)
                                }
                            } label: {
                                Label(category.shortTitle, systemImage: category.symbol)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .frame(height: 37)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().stroke(category.tint.opacity(0.48)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mxCategory_\(category.rawValue)")
                        }
                    }
                    .padding(.horizontal, 14)
                }
                // Stays beneath the map search without covering the map itself.
                .padding(.top, 74)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $navigation.openCategory) {
                MXPremiumCategoryScreen(category: navigation.category)
            }
            .alert("Adults 18+ only", isPresented: $showAdultConfirmation) {
                Button("I am 18 or older") {
                    adultConfirmed = true
                    open(.adultVenues)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Adult nightlife and sex-positive venue discovery is intended for adults only. Listings come from map search and must be verified with venues.")
            }
        }
    }

    private func open(_ category: MXPremiumCategory) {
        navigation.category = category
        navigation.openCategory = true
    }
}

enum MXWingmanTone: String, CaseIterable, Identifiable {
    case gentleman = "Gentleman"
    case playful = "Playful"
    case flirty = "Flirty"
    case bold = "Bold"
    case spicy = "Spicy 18+"
    var id: String { rawValue }
}

enum MXWingmanGoal: String, CaseIterable, Identifiable {
    case first = "First Impression"
    case chemistry = "Build Chemistry"
    case meaningful = "Deeper Conversation"
    case date = "Ask for a Date"
    case reconnect = "Reconnect"
    case boundaries = "Boundaries"
    case afterDark = "Confident 18+"
    var id: String { rawValue }
}
enum MXWingmanLength: String, CaseIterable, Identifiable {
    case concise = "Short"
    case natural = "Natural"
    case expanded = "Detailed"
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
    @EnvironmentObject private var navigation: MXPremiumNavigation
    @AppStorage("mxWingmanDraft") private var incoming = ""
    @AppStorage("mxWingmanSavedReplies") private var savedReplies = ""
    @FocusState private var inputFocused: Bool
    @FocusState private var translationFocused: Bool
    @State private var tone: MXWingmanTone = .gentleman
    @State private var goal: MXWingmanGoal = .chemistry
    @State private var length: MXWingmanLength = .natural
    @AppStorage("mxWingmanConversationContext") private var chatContext = ""
    @State private var copiedIndex: Int?
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
                                .focused($inputFocused)
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
                            .pickerStyle(.menu)
                            HStack(spacing: 10) {
                                Picker("Goal", selection: $goal) {
                                    ForEach(MXWingmanGoal.allCases) { item in
                                        Text(item.rawValue).tag(item)
                                    }
                                }.pickerStyle(.menu)
                                Picker("Length", selection: $length) {
                                    ForEach(MXWingmanLength.allCases) { item in
                                        Text(item.rawValue).tag(item)
                                    }
                                }.pickerStyle(.menu)
                            }
                            TextField("Context: where you met, interests, vibe (optional)",
                                      text: $chatContext, axis: .vertical)
                                .lineLimit(1...3)
                                .font(.subheadline)
                                .padding(10)
                                .background(MXPremiumStyle.background,
                                            in: RoundedRectangle(cornerRadius: 12))
                            Button {
                                inputFocused = false
                                translationFocused = false
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
                                            copiedIndex = index
                                        } label: {
                                            Label(copiedIndex == index ? "Copied" : "Copy", systemImage: "doc.on.doc")
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
                                .focused($translationFocused)
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
            .scrollDismissesKeyboard(.interactively)
            .background(MXPremiumStyle.background)
            .navigationTitle("Wingman")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        inputFocused = false
                        translationFocused = false
                        navigation.tab = 0
                    } label: {
                        Label("Explore", systemImage: "chevron.left")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        inputFocused = false
                        translationFocused = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .onDisappear {
                inputFocused = false
                translationFocused = false
            }
            .onAppear {
                if let data = savedReplies.data(using: .utf8),
                   let restored = try? JSONDecoder().decode([String].self, from: data) {
                    replies = restored
                }
            }
            .onChange(of: replies) { _, value in
                if let data = try? JSONEncoder().encode(value),
                   let text = String(data: data, encoding: .utf8) {
                    savedReplies = text
                }
            }
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
                    Create authentic, specific, natural messages based on the chat and user goals. Respect consent and boundaries; use confident flirting only where mutual interest is plausible. Never pressure anyone. Adapt tone and reply length.
                    Never fabricate knowledge about another person's emotions or imply certainty.
                    Answer in English. Use exactly 5 lines, each beginning with its label:
                    ONE|reply text
                    TWO|reply text
                    THREE|reply text
                    WHY|short explanation
                    NEXT|one specific next step
                    Do not add any other lines, angle brackets, tags, or markdown fences.
                    A spicy tone may be daring but must remain between consenting adults.
                    """
                let prompt = """
                    Conversation to respond to:
                    \(message)
                    Preferred style: \(tone.rawValue).\n                     Conversation goal: \(goal.rawValue).\n                     Response length: \(length.rawValue).\n                     Optional user context: \(String(chatContext.prefix(420))).
                    Suggest 3 distinct, usable messages: one warm, one playful or flirty, and one more direct. Reference meaningful concrete details when provided. Adult flirting should be bold, consensual, and non-explicit.
                    """
                let session = LanguageModelSession(instructions: instructions)
                let result = try await session.respond(to: prompt)
                let lines = result.content.components(separatedBy: .newlines)
                func extract(_ key: String) -> String? {
                    guard let line = lines.first(where: { $0.hasPrefix(key + "|") }) else { return nil }
                    var value = String(line.dropFirst(key.count + 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // Foundation Models may copy <placeholder> delimiters literally.
                    while value.count > 2 && value.hasPrefix("<") && value.hasSuffix(">") {
                        value = String(value.dropFirst().dropLast())
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if value.count > 2 && value.hasPrefix("`") && value.hasSuffix("`") {
                        value = String(value.dropFirst().dropLast())
                    }
                    return value
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

        switch goal {
        case .first:
            replies = [
                "Hey! What is something you are genuinely excited about lately?",
                "I had to say hello 😄 Are you more into spontaneous adventures or quiet conversations?",
                "Hi! What would your perfect free evening look like?"
            ]
            why = "Make your first message specific and easy to answer rather than using generic praise."
        case .meaningful:
            replies = [
                "What matters most to you when you're getting to know someone?",
                "I like deeper conversations. What's something that changed your perspective on life?",
                "What makes you feel really understood by someone?"
            ]
            why = "Invite depth without assuming the other person wants an intense conversation."
        case .date:
            replies = [
                "I've enjoyed talking with you. Would you like to grab coffee this weekend?",
                "This has been fun! Want to continue our conversation over dinner?",
                "I'd like to meet you somewhere nice. Are you free for a relaxed date soon?"
            ]
            why = "A clear invitation with an easy way to decline respects both people's time."
            nextStep = "Offer a public place and a specific time only if she is interested."
        case .reconnect:
            replies = [
                "Hey, I was thinking of our conversation. How have you been?",
                "Hi! It's been a little while 😊 How is your week going?",
                "I enjoyed our last chat and thought I'd say hello again."
            ]
            why = "Reconnect without guilt or pressure."
        case .boundaries:
            replies = [
                "I value honesty and comfort for both of us. Can we talk about what we're looking for?",
                "I appreciate the conversation. I prefer moving at a pace we're both comfortable with.",
                "I'd rather be clear about my expectations than leave either of us guessing."
            ]
            why = "Boundaries are strongest when they are kind and direct."
        case .afterDark:
            replies = [
                "I like the chemistry here. You're making it hard not to flirt a little 😉",
                "I'm all for chemistry with a touch of mischief. Are we on the same page?",
                "There's definitely a spark in this conversation. Want to see if it's there in person?"
            ]
            why = "Adult flirtation can be confident and suggestive without presuming consent."
            nextStep = "Match her level of interest; ease off if she isn't reciprocating."
        case .chemistry:
            break
        }
        if length == .concise {
            replies = replies.map { reply in
                let words = reply.split(separator: " ")
                return words.count > 21 ? words.prefix(21).joined(separator: " ") + "…" : reply
            }
        }
        if tone == .spicy {
            replies[1] = "You're making it difficult not to flirt with you 😉 Is that intentional?"
        } else if tone == .bold {
            replies[1] = "I like our chemistry. I'd love to take you on a proper date if you're up for it."
        } else if tone == .flirty {
            replies[1] = "You have an interesting way of telling stories 😉 I'd like to hear more."
        } else if tone == .playful {
            replies[1] = "Okay, now you've got my curiosity working overtime 😄 Tell me more!"
        }
        if modelStatus.isEmpty || !modelStatus.contains("unavailable") {
            modelStatus = "Offline quick suggestions · Apple Intelligence not ready."
        }
    }
}
