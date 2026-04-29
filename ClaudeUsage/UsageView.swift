import SwiftUI

struct UsageView: View {
    @ObservedObject var vm: UsageViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            content
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    private var header: some View {
        HStack {
            Text("CLAUDE USAGE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if vm.isLoading {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
            } else {
                Button(action: { vm.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let err = vm.errorMsg {
            errorView(err)
        } else if let d = vm.data {
            dataView(d)
        } else {
            loadingView
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(msg)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("불러오는 중...")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func dataView(_ d: UsageData) -> some View {
        VStack(spacing: 14) {
            UsageRow(
                label: "세션",
                sublabel: "5시간 사용량",
                pct: d.sessionPct,
                resetAt: d.sessionResetAt,
                isCountdown: true
            )

            Divider().background(Color.white.opacity(0.06))

            UsageRow(
                label: "주간",
                sublabel: "7일 사용량",
                pct: d.weeklyPct,
                resetAt: d.weeklyResetAt,
                isCountdown: false
            )

            if let updated = vm.lastUpdated {
                Text("업데이트: \(updated, formatter: timeFormatter)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}


private struct UsageRow: View {
    let label: String
    let sublabel: String
    let pct: Double
    let resetAt: Date?
    let isCountdown: Bool

    private var color: Color {
        pct >= 80 ? .red : pct >= 50 ? .orange : .green
    }

    private var resetText: String {
        guard let date = resetAt else { return "" }
        if isCountdown {
            let secs = max(0, date.timeIntervalSinceNow)
            let h = Int(secs) / 3600
            let m = (Int(secs) % 3600) / 60
            return secs <= 0 ? "곧 리셋" : h > 0 ? "\(h)h \(m)m 후 리셋" : "\(m)m 후 리셋"
        } else {
            return date.formatted(.dateTime.month().day().hour().minute()) + " 리셋"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(sublabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(String(format: "%.1f%%", pct))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat(min(pct, 100) / 100), height: 6)
                        .animation(.easeOut(duration: 0.5), value: pct)
                }
            }
            .frame(height: 6)

            if !resetText.isEmpty {
                Text(resetText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()
