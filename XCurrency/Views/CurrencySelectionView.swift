import SwiftUI

struct CurrencySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var selected: Set<String>
    @State private var isFiatExpanded: Bool = true
    @State private var isCryptoExpanded: Bool = true

    let onDone: ([String]) -> Void

    init(selected: [String], onDone: @escaping ([String]) -> Void) {
        self._selected = State(initialValue: Set(selected))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            List {
                if !selected.isEmpty && query.isEmpty {
                    Section("Выбранные") {
                        ForEach(selected.sorted(), id: \.self) { code in
                            if let currency = Currency.lookup(code: code) {
                                row(for: currency)
                            }
                        }
                    }
                }
                section(for: .fiat)
                section(for: .crypto)
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Источники:")
                        Text("exchangerate.host, frankfurter.app, open.er-api.com, api.coingecko.com")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Валюты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        finish()
                    }
                }
            }
        }
    }

    private func section(for kind: CurrencyKind) -> some View {
        let title = kind == .fiat ? "Фиат" : "Крипто"
        let expanded = kind == .fiat ? isFiatExpanded : isCryptoExpanded
        let showContent = expanded || !query.isEmpty

        return Section {
            if showContent {
                ForEach(filtered(kind: kind)) { currency in
                    row(for: currency)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toggle(kind)
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees((kind == .fiat ? isFiatExpanded : isCryptoExpanded) ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(filtered(kind: kind).count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func filtered(kind: CurrencyKind) -> [Currency] {
        Currency.all
            .filter { $0.kind == kind }
            .filter {
                query.isEmpty
                || $0.code.lowercased().contains(query.lowercased())
                || $0.displayName.lowercased().contains(query.lowercased())
            }
            .sorted { $0.code < $1.code }
    }

    private func finish() {
        onDone(Array(selected).sorted())
        dismiss()
    }

    private func toggle(_ kind: CurrencyKind) {
        switch kind {
        case .fiat: isFiatExpanded.toggle()
        case .crypto: isCryptoExpanded.toggle()
        }
    }

    private func row(for currency: Currency) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(currency.code)
                HStack(spacing: 6) {
                    Text(currency.displayName)
                    if currency.kind == .crypto {
                        Text("Крипто")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                    }
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { selected.contains(currency.code) },
                set: { isOn in
                    if isOn { selected.insert(currency.code) } else { selected.remove(currency.code) }
                    onDone(Array(selected).sorted())
                }
            ))
            .labelsHidden()
        }
    }
}

