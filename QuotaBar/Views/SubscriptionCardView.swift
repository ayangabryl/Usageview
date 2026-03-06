import SwiftUI

struct AccountCardView: View {
    let account: Account
    let isConnected: Bool
    let isRefreshing: Bool
    @Binding var renamingId: UUID?
    @Binding var renameText: String
    var onConnect: () -> Void = {}
    var onRefresh: () -> Void = {}
    var onSaveRename: () -> Void = {}
    var onDisconnect: () -> Void = {}
    var onRemove: () -> Void = {}
    var onTap: () -> Void = {}
    var showWeeklyLimit: Bool = false

    private var isRenaming: Bool { renamingId == account.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: icon + name + menu
            HStack(spacing: 10) {
                ServiceIconView(
                    serviceType: account.serviceType,
                    avatarURL: isConnected ? account.avatarURL : nil,
                    size: 28
                )

                if isRenaming {
                    HStack(spacing: 4) {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .onSubmit { onSaveRename() }

                        Button {
                            onSaveRename()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(account.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button {
                            renamingId = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isConnected
                            ? (account.label.isEmpty
                                ? (account.username ?? account.serviceType.displayName)
                                : account.label)
                            : account.serviceType.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        if isConnected, (account.username != nil || !account.label.isEmpty) {
                            Text(account.serviceType.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if account.isAtLimit && isConnected {
                        Text("LIMIT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                    }

                    AccountMenuButton(
                        isConnected: isConnected,
                        onRefresh: onRefresh,
                        onRename: {
                            renameText = account.label.isEmpty ? (account.username ?? "") : account.label
                            renamingId = account.id
                        },
                        onDisconnect: onDisconnect,
                        onRemove: onRemove
                    )
                }
            }

            if isConnected {
                if account.isStatusOnly {
                    // Status-only: show a clean status badge
                    HStack(spacing: 6) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(account.formattedUsage == "Inactive" ? .orange : .green)
                                .frame(width: 6, height: 6)
                            Text(account.formattedUsage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "key")
                                .font(.system(size: 9))
                            Text("API Key")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                } else if account.hasDualWindows {
                    // Claude rate windows
                    if isRefreshing {
                        HStack {
                            ProgressView()
                                .controlSize(.mini)
                            Spacer()
                        }
                    }

                    if showWeeklyLimit {
                        // Show both windows, labeled by reset countdown
                        claudeRateRow(
                            usage: account.fiveHourUsage ?? 0,
                            resetDate: account.fiveHourResetDate
                        )

                        claudeRateRow(
                            usage: account.sevenDayUsage ?? 0,
                            resetDate: account.sevenDayResetDate
                        )
                    } else {
                        // Show only 5-hour window — same layout as GitHub
                        let fiveHourPct = min((account.fiveHourUsage ?? 0) / 100.0, 1.0)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.primary.opacity(0.08))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(rateBarColor(account.fiveHourUsage ?? 0))
                                    .frame(width: max(0, geo.size.width * fiveHourPct))
                            }
                        }
                        .frame(height: 5)

                        HStack(spacing: 0) {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .padding(.trailing, 6)
                            }

                            Text("\(Int(account.fiveHourUsage ?? 0))% used")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if Account.isResetReasonable(account.fiveHourResetDate, maxHours: 6) {
                                Text("resets \(Account.resetLabel(for: account.fiveHourResetDate))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else {
                    // Usage bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.primary.opacity(0.06))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor)
                                .frame(width: max(0, geo.size.width * account.usagePercentage))
                        }
                    }
                    .frame(height: 5)

                    // Footer: usage text + reset
                    HStack(spacing: 0) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                                .padding(.trailing, 6)
                        }

                        Text(account.formattedUsage)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("resets \(account.resetLabel)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Button { onConnect() } label: {
                    Text("Connect")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .tint(account.accentColor)
            }
        }
        .padding(10)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            if isConnected && !isRenaming { onTap() }
        }
    }

    private var barColor: Color {
        if account.usagePercentage >= 1.0 { return .red }
        if account.usagePercentage >= 0.8 { return .orange }
        return account.accentColor
    }

    private func rateBarColor(_ pct: Double) -> Color {
        if pct >= 100 { return .red }
        if pct >= 80 { return .orange }
        return account.accentColor
    }

    private func claudeRateRow(usage: Double, resetDate: Date?) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(rateBarColor(usage))
                        .frame(width: max(0, geo.size.width * min(usage / 100, 1.0)))
                }
            }
            .frame(height: 4)

            Text("\(Int(usage))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(usage >= 100 ? .red : .secondary)
                .frame(width: 30, alignment: .trailing)

            if Account.isResetReasonable(resetDate, maxHours: 192) {
                Text(Account.resetLabel(for: resetDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 42, alignment: .trailing)
            } else {
                Color.clear.frame(width: 42)
            }
        }
    }
}

// MARK: - Service Icon (bundled logos + AsyncImage for user avatars)

struct ServiceIconView: View {
    let serviceType: ServiceType
    let avatarURL: String?
    let size: CGFloat

    var body: some View {
        if let avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    brandIcon
                default:
                    brandIcon
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            brandIcon
        }
    }

    private var brandIcon: some View {
        Image(serviceType.assetName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

// MARK: - Compact Account Row (single-line, dense)

struct CompactAccountRow: View {
    let account: Account
    let isConnected: Bool
    let isRefreshing: Bool
    @Binding var renamingId: UUID?
    @Binding var renameText: String
    var onConnect: () -> Void = {}
    var onRefresh: () -> Void = {}
    var onSaveRename: () -> Void = {}
    var onDisconnect: () -> Void = {}
    var onRemove: () -> Void = {}
    var onTap: () -> Void = {}
    var showWeeklyLimit: Bool = false

    private var isRenaming: Bool { renamingId == account.id }

    var body: some View {
        HStack(spacing: 6) {
            ServiceIconView(
                serviceType: account.serviceType,
                avatarURL: isConnected ? account.avatarURL : nil,
                size: 20
            )

            if isRenaming {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { onSaveRename() }

                Button {
                    onSaveRename()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(account.accentColor)
                }
                .buttonStyle(.plain)

                Button {
                    renamingId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(isConnected
                    ? (account.label.isEmpty
                        ? (account.username ?? account.serviceType.displayName)
                        : account.label)
                    : account.serviceType.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 60, alignment: .leading)

                if isConnected {
                    Spacer(minLength: 4)

                    if account.isStatusOnly {
                        // Status-only: compact dot + label
                        Circle()
                            .fill(account.formattedUsage == "Inactive" ? .orange : .green)
                            .frame(width: 5, height: 5)
                        Text(account.formattedUsage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    } else if account.hasDualWindows {
                        if showWeeklyLimit {
                            // Both rate windows with countdown labels
                            VStack(alignment: .trailing, spacing: 2) {
                                compactRateRow(usage: account.fiveHourUsage ?? 0, resetDate: account.fiveHourResetDate)
                                compactRateRow(usage: account.sevenDayUsage ?? 0, resetDate: account.sevenDayResetDate)
                            }
                            .frame(maxWidth: 120)
                        } else {
                            // Single 5-hour bar — same as GitHub layout
                            let fiveHourPct = min((account.fiveHourUsage ?? 0) / 100.0, 1.0)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.primary.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(compactRateBarColor(account.fiveHourUsage ?? 0))
                                        .frame(width: max(0, geo.size.width * fiveHourPct))
                                }
                            }
                            .frame(maxWidth: 60, maxHeight: 4)

                            Text("\(Int(account.fiveHourUsage ?? 0))%")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle((account.fiveHourUsage ?? 0) >= 100 ? .red : .secondary)
                                .fixedSize()

                            if Account.isResetReasonable(account.fiveHourResetDate, maxHours: 6) {
                                Text(Account.resetLabel(for: account.fiveHourResetDate))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .fixedSize()
                            }
                        }
                    } else {
                        // Inline usage bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.primary.opacity(0.06))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(barColor)
                                    .frame(width: max(0, geo.size.width * account.usagePercentage))
                            }
                        }
                        .frame(maxWidth: 60, maxHeight: 4)

                        Text(compactUsage)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(account.isAtLimit ? .red : .secondary)
                            .fixedSize()

                        Text(account.resetLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }

                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    }

                    AccountMenuButton(
                        isConnected: isConnected,
                        compact: true,
                        onRefresh: onRefresh,
                        onRename: {
                            renameText = account.label.isEmpty ? (account.username ?? "") : account.label
                            renamingId = account.id
                        },
                        onDisconnect: onDisconnect,
                        onRemove: onRemove
                    )
                } else {
                    Spacer()
                    Button { onConnect() } label: {
                        Text("Connect")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(account.accentColor)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if isConnected && !isRenaming { onTap() }
        }
    }

    private var compactUsage: String {
        if account.usageUnit == "% used" {
            return "\(Int(account.currentUsage))%"
        }
        return "\(Int(account.currentUsage))/\(Int(account.usageLimit))"
    }

    private var barColor: Color {
        if account.usagePercentage >= 1.0 { return .red }
        if account.usagePercentage >= 0.8 { return .orange }
        return account.accentColor
    }

    private func compactRateBarColor(_ usage: Double) -> Color {
        let pct = usage / 100.0
        if pct >= 1.0 { return .red }
        if pct >= 0.8 { return .orange }
        return account.accentColor
    }

    @ViewBuilder
    private func compactRateRow(usage: Double, resetDate: Date?) -> some View {
        let pct = min(usage / 100.0, 1.0)
        HStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(compactRateBarColor(usage))
                        .frame(width: max(0, geo.size.width * pct))
                }
            }
            .frame(maxWidth: 40, maxHeight: 3)

            Text("\(Int(usage))%")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(usage >= 100 ? .red : .secondary)
                .frame(width: 26, alignment: .trailing)

            if let resetDate, resetDate.timeIntervalSince(.now) > 0 {
                Text(Account.resetLabel(for: resetDate))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, alignment: .trailing)
            } else {
                Color.clear.frame(width: 32)
            }
        }
    }
}

// MARK: - Account Menu Button (visible ... menu with Refresh/Disconnect/Remove)

struct AccountMenuButton: View {
    let isConnected: Bool
    var compact: Bool = false
    var onRefresh: () -> Void = {}
    var onRename: () -> Void = {}
    var onDisconnect: () -> Void = {}
    var onRemove: () -> Void = {}

    var body: some View {
        Menu {
            if isConnected {
                Button { onRefresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button { onRename() } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Divider()
                Button { onDisconnect() } label: {
                    Label("Disconnect", systemImage: "person.crop.circle.badge.minus")
                }
            }
            Button(role: .destructive) { onRemove() } label: {
                Label("Remove Account", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.tertiary)
                .frame(width: compact ? 24 : 28, height: compact ? 24 : 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: compact ? 24 : 28)
    }
}
