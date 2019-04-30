import Foundation
import UIKit
import CoreData
import ReadingList_Foundation

class AddToExistingLists: UITableViewController {
    var resultsController: NSFetchedResultsController<List>!
    var onComplete: (() -> Void)?
    var books: Set<Book>!
    @IBOutlet private weak var doneButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        guard !books.isEmpty else { preconditionFailure() }

        let fetchRequest = NSManagedObject.fetchRequest(List.self, batch: 40)
        fetchRequest.predicate = NSPredicate.or(books.map {
            NSPredicate(format: "SELF IN %@", $0.lists).not()
        })
        fetchRequest.sortDescriptors = [NSSortDescriptor(\List.sort), NSSortDescriptor(\List.name)]
        resultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: PersistentStoreManager.container.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        resultsController.delegate = tableView
        try! resultsController.performFetch()

        monitorThemeSetting()
        setEditing(true, animated: false)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return resultsController.sections![0].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ExistingListCell", for: indexPath)
        cell.defaultInitialise(withTheme: UserDefaults.standard[.theme])

        let list = resultsController.object(at: IndexPath(row: indexPath.row, section: 0))
        cell.textLabel!.text = list.name
        cell.detailTextLabel!.text = "\(list.books.count) book\(list.books.count == 1 ? "" : "s")"

        if books.count > 1 {
            let overlapCount = getBookListOverlap(list)
            if overlapCount > 0 {
                cell.detailTextLabel!.text?.append(" (\(overlapCount) already added)")
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        updateNavigationItem()
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        updateNavigationItem()
    }

    private func updateNavigationItem() {
        if let selectedRows = tableView.indexPathsForSelectedRows, !selectedRows.isEmpty {
            navigationItem.title = selectedRows.count == 1 ? "Add To List" : "Add To \(selectedRows.count) Lists"
            navigationItem.rightBarButtonItem?.isEnabled = true
        } else {
            navigationItem.title = "Add To List"
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }

    @IBAction private func doneButtonTapped(_ sender: UIBarButtonItem) {
        guard let selectedRows = tableView.indexPathsForSelectedRows else { return }
        let bookSubject = books.count == 1 ? "this book" : "all \(books.count) books"
        let alert = UIAlertController(
            title: "Add To \(selectedRows.count == 1 ? "List" : "\(selectedRows.count) Lists")",
            message: "Are you sure you want to add \(bookSubject) to the \(selectedRows.count) selected List\(selectedRows.count == 1 ? "" : "s")?",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Add To \(selectedRows.count > 1 ? "All" : "List")", style: .default) { [unowned self] _ in
            let lists = selectedRows.map { self.resultsController.object(at: $0) }
            let bookSet = NSOrderedSet(set: self.books)
            PersistentStoreManager.container.viewContext.performAndSave {
                for list in lists {
                    list.addBooks(bookSet)
                }
            }
            self.navigationController?.dismiss(animated: true, completion: self.onComplete)
            UserEngagement.logEvent(.bulkAddBookToList)
        })

        present(alert, animated: true, completion: nil)
    }

    private func getBookListOverlap(_ list: List) -> Int {
        let listBooks = list.books.set
        let overlapSet = (books as NSSet).mutableCopy() as! NSMutableSet
        overlapSet.intersect(listBooks)
        return overlapSet.count
    }
}