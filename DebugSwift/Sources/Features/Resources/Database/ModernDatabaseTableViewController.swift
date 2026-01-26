//
//  ModernDatabaseTableViewController.swift
//  DebugSwift
//
//  Modern grid-based database table viewer with enhanced QA features
//

import UIKit

@MainActor
final class ModernDatabaseTableViewController: BaseController {

    // MARK: - Properties

    private let database: DatabaseFile
    private let table: DatabaseTable
    private var columns: [String] = []
    private var allRows: [[Any?]] = []
    private var filteredRows: [[Any?]] = []
    private var currentPage = 0
    private let pageSize = 100
    private var sortColumn: String?
    private var sortAscending = true
    private var columnFilters: [String: String] = [:]
    private var hiddenColumns: Set<String> = []
    private var selectedRows: Set<Int> = []

    // MARK: - UI Components

    private lazy var collectionView: UICollectionView = {
        let layout = createGridLayout()
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.delegate = self
        collection.dataSource = self
        collection.backgroundColor = .systemBackground
        collection.allowsMultipleSelection = true
        collection.register(ModernDataCell.self, forCellWithReuseIdentifier: ModernDataCell.reuseId)
        collection.register(
            ModernHeaderCell.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: ModernHeaderCell.reuseId
        )
        return collection
    }()

    private lazy var toolbarView: ModernToolbarView = {
        let toolbar = ModernToolbarView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.delegate = self
        return toolbar
    }()

    private lazy var filterBar: ModernFilterBarView = {
        let bar = ModernFilterBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.delegate = self
        bar.isHidden = true
        return bar
    }()

    private lazy var statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var pageControl: ModernPageControl = {
        let control = ModernPageControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.delegate = self
        return control
    }()

    private var filterBarHeightConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    init(database: DatabaseFile, table: DatabaseTable) {
        self.database = database
        self.table = table
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        loadTableData()
    }

    // MARK: - Layout

    private func createGridLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self = self else { return nil }

            let visibleColumnCount = max(1, self.columns.count - self.hiddenColumns.count)
            let columnWidth: CGFloat = 140

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(columnWidth),
                heightDimension: .absolute(50)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .absolute(CGFloat(visibleColumnCount) * columnWidth),
                heightDimension: .absolute(50)
            )

            // Use the subitem array API which is available on older iOS versions
            let subitems = Array(repeating: item, count: visibleColumnCount)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: subitems)

            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous

            let headerSize = NSCollectionLayoutSize(
                widthDimension: .absolute(CGFloat(visibleColumnCount) * columnWidth),
                heightDimension: .absolute(60)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]

            return section
        }
    }
}

// MARK: - Setup

private extension ModernDatabaseTableViewController {
    func setup() {
        setupViews()
        setupNavigation()
        setupGestures()
    }

    func setupViews() {
        view.addSubview(toolbarView)
        view.addSubview(filterBar)
        view.addSubview(collectionView)
        view.addSubview(statsLabel)
        view.addSubview(pageControl)

        filterBarHeightConstraint = filterBar.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 44),

            filterBar.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterBarHeightConstraint!,

