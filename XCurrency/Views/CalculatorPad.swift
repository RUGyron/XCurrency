import SwiftUI
import UIKit

struct CalculatorPad: View {
    let onDigit: (String) -> Void
    let onClear: () -> Void
    let onBackspace: () -> Void
    let onToggleSign: () -> Void
    let onOperator: (CalculatorOperator) -> Void
    let onEquals: () -> Void

    private let layout: [[PadButton]] = [
        [.operation(.divide), .action("⌫"), .action("±"), .action("C")],
        [.operation(.multiply), .digit("7"), .digit("8"), .digit("9")],
        [.operation(.subtract), .digit("4"), .digit("5"), .digit("6")],
        [.operation(.add), .digit("1"), .digit("2"), .digit("3")],
        [.equals, .digit("."), .digit("0")]
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(layout.indices, id: \.self) { rowIndex in
                HStack(spacing: 10) {
                    ForEach(layout[rowIndex]) { item in
                        Button {
                            handle(item)
                        } label: {
                            Text(item.label)
                                .font(.title2)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                                .background(item.backgroundColor)
                                .foregroundColor(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func handle(_ button: PadButton) {
        Haptic.light()
        switch button {
        case .digit(let value):
            // Игнорируем арифметику, калькулятор только вводит число
            if value.count == 1, value.first!.isNumber || value == "." {
                onDigit(value)
            }
        case .operation(let op):
            onOperator(op)
        case .equals:
            onEquals()
        case .action(let label):
            switch label {
            case "C": onClear()
            case "⌫": onBackspace()
            case "±": onToggleSign()
            default: break
            }
        }
    }
}

private enum PadButton: Identifiable {
    case digit(String)
    case action(String)
    case operation(CalculatorOperator)
    case equals

    var id: String { label }

    var label: String {
        switch self {
        case .digit(let value): return value
        case .action(let label): return label
        case .operation(let op): return op.symbol
        case .equals: return "="
        }
    }

    var backgroundColor: Color {
        switch self {
        case .digit: return Color.blue.opacity(0.12)
        case .action: return Color.gray.opacity(0.15)
        case .operation: return Color.orange.opacity(0.2)
        case .equals: return Color.green.opacity(0.2)
        }
    }
}

private enum Haptic {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
