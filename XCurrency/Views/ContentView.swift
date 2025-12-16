import SwiftUI
import SwiftData
import Observation
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("themePreference") private var themePreference: ThemePreference = .system
    @AppStorage("appIconPreference") private var appIconPreference: AppIconPreference = .light
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: RateViewModel?
    @State private var showSelector = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    MainScreen(viewModel: viewModel, showSelector: $showSelector, showSettings: $showSettings)
                } else {
                    ProgressView("Загрузка...")
                        .task {
                            if viewModel == nil {
                                viewModel = RateViewModel(context: context, fetcher: RateFetcher())
                            }
                        }
                }
            }
        }
        .preferredColorScheme(themePreference.colorScheme)
        .environment(\.colorScheme, themePreference.effectiveColorScheme(current: colorScheme))
        .onAppear { updateIcon(for: appIconPreference, style: colorScheme == .light ? .light : .dark) }
        .sheet(isPresented: $showSelector) {
            if let viewModel {
                CurrencySelectionView(
                    selected: viewModel.selectedCodes,
                    onDone: { codes in
                        viewModel.updateSelection(codes)
                    }
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(themePreference: $themePreference, appIconPreference: $appIconPreference)
                .preferredColorScheme(themePreference.colorScheme)
                .environment(\.colorScheme, themePreference.effectiveColorScheme(current: colorScheme))
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel?.refreshNow() }
                updateIcon(for: appIconPreference, style: colorScheme == .light ? .light : .dark)
            }
        }
        .onChange(of: appIconPreference) { _, newValue in
            updateIcon(for: newValue, style: colorScheme == .light ? .light : .dark)
        }
        .onChange(of: colorScheme) { _, newValue in
            updateIcon(for: appIconPreference, style: newValue == .light ? .light : .dark)
        }
    }
}

private struct MainScreen: View {
    @Bindable var viewModel: RateViewModel
    @Binding var showSelector: Bool
    @Binding var showSettings: Bool
    @Environment(\.colorScheme) private var colorScheme
    private let padHeight: CGFloat = 340