            collectionView.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            statsLabel.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 4),
            statsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            pageControl.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 4),
            pageControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            pageControl.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    func setupNavigation() {
        title = table.name

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(showMoreOptions)
        )

        let switchUIButton = UIBarButtonItem(
            image: UIImage(systemName: "rectangle.split.3x3"),
            style: .plain,
            target: self,
            action: #selector(switchToClassicUI)
        )

        navigationItem.rightBarButtonItems = [moreButton, switchUIButton]
    }

    func setupGestures() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        collectionView.addGestureRecognizer(longPress)
    }

    func loadTableData() {
        let result = SQLiteManager.shared.getTableData(
            from: database.path,
            table: table.name,
            limit: pageSize,
            offset: currentPage * pageSize,
            orderBy: sortColumn,
            ascending: sortAscending
        )

        columns = result.columns
        allRows = result.rows
        applyFilters()

        toolbarView.configure(rowCount: table.rowCount, columnCount: columns.count)
        filterBar.configure(with: columns)
        updateStats()
        updatePageControl()

        collectionView.collectionViewLayout = createGridLayout()
        collectionView.reloadData()
    }

    func applyFilters() {
        if columnFilters.isEmpty {
            filteredRows = allRows
        } else {
            filteredRows = allRows.filter { row in
                for (column, filterText) in columnFilters {
                    guard let columnIndex = columns.firstIndex(of: column),
                          columnIndex < row.count else { continue }

                    let value = row[columnIndex]
                    let stringValue: String
                    if let v = value {
                        stringValue = "\(v)".lowercased()
                    } else {
                        stringValue = "null"
                    }

                    if !stringValue.contains(filterText.lowercased()) {
                        return false
                    }
                }
                return true
            }
        }
        collectionView.reloadData()
        updateStats()
    }

    func updateStats() {
        let totalRows = table.rowCount
        let showing = filteredRows.count
        let filtered = columnFilters.isEmpty ? "" : " (filtered)"
        let page = currentPage + 1
        let totalPages = max(1, (totalRows + pageSize - 1) / pageSize)

        statsLabel.text = "Showing \(showing) of \(totalRows) rows\(filtered) | Page \(page)/\(totalPages)"
    }

    func updatePageControl() {
        let totalPages = max(1, (table.rowCount + pageSize - 1) / pageSize)
        pageControl.configure(currentPage: currentPage, totalPages: totalPages)
    }
}

// MARK: - Actions

private extension ModernDatabaseTableViewController {
    @objc func showMoreOptions() {
        let alert = UIAlertController(title: "Options", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Export Visible Data (CSV)", style: .default) { [weak self] _ in
            self?.exportData(format: .csv)
        })

        alert.addAction(UIAlertAction(title: "Export Visible Data (JSON)", style: .default) { [weak self] _ in
            self?.exportData(format: .json)
        })

        alert.addAction(UIAlertAction(title: "Copy All Data", style: .default) { [weak self] _ in
            self?.copyAllData()
        })

        if database.type == .sqlite {
            alert.addAction(UIAlertAction(title: "SQL Query Editor", style: .default) { [weak self] _ in
                self?.openSQLEditor()
            })

            alert.addAction(UIAlertAction(title: "Add New Row", style: .default) { [weak self] _ in
                self?.addNewRow()
            })
        }

        alert.addAction(UIAlertAction(title: "Manage Columns", style: .default) { [weak self] _ in
            self?.showColumnManager()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }

        present(alert, animated: true)
    }

