import SwiftUI

struct ChatHistorySheet: View {
    @ObservedObject var chatStore: ChatStore
    let onSelect: (String) -> Void
    let onNewChat: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(NB.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("CHAT HISTORY"))
                        .font(NBFont.dot(700, 14))
                        .tracking(0.04 * 14)
                        .foregroundStyle(NB.text1)
                    Text("\(chatStore.sessions.count) " + (L("SAVED CONVERSATIONS")))
                        .font(NBFont.ui(400, 12))
                        .foregroundStyle(NB.lime1)
                }

                Spacer()

                Button(action: onNewChat) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NB.carbon)
                        Text(L("NEW CHAT"))
                            .font(NBFont.dot(700, 11))
                            .foregroundStyle(NB.carbon)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(NB.lime1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(chatStore.sessions) { session in
                        let isActive = session.id == chatStore.currentSessionID
                        Button {
                            onSelect(session.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(session.title)
                                        .font(NBFont.brand(600, 14))
                                        .foregroundStyle(NB.text1)
                                        .lineLimit(1)
                                    Spacer()
                                    if isActive {
                                        Text(L("CURRENT"))
                                            .font(NBFont.dot(600, 10))
                                            .foregroundStyle(NB.lime1)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(NB.lime1.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    } else if session.photosCount > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "photo")
                                                .font(.system(size: 10))
                                            Text("\(session.photosCount) " + (L("PHOTOS")))
                                                .font(NBFont.dot(500, 10))
                                        }
                                        .foregroundStyle(NB.cyan1)
                                    }
                                }

                                if !session.subtitle.isEmpty {
                                    Text(session.subtitle)
                                        .font(NBFont.ui(400, 13))
                                        .foregroundStyle(NB.text2)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }

                                HStack {
                                    Text(formattedTime(session.updatedAt))
                                        .font(NBFont.dot(400, 10))
                                        .foregroundStyle(NB.text3Prod)
                                    Spacer()
                                    ForEach(session.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(NBFont.dot(500, 10))
                                            .foregroundStyle(isActive ? NB.lime1 : NB.text3Prod)
                                    }
                                }
                                .padding(.top, 2)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isActive ? NB.lime1.opacity(0.06) : Color(hex: 0x111116))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isActive ? NB.lime1.opacity(0.4) : NB.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Text(L("SAVED ON THIS DEVICE"))
                    .font(NBFont.dot(400, 10))
                    .foregroundStyle(NB.text3Prod)
                Spacer()
                Button {
                    chatStore.clearAll()
                    onDismiss()
                } label: {
                    Text(L("CLEAR ALL"))
                        .font(NBFont.dot(600, 11))
                        .foregroundStyle(NB.alert2)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 18)
        .background(Color(hex: 0x0D0D11).ignoresSafeArea())
    }

    private func formattedTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return (L("TODAY ")) + f.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return L("YESTERDAY")
        } else {
            let f = DateFormatter()
            f.dateFormat = L("MMM d")
            return f.string(from: date)
        }
    }
}
