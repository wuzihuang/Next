import SwiftUI
import PhotosUI
import UIKit

struct ChatDetailView: View {
    let sessionID: String?
    let initialQuery: String?
    let initialAttachmentDataURL: String?

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var dataStore: DataStore
    @StateObject private var chatStore = ChatStore.shared
    @ObservedObject private var ai = ChatStore.shared.ai

    @State private var inputText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var attachedDataURL: String?
    @State private var showPhotoPicker: Bool = false
    @State private var showHistorySheet: Bool = false
    @State private var didOpenSession = false
    @FocusState private var isInputFocused: Bool
    var body: some View {
        // ⚠️ The scroll view is the root, not a middle row of a VStack: inside NavigationStack
        // a column only claims its content's height, which strands the dock under the header
        // with dead space beneath it. As insets, the bar and the dock hug the page's edges and
        // the message lane takes everything between them.
        messageScrollView
            .safeAreaInset(edge: .top, spacing: 0) {
                ChatTopBarView(
                    onBack: {
                        isInputFocused = false
                        AISession.shared.endChat()
                        router.back()
                    },
                    onHistory: {
                        isInputFocused = false
                        showHistorySheet = true
                    }
                )
                .modifier(ChatChromeBand(band: .header))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatBottomDockView(
                    inputText: $inputText,
                    isInputFocused: $isInputFocused,
                    attachedImage: $attachedImage,
                    canSend: canSend,
                    onPickPhoto: { showPhotoPicker = true },
                    onRemovePhoto: {
                        attachedImage = nil
                        attachedDataURL = nil
                        selectedPhotoItem = nil
                    },
                    onQuickPrompt: { prompt in
                        sendDirect(prompt)
                    },
                    onSubmit: {
                        submitMessage()
                    }
                )
                .modifier(ChatChromeBand(band: .dock))
            }
            .carbonPage()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .detailEdgeBack {
                isInputFocused = false
                AISession.shared.endChat()
                router.back()
            }
            .sheet(isPresented: $showHistorySheet) {
                ChatHistorySheet(
                    chatStore: chatStore,
                    onSelect: { id in
                        chatStore.selectSession(id)
                        showHistorySheet = false
                    },
                    onNewChat: {
                        chatStore.startNewSession()
                        showHistorySheet = false
                    },
                    onDismiss: {
                        showHistorySheet = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onDisappear { StreamHaptics.shared.deactivate() }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                handlePhotoSelection(item)
            }
            .task {
                guard !didOpenSession else { return }
                didOpenSession = true
                chatStore.prepareForCurrentAccount()
                if let sessionID {
                    chatStore.selectSession(sessionID)
                } else if chatStore.sessions.isEmpty {
                    chatStore.startNewSession()
                }
                if let initialQuery, !initialQuery.isEmpty {
                    await chatStore.send(text: initialQuery, dataURL: initialAttachmentDataURL, dataStore: dataStore)
                } else if chatStore.currentSession?.messages.isEmpty ?? true {
                    try? await Task.sleep(for: .milliseconds(350))
                    isInputFocused = true
                }
                #if DEBUG
                if let draft = ProcessInfo.processInfo.environment["NB_DEBUG_CHAT_DRAFT"] {
                    inputText = draft
                    isInputFocused = true
                }
                if ProcessInfo.processInfo.environment["NB_DEBUG_CHAT_HISTORY"] == "1" {
                    showHistorySheet = true
                }
                #if targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["NB_DEBUG_CHAT_PHOTO"] == "1" {
                    attachedImage = Self.debugPlateImage()
                    if inputText.isEmpty {
                        inputText = ProcessInfo.processInfo.environment["NB_DEBUG_CHAT_DRAFT"]
                            ?? "Is this enough protein"
                    }
                    isInputFocused = true
                }
                #endif
                #endif
            }
    }

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    if let error = chatStore.persistenceError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                            Button(L("Retry")) { chatStore.retryPersistence() }
                        }
                        .font(NBFont.ui(400, 13))
                        .foregroundStyle(NB.text2)
                    }
                    if let session = chatStore.currentSession {
                        ForEach(session.messages) { message in
                            if message.sender == .user {
                                UserBubbleView(message: message)
                                    .id(message.id.uuidString)
                                    .accessibilityIdentifier(latestMessageID == message.id ? "chat.latest-message" : "chat.message")
                            } else {
                                ChatAnswerView(message: message, onTap: { router.open($0) })
                                    .id(message.id.uuidString)
                                    .accessibilityIdentifier(latestMessageID == message.id ? "chat.latest-message" : "chat.message")
                            }
                        }
                    }

                    if chatStore.isSendingCurrentSession {
                        ThinkingStatusView(thoughts: ai.thoughts)
                            .id(ChatScrollTarget.thinking)
                    }

                    Color.clear
                        .frame(height: 4)
                        .id(ChatScrollTarget.bottom)
                }
                .padding(.horizontal, NB.Layout.gutter)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { isInputFocused = false }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10).onChanged { _ in
                    isInputFocused = false
                }
            )
            .task(id: chatStore.currentSessionID) {
                await jumpToLatest(proxy, animated: false)
            }
            .onChange(of: chatStore.currentSession?.messages.count) { _, _ in
                Task { await jumpToLatest(proxy, animated: true) }
            }
            .onChange(of: isInputFocused) { _, focused in
                guard focused else { return }
                Task { await jumpToLatest(proxy, animated: true) }
            }
            .onChange(of: ai.thoughts.last?.id) { _, _ in
                guard chatStore.isSendingCurrentSession else { return }
                withAnimation { proxy.scrollTo(ChatScrollTarget.thinking, anchor: .bottom) }
            }
            .onChange(of: chatStore.isSendingCurrentSession) { _, sending in
                if sending {
                    // Warm the haptic engine with the turn so the first character is not
                    // ahead of it, and tap once when the answer takes the floor.
                    StreamHaptics.shared.activate()
                    withAnimation { proxy.scrollTo(ChatScrollTarget.thinking, anchor: .bottom) }
                } else {
                    StreamHaptics.shared.deactivate()
                    StreamHaptics.shared.settled()
                    Task { await jumpToLatest(proxy, animated: true) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var latestMessageID: UUID? {
        chatStore.currentSession?.messages.last?.id
    }

    private var latestScrollID: String {
        ChatScrollTarget.id(
            lastMessageID: latestMessageID,
            isThinking: chatStore.isSendingCurrentSession
        )
    }

    @MainActor
    private func jumpToLatest(_ proxy: ScrollViewProxy, animated: Bool) async {
        let run = {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(latestScrollID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(latestScrollID, anchor: .bottom)
            }
        }
        // Layout is often still settling on first appear and when the keyboard lifts, so
        // the same landing is retried until the latest line is actually in view.
        for delay in [0, 50, 180, 400] as [UInt64] {
            if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
            run()
        }
    }

    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil) && !chatStore.isSending
    }

    private func submitMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        let img = attachedImage
        let dataURL = attachedDataURL

        inputText = ""
        attachedImage = nil
        attachedDataURL = nil
        selectedPhotoItem = nil
        isInputFocused = false

        Task {
            await chatStore.send(text: text, image: img, dataURL: dataURL, dataStore: dataStore)
        }
    }

    private func sendDirect(_ prompt: String) {
        Task {
            await chatStore.send(text: prompt, dataStore: dataStore)
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        Task {
            guard let item,
                  let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            let resized = image.nb_resized(maxSide: 1024)
            let jpeg = resized.jpegData(compressionQuality: 0.72) ?? data
            attachedImage = resized
            attachedDataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private static func debugPlateImage() -> UIImage {
        let size = CGSize(width: 240, height: 240)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.94, green: 0.64, blue: 0.11, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 28, y: 28, width: 184, height: 184))
            UIColor(red: 0.86, green: 0.35, blue: 0.12, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 70, y: 78, width: 100, height: 70))
        }
    }
    #endif
}