    @objc func switchToClassicUI() {
        DebugSwift.Database.shared.viewerMode = .classic

        let classicVC = DatabaseTableViewController(database: database, table: table)

        guard let navController = navigationController else { return }
        var viewControllers = navController.viewControllers
        if let index = viewControllers.firstIndex(of: self) {
            viewControllers[index] = classicVC
            navController.setViewControllers(viewControllers, animated: false)
        }
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        let point = gesture.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point) {
            showCellOptions(at: indexPath)
        }
    }

    func showCellOptions(at indexPath: IndexPath) {
        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }
        let columnIndex = indexPath.item % visibleColumns.count
        let rowIndex = indexPath.item / visibleColumns.count

        guard rowIndex < filteredRows.count else { return }

        let column = visibleColumns[columnIndex]
        let actualColumnIndex = columns.firstIndex(of: column) ?? columnIndex
        let value = filteredRows[rowIndex][actualColumnIndex]

        let alert = UIAlertController(
            title: column,
            message: formatValue(value),
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Copy Value", style: .default) { [weak self] _ in
            UIPasteboard.general.string = self?.formatValue(value) ?? ""
            self?.showToast("Copied to clipboard")
        })

        alert.addAction(UIAlertAction(title: "Filter by This Value", style: .default) { [weak self] _ in
            self?.columnFilters[column] = self?.formatValue(value) ?? ""
            self?.applyFilters()
            self?.showFilterBar(true)
        })

        if database.type == .sqlite {
            alert.addAction(UIAlertAction(title: "Edit Row", style: .default) { [weak self] _ in
                self?.editRow(at: rowIndex)
            })

            alert.addAction(UIAlertAction(title: "Delete Row", style: .destructive) { [weak self] _ in
                self?.confirmDeleteRow(at: rowIndex)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            if let cell = collectionView.cellForItem(at: indexPath) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            }
        }

        present(alert, animated: true)
    }

    func editRow(at rowIndex: Int) {
        guard rowIndex < filteredRows.count else { return }

        let row = filteredRows[rowIndex]
        let editVC = DatabaseRowEditViewController(
            database: database,
            table: table,
            columns: columns,
            row: row,
            isNewRow: false
        )
        editVC.delegate = self
        let navController = UINavigationController(rootViewController: editVC)
        present(navController, animated: true)
    }

    func confirmDeleteRow(at rowIndex: Int) {
        let alert = UIAlertController(
            title: "Delete Row",
            message: "Are you sure you want to delete this row?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteRow(at: rowIndex)
        })

        present(alert, animated: true)
    }

    func deleteRow(at rowIndex: Int) {
        guard let primaryKeyColumn = table.columns.first(where: { $0.isPrimaryKey })?.name,
              let primaryKeyIndex = columns.firstIndex(of: primaryKeyColumn),
              rowIndex < filteredRows.count else {
            showAlert(with: "Cannot delete row without primary key")
            return
        }

        let row = filteredRows[rowIndex]
        guard let primaryKeyValue = row[primaryKeyIndex] else {
            showAlert(with: "Primary key value is missing")
            return
        }

        let whereClause = "\(primaryKeyColumn) = ?"
        let result = SQLiteManager.shared.executeDelete(
            path: database.path,
            table: table.name,
            whereClause: whereClause,
            values: [primaryKeyValue]
        )

        switch result {
        case .update(let affectedRows):
            if affectedRows > 0 {
                loadTableData()
                showToast("Row deleted")
            } else {
                showAlert(with: "No rows were deleted")
            }
        case .error(let message):
            showAlert(with: "Error: \(message)")
        default:
            break
        }
    }

    func addNewRow() {
        let addVC = DatabaseRowEditViewController(
            database: database,
            table: table,
            columns: columns,
            row: nil,
            isNewRow: true
        )
        addVC.delegate = self
        let navController = UINavigationController(rootViewController: addVC)
        present(navController, animated: true)
    }

    func openSQLEditor() {
        let queryVC = SQLQueryViewController(database: database)
        let navController = UINavigationController(rootViewController: queryVC)
        present(navController, animated: true)
    }

    func showColumnManager() {
        let alert = UIAlertController(title: "Manage Columns", message: "Toggle column visibility", preferredStyle: .actionSheet)

        for column in columns {
            let isHidden = hiddenColumns.contains(column)
            let title = isHidden ? "☐ \(column)" : "☑ \(column)"

            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                if isHidden {
                    self?.hiddenColumns.remove(column)
                } else if self?.hiddenColumns.count ?? 0 < (self?.columns.count ?? 1) - 1 {
                    self?.hiddenColumns.insert(column)
                }
                self?.collectionView.collectionViewLayout = self?.createGridLayout() ?? UICollectionViewFlowLayout()
                self?.collectionView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Show All", style: .default) { [weak self] _ in
            self?.hiddenColumns.removeAll()
            self?.collectionView.collectionViewLayout = self?.createGridLayout() ?? UICollectionViewFlowLayout()
            self?.collectionView.reloadData()
        })

        alert.addAction(UIAlertAction(title: "Done", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }

        present(alert, animated: true)
    }

    func showFilterBar(_ show: Bool) {
        filterBar.isHidden = !show
        filterBarHeightConstraint?.constant = show ? 50 : 0

        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }

    func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "NULL" }

        if let data = value as? Data {
            if let jsonString = data.toJSONString() {
                return jsonString
            }
            return "<BLOB \(data.count) bytes>"
        }

        return "\(value)"
    }

    func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.textAlignment = .center
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toast.textColor = .white
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            toast.heightAnchor.constraint(equalToConstant: 36)
        ])

        toast.alpha = 0
        UIView.animate(withDuration: 0.2) {
            toast.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            UIView.animate(withDuration: 0.2) {
                toast.alpha = 0
            } completion: { _ in
                toast.removeFromSuperview()
            }
        }
    }
}

