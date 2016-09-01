//
//  ViewController.swift
//  Swift3MIDI
//
//  Created by Gene De Lisa on 7/24/16.
//  Copyright © 2016 Gene De Lisa. All rights reserved.
//

import UIKit
import os.log

class ViewController: UIViewController {

    static let uiLog = OSLog(subsystem: "com.rockhoppertech.Swift3MIDI", category: "UI")

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func playAction(_ sender: UIButton) {
        os_log("playing with MusicPlayer", log: ViewController.uiLog, type: .info)
        
        MIDIManager.sharedInstance.playWithMusicPlayer()
    }

}

