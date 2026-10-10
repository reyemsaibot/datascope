import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ProfilingCore

@MainActor @Observable final class Model {
    var url: URL?
    var options = ImportOptions()
    var profile: Profile?
    var status = "Bereit für deine Daten"
    var error: String?
    var running = false
    var token: Cancellation?
    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv")!, UTType(filenameExtension: "tsv")!, UTType(filenameExtension: "xlsx")!]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { url = panel.url; profile = nil; error = nil; status = "Importoptionen prüfen und Analyse starten" }
    }
    func run() {
        guard let url, !running else { return }
        let options = options
        let cancellation = Cancellation(); token = cancellation
        profile = nil; error = nil; running = true; status = "Analyse startet …"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    try Profiler.run(url: url, options: options, cancellation: cancellation) { message in
                        Task { @MainActor [self] in
                            guard running else { return }; status = message
                        }
                    }
                }.value
                profile = result; status = "Vollständige Analyse abgeschlossen"
            } catch is CancellationError { status = "Analyse abgebrochen" }
            catch { self.error = error.localizedDescription; status = "Import oder Analyse fehlgeschlagen" }
            running = false; token = nil
        }
    }
    func cancel() { token?.cancel(); status = "Analyse wird abgebrochen …" }
}

@main struct DataScopeApp: App {
    @State private var model = Model()

    init() {
        // Keep the live Dock tile aligned with the bundled AppIcon. This is
        // also the path used by Nori, whose icon remains correct after launch.
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                .onAppear { NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Datei öffnen …") { model.choose() }.keyboardShortcut("o").disabled(model.running)
            }
        }
    }
}

struct ContentView: View {
    @Bindable var model: Model
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                BrandLogo()
                Text("LOKALES DATA PROFILING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Label(model.url?.lastPathComponent ?? "Keine Datenquelle", systemImage: "doc.text")
                    .font(.headline).lineLimit(3)
                Text("CSV · TSV · Excel").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(22)
                .navigationSplitViewColumnWidth(230)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Deine Daten verstehen.").font(.largeTitle.bold())
                        Text("Vollständigkeit und Werte prüfen – direkt auf deinem Mac.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Datei öffnen …", systemImage: "folder") { model.choose() }.disabled(model.running)
                }
                if let url = model.url {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(url.lastPathComponent).font(.headline)
                            HStack(spacing: 18) {
                                Toggle("Erste Zeile enthält Überschriften", isOn: $model.options.header)
                                if url.pathExtension.lowercased() == "xlsx" {
                                    TextField("Blattname (leer = erstes Blatt)", text: $model.options.sheet).frame(maxWidth: 240)
                                } else {
                                    Picker("Trennzeichen", selection: $model.options.delimiter) {
                                        Text("Automatisch").tag(""); Text("Semikolon").tag(";")
                                        Text("Komma").tag(","); Text("Tab").tag("\t"); Text("Pipe").tag("|")
                                    }.frame(maxWidth: 240)
                                }
                                Toggle("Deutsche Zahlen", isOn: $model.options.decimalComma)
                            }.disabled(model.running)
                            Text(url.pathExtension.lowercased() == "xlsx"
                                 ? "Excel: gespeicherte Zellwerte, keine Formel-Neuberechnung oder Anzeigeformatierung."
                                 : "CSV/TSV: UTF-8. Nicht zitierte leere Felder gelten als NULL; zitierte leere Felder als leerer Text.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(8)
                    }
                    HStack {
                        if model.running {
                            ProgressView().controlSize(.small)
                            Button("Abbrechen") { model.cancel() }
                        } else {
                            Button("Profil berechnen", systemImage: "play.fill") { model.run() }.buttonStyle(.borderedProminent)
                        }
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let error = model.error {
                    ScrollView { Text(error).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .padding().background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).frame(maxHeight: 160)
                }
                if let profile = model.profile, let sourceURL = model.url {
                    ScrollView {
                        ProfileView(profile: profile, sourceURL: sourceURL, options: model.options)
                            .padding(.bottom, 4)
                    }
                } else if !model.running && model.error == nil {
                    ContentUnavailableView("Ein klarer Blick auf deine Daten", systemImage: "tablecells.badge.ellipsis",
                                           description: Text("Öffne eine Datei. DataScope erhält Rohwerte und prüft jede Zeile auf fehlende und interpretierbare Werte."))
                } else { Spacer() }
            }.padding(28)
        }
    }
}