// MARK: - Export

private extension ModernDatabaseTableViewController {
    enum ExportFormat {
        case csv
        case json
    }

    func exportData(format: ExportFormat) {
        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }

        var exportString: String

        switch format {
        case .csv:
            exportString = exportAsCSV(columns: visibleColumns)
        case .json:
            exportString = exportAsJSON(columns: visibleColumns)
        }

        let activityVC = UIActivityViewController(activityItems: [exportString], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }

        present(activityVC, animated: true)
    }

    func exportAsCSV(columns: [String]) -> String {
        var csv = columns.joined(separator: ",") + "\n"

        for row in filteredRows {
            var rowValues: [String] = []
            for column in columns {
                if let index = self.columns.firstIndex(of: column), index < row.count {
                    let value = formatValue(row[index])
                    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                    rowValues.append("\"\(escaped)\"")
                }
            }
            csv += rowValues.joined(separator: ",") + "\n"
        }

        return csv
    }

    func exportAsJSON(columns: [String]) -> String {
        var jsonArray: [[String: Any]] = []

        for row in filteredRows {
            var dict: [String: Any] = [:]
            for column in columns {
                if let index = self.columns.firstIndex(of: column), index < row.count {
                    if let value = row[index] {
                        if let data = value as? Data, let jsonString = data.toJSONString() {
                            dict[column] = jsonString
                        } else {
                            dict[column] = value
                        }
                    } else {
                        dict[column] = NSNull()
                    }
                }
            }
            jsonArray.append(dict)
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "[]"
    }

    func copyAllData() {
        let csv = exportAsCSV(columns: columns.filter { !hiddenColumns.contains($0) })
        UIPasteboard.general.string = csv
        showToast("Data copied to clipboard")
    }
}

// MARK: - UICollectionViewDataSource

extension ModernDatabaseTableViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let visibleColumnCount = columns.count - hiddenColumns.count
        return filteredRows.count * visibleColumnCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ModernDataCell.reuseId, for: indexPath) as! ModernDataCell

        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }
        let columnIndex = indexPath.item % visibleColumns.count
        let rowIndex = indexPath.item / visibleColumns.count

        if rowIndex < filteredRows.count {
            let column = visibleColumns[columnIndex]
            let actualColumnIndex = columns.firstIndex(of: column) ?? columnIndex
            let value = filteredRows[rowIndex][actualColumnIndex]
            cell.configure(value: value, isAlternateRow: rowIndex % 2 == 1)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: ModernHeaderCell.reuseId,
            for: indexPath
        ) as! ModernHeaderCell

        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }
        header.configure(columns: visibleColumns, sortColumn: sortColumn, sortAscending: sortAscending)
        header.delegate = self

        return header
    }
}

// MARK: - UICollectionViewDelegate

extension ModernDatabaseTableViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        showCellOptions(at: indexPath)
    }
}

// MARK: - Delegate Conformances

extension ModernDatabaseTableViewController: ModernToolbarDelegate {
    func toolbarDidTapFilter() {
        let isVisible = !filterBar.isHidden
        showFilterBar(!isVisible)
    }

    func toolbarDidTapRefresh() {
        loadTableData()
    }

    func toolbarDidTapSearch() {
        // Search functionality through filter bar
        showFilterBar(true)
    }
}

