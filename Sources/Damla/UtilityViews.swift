import SwiftUI

struct CleaningPanelView: View {
    @ObservedObject var cleaning: KeyboardCleaning
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 24)).foregroundStyle(Theme.accent)
                Text("Klavye kilitli").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(cleaning.remaining) sn").font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
            }
            Text("Fare çalışır. Süre sonunda klavye otomatik açılır.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("Esc’yi 2 sn basılı tut veya").font(.system(size: 11)).foregroundStyle(Theme.dim)
                Button("Kilidi aç") { cleaning.stop() }.font(.system(size: 12, weight: .semibold)).buttonStyle(PillStyle(accent: true))
            }
            Text("Güç / Touch ID tuşu kilitlenmez.").font(.system(size: 10)).foregroundStyle(Theme.faint)
        }
        .foregroundStyle(.white).padding(.horizontal, 28).frame(height: Layout.contentHeight)
    }
}

struct AgentPanelView: View {
    @ObservedObject var service: AgentStatusService
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Agent’lar").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    ForEach(AgentProvider.allCases.filter { $0.appURL != nil }, id: \.rawValue) { provider in
                        Button(provider.title) { service.open(provider) }
                            .font(.system(size: 10, weight: .medium)).buttonStyle(PillStyle())
                    }
                }
                if service.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Henüz durum gelmedi", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .medium))
                        Text("Bağlı bir Claude Code veya Codex oturumunda yeni bir mesajla başlar.")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                        Text("Codex ilk bağlantıda /hooks üzerinden güven onayı ister.")
                            .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(service.sessions.prefix(12)) { session in
                                let phase = session.effectivePhase(at: context.date)
                                HStack(spacing: 9) {
                                    AgentMascot(session: session, size: 24).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.project).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                                        Text("\(session.provider.title) · \(phase == .waiting ? session.detail : phase.title)")
                                            .font(.system(size: 10)).foregroundStyle(Theme.dim)
                                    }
                                    Spacer(minLength: 4)
                                    Text(session.updated, style: .relative).font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.faint)
                                }
                                .padding(8).background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            }
        }
    }
}
