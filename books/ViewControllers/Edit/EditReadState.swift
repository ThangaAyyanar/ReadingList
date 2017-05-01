//
//  EditReadState.swift
//  books
//
//  Created by Andrew Bennet on 25/05/2016.
//  Copyright © 2016 Andrew Bennet. All rights reserved.
//

import Foundation
import UIKit

class EditReadState: ReadStateForm {
    
    var bookToEdit: Book!
    
    @IBOutlet weak var doneButton: UIBarButtonItem!

    override func viewDidLoad(){
        super.viewDidLoad()
        
        navigationItem.title = bookToEdit.title
        
        // Load the existing values on to the form; if dates are missing, use the current date
        // if the date entry field becomes visible
        readState = bookToEdit.readState
        if let started = bookToEdit.startedReading {
            startedReading = started
        }
        if let finished = bookToEdit.finishedReading {
            finishedReading = finished
        }
    }
    
    override func formValidated(isValid: Bool) {
        doneButton.isEnabled = isValid
    }
    
    @IBAction func doneWasPressed(_ sender: UIBarButtonItem) {
        self.view.endEditing(true)
        
        // Create an object representation of the form values
        let newReadStateInfo = BookReadingInformation(readState: readState, startedWhen: startedReading, finishedWhen: finishedReading)
        
        // Update the book
        appDelegate.booksStore.update(book: bookToEdit, withReadingInformation: newReadStateInfo)
        
        self.navigationController?.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func cancelWasPressed(_ sender: UIBarButtonItem) {
        // Just exit
        self.view.endEditing(true)
        self.navigationController?.dismiss(animated: true, completion: nil)
    }
}