extension ModernDatabaseTableViewController: ModernFilterBarDelegate {
    func filterBar(_ filterBar: ModernFilterBarView, didUpdateFilter filter: String, forColumn column: String) {
        if filter.isEmpty {
            columnFilters.removeValue(forKey: column)
        } else {
            columnFilters[column] = filter
        }
        applyFilters()
    }

    func filterBarDidClearAll(_ filterBar: ModernFilterBarView) {
        columnFilters.removeAll()
        applyFilters()
        showFilterBar(false)
    }
}

extension ModernDatabaseTableViewController: ModernPageControlDelegate {
    func pageControl(_ control: ModernPageControl, didChangeTo page: Int) {
        currentPage = page
        loadTableData()
    }
}

extension ModernDatabaseTableViewController: ModernHeaderDelegate {
    func header(_ header: ModernHeaderCell, didTapColumn column: String) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
        currentPage = 0
        loadTableData()
    }
}

extension ModernDatabaseTableViewController: DatabaseRowEditDelegate {
    func didSaveRow() {
        loadTableData()
    }
}

// MARK: - Modern Data Cell

final class ModernDataCell: UICollectionViewCell {
    static let reuseId = "ModernDataCell"

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let separatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.addSubview(label)
        contentView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            separatorView.widthAnchor.constraint(equalToConstant: 1)
        ])
    }

    func configure(value: Any?, isAlternateRow: Bool) {
        backgroundColor = isAlternateRow ? UIColor.systemGray6 : .systemBackground

        if let value = value {
            if let data = value as? Data {
                if let jsonString = data.toJSONString() {
                    label.text = jsonString
                    label.textColor = .systemBlue
                } else {
                    label.text = "<BLOB \(data.count)b>"
                    label.textColor = .systemGray
                }
            } else {
                label.text = "\(value)"
                label.textColor = .label
            }
        } else {
            label.text = "NULL"
            label.textColor = .systemOrange
        }
    }
}

// MARK: - Modern Header Cell

@MainActor
protocol ModernHeaderDelegate: AnyObject {
    func header(_ header: ModernHeaderCell, didTapColumn column: String)
}

final class ModernHeaderCell: UICollectionReusableView {
    static let reuseId = "ModernHeaderCell"

    weak var delegate: ModernHeaderDelegate?
    private var columns: [String] = []

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemGray5
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(columns: [String], sortColumn: String?, sortAscending: Bool) {
        self.columns = columns
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, column) in columns.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index

            var title = column
            if column == sortColumn {
                title += sortAscending ? " ↑" : " ↓"
            }

            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.contentHorizontalAlignment = .left
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            button.addTarget(self, action: #selector(columnTapped(_:)), for: .touchUpInside)

            stackView.addArrangedSubview(button)
        }
    }

    @objc private func columnTapped(_ sender: UIButton) {
        let column = columns[sender.tag]
        delegate?.header(self, didTapColumn: column)
    }
}

// MARK: - Modern Toolbar View

@MainActor
protocol ModernToolbarDelegate: AnyObject {
    func toolbarDidTapFilter()
    func toolbarDidTapRefresh()
    func toolbarDidTapSearch()
}

final class ModernToolbarView: UIView {
    weak var delegate: ModernToolbarDelegate?

    private let statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var filterButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "line.3.horizontal.decrease.circle"), for: .normal)
        button.addTarget(self, action: #selector(filterTapped), for: .touchUpInside)
        return button
    }()

    private lazy var refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemGray6

        addSubview(statsLabel)
        addSubview(filterButton)
        addSubview(refreshButton)

        NSLayoutConstraint.activate([
            statsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 44),

            filterButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -8),
            filterButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            filterButton.widthAnchor.constraint(equalToConstant: 44)
        ])
    }

    func configure(rowCount: Int, columnCount: Int) {
        statsLabel.text = "\(rowCount) rows × \(columnCount) columns"
    }

    @objc private func filterTapped() {
        delegate?.toolbarDidTapFilter()
    }

    @objc private func refreshTapped() {
        delegate?.toolbarDidTapRefresh()
    }
}

// MARK: - Modern Filter Bar View