// MARK: - Top Bar · Cyber Telemetry
private struct ChatTopBarView: View {
    let onBack: () -> Void
    let onHistory: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onBack) {
                HStack(alignment: .center, spacing: 10) {
                    BackChevron(height: 15, line: 1.8)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L("AI COACH"))
                                .font(NBFont.dot(700, 13))
                                .tracking(0.06 * 13)
                                .foregroundStyle(NB.text1)
                            Circle()
                                .fill(NB.lime1)
                                .frame(width: 7, height: 7)
                        }
                        Text(L("ASK ANYTHING · YOUR AI COACH"))
                            .font(NBFont.dot(500, 10))
                            .tracking(0.04 * 10)
                            .foregroundStyle(NB.lime1)
                    }
                }
                .frame(minHeight: DetailBack.hitHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HotZoneTap(pressedOpacity: 1, pressedScale: 1))
            .accessibilityLabel(L("Back"))
            .accessibilityValue(L("AI COACH"))

            Spacer()

            Button(action: onHistory) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NB.lime1)
                    Text(L("HISTORY"))
                        .font(NBFont.dot(700, 11))
                        .tracking(0.04 * 11)
                        .foregroundStyle(NB.text1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(hex: 0x16161C), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(NB.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NB.Layout.gutter)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - User Message Bubble
private struct UserBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 8) {
                if let img = message.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !message.text.isEmpty {
                    ChatMarkdownView(
                        source: message.text,
                        family: .brand,
                        size: 14,
                        color: NB.text1,
                        accessibilityName: "chat.user-markdown",
                        expands: false
                    )
                    .multilineTextAlignment(.leading)
                }

