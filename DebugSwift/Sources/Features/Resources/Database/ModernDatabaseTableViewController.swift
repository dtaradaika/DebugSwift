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
    private var totalRowCount = 0
    private var sortColumn: String?
    private var sortAscending = true
    private var columnFilters: [String: String] = [:]
    private var hiddenColumns: Set<String> = []
    private let columnWidth: CGFloat = 140

    // MARK: - UI Components

    private lazy var mainScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = self
        return scrollView
    }()

    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        return stack
    }()

    private lazy var headerScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.isUserInteractionEnabled = false
        return scrollView
    }()

    private lazy var headerStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 0
        stack.distribution = .fill
        return stack
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(ModernGridRowCell.self, forCellReuseIdentifier: ModernGridRowCell.reuseId)
        table.separatorStyle = .singleLine
        table.separatorInset = .zero
        table.rowHeight = 50
        return table
    }()

    private lazy var toolbarView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray6
        return view
    }()

    private lazy var statsLabel: UILabel = {
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
        button.addTarget(self, action: #selector(toggleFilterBar), for: .touchUpInside)
        return button
    }()

    private lazy var refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.addTarget(self, action: #selector(refreshData), for: .touchUpInside)
        return button
    }()

    private lazy var filterBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray6
        view.isHidden = true
        return view
    }()

    private lazy var columnPickerButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Column", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14)
        button.showsMenuAsPrimaryAction = true
        return button
    }()

    private lazy var filterTextField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = "Filter value..."
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 14)
        field.clearButtonMode = .whileEditing
        field.addTarget(self, action: #selector(filterTextChanged), for: .editingChanged)
        return field
    }()

    private lazy var clearFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .systemGray
        button.addTarget(self, action: #selector(clearFilters), for: .touchUpInside)
        return button
    }()

    private lazy var pageControl: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var prevButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.addTarget(self, action: #selector(prevPage), for: .touchUpInside)
        return button
    }()

    private lazy var pageLabel: UILabel = {
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
        button.addTarget(self, action: #selector(nextPage), for: .touchUpInside)
        return button
    }()

    private var filterBarHeightConstraint: NSLayoutConstraint?
    private var contentWidthConstraint: NSLayoutConstraint?
    private var headerWidthConstraint: NSLayoutConstraint?
    private var selectedFilterColumn: String?

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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }
        guard !visibleColumns.isEmpty else { return }
        let width = CGFloat(visibleColumns.count) * columnWidth
        mainScrollView.contentSize = CGSize(width: width, height: mainScrollView.bounds.height)
    }
}

// MARK: - Setup

private extension ModernDatabaseTableViewController {
    func setup() {
        setupViews()
        setupNavigation()
    }

    func setupViews() {
        // Toolbar
        view.addSubview(toolbarView)
        toolbarView.addSubview(statsLabel)
        toolbarView.addSubview(filterButton)
        toolbarView.addSubview(refreshButton)

        // Filter bar
        view.addSubview(filterBar)
        filterBar.addSubview(columnPickerButton)
        filterBar.addSubview(filterTextField)
        filterBar.addSubview(clearFilterButton)

        // Header
        view.addSubview(headerScrollView)
        headerScrollView.addSubview(headerStackView)

        // Main content
        view.addSubview(mainScrollView)
        mainScrollView.addSubview(tableView)

        // Page control
        view.addSubview(pageControl)
        pageControl.addSubview(prevButton)
        pageControl.addSubview(pageLabel)
        pageControl.addSubview(nextButton)

        filterBarHeightConstraint = filterBar.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Toolbar
            toolbarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 44),

