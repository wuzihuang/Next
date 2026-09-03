import SwiftUI
import PhotosUI

struct ChatDetailView: View {
    let sessionID: String?
    let initialQuery: String?
    let initialAttachmentDataURL: String?

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var dataStore: DataStore
    @StateObject private var chatStore = ChatStore.shared
    @ObservedObject private var ai = AIService.shared

    @State private var inputText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var attachedDataURL: String?
    @State private var showPhotoPicker: Bool = false
    @State private var showHistorySheet: Bool = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChatTopBarView(
                onBack: {
                    isInputFocused = false
                    router.back()
                },
                onHistory: {
                    isInputFocused = false
                    showHistorySheet = true
                }
            )

            messageScrollView

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
        }
        .carbonPage()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .detailEdgeBack {
            isInputFocused = false
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
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            handlePhotoSelection(item)
        }
        .task {
            if let sessionID {
                chatStore.selectSession(sessionID)
            } else if chatStore.sessions.isEmpty {
                chatStore.startNewSession()
            }
            if let initialQuery, !initialQuery.isEmpty {
                await chatStore.send(text: initialQuery, dataURL: initialAttachmentDataURL, dataStore: dataStore)
            } else {
                try? await Task.sleep(for: .milliseconds(350))
                isInputFocused = true
            }
        }
    }

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    if let session = chatStore.currentSession {
                        ForEach(session.messages) { message in
                            if message.sender == .user {
                                UserBubbleView(message: message)
                                    .id(message.id.uuidString)
                            } else {
                                AiTelemetryCardView(message: message)
                                    .id(message.id.uuidString)
                            }
                        }
                    }

                    if chatStore.isSending {
                        ThinkingStatusView(thoughtText: ai.thoughts.last?.text)
                            .id("thinking-indicator")
                    }

                    Color.clear.frame(height: 4)
                }
                .padding(.horizontal, NB.Layout.gutter)
                .padding(.top, 16)
                .padding(.bottom, 20)
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
            .onChange(of: chatStore.currentSession?.messages.count) { _, _ in
                withAnimation {
                    let targetID = chatStore.currentSession?.messages.last?.id.uuidString ?? "thinking-indicator"
                    proxy.scrollTo(targetID, anchor: .bottom)
                }
            }
            .onChange(of: chatStore.isSending) { _, sending in
                if sending {
                    withAnimation { proxy.scrollTo("thinking-indicator", anchor: .bottom) }
                }
            }
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
}