@MainActor
protocol ModernFilterBarDelegate: AnyObject {
    func filterBar(_ filterBar: ModernFilterBarView, didUpdateFilter filter: String, forColumn column: String)
    func filterBarDidClearAll(_ filterBar: ModernFilterBarView)
}

final class ModernFilterBarView: UIView {
    weak var delegate: ModernFilterBarDelegate?
    private var columns: [String] = []
    private var selectedColumn: String?

    private let columnPicker: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Column", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14)
        return button
    }()

    private let filterTextField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = "Filter value..."
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 14)
        field.clearButtonMode = .whileEditing
        return field
    }()

    private lazy var clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .systemGray
        button.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemGray6

        addSubview(columnPicker)
        addSubview(filterTextField)
        addSubview(clearButton)

        filterTextField.addTarget(self, action: #selector(filterChanged), for: .editingChanged)

        NSLayoutConstraint.activate([
            columnPicker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            columnPicker.centerYAnchor.constraint(equalTo: centerYAnchor),
            columnPicker.widthAnchor.constraint(equalToConstant: 100),

            filterTextField.leadingAnchor.constraint(equalTo: columnPicker.trailingAnchor, constant: 8),
            filterTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            filterTextField.heightAnchor.constraint(equalToConstant: 34),

            clearButton.leadingAnchor.constraint(equalTo: filterTextField.trailingAnchor, constant: 8),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 34)
        ])

        setupColumnPicker()
    }

    private func setupColumnPicker() {
        columnPicker.showsMenuAsPrimaryAction = true
        updateColumnPickerMenu()
    }

    private func updateColumnPickerMenu() {
        let actions = columns.map { column in
            UIAction(title: column, state: column == selectedColumn ? .on : .off) { [weak self] _ in
                self?.selectedColumn = column
                self?.columnPicker.setTitle(column, for: .normal)
                self?.updateColumnPickerMenu()
                if let text = self?.filterTextField.text, !text.isEmpty {
                    self?.delegate?.filterBar(self!, didUpdateFilter: text, forColumn: column)
                }
            }
        }
        columnPicker.menu = UIMenu(children: actions)
    }

    func configure(with columns: [String]) {
        self.columns = columns
        if let first = columns.first {
            selectedColumn = first
            columnPicker.setTitle(first, for: .normal)
        }
        updateColumnPickerMenu()
    }

    @objc private func filterChanged() {
        guard let column = selectedColumn else { return }
        delegate?.filterBar(self, didUpdateFilter: filterTextField.text ?? "", forColumn: column)
    }

    @objc private func clearTapped() {
        filterTextField.text = ""
        delegate?.filterBarDidClearAll(self)
    }
}

// MARK: - Modern Page Control

@MainActor
protocol ModernPageControlDelegate: AnyObject {
    func pageControl(_ control: ModernPageControl, didChangeTo page: Int)
}

final class ModernPageControl: UIView {
    weak var delegate: ModernPageControlDelegate?
    private var currentPage = 0
    private var totalPages = 1

    private lazy var prevButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        return button
    }()

    private let pageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        return label
    }()

    private lazy var nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        button.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        addSubview(prevButton)
        addSubview(pageLabel)
        addSubview(nextButton)

        NSLayoutConstraint.activate([
            prevButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 44),

            pageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 44)
        ])
    }

    func configure(currentPage: Int, totalPages: Int) {
        self.currentPage = currentPage
        self.totalPages = totalPages

        pageLabel.text = "Page \(currentPage + 1) of \(totalPages)"
        prevButton.isEnabled = currentPage > 0
        nextButton.isEnabled = currentPage < totalPages - 1
    }

    @objc private func prevTapped() {
        if currentPage > 0 {
            delegate?.pageControl(self, didChangeTo: currentPage - 1)
        }
    }

    @objc private func nextTapped() {
        if currentPage < totalPages - 1 {
            delegate?.pageControl(self, didChangeTo: currentPage + 1)
        }
    }
}
