import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

extension List: Sortable {
    public var sortIndex: Int32 {
        get { return sort }
        set(newValue) { sort = newValue }
    }
}

enum ListSortOrder: Int, CustomStringConvertible, CaseIterable, UserSettingType {
    case custom = 0
    case alphabetical = 1

    var description: String {
        switch self {
        case .custom: return "Custom"
        case .alphabetical: return "Alphabetical"
        }
    }
}

class Organize: SearchableEmptyStateTableViewController {

    var resultsController: NSFetchedResultsController<List>!
    var sortManager: SortManager<List>!

    override func viewDidLoad() {
        super.viewDidLoad()

        clearsSelectionOnViewWillAppear = true
        configureNavigationBarButtons()

        tableView.register(BookTableHeader.self)

        sortManager = SortManager(tableView) {
            self.resultsController.object(at: $0)
        }

        searchController = UISearchController(filterPlaceholderText: "Your Lists")
        searchController.searchResultsUpdater = self

        resultsController = buildResultsController()
        try! resultsController.performFetch()

        NotificationCenter.default.addObserver(self, selector: #selector(refetch), name: NSNotification.Name.PersistentStoreBatchOperationOccurred, object: nil)

        monitorThemeSetting()
    }

    override func configureNavigationBarButtons() {
        if !isShowingEmptyState {
            navigationItem.leftBarButtonItem = editButtonItem
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    private func buildResultsController() -> NSFetchedResultsController<List> {
        let controller = NSFetchedResultsController<List>(fetchRequest: fetchRequest(), managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        controller.delegate = self
        return controller
    }

    private func fetchRequest() -> NSFetchRequest<List> {
        let fetchRequest = NSManagedObject.fetchRequest(List.self, batch: 25)
        var sortDescriptors = [NSSortDescriptor(\List.name)]
        switch UserDefaults.standard[.listSortOrder] {
        case .custom:
            sortDescriptors.insert(NSSortDescriptor(\List.sort), at: 0)
        case .alphabetical:
            break
        }
        fetchRequest.sortDescriptors = sortDescriptors
        return fetchRequest
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        searchController.searchBar.isEnabled = !editing
        reloadHeaders()
    }

    @objc func refetch() {
        try! resultsController.performFetch()
        tableView.reloadData()
    }

    override func sectionCount(in tableView: UITableView) -> Int {
        return resultsController.sections!.count
    }

    override func rowCount(in tableView: UITableView, forSection section: Int) -> Int {
        return resultsController.sections![section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ListCell", for: indexPath)
        let list = resultsController.object(at: indexPath)
        cell.textLabel!.text = list.name
        cell.detailTextLabel!.text = "\(list.books.count) book\(list.books.count == 1 ? "" : "s")"
        if #available(iOS 13.0, *) { } else {
            cell.defaultInitialise(withTheme: UserDefaults.standard[.theme])
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 0 && tableView.numberOfRows(inSection: 0) > 0 else { return nil }
        let header = tableView.dequeue(BookTableHeader.self)
        configureHeader(header, at: section)
        header.onSortButtonTap = { [unowned self] button in
            let alert = UIAlertController.selectOption(ListSortOrder.allCases, title: "Choose Order", selected: UserDefaults.standard[.listSortOrder]) { [unowned self] sortOrder in
                UserDefaults.standard[.listSortOrder] = sortOrder
                self.resultsController = self.buildResultsController()
                try! self.resultsController.performFetch()
                tableView.reloadData()
            }
            alert.popoverPresentationController?.setButton(button)
            self.present(alert, animated: true)
        }
        return header
    }

    private func renameList(_ list: List) {
        let existingListNames = List.names(fromContext: PersistentStoreManager.container.viewContext)
        let renameListAlert = TextBoxAlert(title: "Rename List", message: "Choose a new name for this list", initialValue: list.name, placeholder: "New list name", keyboardAppearance: UserDefaults.standard[.theme].keyboardAppearance, textValidator: { listName in
                guard let listName = listName, !listName.isEmptyOrWhitespace else { return false }
                return listName == list.name || !existingListNames.contains(listName)
            }, onOK: {
                guard let listName = $0 else { return }
                UserEngagement.logEvent(.renameList)
                list.managedObjectContext!.performAndSave {
                    list.name = listName
                }
            }
        )

        self.present(renameListAlert, animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return UISwipeActionsConfiguration(performFirstActionWithFullSwipe: false, actions: [
            UIContextualAction(style: .destructive, title: "Delete") { _, _, callback in
                self.deleteList(forRowAt: indexPath)
                // We never perform the deletion right-away
                callback(false)
            },
            UIContextualAction(style: .normal, title: "Rename") { _, _, callback in
                self.setEditing(false, animated: true)
                let list = self.resultsController.object(at: indexPath)
                self.renameList(list)
                callback(true)
            }
        ])
    }

    @IBAction private func addWasTapped(_ sender: UIBarButtonItem) {
        present(ManageLists.newListAlertController([]) { [unowned self] list in
            guard let indexPath = self.resultsController.indexPath(forObject: list) else {
                assertionFailure()
                return
            }
            self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        }, animated: true)
    }

    func deleteList(forRowAt indexPath: IndexPath) {
        let confirmDelete = UIAlertController(title: "Confirm delete", message: nil, preferredStyle: .actionSheet)

        confirmDelete.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.resultsController.object(at: indexPath).deleteAndSave()
            UserEngagement.logEvent(.deleteList)
            self.setEditing(false, animated: true)

            // When the table goes from 1 row to 0 rows in the single section, the section header remains unless the table is reloaded
            if self.tableView.numberOfRows(inSection: 0) == 0 {
                self.tableView.reloadData()
            }
        })
        confirmDelete.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        confirmDelete.popoverPresentationController?.setSourceCell(atIndexPath: indexPath, inTable: tableView)
        present(confirmDelete, animated: true, completion: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let listBookTable = segue.destination as? ListBookTable {
            let list: List
            if let index = sender as? IndexPath {
                list = resultsController.object(at: index)
            } else if let cell = sender as? UITableViewCell, let index = tableView.indexPath(for: cell) {
                list = resultsController.object(at: index)
            } else { preconditionFailure() }

            listBookTable.list = list

            // If the search bar is visible on this view, then it should be visible on the presented view too to
            // prevent an animation issue from occuring (https://stackoverflow.com/a/55043782/5513562) on iOS <13.
            if #available(iOS 13.0, *) { /* issue is fixed */ } else {
                listBookTable.showSearchBarOnAppearance = !searchController.isActive && searchController.searchBar.frame.height > 0 && !list.books.isEmpty
            }
        }
    }

    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        // No segue in edit mode
        return !tableView.isEditing
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard UserDefaults.standard[.listSortOrder] == .custom else { return false }
        return resultsController.sections![0].numberOfObjects > 1
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard UserDefaults.standard[.listSortOrder] == .custom else {
            assertionFailure()
            return
        }
        resultsController.delegate = nil
        sortManager.move(objectAt: sourceIndexPath, to: destinationIndexPath)
        try! resultsController.performFetch()
        PersistentStoreManager.container.viewContext.saveAndLogIfErrored()
        resultsController.delegate = tableView
    }

    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // the PreviewProvider doesn't seem to work when instantiating the ListBookTable - all the cells become really
        // big, and that persists when you open from the preview.
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                    let list = self.resultsController.object(at: indexPath)
                    self.renameList(list)
                },
                UIAction(title: "Delete", image: UIImage(systemName: "trash.fill"), attributes: .destructive) { _ in
                    self.deleteList(forRowAt: indexPath)
                }
            ])
        }
    }

    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let indexPath = configuration.identifier as? IndexPath else { return }
        animator.addAnimations {
            self.performSegue(withIdentifier: "selectList", sender: indexPath)
        }
    }

    override func titleForNonSearchEmptyState() -> String {
         return NSLocalizedString("OrganizeEmptyHeader", comment: "")
    }

    override func textForSearchEmptyState() -> NSAttributedString {
        return NSMutableAttributedString("Try changing your search, or add a new list by tapping the ", font: emptyStateDescriptionFont)
                .appending("+", font: emptyStateDescriptionBoldFont)
                .appending(" button.", font: emptyStateDescriptionFont)

    }

    override func textForNonSearchEmptyState() -> NSAttributedString {
        return NSMutableAttributedString(NSLocalizedString("OrganizeInstruction", comment: ""), font: emptyStateDescriptionFont)
            .appending("\n\nTo create a new list, tap the ", font: emptyStateDescriptionFont)
            .appending("+", font: emptyStateDescriptionBoldFont)
            .appending(" button above, or tap ", font: emptyStateDescriptionFont)
            .appending("Manage Lists", font: emptyStateDescriptionBoldFont)
            .appending(" when viewing a book.", font: emptyStateDescriptionFont)
    }
}