            statsLabel.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 16),
            statsLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -16),
            refreshButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 44),

            filterButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -8),
            filterButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            filterButton.widthAnchor.constraint(equalToConstant: 44),

            // Filter bar
            filterBar.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterBarHeightConstraint!,

            columnPickerButton.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor, constant: 8),
            columnPickerButton.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            columnPickerButton.widthAnchor.constraint(equalToConstant: 100),

            filterTextField.leadingAnchor.constraint(equalTo: columnPickerButton.trailingAnchor, constant: 8),
            filterTextField.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            filterTextField.heightAnchor.constraint(equalToConstant: 34),

            clearFilterButton.leadingAnchor.constraint(equalTo: filterTextField.trailingAnchor, constant: 8),
            clearFilterButton.trailingAnchor.constraint(equalTo: filterBar.trailingAnchor, constant: -8),
            clearFilterButton.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            clearFilterButton.widthAnchor.constraint(equalToConstant: 34),

            // Header scroll view
            headerScrollView.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            headerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerScrollView.heightAnchor.constraint(equalToConstant: 50),

            headerStackView.topAnchor.constraint(equalTo: headerScrollView.topAnchor),
            headerStackView.leadingAnchor.constraint(equalTo: headerScrollView.leadingAnchor),
            headerStackView.bottomAnchor.constraint(equalTo: headerScrollView.bottomAnchor),
            headerStackView.heightAnchor.constraint(equalTo: headerScrollView.heightAnchor),

            // Main scroll view
            mainScrollView.topAnchor.constraint(equalTo: headerScrollView.bottomAnchor),
            mainScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainScrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor),

            tableView.topAnchor.constraint(equalTo: mainScrollView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: mainScrollView.leadingAnchor),
            tableView.bottomAnchor.constraint(equalTo: mainScrollView.bottomAnchor),
            tableView.heightAnchor.constraint(equalTo: mainScrollView.heightAnchor),

            // Page control
            pageControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            pageControl.heightAnchor.constraint(equalToConstant: 44),

            prevButton.leadingAnchor.constraint(equalTo: pageControl.leadingAnchor, constant: 16),
            prevButton.centerYAnchor.constraint(equalTo: pageControl.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 44),

            pageLabel.centerXAnchor.constraint(equalTo: pageControl.centerXAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: pageControl.centerYAnchor),

            nextButton.trailingAnchor.constraint(equalTo: pageControl.trailingAnchor, constant: -16),
            nextButton.centerYAnchor.constraint(equalTo: pageControl.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 44)
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
            image: UIImage(systemName: "list.bullet.rectangle"),
            style: .plain,
            target: self,
            action: #selector(switchToClassicUI)
        )

        navigationItem.rightBarButtonItems = [moreButton, switchUIButton]
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
        totalRowCount = SQLiteManager.shared.getRowCount(from: database.path, table: table.name)
        applyFilters()

        setupHeader()
        setupColumnPicker()
        updateStats()
        updatePageControl()
        updateContentWidth()

        tableView.reloadData()
    }

    func setupHeader() {
        headerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        headerScrollView.backgroundColor = .systemGray5

        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }

        for column in visibleColumns {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false

            var title = column
            if column == sortColumn {
                title += sortAscending ? " ↑" : " ↓"
            }

            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.contentHorizontalAlignment = .left
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            button.addTarget(self, action: #selector(headerColumnTapped(_:)), for: .touchUpInside)

            button.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
            headerStackView.addArrangedSubview(button)
        }

        headerWidthConstraint?.isActive = false
        headerWidthConstraint = headerStackView.widthAnchor.constraint(equalToConstant: CGFloat(visibleColumns.count) * columnWidth)
        headerWidthConstraint?.isActive = true
    }

    func setupColumnPicker() {
        guard !columns.isEmpty else { return }

        if selectedFilterColumn == nil {
            selectedFilterColumn = columns.first
            columnPickerButton.setTitle(columns.first, for: .normal)
        }

        let actions = columns.map { column in
            UIAction(title: column, state: column == selectedFilterColumn ? .on : .off) { [weak self] _ in
                self?.selectedFilterColumn = column
                self?.columnPickerButton.setTitle(column, for: .normal)
                self?.setupColumnPicker()
            }
        }
        columnPickerButton.menu = UIMenu(children: actions)
    }

    func updateContentWidth() {
        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }
        let width = CGFloat(visibleColumns.count) * columnWidth

        contentWidthConstraint?.isActive = false
        contentWidthConstraint = tableView.widthAnchor.constraint(equalToConstant: width)
        contentWidthConstraint?.isActive = true
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
        tableView.reloadData()
        updateStats()
    }

    func updateStats() {
        let showing = filteredRows.count
        let filtered = columnFilters.isEmpty ? "" : " (filtered)"

        statsLabel.text = "\(showing)/\(totalRowCount) rows\(filtered) • \(columns.count) cols"
    }

    func updatePageControl() {
        let totalPages = max(1, (totalRowCount + pageSize - 1) / pageSize)
        pageLabel.text = "Page \(currentPage + 1) of \(totalPages)"
        prevButton.isEnabled = currentPage > 0
        nextButton.isEnabled = currentPage < totalPages - 1
    }
}

