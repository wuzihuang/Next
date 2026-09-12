import SwiftUI
import PhotosUI
import UIKit

/// 11 · REPORT A PROBLEM. A title, the words, up to three screenshots, one Send. It replaces
/// EXPORT MY DATA in the DATA & LEGAL group: that row assembled an archive it was never allowed
/// to send anywhere, while this one has exactly one destination — an issue on the product
/// repo, filed with the build and the phone so the first reply is never "which version?".
///
/// The form survives a failure: nothing is cleared until the server has answered with an
/// issue number. Sending is the only thing that leaves the phone.
struct FeedbackSheet: View {
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var body_ = ""
    @State private var images: [FeedbackReport.Image] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var sending = false
    @State private var outcome: FeedbackReport.Outcome?
    @FocusState private var focus: Field?
    private enum Field { case title, body }

    private var canSend: Bool {
        !sending && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SheetFrame(title: L("Report a problem")) {
            if case .filed(let filed) = outcome {
                filedView(filed)
            } else {
                form
            }
        } footer: {
            if case .filed = outcome {
                LimePillButton(title: L("Done")) { dismiss() }
            } else {
                LimePillButton(title: sending ? L("SENDING …") : L("Send"), enabled: canSend) { send() }
            }
        }
        .onChange(of: pickerItems) { _, items in loadPicked(items) }
        #if DEBUG
        .task {
            // `SIMCTL_CHILD_NB_DEBUG_EDGE=feedback_filled` walks the sheet with the form full.
            if DebugEdge.on("feedback_filled") {
                title = "Sleep page shows —— after a full night"
                body_ = "Wore the band all night, opened the app at 7:40, the sleep card is blank until I pull to refresh."
            }
        }
        #endif
    }

    // MARK: the form

    private var form: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                FieldBox(label: L("Title"), text: $title)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .body }

                descriptionBox

                screenshotsRow

                Text(L("Goes to the NEXTBODY issue tracker with your app version and phone model. No health data is attached."))
                    .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                    .lineSpacing(4)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .padding(.top, 4)

                if let line = failureLine {
                    Text(line)
                        .font(NBFont.ui(400, 12)).tracking(0.02 * 12)
                        .lineSpacing(4)
                        .foregroundStyle(NB.alert2)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The description is the one field allowed to grow. Same chip as `FieldBox`, taller.
    private var descriptionBox: some View {
        ZStack(alignment: .topLeading) {
            if body_.isEmpty {
                Text(L("What happened, and what you expected instead."))
                    .font(NBFont.ui(400, 15))
                    .foregroundStyle(NB.white.opacity(0.28))
                    .padding(.horizontal, 16 + 5)
                    .padding(.top, 14 + 8)
            }
            TextEditor(text: $body_)
                .font(NBFont.ui(400, 15))
                .foregroundStyle(NB.text1)
                .tint(NB.lime1)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 132)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .focused($focus, equals: .body)
        }
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
    }

    /// Thumbnails first, the picker tile last. Three fills the row; the tile goes away.
    private var screenshotsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("SCREENSHOTS · UP TO 3"))
                .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                .foregroundStyle(NB.text2)
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, im in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: im.preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(NB.hairline, lineWidth: 1))
                        Button {
                            images.remove(at: i)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(NB.carbon)
                                .frame(width: 20, height: 20)
                                .background(NB.lime1, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .disabled(sending)
                    }
                }
                if images.count < FeedbackReport.maxImages {
                    PhotosPicker(selection: $pickerItems,
                                 maxSelectionCount: FeedbackReport.maxImages - images.count,
                                 matching: .images) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(NB.lime1)
                            .frame(width: 72, height: 72)
                            .background(NB.carbon4, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(NB.lime1.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .disabled(sending)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 4)
    }

    private var failureLine: String? {
        switch outcome {
        case .failed: L("Could not reach the server. Nothing was sent — your words are still here.")
        case .unconfigured: L("Reporting is not set up on this server yet.")
        case .rateLimited: L("Too many reports in a minute. Wait a moment and send again.")
        case .filed, nil: nil
        }
    }

    // MARK: filed

    private func filedView(_ filed: FeedbackReport.Filed) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(NB.lime1).frame(width: 6, height: 6)
                Text(L("FILED"))
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.lime1)
            }
            Text(L("Filed as #%@. Thank you — we read every one.", String(filed.number)))
                .font(NBFont.brand(400, 14))
                .lineSpacing(7)
                .foregroundStyle(NB.text2)
            Text(title)
                .font(NBFont.ui(500, 16)).tracking(0.01 * 16)
                .foregroundStyle(NB.text1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
                    .stroke(NB.hairline, lineWidth: 1))
        }
    }

    // MARK: actions

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickerItems = []
        Task {
            for item in items where images.count < FeedbackReport.maxImages {
                guard let raw = try? await item.loadTransferable(type: Data.self),
                      let ui = UIImage(data: raw),
                      let prepared = FeedbackReport.Image.prepare(ui) else { continue }
                images.append(prepared)
            }
        }
    }

    private func send() {
        guard canSend else { return }
        focus = nil
        sending = true
        outcome = nil
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body_.trimmingCharacters(in: .whitespacesAndNewlines)
        let imgs = images
        let band = data.band
        Task {
            let result = await FeedbackReport.send(title: t, body: b, images: imgs, band: band)
            sending = false
            outcome = result
        }
    }
}