struct BrandLogo: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "DataScopeLogo", withExtension: "png"),
           let logo = NSImage(contentsOf: url) {
            Image(nsImage: logo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 172, alignment: .leading)
                .accessibilityLabel("DataScope")
        } else {
            Label("DataScope", systemImage: "chart.bar.xaxis").font(.title2.bold())
        }
    }
}

struct ProfileView: View {
    let profile: Profile
    let sourceURL: URL
    let options: ImportOptions
    @State private var selectedColumnIDs: Set<ColumnProfile.ID> = []
    @State private var filter: RowFilter = .all
    @State private var rules: [ProfileRule] = []
    @State private var ruleRevision = 0
    @State private var detail: ColumnDetail?
    @State private var detailError: String?
    @State private var detailLoading = false

    private var selectedColumn: ColumnProfile? {
        guard let id = selectedColumnIDs.first else { return nil }
        return profile.columns.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                metric("ZEILEN", profile.rows.formatted())
                metric("SPALTEN", profile.columns.count.formatted())
                metric("LEERE / FEHLENDE ZELLEN", profile.columns.reduce(0) { $0 + $1.missing }.formatted())
                metric("LAUFZEIT", String(format: "%.2f s", profile.totalSeconds))
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Text("Spaltenprofil · alle Zeilen analysiert").font(.headline)
            Table(profile.columns, selection: $selectedColumnIDs) {
                TableColumn("Spalte", value: \.name).width(min: 120)
                TableColumn("NULL") { Text($0.nulls.formatted()) }.width(55)
                TableColumn("Leer") { Text($0.empty.formatted()) }.width(50)
                TableColumn("Whitespace") { Text($0.whitespace.formatted()) }.width(85)
                TableColumn("Verschieden") { Text($0.distinct.formatted()) }.width(85)
                TableColumn("Typ") { Text($0.dataType.displayName) }.width(100)
                TableColumn("Max. Länge") { Text($0.maximumLength.formatted()) }.width(85)
                TableColumn("Numerisch") { Text($0.numeric.formatted()) }.width(75)
                TableColumn("Min / Max / Ø") {
                    Text("\(number($0.minimum)) / \(number($0.maximum)) / \(number($0.mean))")
                }.width(min: 160)
            }.frame(minHeight: 140)
            Text("Eine Spalte auswählen, um ihr Profil zu lesen. Typ: alle befüllten Werte müssen zum selben Format passen. Datum: JJJJ-MM-TT, TT.MM.JJJJ oder TT/MM/JJJJ. IDs mit führenden Nullen bleiben Text.")
                .font(.caption).foregroundStyle(.secondary)
            if let selectedColumn {
                ColumnDetailView(column: selectedColumn, rows: profile.rows)
                ColumnAnalysisView(column: selectedColumn, headers: profile.columns.map(\.name), detail: detail, filter: $filter, rules: $rules,
                                   loading: detailLoading, error: detailError,
                                   refreshRules: { ruleRevision += 1 })
            }
            DisclosureGroup("Datenvorschau · maximal 100 Zeilen") {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { ForEach(profile.columns) { Text($0.name).bold().frame(width: 150, alignment: .leading) } }
                        ForEach(Array(profile.preview.enumerated()), id: \.offset) { _, row in
                            HStack { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell.map { $0.isEmpty ? "⟨leer⟩" : $0 } ?? "⟨NULL⟩")
                                    .lineLimit(1).frame(width: 150, alignment: .leading).help(cell ?? "NULL")
                            } }
                        }
                    }.font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(8)
                }.frame(height: 140)
            }
        }.onAppear {
            if selectedColumnIDs.isEmpty, let firstColumn = profile.columns.first {
                selectedColumnIDs = [firstColumn.id]
            }
        }.onChange(of: profile.source) { _, _ in
            selectedColumnIDs = profile.columns.first.map { [$0.id] } ?? []
            rules = []
            filter = .all
        }.onChange(of: selectedColumnIDs) { _, _ in
            rules = []
            filter = .all
            ruleRevision += 1
        }.task(id: detailTaskID) {
            await loadDetail()
        }
    }

    private var detailTaskID: String {
        "\(selectedColumn?.id ?? "")-\(filter.rawValue)-\(ruleRevision)"
    }

    private func loadDetail() async {
        guard let column = selectedColumn else { return }
        detailLoading = true
        detailError = nil
        let sourceURL = sourceURL
        let options = options
        let selectedID = column.id
        let filter = filter
        let rules = rules
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Profiler.inspect(url: sourceURL, options: options, columnName: column.name,
                                     inferredType: column.dataType, filter: filter, rules: rules)
            }.value
            guard !Task.isCancelled, selectedColumn?.id == selectedID else { return }
            detail = result
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            detailError = error.localizedDescription
            detail = nil
        }
        detailLoading = false
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
    }
    private func number(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...3))) } ?? "–"
    }
}