extension Organize: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
        reloadHeaders()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        tableView.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
}

extension Organize: HeaderConfigurable {
    func configureHeader(_ header: UITableViewHeaderFooterView, at index: Int) {
        guard let header = header as? BookTableHeader else { preconditionFailure() }
        let numberOfRows = tableView.numberOfRows(inSection: index)
        if numberOfRows == 0 {
            header.removeFromSuperview()
        } else {
            header.configure(labelText: "YOUR LISTS", enableSort: !isEditing && !searchController.isActive)
        }
    }
}

extension Organize: UISearchResultsUpdating {
    func predicate(forSearchText searchText: String?) -> NSPredicate {
        if let searchText = searchText, !searchText.isEmptyOrWhitespace && searchText.trimming().count >= 2 {
            return NSPredicate(fieldName: #keyPath(List.name), containsSubstring: searchText)
        }
        return NSPredicate(boolean: true) // If we cannot filter with the search text, we should return all results
    }

    func updateSearchResults(for searchController: UISearchController) {
        let searchTextPredicate = self.predicate(forSearchText: searchController.searchBar.text)

        if resultsController.fetchRequest.predicate != searchTextPredicate {
            resultsController.fetchRequest.predicate = searchTextPredicate
            try! resultsController.performFetch()
        }
        tableView.reloadData()
    }
}

extension Organize: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchWillBeDismissed()
    }
}
