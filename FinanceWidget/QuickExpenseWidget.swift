//
//  QuickExpenseWidget.swift
//  FinanceWidget
//
//  Created by OpenCode on 04/03/2026.
//

import WidgetKit
import SwiftUI

/// Simple static widget that opens Finance's "Add Expense" form via deep link.
struct QuickExpenseWidget: Widget {
    let kind = "QuickExpenseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickExpenseTimelineProvider()) { entry in
            QuickExpenseWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Añadir gasto")
        .description("Abre Finance para registrar un gasto rápidamente.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickExpenseEntry: TimelineEntry {
    let date: Date
}

struct QuickExpenseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickExpenseEntry {
        QuickExpenseEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickExpenseEntry) -> Void) {
        completion(QuickExpenseEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickExpenseEntry>) -> Void) {
        let entry = QuickExpenseEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct QuickExpenseWidgetView: View {
    var entry: QuickExpenseEntry

    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            smallLayout
        default:
            mediumLayout
        }
    }

    private var smallLayout: some View {
        Link(destination: URL(string: "finance://add-expense")!) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("Añadir gasto")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Abrir Finance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var mediumLayout: some View {
        Link(destination: URL(string: "finance://add-expense")!) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Añadir gasto")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Toca para registrar un gasto rápido en Finance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