struct ColumnDetailView: View {
    let column: ColumnProfile
    let rows: Int

    private var populated: Int { max(0, rows - column.missing) }

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(column.name).font(.headline)
                    Text(column.dataType.displayName).foregroundStyle(.secondary)
                }.frame(minWidth: 150, alignment: .leading)
                detail("BEFÜLLT", "\(populated.formatted()) von \(rows.formatted())")
                detail("FEHLEND", column.missing.formatted())
                detail("VERSCHIEDEN", column.distinct.formatted())
                detail("MAX. LÄNGE", column.maximumLength.formatted())
                if column.numeric > 0 {
                    detail("NUMERISCH", "\(column.numeric.formatted()) von \(populated.formatted())")
                }
                Spacer(minLength: 0)
            }.padding(4)
        } label: {
            Label("Spaltendetails", systemImage: "rectangle.and.text.magnifyingglass")
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
        }
    }
}

struct ColumnAnalysisView: View {
    let column: ColumnProfile
    let headers: [String]
    let detail: ColumnDetail?
    @Binding var filter: RowFilter
    @Binding var rules: [ProfileRule]
    let loading: Bool
    let error: String?
    let refreshRules: () -> Void

    var body: some View {
        GroupBox("Werte und Auffälligkeiten") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("Zeilen", selection: $filter) {
                        ForEach(RowFilter.allCases) { Text($0.displayName).tag($0) }
                    }.frame(width: 190)
                    if loading { ProgressView().controlSize(.small) }
                    if let detail { Text("\(detail.matchingRows.formatted()) Treffer").foregroundStyle(.secondary) }
                    Spacer()
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                } else if let detail {
                    analysis(detail)
                } else if !loading {
                    ContentUnavailableView("Keine Detaildaten", systemImage: "magnifyingglass")
                }
            }.padding(4)
        }
        RuleEditor(rules: $rules, results: detail?.ruleResults ?? [], refresh: refreshRules)
    }

    @ViewBuilder private func analysis(_ detail: ColumnDetail) -> some View {
        if !detail.frequentValues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Häufigste Werte").font(.subheadline.weight(.semibold))
                ForEach(detail.frequentValues) { value in
                    HStack {
                        Text(value.value).lineLimit(1).help(value.value)
                        Spacer()
                        Text(value.count.formatted()).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !detail.textPatterns.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Textmuster · 0 = Ziffer, A = Buchstabe").font(.subheadline.weight(.semibold))
                ForEach(detail.textPatterns) { pattern in
                    HStack {
                        Text(pattern.value).lineLimit(1)
                        Spacer()
                        Text(pattern.count.formatted()).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        if let distribution = detail.numericDistribution {
            NumericDistributionView(distribution: distribution)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Betroffene Zeilen · maximal 200 angezeigt").font(.subheadline.weight(.semibold))
            if detail.rows.isEmpty {
                Text("Keine Zeilen für diesen Filter.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                        GridRow {
                            Text("Zeile").bold().frame(width: 54, alignment: .leading)
                            ForEach(0..<(detail.rows.first?.values.count ?? 0), id: \.self) { index in
                                Text(headers.indices.contains(index) ? headers[index] : "Wert \(index + 1)")
                                    .bold().frame(width: 150, alignment: .leading)
                            }
                        }
                        ForEach(detail.rows) { row in
                            GridRow {
                                Text(row.rowNumber.formatted()).frame(width: 54, alignment: .leading)
                                ForEach(row.values.indices, id: \.self) { index in
                                    Text(display(row.values[index])).lineLimit(1).help(row.values[index] ?? "NULL")
                                        .frame(width: 150, alignment: .leading)
                                }
                            }
                        }
                    }.font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }.frame(maxHeight: 180)
            }
        }
    }

    private func display(_ value: String?) -> String {
        value.map { $0.isEmpty ? "⟨leer⟩" : $0 } ?? "⟨NULL⟩"
    }
}

struct NumericDistributionView: View {
    let distribution: NumericDistribution

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Numerische Verteilung").font(.subheadline.weight(.semibold))
            HStack(spacing: 18) {
                number("Q1", distribution.firstQuartile)
                number("Median", distribution.median)
                number("Q3", distribution.thirdQuartile)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(distribution.bins.enumerated()), id: \.offset) { _, count in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.teal.opacity(0.7))
                        .frame(width: 30, height: max(5, 52 * CGFloat(count) / CGFloat(max(distribution.bins.max() ?? 1, 1))))
                        .help("\(count) Werte")
                }
            }
        }
    }

    private func number(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value.formatted(.number.precision(.fractionLength(0...3)))).monospacedDigit()
        }
    }
}