                HStack(spacing: 4) {
                    Text(formatTime(message.at))
                        .font(NBFont.dot(400, 10))
                        .foregroundStyle(NB.text3Prod)
                    Text(L("· DELIVERED"))
                        .font(NBFont.dot(500, 10))
                        .foregroundStyle(NB.text3Prod)
                }
            }
            .padding(14)
            .background(Color(hex: 0x1C1C24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NB.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Query-selected answer
private struct ChatAnswerView: View {
    let message: ChatMessage
    let onTap: (Destination) -> Void

    var body: some View {
        Group {
            if let widget = message.widget, widget.type != .text {
                GeometryReader { geometry in
                    PanelWidgetView(widget: widget, onTap: onTap)
                        .frame(width: 358, height: 470)
                        .scaleEffect(geometry.size.width / 358, anchor: .topLeading)
                }
                .aspectRatio(358.0 / 470.0, contentMode: .fit)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !message.text.isEmpty {
                        ChatMarkdownView(
                            source: message.text,
                            family: .ui,
                            size: 15,
                            color: NB.text1,
                            accessibilityName: "chat.markdown"
                        )
                    }
                    if let detail = message.widget?.headline?.sub,
                       !detail.isEmpty, detail != message.text {
                        ChatMarkdownView(
                            source: detail,
                            family: .ui,
                            size: 14,
                            color: NB.text2,
                            accessibilityName: "chat.markdown.detail"
                        )
                    }
                }
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(hex: 0x111116), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Thinking View
private struct ThinkingStatusView: View {
    let thoughts: [AIService.Thought]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Characters a second, the panel's rate — the two surfaces print at the same pace.
    private static let typeRate = 46.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let now = tl.date
            card(now: now)
                // The same tick as the panel: one under the characters, one when a line lands.
                .onChange(of: typedCount(now: now)) { old, new in
                    if new > old { StreamHaptics.shared.type() }
                }
                .onChange(of: thoughts.last?.id) { _, _ in StreamHaptics.shared.lineLanded() }
        }
    }

    private func card(now: Date) -> some View {
        let rows = Array(thoughts.suffix(4))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(NB.lime1)
                    .frame(width: 7, height: 7)
                Text(L("THINKING..."))
                    .font(NBFont.dot(600, 11))
                    .tracking(0.04 * 11)
                    .foregroundStyle(NB.lime1)
            }

            ForEach(rows.indices, id: \.self) { i in
                // Only the newest line is still arriving; the ones above it are whole.
                let live = i == rows.count - 1
                let text = live ? String(rows[i].text.prefix(typedCount(now: now))) : rows[i].text
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(text)
                        .font(NBFont.ui(400, 13))
                        .foregroundStyle(NB.text2)
                    if live, !reduceMotion, typedCount(now: now) < rows[i].text.count {
                        Rectangle().fill(NB.lime1).frame(width: 5, height: 12)
                    }
                }
            }
        }
        .accessibilityIdentifier("chat.thinking")
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x111116), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NB.lime1.opacity(0.2), lineWidth: 1))
    }

    /// How much of the newest line has been typed. Reduce Motion prints it whole.
    private func typedCount(now: Date) -> Int {
        guard let last = thoughts.last else { return 0 }
        if reduceMotion { return last.text.count }
        return min(last.text.count, Int(max(0, now.timeIntervalSince(last.at)) * Self.typeRate))
    }
}