    var body: some View {
        ScrollView(showsIndicators: false) {
            topPanel
        }
        .navigationTitle(baseTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                CalculatorPad(
                    onDigit: viewModel.handleDigit,
                    onClear: viewModel.clear,
                    onBackspace: viewModel.backspace,
                    onToggleSign: viewModel.toggleSign,
                    onOperator: viewModel.handleOperator,
                    onEquals: viewModel.handleEquals
                )
                .frame(height: padHeight)
                .frame(maxWidth: .infinity)
                .background(colorScheme == .dark ? Color.black : Color.white)
            }
            .background(
                (colorScheme == .dark ? Color.black : Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 10, y: -4)
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.isFetching {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.secondary)
                } else {
                    statusButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSelector = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    private var topPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            updateNote
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.displayRates) { item in
                    currencyRow(item)
                        .onTapGesture {
                            Haptic.light()
                            viewModel.setBaseCurrency(item.currency.code)
                        }
                }
            }
            .padding(.vertical, 6)
        }
        .padding()
    }
    
    private var statusButton: some View {
        Button {
            Haptic.light()
            Task { await viewModel.refreshNow() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .rotationEffect(.degrees(60))
        }
    }

    private var statusBadge: some View {
        Group {
            if viewModel.isFetching {
                Text("Обновляем…")
            } else if let date = viewModel.lastUpdated {
                Text(Self.dateFormatter.string(from: date))
            } else {
                Text("Нет данных")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private static let fiatFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let cryptoFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var baseTitle: String {
        let value = Double(viewModel.amountText) ?? 0
        let formatter = formatter(for: baseCurrencyKind)
        let formatted = formatter.string(from: value as NSNumber) ?? viewModel.amountText
        return "Курс \(formatted) \(viewModel.baseCurrencyCode)"
    }

    private var updateNote: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fiat = viewModel.lastUpdatedFiat
            let crypto = viewModel.lastUpdatedCrypto
            let fiatText = relative(fiat, now: context.date)
            let cryptoText = relative(crypto, now: context.date)
            HStack(spacing: 6) {
                Text("Обновлено")
                    .foregroundStyle(.secondary)
                Text("Фиат:")
                    .foregroundStyle(.secondary)
                Text(fiatText)
                    .foregroundStyle(fiatColor(fiat, now: context.date))
                Text("•")
                    .foregroundStyle(.secondary)
                Text("Крипто:")
                    .foregroundStyle(.secondary)
                Text(cryptoText)
                    .foregroundStyle(cryptoColor(crypto, now: context.date))
            }
            .font(.caption2)
            .padding(.horizontal, 8)
        }
    }

    private func currencyRow(_ item: CurrencyAmount) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.currency.code)
                        .font(.headline)
                    if item.currency.kind == .crypto {
                        Text("Крипто")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                    }
                    if item.isBase {
                        Text("Выбрано")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                    }
                }
                Text(item.currency.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.hasRate {
                Text(formatter(for: item.currency.kind).string(from: item.amount as NSNumber) ?? "—")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(item.isBase ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(item.isBase ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }
    private var baseCurrencyKind: CurrencyKind {
        Currency.lookup(code: viewModel.baseCurrencyCode)?.kind ?? .fiat
    }

    private func formatter(for kind: CurrencyKind) -> NumberFormatter {
        switch kind {
        case .fiat: return Self.fiatFormatter
        case .crypto: return Self.cryptoFormatter
        }
    }

    private func relative(_ date: Date?, now: Date) -> String {
        guard let date else { return "нет данных" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "только что" }
        if seconds < 90 { return "\(seconds) сек назад" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) мин назад" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) ч назад" }
        let days = hours / 24
        if days < 30 { return "\(days) дн назад" }
        let months = days / 30
        return "\(months) мес назад"
    }

    private func fiatColor(_ date: Date?, now: Date) -> Color {
        guard let date else { return .red }
        let seconds = now.timeIntervalSince(date)
        if seconds > (65 * 60) { return .orange }
        return .green
    }

    private func cryptoColor(_ date: Date?, now: Date) -> Color {
        guard let date else { return .red }
        let seconds = now.timeIntervalSince(date)
        if seconds > 70 { return .orange }
        return .green
    }
}

private enum Haptic {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

@MainActor
private func updateIcon(for icon: AppIconPreference, style: UIUserInterfaceStyle? = nil) {
    guard UIApplication.shared.supportsAlternateIcons else { return }

    let _: UIUserInterfaceStyle = {
        if let style {
            return style
        }
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            return scene.traitCollection.userInterfaceStyle
        }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return scene.traitCollection.userInterfaceStyle
        }
        return UITraitCollection.current.userInterfaceStyle
    }()

    let target: String? = {
        switch icon {
        case .light: return nil
        case .dark: return "AppIconDark"
        }
    }()

    if UIApplication.shared.alternateIconName != target {
        UIApplication.shared.setAlternateIconName(target) { error in
            if let error {
                print("RateApp: alternate icon switch failed: \(error)")
            } else {
                print("RateApp: alternate icon set to \(target ?? "primary")")
            }
        }
    } else {
        print("RateApp: alternate icon already \(target ?? "primary")")
    }
}

private struct SettingsView: View {
    @Binding var themePreference: ThemePreference
    @Binding var appIconPreference: AppIconPreference

    var body: some View {
        NavigationStack {
            Form {
                Section("Тема") {
                    Picker("Тема", selection: $themePreference) {
                        ForEach(ThemePreference.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Иконка") {
                    HStack(spacing: 16) {
                        iconChoice(for: .light)
                        iconChoice(for: .dark)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func iconChoice(for icon: AppIconPreference) -> some View {
        Button {
            appIconPreference = icon
        } label: {
            VStack(spacing: 8) {
                iconPreview(name: icon == .dark ? "AppIconDarkPreview" : "AppIconPreview")
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(appIconPreference == icon ? Color.blue : Color.clear, lineWidth: 2)
                    )
                Text(icon.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconPreview(name: String) -> some View {
        let candidates = [
            name,
            "\(name)-60x60",
            "\(name)-29x29",
            "AppIconPreview",
            "AppIconDarkPreview"
        ]

        if let found = candidates.compactMap({ UIImage(named: $0) }).first {
            return AnyView(
                Image(uiImage: found)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .cornerRadius(16)
            )
        } else {
            return AnyView(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(name)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    )
            )
        }
    }
}

enum AppIconPreference: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Система"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func effectiveColorScheme(current: ColorScheme) -> ColorScheme {
        switch self {
        case .system: return current
        case .light: return .light
        case .dark: return .dark
        }
    }
}
#if DEBUG
#Preview("Mock") {
    NavigationStack {
        MainScreen(
            viewModel: PreviewMocks.makeViewModel(),
            showSelector: .constant(false),
            showSettings: .constant(false)
        )
    }
}
#endif

#if DEBUG
#Preview("Full App") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: StoredRate.self, configurations: configuration)
    ContentView()
        .modelContainer(container)
}
#endif