struct RuleEditor: View {
    @Binding var rules: [ProfileRule]
    let results: [RuleResult]
    let refresh: () -> Void

    var body: some View {
        GroupBox("Prüfregeln") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Menu("Regel hinzufügen", systemImage: "plus") {
                        ForEach(RuleKind.allCases) { kind in
                            Button(kind.displayName) { rules.append(ProfileRule(kind: kind)) }
                        }
                    }
                    .accessibilityLabel("Prüfregel hinzufügen")
                    Button("Regeln prüfen", systemImage: "checkmark.shield") { refresh() }
                        .disabled(rules.isEmpty)
                    Spacer()
                }
                ForEach($rules) { $rule in
                    HStack(spacing: 10) {
                        Text(rule.kind.displayName).frame(width: 132, alignment: .leading)
                        switch rule.kind {
                        case .numberRange:
                            TextField("Minimum", text: numberText($rule, \.minimum)).frame(width: 100)
                            TextField("Maximum", text: numberText($rule, \.maximum)).frame(width: 100)
                        case .matchesPattern:
                            TextField("Regex, z. B. [A-Z]{2}[0-9]+", text: $rule.pattern).frame(minWidth: 220)
                        case .required, .unique:
                            Text(rule.kind == .required ? "Leere Werte sind ungültig." : "Doppelte nichtleere Werte sind ungültig.")
                                .foregroundStyle(.secondary)
                        }
                        if let result = results.first(where: { $0.ruleID == rule.id }) {
                            Text("\(result.violations.formatted()) Verstöße").foregroundStyle(result.violations == 0 ? .green : .orange)
                        }
                        Button("Entfernen", systemImage: "trash") { rules.removeAll { $0.id == rule.id } }
                            .labelStyle(.iconOnly).help("Regel entfernen")
                    }
                }
            }.padding(4)
        }
    }

    private func numberText(_ rule: Binding<ProfileRule>, _ keyPath: WritableKeyPath<ProfileRule, Double?>) -> Binding<String> {
        Binding(get: { rule.wrappedValue[keyPath: keyPath].map { String($0) } ?? "" }, set: { value in
            rule.wrappedValue[keyPath: keyPath] = Double(value.replacingOccurrences(of: ",", with: "."))
        })
    }
}
