// SwooshGenerativeUI/DataComponents.swift — Built-in data component views (0.4A)

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct UIListView: View {
    let items: [String]
    let style: String?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        let renderedItems = listItems(items)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(renderedItems, id: \.id) { item in
                HStack(alignment: .top, spacing: 8) {
                    if style == "bullet" {
                        Text("•").foregroundStyle(.secondary)
                    } else if style == "numbered" {
                        Text("\(item.number).")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    UIComponentRenderer(componentID: item.componentID, surface: surface, catalog: catalog, handler: handler)
                }
            }
        }
    }
}

struct UIChartView: View {
    let series: [ChartSeries]
    let kind: String
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            #if canImport(Charts)
            Chart {
                ForEach(chartSeriesItems(series), id: \.id) { item in
                    let s = item.element
                    ForEach(chartPoints(seriesID: item.id, values: s.values), id: \.id) { point in
                        switch kind {
                        case "bar":
                            BarMark(x: .value("Index", point.index), y: .value(s.name, point.value))
                                .foregroundStyle(by: .value("Series", s.name))
                        case "area":
                            AreaMark(x: .value("Index", point.index), y: .value(s.name, point.value))
                                .foregroundStyle(by: .value("Series", s.name))
                        default:
                            LineMark(x: .value("Index", point.index), y: .value(s.name, point.value))
                                .foregroundStyle(by: .value("Series", s.name))
                        }
                    }
                }
            }
            .frame(height: 140)
            #else
            Text("Charts framework unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
    }
}

struct UIKeyValueView: View {
    let pairs: [KeyValuePair]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<pairs.count, id: \.self) { i in
                HStack {
                    Text(pairs[i].key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pairs[i].value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

struct UITableView: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        let columnCount = columns.count
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ForEach(0..<columnCount, id: \.self) { idx in
                    Text(columns[idx])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            ForEach(0..<rows.count, id: \.self) { rowIdx in
                let row = normalizedTableRow(rows[rowIdx], columnCount: columnCount)
                HStack {
                    ForEach(tableCellIDs(row: rowIdx, columnCount: columnCount), id: \.self) { cell in
                        Text(row[cell.column])
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct UIListItemID: Hashable, Sendable {
    let componentID: String
    let occurrence: Int
}

struct UIListItem: Identifiable, Sendable {
    let id: UIListItemID
    let number: Int
    let componentID: String
}

func listItems(_ items: [String]) -> [UIListItem] {
    var occurrences: [String: Int] = [:]
    return items.enumerated().map { item in
        let occurrence = occurrences[item.element, default: 0]
        occurrences[item.element] = occurrence + 1
        return UIListItem(
            id: UIListItemID(componentID: item.element, occurrence: occurrence),
            number: item.offset + 1,
            componentID: item.element
        )
    }
}

struct UIChartSeriesItem: Identifiable, Sendable {
    let id: String
    let element: ChartSeries
}

func chartSeriesItems(_ series: [ChartSeries]) -> [UIChartSeriesItem] {
    var occurrences: [String: Int] = [:]
    return series.map { item in
        let key = chartSeriesKey(item)
        let occurrence = occurrences[key, default: 0]
        occurrences[key] = occurrence + 1
        return UIChartSeriesItem(id: "\(key)#\(occurrence)", element: item)
    }
}

func chartSeriesKey(_ series: ChartSeries) -> String {
    let values = series.values.map { String($0) }.joined(separator: ",")
    return "\(series.name)|\(series.color ?? "")|\(values)"
}

struct UIChartPoint: Equatable, Identifiable, Sendable {
    let id: String
    let index: Int
    let value: Double
}

func chartPoints(seriesID: String, values: [Double]) -> [UIChartPoint] {
    values.enumerated().map { item in
        UIChartPoint(id: "\(seriesID)-\(item.offset)", index: item.offset, value: item.element)
    }
}

struct UITableCellID: Hashable, Sendable {
    let row: Int
    let column: Int
}

func tableCellIDs(row: Int, columnCount: Int) -> [UITableCellID] {
    (0..<columnCount).map { UITableCellID(row: row, column: $0) }
}

func normalizedTableRow(_ row: [String], columnCount: Int) -> [String] {
    guard row.count < columnCount else { return Array(row.prefix(columnCount)) }
    return row + Array(repeating: "", count: columnCount - row.count)
}