// MARK: - Bottom Dock View · Cyber Telemetry
private struct ChatBottomDockView: View {
    @Binding var inputText: String
    var isInputFocused: FocusState<Bool>.Binding
    @Binding var attachedImage: UIImage?
    let canSend: Bool
    let onPickPhoto: () -> Void
    let onRemovePhoto: () -> Void
    let onQuickPrompt: (String) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            quickCommandScrollView

            if let img = attachedImage {
                stagedPhotoPill(img)
            }

            inputRow
        }
        .padding(.horizontal, NB.Layout.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var quickCommandScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    onQuickPrompt(L("Evaluate next week's deload training schedule"))
                } label: {
                    Text(L("[CMD: ADJUST PLAN]"))
                        .font(NBFont.dot(600, 11))
                        .tracking(0.03 * 11)
                        .foregroundStyle(NB.lime1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NB.lime1.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(NB.lime1.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    onQuickPrompt(L("Correlate sleep stages with nocturnal HRV"))
                } label: {
                    Text(L("[CMD: SLEEP CORRELATION]"))
                        .font(NBFont.dot(500, 11))
                        .tracking(0.03 * 11)
                        .foregroundStyle(NB.text2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NB.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(NB.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stagedPhotoPill(_ img: UIImage) -> some View {
        HStack(spacing: 10) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(L("Photo attached ready for analysis"))
                .font(NBFont.ui(400, 13))
                .foregroundStyle(NB.text1)

            Spacer()

            Button(action: onRemovePhoto) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(NB.text3Prod)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(hex: 0x16161C), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            Button(action: onPickPhoto) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(NB.white.opacity(0.06))
                        .frame(width: 40, height: 40)
                    Image(systemName: "camera")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(NB.lime1)
                }
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NB.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            TextField(
                "",
                text: $inputText,
                prompt: Text(L("Ask anything, or share a photo..."))
                    .font(NBFont.brand(400, 14))
                    .foregroundColor(NB.text3Prod)
            )
            .accessibilityIdentifier("coach-input")
            .focused(isInputFocused)
            .font(NBFont.brand(400, 14))
            .foregroundStyle(NB.text1)
            .tint(NB.lime1)
            .submitLabel(.send)
            .onSubmit {
                onSubmit()
            }

            Button(action: onSubmit) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(canSend ? NB.lime1 : NB.carbon4)
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSend ? NB.carbon : NB.text3Prod)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach-send")
            .accessibilityLabel(L("Send"))
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0x131318), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }
}

/// Header and dock sit on the same carbon as the thread, so a fill alone disappears.
/// A lifted plate, a lime hairline on the inner edge, and a shadow on the messages
/// are what separate those two bands from the page.
private struct ChatChromeBand: ViewModifier {
    enum Band { case header, dock }
    let band: Band

    func body(content: Content) -> some View {
        content
            .background {
                NB.ledOff
                    .ignoresSafeArea(edges: band == .header ? .top : .bottom)
                    .shadow(
                        color: .black.opacity(0.72),
                        radius: 22,
                        y: band == .header ? 12 : -12
                    )
                    .overlay(alignment: band == .header ? .bottom : .top) {
                        Rectangle()
                            .fill(NB.lime1.opacity(0.45))
                            .frame(height: 1)
                    }
            }
    }
}