// MARK: - Top Bar · Cyber Telemetry
private struct ChatTopBarView: View {
    let onBack: () -> Void
    let onHistory: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                ZStack {
                    Circle()
                        .fill(NB.smokeKey)
                        .frame(width: 40, height: 40)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NB.text1)
                }
                .overlay(Circle().stroke(NB.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("DIAGNOSTIC TERMINAL")
                        .font(NBFont.dot(700, 13))
                        .tracking(0.06 * 13)
                        .foregroundStyle(NB.text1)
                    Circle()
                        .fill(NB.lime1)
                        .frame(width: 7, height: 7)
                }
                Text("LINKED: VEEPOO-BAND · PPG 50HZ")
                    .font(NBFont.dot(500, 10))
                    .tracking(0.04 * 10)
                    .foregroundStyle(NB.lime1)
            }

            Spacer()

            Button(action: onHistory) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NB.lime1)
                    Text(AppLanguage.isEnglish ? "HISTORY" : "历史记录")
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
        .padding(.top, ScreenMetrics.safeArea.top + 10)
        .padding(.bottom, 14)
        .background(Color(hex: 0x070709).overlay(alignment: .bottom) {
            Rectangle().fill(NB.hairline).frame(height: 1)
        })
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
                    Text(message.text)
                        .font(NBFont.brand(500, 14))
                        .foregroundStyle(NB.text1)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 4) {
                    Text(formatTime(message.at))
                        .font(NBFont.dot(400, 10))
                        .foregroundStyle(NB.text3Prod)
                    Text("· DELIVERED")
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

// MARK: - AI Cyber Telemetry Card
private struct AiTelemetryCardView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = message.telemetry {
                HStack(spacing: 8) {
                    Text(t.category)
                        .font(NBFont.dot(600, 10))
                        .tracking(0.04 * 10)
                        .foregroundStyle(NB.lime1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NB.lime1.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(t.confidence)
                        .font(NBFont.dot(400, 10))
                        .foregroundStyle(NB.text3Prod)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if let t = message.telemetry {
                    HStack(alignment: .firstTextBaseline) {
                        Text(t.verdict)
                            .font(NBFont.dot(700, 15))
                            .tracking(0.02 * 15)
                            .foregroundStyle(t.verdictLevel.color)
                        Spacer()
                        Text(t.verdictTag)
                            .font(NBFont.dot(700, 10))
                            .foregroundStyle(t.verdictLevel.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(t.verdictLevel.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    Text(t.analysis)
                        .font(NBFont.ui(400, 13))
                        .foregroundStyle(NB.text1)
                        .lineSpacing(4)

                    telemetryTable(t.metrics)

                    prescriptionsList(t.prescriptions)
                } else if !message.text.isEmpty {
                    Text(message.text)
                        .font(NBFont.ui(400, 14))
                        .foregroundStyle(NB.text1)
                        .lineSpacing(4)
                }
            }
            .padding(14)
            .background(Color(hex: 0x111116), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(NB.lime1.opacity(0.25), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func telemetryTable(_ metrics: [TelemetryMetricItem]) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("TELEMETRY METRICS")
                    .font(NBFont.dot(600, 10))
                    .tracking(0.06 * 10)
                    .foregroundStyle(NB.text3Prod)
                Spacer()
                Text("DELTA (14D)")
                    .font(NBFont.dot(600, 10))
                    .tracking(0.06 * 10)
                    .foregroundStyle(NB.text3Prod)
            }

            ForEach(metrics) { m in
                HStack {
                    Text(m.name)
                        .font(NBFont.brand(500, 13))
                        .foregroundStyle(NB.text2)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(m.value)
                            .font(NBFont.dot(700, 13))
                            .foregroundStyle(m.level.color)
                        Text(m.delta)
                            .font(NBFont.dot(400, 11))
                            .foregroundStyle(NB.text3Prod)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }

    private func prescriptionsList(_ list: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLanguage.isEnglish ? "PRESCRIPTION · ACTION STEPS:" : "PRESCRIPTION · 处方调整：")
                .font(NBFont.dot(700, 11))
                .tracking(0.04 * 11)
                .foregroundStyle(NB.lime1)

            ForEach(list, id: \.self) { p in
                Text(p)
                    .font(NBFont.ui(400, 13))
                    .foregroundStyle(NB.text2)
                    .lineSpacing(3)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Thinking View
private struct ThinkingStatusView: View {
    let thoughtText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(NB.lime1)
                    .frame(width: 7, height: 7)
                Text("SYNCHRONIZING BAND SENSORS...")
                    .font(NBFont.dot(600, 11))
                    .tracking(0.04 * 11)
                    .foregroundStyle(NB.lime1)
            }

            if let thoughtText, !thoughtText.isEmpty {
                Text(thoughtText)
                    .font(NBFont.ui(400, 13))
                    .foregroundStyle(NB.text2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x111116), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NB.lime1.opacity(0.2), lineWidth: 1))
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
        .padding(.top, 12)
        .padding(.bottom, max(ScreenMetrics.safeArea.bottom, 10) + 6)
        .background(Color(hex: 0x070709).overlay(alignment: .top) {
            Rectangle().fill(NB.hairline).frame(height: 1)
        })
    }

    private var quickCommandScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    onQuickPrompt(AppLanguage.isEnglish ? "Evaluate next week's deload training schedule" : "评估下周减量训练排期")
                } label: {
                    Text(AppLanguage.isEnglish ? "[CMD: ADJUST PLAN]" : "[CMD: 调整训练计划]")
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
                    onQuickPrompt(AppLanguage.isEnglish ? "Correlate sleep stages with nocturnal HRV" : "比对夜间睡眠分期与HRV")
                } label: {
                    Text(AppLanguage.isEnglish ? "[CMD: SLEEP CORRELATION]" : "[CMD: 交叉比对睡眠曲线]")
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

            Text(AppLanguage.isEnglish ? "Photo attached ready for analysis" : "已附带照片，可进行生理动作分析")
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
                prompt: Text(AppLanguage.isEnglish ? "Ask advice, command or attach photo..." : "探讨方案，或发照片诊断分析...")
                    .font(NBFont.brand(400, 14))
                    .foregroundColor(NB.text3Prod)
            )
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
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0x131318), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }
}