// MARK: - Actions

private extension ModernDatabaseTableViewController {
    @objc func headerColumnTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        let column = title.replacingOccurrences(of: " ↑", with: "").replacingOccurrences(of: " ↓", with: "")

        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
        currentPage = 0
        loadTableData()
    }

    @objc func toggleFilterBar() {
        let isVisible = !filterBar.isHidden
        filterBar.isHidden = isVisible
        filterBarHeightConstraint?.constant = isVisible ? 0 : 50

        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }

    @objc func refreshData() {
        loadTableData()
    }

    @objc func filterTextChanged() {
        guard let column = selectedFilterColumn else { return }
        let text = filterTextField.text ?? ""

        if text.isEmpty {
            columnFilters.removeValue(forKey: column)
        } else {
            columnFilters[column] = text
        }
        applyFilters()
    }

    @objc func clearFilters() {
        filterTextField.text = ""
        columnFilters.removeAll()
        applyFilters()
    }

    @objc func prevPage() {
        if currentPage > 0 {
            currentPage -= 1
            loadTableData()
        }
    }

    @objc func nextPage() {
        let totalPages = max(1, (table.rowCount + pageSize - 1) / pageSize)
        if currentPage < totalPages - 1 {
            currentPage += 1
            loadTableData()
        }
    }

    @objc func showMoreOptions() {
        let alert = UIAlertController(title: "Options", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Export as CSV", style: .default) { [weak self] _ in
            self?.exportData(format: .csv)
        })

        alert.addAction(UIAlertAction(title: "Export as JSON", style: .default) { [weak self] _ in
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

    func showRowOptions(at rowIndex: Int) {
        guard rowIndex < filteredRows.count else { return }

        let alert = UIAlertController(title: "Row Actions", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Copy Row", style: .default) { [weak self] _ in
            self?.copyRow(at: rowIndex)
        })

        if database.type == .sqlite {
            alert.addAction(UIAlertAction(title: "Edit Row", style: .default) { [weak self] _ in
                self?.editRow(at: rowIndex)
            })

            alert.addAction(UIAlertAction(title: "Duplicate Row", style: .default) { [weak self] _ in
                self?.duplicateRow(at: rowIndex)
            })

            alert.addAction(UIAlertAction(title: "Delete Row", style: .destructive) { [weak self] _ in
                self?.confirmDeleteRow(at: rowIndex)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController,
           let cell = tableView.cellForRow(at: IndexPath(row: rowIndex, section: 0)) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }

        present(alert, animated: true)
    }

    func copyRow(at rowIndex: Int) {
        guard rowIndex < filteredRows.count else { return }
        let row = filteredRows[rowIndex]
        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }

        var values: [String] = []
        for column in visibleColumns {
            if let index = columns.firstIndex(of: column), index < row.count {
                values.append(formatValue(row[index]))
            }
        }

        UIPasteboard.general.string = values.joined(separator: "\t")
        showToast("Row copied")
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

    func duplicateRow(at rowIndex: Int) {
        guard rowIndex < filteredRows.count else { return }

        var row = filteredRows[rowIndex]

        if let primaryKeyColumn = table.columns.first(where: { $0.isPrimaryKey }),
           let primaryKeyIndex = columns.firstIndex(of: primaryKeyColumn.name) {
            row[primaryKeyIndex] = nil
        }

        let editVC = DatabaseRowEditViewController(
            database: database,
            table: table,
            columns: columns,
            row: row,
            isNewRow: true
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
        guard rowIndex < filteredRows.count else { return }

        let row = filteredRows[rowIndex]
        let whereClause: String
        let whereValues: [Any?]

        if let primaryKeyColumn = table.columns.first(where: { $0.isPrimaryKey })?.name,
           let primaryKeyIndex = columns.firstIndex(of: primaryKeyColumn) {
            whereClause = "\"\(primaryKeyColumn)\" = ?"
            whereValues = [row[primaryKeyIndex]]
        } else {
            // No explicit PK — match all columns to identify the row
            var clauses: [String] = []
            var vals: [Any?] = []
            for (i, col) in columns.enumerated() where i < row.count {
                if row[i] == nil {
                    clauses.append("\"\(col)\" IS NULL")
                } else {
                    clauses.append("\"\(col)\" = ?")
                    vals.append(row[i])
                }
            }
            guard !clauses.isEmpty else {
                showAlert(with: "Cannot delete row: no column data")
                return
            }
            whereClause = clauses.joined(separator: " AND ")
            whereValues = vals
        }

        let result = SQLiteManager.shared.executeDelete(
            path: database.path,
            table: table.name,
            whereClause: whereClause,
            values: whereValues
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
        let alert = UIAlertController(title: "Manage Columns", message: "Toggle visibility", preferredStyle: .actionSheet)

        for column in columns {
            let isHidden = hiddenColumns.contains(column)
            let title = isHidden ? "☐ \(column)" : "☑ \(column)"

            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                if isHidden {
                    self.hiddenColumns.remove(column)
                } else if self.hiddenColumns.count < self.columns.count - 1 {
                    self.hiddenColumns.insert(column)
                }
                self.setupHeader()
                self.updateContentWidth()
                self.tableView.reloadData()
            })
        }

        alert.addAction(UIAlertAction(title: "Show All", style: .default) { [weak self] _ in
            self?.hiddenColumns.removeAll()
            self?.setupHeader()
            self?.updateContentWidth()
            self?.tableView.reloadData()
        })

        alert.addAction(UIAlertAction(title: "Done", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }

        present(alert, animated: true)
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
            toast.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -16),
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
        showToast("Data copied")
    }
}

// MARK: - UITableViewDataSource

extension ModernDatabaseTableViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ModernGridRowCell.reuseId, for: indexPath) as! ModernGridRowCell

        let visibleColumns = columns.filter { !hiddenColumns.contains($0) }
        let row = filteredRows[indexPath.row]

        var values: [Any?] = []
        for column in visibleColumns {
            if let index = columns.firstIndex(of: column), index < row.count {
                values.append(row[index])
            } else {
                values.append(nil)
            }
        }

        cell.configure(values: values, columnWidth: columnWidth, isAlternate: indexPath.row % 2 == 1)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ModernDatabaseTableViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showRowOptions(at: indexPath.row)
    }
}

// MARK: - UIScrollViewDelegate

extension ModernDatabaseTableViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == mainScrollView {
            headerScrollView.contentOffset.x = scrollView.contentOffset.x
        }
    }
}

// MARK: - DatabaseRowEditDelegate

extension ModernDatabaseTableViewController: DatabaseRowEditDelegate {
    func didSaveRow() {
        loadTableData()
    }
}

// MARK: - Modern Grid Row Cell

final class ModernGridRowCell: UITableViewCell {
    static let reuseId = "ModernGridRowCell"

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 0
        stack.distribution = .fill
        return stack
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func configure(values: [Any?], columnWidth: CGFloat, isAlternate: Bool) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        backgroundColor = isAlternate ? UIColor.systemGray6 : .systemBackground

        for value in values {
            let cellView = createCellView(for: value, width: columnWidth)
            stackView.addArrangedSubview(cellView)
        }
    }

    private func createCellView(for value: Any?, width: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail

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

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator

        container.addSubview(label)
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            separator.widthAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }
}
