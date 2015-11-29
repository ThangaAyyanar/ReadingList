//
//  BookDetailsViewController.swift
//  books
//
//  Created by Andrew Bennet on 09/11/2015.
//  Copyright © 2015 Andrew Bennet. All rights reserved.
//

import Foundation
import UIKit
import CoreData

class BookDetailsViewController: UIViewController{
    
    var book: Book!
    lazy var booksStore = appDelegate().booksStore
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var authorLabel: UILabel!
    @IBOutlet weak var imageView: UIImageView!
    
    override func viewDidLoad() {
        titleLabel.text = book.title
        authorLabel.text = book.authorListString
        if let coverImg = book.coverImage {
            imageView.image = UIImage(data: coverImg)
        }
    }
    
    @IBAction func deleteIsPressed(sender: AnyObject) {
        // Delete the book and go back a page
        booksStore.deleteBook(book)
        booksStore.save()
        
        navigationController?.popViewControllerAnimated(true)
    }
}