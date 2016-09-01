//
//  MIDIManager.swift
//  SwiftMIDIThru
//
//  Created by Gene De Lisa on 7/22/16.
//  Copyright © 2015 Gene De Lisa. All rights reserved.
//

import Foundation
import CoreMIDI
import CoreAudio
import AudioToolbox

import AVFoundation
import os.log


/// The `Singleton` instance
private let MIDIManagerInstance = MIDIManager()


/**
 # MIDIManager
 
 > Here is an initial cut at using the new Swift 3.0 MIDI frobs.
 
 */
class MIDIManager : NSObject {
    
    class var sharedInstance:MIDIManager {
        return MIDIManagerInstance
    }
    
    static let midiLog = OSLog(subsystem: "com.rockhoppertech.Swift3MIDI", category: "MIDI")

    
    var sequencer:AVAudioSequencer!
    
    
    var midiClient = MIDIClientRef()
    
    var outputPort = MIDIPortRef()
    
    var inputPort = MIDIPortRef()
    
    var virtualSourceEndpointRef = MIDIEndpointRef()
    
    var virtualDestinationEndpointRef = MIDIEndpointRef()
    
    var midiInputPortref = MIDIPortRef()
    
    var musicPlayer:MusicPlayer?
    
    var musicSequence:MusicSequence?
    
    var processingGraph:AUGraph?
    
    var samplerUnit:AudioUnit?
    
    
    /**
     This will initialize the midiClient, outputPort, and inputPort variables.
     It will also create a virtual destination.
     */
    
    func initMIDI(midiNotifier: MIDINotifyBlock? = nil, reader: MIDIReadBlock? = nil) {
        
        os_log("initializing MIDI", log: MIDIManager.midiLog, type: .debug)

        
        observeNotifications()
        
        enableNetwork()
        
        
        var notifyBlock: MIDINotifyBlock
        
        if midiNotifier != nil {
            notifyBlock = midiNotifier!
        } else {
            notifyBlock = MyMIDINotifyBlock
        }
        
        var readBlock: MIDIReadBlock
        if reader != nil {
            readBlock = reader!
        } else {
            readBlock = MyMIDIReadBlock
        }
        
        var status = noErr
        status = MIDIClientCreateWithBlock("com.rockhoppertech.MyMIDIClient" as CFString, &midiClient, notifyBlock)
        
        if status == noErr {
            os_log("created MIDI client %d", log: MIDIManager.midiLog, type: .debug, midiClient)
        } else {
            os_log("error creating MIDI client %@", log: MIDIManager.midiLog, type: .error, status)
            checkError(status)
        }
        
        
        if status == noErr {
            
            status = MIDIInputPortCreateWithBlock(midiClient, "com.rockhoppertech.MIDIInputPort" as CFString, &inputPort, readBlock)
            if status == noErr {
                os_log("created input port %d", log: MIDIManager.midiLog, type: .debug, inputPort)
            } else {
                os_log("error creating input port %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
            
            
            status = MIDIOutputPortCreate(midiClient,
                                          "com.rockhoppertech.OutputPort" as CFString,
                                          &outputPort)

            if status == noErr {
                os_log("created output port %d", log: MIDIManager.midiLog, type: .debug, outputPort)
            } else {
                os_log("error creating output port %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
            
            
            // this is the sequence's destination. Remember to set background mode in info.plist
            status = MIDIDestinationCreateWithBlock(midiClient,
                                                    "Swift3MIDI.VirtualDestination" as CFString,
                                                    &virtualDestinationEndpointRef,
                                                    MIDIPassThru)
            //                                                    readBlock)
            
             if status == noErr {
                os_log("created virtual destination %d", log: MIDIManager.midiLog, type: .debug, virtualDestinationEndpointRef)
            } else {
                os_log("error creating virtual destination %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
            
            //use MIDIReceived to transmit MIDI messages from your virtual source to any clients connected to the virtual source
            status = MIDISourceCreate(midiClient,
                                      "Swift3MIDI.VirtualSource" as CFString,
                                      &virtualSourceEndpointRef
            )
     
            if status == noErr {
                os_log("created virtual source %d", log: MIDIManager.midiLog, type: .debug, virtualSourceEndpointRef)
            } else {
                os_log("error creating virtual source %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
            
            
            connectSourcesToInputPort()
            
            initGraph()
            
            // let's see some device info for fun
            print("all devices")
            allDeviceProps()
            
            print("all external devices")
            allExternalDeviceProps()
            
            print("all destinations")
            allDestinationProps()
            
            print("all sources")
            allSourceProps()
        }
        
    }
    
    func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(midiNetworkChanged(notification:)),
                                               name:NSNotification.Name(rawValue: MIDINetworkNotificationSessionDidChange),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(midiNetworkContactsChanged(notification:)),
                                               name:NSNotification.Name(rawValue: MIDINetworkNotificationContactsDidChange),
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        MIDIClientDispose(self.midiClient)
    }
    
    // signifies that other aspects of the session changed, such as the connection list, connection policy
    func midiNetworkChanged(notification:NSNotification) {
        print("\(#function)")
        print("\(notification)")
        if let session = notification.object as? MIDINetworkSession {
            print("session \(session)")
            for con in session.connections() {
                print("con \(con)")
            }
            print("isEnabled \(session.isEnabled)")
            print("sourceEndpoint \(session.sourceEndpoint())")
            print("destinationEndpoint \(session.destinationEndpoint())")
            print("networkName \(session.networkName)")
            print("localName \(session.localName)")
            
            if let name = getDeviceName(session.sourceEndpoint()) {
                print("source name \(name)")
            }
            
            if let name = getDeviceName(session.destinationEndpoint()) {
                print("destination name \(name)")
            }
        }
    }
    
    func midiNetworkContactsChanged(notification:NSNotification) {
        print("\(#function)")
        print("\(notification)")
        if let session = notification.object as? MIDINetworkSession {
            print("session \(session)")
            for con in session.contacts() {
                print("contact \(con)")
            }
        }
    }
    
    
    func initGraph() {
        augraphSetup()
        graphStart()
        // after the graph starts
        loadSF2Preset(0)
        CAShow(UnsafeMutablePointer<MusicSequence>(self.processingGraph!))
    }
    
    
    // swift 2
    // typealias MIDIReadBlock = (UnsafePointer<MIDIPacketList>, UnsafeMutablePointer<Void>) -> Void
    // swift 3
    // typealias MIDIReadBlock = (UnsafePointer<MIDIPacketList>, UnsafeMutablePointer<Swift.Void>?) -> Swift.Void
    
    func MIDIPassThru(_ packetList: UnsafePointer<MIDIPacketList>, srcConnRefCon: UnsafeMutableRawPointer?) -> Swift.Void {
        MIDIReceived(virtualSourceEndpointRef, packetList)
    }
    
    // now in beta 6
    //    public typealias MIDIReadBlock = (UnsafePointer<MIDIPacketList>, UnsafeMutableRawPointer?) -> Swift.Void
    
    //    func MyMIDIReadBlock(packetList: UnsafePointer<MIDIPacketList>, srcConnRefCon: UnsafeMutablePointer<Swift.Void>?) -> Swift.Void {
    
    func MyMIDIReadBlock(packetList: UnsafePointer<MIDIPacketList>, srcConnRefCon: UnsafeMutableRawPointer?) -> Swift.Void {
        
        let packets = packetList.pointee
        
        let packet:MIDIPacket = packets.packet
        
        var ap = UnsafeMutablePointer<MIDIPacket>.allocate(capacity: 1)
        ap.initialize(to:packet)
        
        for _ in 0 ..< packets.numPackets {
            let p = ap.pointee
            print("timestamp \(p.timeStamp)", terminator: "")
            var hex = String(format:"0x%X", p.data.0)
            print(" \(hex)", terminator: "")
            hex = String(format:"0x%X", p.data.1)
            print(" \(hex)", terminator: "")
            hex = String(format:"0x%X", p.data.2)
            print(" \(hex)")
            
            handle(p)
            
            ap = MIDIPacketNext(ap)
        }
    }
    
    func handle(_ packet:MIDIPacket) {
        
        let status = packet.data.0
        let d1 = packet.data.1
        let d2 = packet.data.2
        let rawStatus = status & 0xF0 // without channel
        let channel = status & 0x0F
        
        switch rawStatus {
            
        case 0x80:
            print("Note off. Channel \(channel) note \(d1) velocity \(d2)")
            // forward to sampler
            playNoteOff(UInt32(channel), noteNum: UInt32(d1))
            
        case 0x90:
            print("Note on. Channel \(channel) note \(d1) velocity \(d2)")
            // forward to sampler
            playNoteOn(UInt32(channel), noteNum:UInt32(d1), velocity: UInt32(d2))
            
        case 0xA0:
            print("Polyphonic Key Pressure (Aftertouch). Channel \(channel) note \(d1) pressure \(d2)")
            
        case 0xB0:
            print("Control Change. Channel \(channel) controller \(d1) value \(d2)")
            
        case 0xC0:
            print("Program Change. Channel \(channel) program \(d1)")
            
        case 0xD0:
            print("Channel Pressure (Aftertouch). Channel \(channel) pressure \(d1)")
            
        case 0xE0:
            print("Pitch Bend Change. Channel \(channel) lsb \(d1) msb \(d2)")
            
        default: print("Unhandled message \(status)")
        }
    }
    
    
    func showMIDIObjectType(_ ot: MIDIObjectType) {
        switch ot {
        case .other:
            os_log("midiObjectType: Other", log: MIDIManager.midiLog, type: .debug)
            break
            
        case .device:
            os_log("midiObjectType: Device", log: MIDIManager.midiLog, type: .debug)
            break
            
        case .entity:
            os_log("midiObjectType: Entity", log: MIDIManager.midiLog, type: .debug)
            break
            
        case .source:
            os_log("midiObjectType: Source", log: MIDIManager.midiLog, type: .debug)
            break
            
        case .destination:
            os_log("midiObjectType: Destination", log: MIDIManager.midiLog, type: .debug)
            break
            
        case .externalDevice:
            os_log("midiObjectType: ExternalDevice", log: MIDIManager.midiLog, type: .debug)
            break
            
        case .externalEntity:
            print("midiObjectType: ExternalEntity")
            os_log("midiObjectType: ExternalEntity", log: MIDIManager.midiLog, type: .debug)
            break
            
        case .externalSource:
            os_log("midiObjectType: ExternalSource", log: MIDIManager.midiLog, type: .debug)
            break
            
        case .externalDestination:
            os_log("midiObjectType: ExternalDestination", log: MIDIManager.midiLog, type: .debug)
            break
        }
        
    }
    
    //typealias MIDINotifyBlock = (UnsafePointer<MIDINotification>) -> Void
    func MyMIDINotifyBlock(midiNotification: UnsafePointer<MIDINotification>) {
        print("\ngot a MIDINotification!")
        
        let notification = midiNotification.pointee
        print("MIDI Notify, messageId= \(notification.messageID)")
        print("MIDI Notify, messageSize= \(notification.messageSize)")
        
        switch notification.messageID {
            
        // Some aspect of the current MIDISetup has changed.  No data.  Should ignore this  message if messages 2-6 are handled.
        case .msgSetupChanged:
            print("MIDI setup changed")
            let ptr = UnsafeMutablePointer<MIDINotification>(mutating: midiNotification)
            //            let ptr = UnsafeMutablePointer<MIDINotification>(midiNotification)
            let m = ptr.pointee
            print(m)
            print("id \(m.messageID)")
            print("size \(m.messageSize)")
            break
            
            
        // A device, entity or endpoint was added. Structure is MIDIObjectAddRemoveNotification.
        case .msgObjectAdded:
            
            print("added")
            //            let ptr = UnsafeMutablePointer<MIDIObjectAddRemoveNotification>(midiNotification)
            
            midiNotification.withMemoryRebound(to: MIDIObjectAddRemoveNotification.self, capacity: 1) {
                let m = $0.pointee
                print(m)
                print("id \(m.messageID)")
                print("size \(m.messageSize)")
                print("child \(m.child)")
                print("child type \(m.childType)")
                showMIDIObjectType(m.childType)
                print("parent \(m.parent)")
                print("parentType \(m.parentType)")
                showMIDIObjectType(m.parentType)
                print("childName \(getDeviceName(m.child))")
            }
            
            
            break
            
        // A device, entity or endpoint was removed. Structure is MIDIObjectAddRemoveNotification.
        case .msgObjectRemoved:
            print("kMIDIMsgObjectRemoved")
            //            let ptr = UnsafeMutablePointer<MIDIObjectAddRemoveNotification>(midiNotification)
            midiNotification.withMemoryRebound(to: MIDIObjectAddRemoveNotification.self, capacity: 1) {
                
                let m = $0.pointee
                print(m)
                print("id \(m.messageID)")
                print("size \(m.messageSize)")
                print("child \(m.child)")
                print("child type \(m.childType)")
                print("parent \(m.parent)")
                print("parentType \(m.parentType)")
                
                print("childName \(getDeviceName(m.child))")
            }
            
            
            break
            
        // An object's property was changed. Structure is MIDIObjectPropertyChangeNotification.
        case .msgPropertyChanged:
            print("kMIDIMsgPropertyChanged")
            
            
            
            //            let ptr = UnsafeMutablePointer<MIDIObjectPropertyChangeNotification>(midiNotification)
            midiNotification.withMemoryRebound(to: MIDIObjectPropertyChangeNotification.self, capacity: 1) {
                
                let m = $0.pointee
                print(m)
                print("id \(m.messageID)")
                print("size \(m.messageSize)")
                print("object \(m.object)")
                print("objectType  \(m.objectType)")
                print("propertyName  \(m.propertyName)")
                print("propertyName  \(m.propertyName.takeUnretainedValue())")
                
                if m.propertyName.takeUnretainedValue() as String == "apple.midirtp.session" {
                    print("connected")
                }
            }
            
            break
            
        // 	A persistent MIDI Thru connection wasor destroyed.  No data.
        case .msgThruConnectionsChanged:
            print("MIDI thru connections changed.")
            break
            
        //A persistent MIDI Thru connection was created or destroyed.  No data.
        case .msgSerialPortOwnerChanged:
            print("MIDI serial port owner changed.")
            break
            
        case .msgIOError:
            print("MIDI I/O error.")
            
            //let ptr = UnsafeMutablePointer<MIDIIOErrorNotification>(midiNotification)
            midiNotification.withMemoryRebound(to: MIDIIOErrorNotification.self, capacity: 1) {
                let m = $0.pointee
                print(m)
                print("id \(m.messageID)")
                print("size \(m.messageSize)")
                print("driverDevice \(m.driverDevice)")
                print("errorCode \(m.errorCode)")
            }
            break
        }
    }
    
    
    func enableNetwork() {
        MIDINetworkSession.default().isEnabled = true
        MIDINetworkSession.default().connectionPolicy = .anyone
        
        print("net session enabled \(MIDINetworkSession.default().isEnabled)")
        print("net session networkPort \(MIDINetworkSession.default().networkPort)")
        print("net session networkName \(MIDINetworkSession.default().networkName)")
        print("net session localName \(MIDINetworkSession.default().localName)")
        
    }
    
    func connectSourcesToInputPort() {
        let sourceCount = MIDIGetNumberOfSources()
        print("source count \(sourceCount)")
        
        for srcIndex in 0 ..< sourceCount {
            let midiEndPoint = MIDIGetSource(srcIndex)
            
            let status = MIDIPortConnectSource(inputPort,
                                               midiEndPoint,
                                               nil)

            if status == noErr {
                os_log("yay connected endpoint to inputPort", log: MIDIManager.midiLog, type: .debug)
            } else {
                print("oh crap!")
                checkError(status)
            }
        }
    }
    
    func disconnectSourceFromInputPort(_ sourceMidiEndPoint:MIDIEndpointRef) -> OSStatus {
        let status = MIDIPortDisconnectSource(inputPort,
                                              sourceMidiEndPoint
        )
        if status == noErr {
            print("yay disconnected endpoint \(sourceMidiEndPoint) from inputPort! \(inputPort)")
        } else {
            os_log("could not disconnect inputPort %@ endpoint %@ status %@", log: MIDIManager.midiLog, type: .error, inputPort,sourceMidiEndPoint,status )
            checkError(status)
        }
        return status
    }
    
    func playWithMusicPlayer() {
        
        if self.musicSequence == nil {
            self.musicSequence = createMusicSequence()
            createMIDIFile(sequence: self.musicSequence!, filename: "created", ext: "mid")
        }
        
        if let sequence = self.musicSequence {
            self.musicPlayer = createMusicPlayer(musicSequence: sequence)
            playMusicPlayer()
            
        } else {
            os_log("could not create sequence and play it", log: MIDIManager.midiLog, type: .error)
        }
    }
    
    internal func createMusicPlayer(musicSequence:MusicSequence) -> MusicPlayer? {
        var musicPlayer: MusicPlayer?
        var status = noErr
        
        status = NewMusicPlayer(&musicPlayer)
        if status != noErr {
            os_log("error creating music player %@", log: MIDIManager.midiLog, type: .error, status)
            checkError(status)
        }
        
        if let player = musicPlayer {
            
            status = MusicPlayerSetSequence(player, musicSequence)
            if status != noErr {
                os_log("error setting sequence %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
            
            status = MusicPlayerPreroll(player)
            if status != noErr {
                os_log("error prerolling music player %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
            
            return player
        } else {
            os_log("music player is nil", log: MIDIManager.midiLog, type: .error)
            return nil
        }
    }
    
    internal func playMusicPlayer() {
        var status = noErr
        var playing = DarwinBoolean(false)
        
        if let player = self.musicPlayer {
            status = MusicPlayerIsPlaying(player, &playing)
            if playing != false {
                os_log("music player is playing. stopping", log: MIDIManager.midiLog, type: .debug)

                status = MusicPlayerStop(player)
                if status != noErr {
                    os_log("error stopping %@", log: MIDIManager.midiLog, type: .error, status)
                    checkError(status)
                    return
                }
            } else {
                os_log("music player is not playing", log: MIDIManager.midiLog, type: .debug)
            }
            
            status = MusicPlayerSetTime(player, 0)
            if status != noErr {
                os_log("error setting time %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
                return
            }
            
            os_log("starting to play", log: MIDIManager.midiLog, type: .debug)

            status = MusicPlayerStart(player)
            if status != noErr {
                os_log("error starting %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
                return
            }
        }
    }
    
    func createMIDIFile(sequence:MusicSequence, filename:String, ext:String)  {
        
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        if let fileURL = NSURL(fileURLWithPath: documentsDirectory).appendingPathComponent("\(filename).\(ext)") {

            os_log("creating midi file at %@", log: MIDIManager.midiLog, type: .debug, fileURL.absoluteString)

            let timeResolution = determineTimeResolution(musicSequence: sequence)
            let status = MusicSequenceFileCreate(sequence, fileURL as CFURL, .midiType, [.eraseFile], Int16(timeResolution))
            if status != noErr {
                checkError(status)
            }
        }
    }
    
    
    func determineTimeResolution(musicSequence:MusicSequence) -> UInt32 {
        var track:MusicTrack?
        var status = MusicSequenceGetTempoTrack(musicSequence, &track)
        if status != noErr {
            checkError(status)
        }
        
        if let tempoTrack = track {
            var propertyLength = UInt32(0)
            
            //            let n = UnsafeMutablePointer<Swift.Void>(nil)
            var junk = UInt32(0)
            status = MusicTrackGetProperty(tempoTrack,
                                           kSequenceTrackProperty_TimeResolution,
                                           &junk,
                                           &propertyLength)
            if status != noErr {
                checkError(status)
            }
            
            var timeResolution = UInt32(0)
            status = MusicTrackGetProperty(tempoTrack,
                                           kSequenceTrackProperty_TimeResolution,
                                           &timeResolution,
                                           &propertyLength)
            if status != noErr {
                checkError(status)
            }
            return timeResolution
        } else {
            os_log("error getting tempo track", log: MIDIManager.midiLog, type: .error)
            return 0
        }
    }
    
    // the newer API play data but provide no way to create a sequence. So this is the crowbar.
    internal func sequenceData(musicSequence:MusicSequence, resolution:Int16=480) -> NSData? {
        
        var data:Unmanaged<CFData>?
        let status = MusicSequenceFileCreateData(musicSequence,
                                                 MusicSequenceFileTypeID.midiType,
                                                 MusicSequenceFileFlags.eraseFile,
                                                 resolution,
                                                 &data)
        if status != noErr {
            os_log("error turning MusicSequence into NSData %@", log: MIDIManager.midiLog, type: .error, status)
            checkError(status)
            return nil
        }
        
        let ns:NSData = data!.takeUnretainedValue()
        data?.release()
        return ns
    }
    
    func addTimeSignature(musicSequence:MusicSequence) {
        //        //FF 58 nn dd cc bb
        //
        //        A time signature of 4/4, with a metronome click every 1/4 note, would be encoded :
        //        FF 58 04 04 02 18 08
        //        There are 24 MIDI Clocks per quarter-note, hence cc=24 (0x18).
        //
        //        A time signature of 6/8, with a metronome click every 3rd 1/8 note, would be encoded :
        //        FF 58 04 06 03 24 08
        //        Remember, a 1/4 note is 24 MIDI Clocks, therefore a bar of 6/8 is 72 MIDI Clocks.
        //        Hence 3 1/8 notes is 36 (=0x24) MIDI Clocks.
        
        //
        //        nn is a byte specifying the numerator of the time signature (as notated).
        //        dd is a byte specifying the denominator of the time signature as a negative power of 2 (ie 2 represents a quarter-note, 3 represents an eighth-note, etc).
        //        cc is a byte specifying the number of MIDI clocks between metronome clicks.
        //        bb is a byte specifying the number of notated 32nd-notes in a MIDI quarter-note (24 MIDI Clocks). The usual value for this parameter is 8, though some sequencers allow the user to specify that what MIDI thinks of as a quarter note, should be notated as something else.
        
        let numerator = UInt8(0x06)
        let denominator = UInt8(log2(8.0))
        let clocksBetweenMetronomeClicks = UInt8(0x24)
        let thirtySecondsPerQuarterNote = UInt8(0x8)
        let data = [numerator, denominator,clocksBetweenMetronomeClicks,thirtySecondsPerQuarterNote]
        var metaEvent = MIDIMetaEvent()
        metaEvent.metaEventType = UInt8(0x58)
        metaEvent.dataLength = UInt32(data.count)
        
        withUnsafeMutablePointer(to: &metaEvent.data, {
            pointer in
            for i in 0 ..< data.count {
                pointer[i] = data[i]
            }
        })
        
        //        withUnsafeMutablePointer(&metaEvent.data, {
        //            pointer in
        //            for i in 0 ..< data.count {
        //                pointer[i] = data[i]
        //            }
        //        })
        
        var tempo:MusicTrack?
        var status = MusicSequenceGetTempoTrack(musicSequence, &tempo)
        checkError(status)
        if let tempoTrack = tempo {
            status = MusicTrackNewMetaEvent(tempoTrack, 0, &metaEvent)
            if status != noErr {
                os_log("error adding time signature %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
        }
    }
    
    func addKeySignature(musicSequence:MusicSequence) {
        
        //    FF 59 02 sf mi
        //
        //    sf is a byte specifying the number of flats (-ve) or sharps (+ve) that identifies the key signature (-7 = 7 flats, -1 = 1 flat, 0 = key of C, 1 = 1 sharp, etc).
        //    mi is a byte specifying a major (0) or minor (1) key.
        
        let sf = UInt8(2)
        let mi = UInt8(0) // major
        let data = [sf, mi]
        var metaEvent = MIDIMetaEvent()
        metaEvent.metaEventType = UInt8(0x59)
        metaEvent.dataLength = UInt32(data.count)
        
        withUnsafeMutablePointer(to: &metaEvent.data, {
            pointer in
            for i in 0 ..< data.count {
                pointer[i] = data[i]
            }
        })
        
        var tempo:MusicTrack?
        var status = MusicSequenceGetTempoTrack(musicSequence, &tempo)
        checkError(status)
        if let tempoTrack = tempo {
            status = MusicTrackNewMetaEvent(tempoTrack, 0, &metaEvent)
            if status != noErr {
                print("borked adding key sig \(status)")
                checkError(status)
            }
        }
    }
    
    //FIXME: produces junk. But when inline it's fine.
    func createCopyrightEvent(message:String) -> MIDIMetaEvent {
        let data = [UInt8](message.utf8)
        var metaEvent = MIDIMetaEvent()
        metaEvent.metaEventType = 2 // copyright
        metaEvent.dataLength = UInt32(data.count)
        withUnsafeMutablePointer(to: &metaEvent.data, {
            pointer in
            for i in 0 ..< data.count {
                pointer[i] = data[i]
            }
        })
        return metaEvent
    }
    
    //FIXME: produces junk. But when inline it's fine.
    func createNameEvent(text:String) -> MIDIMetaEvent {
        let data = [UInt8](text.utf8)
        var metaEvent = MIDIMetaEvent()
        metaEvent.metaEventType = 3 // sequence or track name
        metaEvent.dataLength = UInt32(data.count)
        withUnsafeMutablePointer(to: &metaEvent.data, {
            pointer in
            for i in 0 ..< data.count {
                pointer[i] = data[i]
            }
        })
        return metaEvent
    }
    
    internal func addCopyright(sequence:MusicSequence, text:String) {
        //var metaEvent = createCopyrightEvent(message: text)
        let data = [UInt8](text.utf8)
        var metaEvent = MIDIMetaEvent()
        metaEvent.metaEventType = 2 // copyright
        metaEvent.dataLength = UInt32(data.count)
        withUnsafeMutablePointer(to: &metaEvent.data, {
            pointer in
            for i in 0 ..< data.count {
                pointer[i] = data[i]
            }
        })
        
        var tempo:MusicTrack?
        var status = MusicSequenceGetTempoTrack(sequence, &tempo)
        checkError(status)
        if let tempoTrack = tempo {
            status = MusicTrackNewMetaEvent(tempoTrack, 0, &metaEvent)
            if status != noErr {
                os_log("Unable to add copyright %@", log: MIDIManager.midiLog, type: .error, status)
            }
        }
    }
    
    
    internal func addLyric(track:MusicTrack, lyric:String, timeStamp:MusicTimeStamp) {
        
        let data = [UInt8](lyric.utf8)
        var metaEvent = MIDIMetaEvent()
        metaEvent.metaEventType = 5 // lyric
        metaEvent.dataLength = UInt32(data.count)
        withUnsafeMutablePointer(to: &metaEvent.data, {
            pointer in
            for i in 0 ..< data.count {
                pointer[i] = data[i]
            }
        })
        
        let status = MusicTrackNewMetaEvent(track, timeStamp, &metaEvent)
        if status != noErr {
            os_log("Unable to add lyric %@", log: MIDIManager.midiLog, type: .error, status)
            checkError(status)
        }
    }
    
    internal func addTrackName(track:MusicTrack, name:String) {
        
        // var metaEvent = createNameEvent(text: name)
        let data = [UInt8](name.utf8)
        var metaEvent = MIDIMetaEvent()
        metaEvent.metaEventType = 3 // sequence or track name
        metaEvent.dataLength = UInt32(data.count)
        withUnsafeMutablePointer(to: &metaEvent.data, {
            pointer in
            for i in 0 ..< data.count {
                pointer[i] = data[i]
            }
        })
        
        let status = MusicTrackNewMetaEvent(track, MusicTimeStamp(0), &metaEvent)
        if status != noErr {
            os_log("Unable to name Track %@", log: MIDIManager.midiLog, type: .error, status)
            checkError(status)
        }
    }
    
    internal func addSequenceName(sequence:MusicSequence, name:String) {
        
        // var metaEvent = createNameEvent(text: name)
        let data = [UInt8](name.utf8)
        var metaEvent = MIDIMetaEvent()
        metaEvent.metaEventType = 3 // sequence or track name
        metaEvent.dataLength = UInt32(data.count)
        withUnsafeMutablePointer(to: &metaEvent.data, {
            pointer in
            for i in 0 ..< data.count {
                pointer[i] = data[i]
            }
        })
        
        // you add it to the tempo track
        var tempo:MusicTrack?
        var status = MusicSequenceGetTempoTrack(sequence, &tempo)
        checkError(status)
        if let tempoTrack = tempo {
            status = MusicTrackNewMetaEvent(tempoTrack, 0, &metaEvent)
            if status != noErr {
                os_log("borked %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
        }
        
        // nope. no equivalent for sequence
        //        let result = MusicTrackNewMetaEvent(sequence, MusicTimeStamp(0), &metaEvent)
        //        if result != 0 {
        //            print("Unable to name sequence")
        //        }
    }
    
    
    internal func createMusicSequence() -> MusicSequence? {
        
        var musicSequence:MusicSequence?
        var status = NewMusicSequence(&musicSequence)
        if status != noErr {
            print("\(#line) bad status \(status) creating sequence")
            checkError(status)
        }
        
        if let sequence = musicSequence {
            
            addSequenceName(sequence: sequence, name: "Test Sequence")
            
            addCopyright(sequence: sequence, text: "Copyright 2016")
            
            addKeySignature(musicSequence: sequence)
            
            addTimeSignature(musicSequence: sequence)
            
            // add a track
            var newtrack: MusicTrack?
            status = MusicSequenceNewTrack(sequence, &newtrack)
            if status != noErr {
                os_log("error creating track %@", log: MIDIManager.midiLog, type: .error, status)
                checkError(status)
            }
            
            if let track = newtrack {
                addTrackName(track: track, name: "Test Track")
                
                addLyric(track: track, lyric: "Meow", timeStamp: MusicTimeStamp(0))
                
                addLyric(track: track, lyric: "Miao", timeStamp: MusicTimeStamp(3))
                
                // bank select msb
                var chanmess = MIDIChannelMessage(status: 0xB0, data1: 0, data2: 0, reserved: 0)
                status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
                if status != noErr {
                    os_log("error creating bank select event %@", log: MIDIManager.midiLog, type: .error, status)
                    checkError(status)
                }
                // bank select lsb
                chanmess = MIDIChannelMessage(status: 0xB0, data1: 32, data2: 0, reserved: 0)
                status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
                if status != noErr {
                    os_log("error creating bank select event %@", log: MIDIManager.midiLog, type: .error, status)

                    checkError(status)
                }
                
                // program change. first data byte is the patch, the second data byte is unused for program change messages.
                chanmess = MIDIChannelMessage(status: 0xC0, data1: 0, data2: 0, reserved: 0)
                status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
                if status != noErr {
                    os_log("error creating program change event %@", log: MIDIManager.midiLog, type: .error, status)
                    checkError(status)
                }
                
                // now make some notes and put them on the track
                var beat = MusicTimeStamp(0.0)
                let duration = Float32(1.0)
                for i:UInt8 in 60...72 {
                    var mess = MIDINoteMessage(channel: 0,
                                               note: i,
                                               velocity: 64,
                                               releaseVelocity: 0,
                                               duration: duration )
                    status = MusicTrackNewMIDINoteEvent(track, beat, &mess)
                    if status != noErr {
                        os_log("error creating new midi note event %@", log: MIDIManager.midiLog, type: .error, status)
                        checkError(status)
                    }
                    beat += 1
                }
                
                // associate the AUGraph with the sequence. In this case, I'm using a virtual destination
                // which will forward the messages so this is commented out here.
                //                status = MusicSequenceSetAUGraph(sequence, self.processingGraph)
                //                checkError(status)
                
                // send it to our virtual destination (which will forward it
                status = MusicSequenceSetMIDIEndpoint(sequence, self.virtualDestinationEndpointRef)
                checkError(status)
                
                
                //public typealias MusicSequenceUserCallback = @convention(c) (UnsafeMutablePointer<Swift.Void>?, MusicSequence, MusicTrack, MusicTimeStamp, UnsafePointer<MusicEventUserData>, MusicTimeStamp, MusicTimeStamp) -> Swift.Void
                
                //in beta 6
                //                public typealias MusicSequenceUserCallback = @convention(c) (UnsafeMutableRawPointer?, MusicSequence, MusicTrack, MusicTimeStamp, UnsafePointer<MusicEventUserData>, MusicTimeStamp, MusicTimeStamp) -> Swift.Void
                
                
                let sequencerCallback: MusicSequenceUserCallback =  {
                    (clientData:UnsafeMutableRawPointer?,
                    sequence:MusicSequence,
                    track:MusicTrack,
                    eventTime:MusicTimeStamp,
                    eventData:UnsafePointer<MusicEventUserData>,
                    startSliceBeat:MusicTimeStamp,
                    endSliceBeat:MusicTimeStamp)
                    -> Void in
                    
                    let userData = eventData.pointee
                    if userData.data == 0xAA {
                        os_log("got user event AA of length %d", log: MIDIManager.midiLog, type: .debug, userData.length)
                    }
                }
                status = MusicSequenceSetUserCallback(sequence, sequencerCallback, nil)
                checkError(status)
                
                var event = MusicEventUserData(length: 1, data: (0xAA))
                // add the user event
                let status = MusicTrackNewUserEvent(track, beat + MusicTimeStamp(duration), &event)
                if status != noErr {
                    checkError(status)
                }
                
                
                // Let's see it
                CAShow(UnsafeMutablePointer<MusicSequence>(sequence))
                
                let info = MusicSequenceGetInfoDictionary(sequence)
                os_log("sequence info %@", log: MIDIManager.midiLog, type: .debug, info as! CVarArg)
                //info[kAFInfoDictionary_Copyright] = "2016 bozosoft"
                
                return sequence
            }
            
        }
        
        return nil
    }
    
    internal func augraphSetup() {
        
        var status = NewAUGraph(&self.processingGraph)
        checkError(status)
        if let graph = self.processingGraph {
            
            // create the sampler
            
            //https://developer.apple.com/library/prerelease/ios/documentation/AudioUnit/Reference/AudioComponentServicesReference/index.html#//apple_ref/swift/struct/AudioComponentDescription
            
            var samplerNode = AUNode()
            var cd = AudioComponentDescription(
                componentType:         OSType(kAudioUnitType_MusicDevice),
                componentSubType:      OSType(kAudioUnitSubType_Sampler),
                componentManufacturer: OSType(kAudioUnitManufacturer_Apple),
                componentFlags:        0,
                componentFlagsMask:    0)
            status = AUGraphAddNode(graph, &cd, &samplerNode)
            checkError(status)
            
            // create the ionode
            var ioNode = AUNode()
            var ioUnitDescription = AudioComponentDescription(
                componentType:         OSType(kAudioUnitType_Output),
                componentSubType:      OSType(kAudioUnitSubType_RemoteIO),
                componentManufacturer: OSType(kAudioUnitManufacturer_Apple),
                componentFlags:        0,
                componentFlagsMask:    0)
            status = AUGraphAddNode(graph, &ioUnitDescription, &ioNode)
            checkError(status)
            
            // now do the wiring. The graph needs to be open before you call AUGraphNodeInfo
            status = AUGraphOpen(graph)
            checkError(status)
            
            status = AUGraphNodeInfo(graph, samplerNode, nil, &self.samplerUnit)
            checkError(status)
            
            var ioUnit: AudioUnit? = nil
            status = AUGraphNodeInfo(graph, ioNode, nil, &ioUnit)
            checkError(status)
            
            let ioUnitOutputElement = AudioUnitElement(0)
            let samplerOutputElement = AudioUnitElement(0)
            status = AUGraphConnectNodeInput(graph,
                                             samplerNode, samplerOutputElement, // srcnode, inSourceOutputNumber
                ioNode, ioUnitOutputElement) // destnode, inDestInputNumber
            checkError(status)
        } else {
            os_log("core audio augraph is nil", log: MIDIManager.midiLog, type: .error)
        }
    }
    
    
    internal func graphStart() {
        //https://developer.apple.com/library/prerelease/ios/documentation/AudioToolbox/Reference/AUGraphServicesReference/index.html#//apple_ref/c/func/AUGraphIsInitialized
        
        if let graph = self.processingGraph {
            var outIsInitialized:DarwinBoolean = false
            var status = AUGraphIsInitialized(graph, &outIsInitialized)
            print("isinit status is \(status)")
            print("bool is \(outIsInitialized)")
            
            if outIsInitialized == false {
                status = AUGraphInitialize(graph)
                checkError(status)
            }
            
            var isRunning = DarwinBoolean(false)
            status = AUGraphIsRunning(graph, &isRunning)
            checkError(status)
            print("running bool is \(isRunning)")
            if isRunning == false {
                status = AUGraphStart(graph)
                checkError(status)
            }
        } else {
            os_log("core audio augraph is nil", log: MIDIManager.midiLog, type: .error)
        }
    }
    
    func playNoteOn(_ channel:UInt32, noteNum:UInt32, velocity:UInt32)    {
        let noteCommand = UInt32(0x90 | channel)
        if let sampler = self.samplerUnit {
            let status = MusicDeviceMIDIEvent(sampler, noteCommand, noteNum, velocity, 0)
            checkError(status)
        }
    }
    
    func playNoteOff(_ channel:UInt32, noteNum:UInt32)    {
        let noteCommand = UInt32(0x80 | channel)
        if let sampler = self.samplerUnit {
            let status = MusicDeviceMIDIEvent(sampler, noteCommand, noteNum, 0, 0)
            checkError(status)
        }
    }
    
    
    /// loads preset into self.samplerUnit
    internal func loadSF2Preset(_ preset:UInt8)  {
        
        // this is a huge soundfont, but it is valid. The GeneralUser GS MuseScore font has problems.
        guard let bankURL = Bundle.main.url(forResource:"FluidR3 GM2-2", withExtension: "SF2") else {
            fatalError("\"FluidR3 GM2-2.SF2\" file not found.")
        }
        
        
        // This is the MuseCore soundfont. Change it to the one you have.
        //        guard let bankURL = Bundle.main.urlForResource("GeneralUser GS MuseScore v1.442", withExtension: "sf2") else {
        ////            fatalError("\"GeneralUser GS MuseScore v1.442.sf2\" file not found.")
        //            print("\"GeneralUser GS MuseScore v1.442.sf2\" file not found.")
        //        }

        // or
        // instrumentType: UInt8(kInstrumentType_DLSPreset),
        
        var instdata = AUSamplerInstrumentData(fileURL: Unmanaged.passUnretained(bankURL as CFURL),
            instrumentType: UInt8(kInstrumentType_SF2Preset),
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB),
            presetID: preset)
        
        if let sampler = self.samplerUnit {
            let status = AudioUnitSetProperty(
                sampler,
                AudioUnitPropertyID(kAUSamplerProperty_LoadInstrument),
                AudioUnitScope(kAudioUnitScope_Global),
                0,
                &instdata,
                UInt32(MemoryLayout<AUSamplerInstrumentData>.size))
            checkError(status)
        }
    }
    
    //The system assigns unique IDs to all objects
    func getUniqueID(_ endpoint:MIDIEndpointRef) -> (OSStatus, MIDIUniqueID) {
        var id = MIDIUniqueID(0)
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
        if status != noErr {
            os_log("error getting unique id. status %@", log: MIDIManager.midiLog, type: .error, status)
            checkError(status)
        }
        return (status,id)
    }
    
    func setUniqueID(_ endpoint:MIDIEndpointRef, id:MIDIUniqueID) -> OSStatus {
        let status = MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyUniqueID, id)
        if status != noErr {
            os_log("error setting unique id. status %@", log: MIDIManager.midiLog, type: .error, status)

            checkError(status)
        }
        return status
    }
    
    func getDeviceName(_ endpoint:MIDIEndpointRef) -> String? {
        var cfs: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &cfs)
        if status != noErr {
            os_log("error getting device name for %@. status %@", log: MIDIManager.midiLog, type: .error, endpoint, status)
            checkError(status)
        }
        
        if let s = cfs {
            return s.takeRetainedValue() as String
        }
        
        return nil
    }
    
    func allExternalDeviceProps() {
        
        let n = MIDIGetNumberOfExternalDevices()
        for i in 0 ..< n {
            let midiDevice = MIDIGetExternalDevice(i)
            printProperties(midiDevice)
        }
    }
    
    func allDeviceProps() {
        
        let n = MIDIGetNumberOfDevices()
        for i in 0 ..< n {
            let midiDevice = MIDIGetDevice(i)
            printProperties(midiDevice)
        }
    }
    
    func allDestinationProps() {
        let numberOfDestinations  = MIDIGetNumberOfDestinations()
        for i in 0 ..< numberOfDestinations {
            let endpoint = MIDIGetDestination(i)
            printProperties(endpoint)
        }
    }
    
    func allSourceProps() {
        let numberOfSources  = MIDIGetNumberOfSources()
        for i in 0 ..< numberOfSources {
            let endpoint = MIDIGetSource(i)
            printProperties(endpoint)
        }
    }
    
    func printProperties(_ midiobject:MIDIObjectRef) {
        var unmanagedProperties: Unmanaged<CFPropertyList>?
        let status = MIDIObjectGetProperties(midiobject, &unmanagedProperties, true)
        checkError(status)
        
        if let midiProperties: CFPropertyList = unmanagedProperties?.takeUnretainedValue() {
            if let midiDictionary = midiProperties as? NSDictionary {
                os_log("MIDI properties %@", log: MIDIManager.midiLog, type: .debug, midiDictionary)
            }
        } else {
            os_log("Couldn't load properties for %@", log: MIDIManager.midiLog, type: .error, midiobject)
        }
    }
    
    func propertyValue(_ midiobject:MIDIObjectRef, propName:String) -> String? {
        var unmanagedProperties: Unmanaged<CFPropertyList>?
        let status = MIDIObjectGetProperties(midiobject, &unmanagedProperties, true)
        checkError(status)
        
        if let midiProperties: CFPropertyList = unmanagedProperties?.takeUnretainedValue() {
            if let midiDictionary = midiProperties as? NSDictionary {
                os_log("MIDI properties %@", log: MIDIManager.midiLog, type: .debug, midiDictionary)
                return midiDictionary[propName] as? String
            }
        } else {
            os_log("Couldn't load properties for %@", log: MIDIManager.midiLog, type: .error, midiobject)
        }
        
        return nil
    }
    
    
    ///  Check the status code returned from most Core MIDI functions.
    ///  Sort of like Adamson's CheckError.
    ///  For other projects you can uncomment the Core MIDI constants.
    ///
    ///  - parameter error: an `OSStatus` returned from a Core MIDI function.
    internal func checkError(_ error:OSStatus) {
        if error == noErr {return}
        
        if let s = MIDIManager.stringFrom4(status:error) {
            print("error string '\(s)'")
            os_log("error string %@", log: MIDIManager.midiLog, type: .error, s)
        }
        
        switch(error) {
            
        case kMIDIInvalidClient :
            os_log("kMIDIInvalidClient", log: MIDIManager.midiLog, type: .error)
            
        case kMIDIInvalidPort :
            os_log("kMIDIInvalidPort", log: MIDIManager.midiLog, type: .error)

        case kMIDIWrongEndpointType :
            os_log("kMIDIWrongEndpointType", log: MIDIManager.midiLog, type: .error)

        case kMIDINoConnection :
            os_log("kMIDINoConnection", log: MIDIManager.midiLog, type: .error)

        case kMIDIUnknownEndpoint :
            os_log("kMIDIUnknownEndpoint", log: MIDIManager.midiLog, type: .error)

        case kMIDIUnknownProperty :
            os_log("kMIDIUnknownProperty", log: MIDIManager.midiLog, type: .error)

        case kMIDIWrongPropertyType :
            os_log("kMIDIWrongPropertyType", log: MIDIManager.midiLog, type: .error)

        case kMIDINoCurrentSetup :
            os_log("kMIDINoCurrentSetup", log: MIDIManager.midiLog, type: .error)

        case kMIDIMessageSendErr :
            os_log("kMIDIMessageSendErr", log: MIDIManager.midiLog, type: .error)

        case kMIDIServerStartErr :
            os_log("kMIDIServerStartErr", log: MIDIManager.midiLog, type: .error)

        case kMIDISetupFormatErr :
            os_log("kMIDISetupFormatErr", log: MIDIManager.midiLog, type: .error)

        case kMIDIWrongThread :
            os_log("kMIDIWrongThread", log: MIDIManager.midiLog, type: .error)

        case kMIDIObjectNotFound :
            os_log("kMIDIObjectNotFound", log: MIDIManager.midiLog, type: .error)

        case kMIDIIDNotUnique :
            os_log("kMIDIIDNotUnique", log: MIDIManager.midiLog, type: .error)

        case kMIDINotPermitted :
            os_log("kMIDINotPermitted", log: MIDIManager.midiLog, type: .error)
            os_log("did you set UIBackgroundModes to audio in your info.plist?", log: MIDIManager.midiLog, type: .error)

        //AUGraph.h
        case kAUGraphErr_NodeNotFound:
            os_log("kAUGraphErr_NodeNotFound", log: MIDIManager.midiLog, type: .error)

        case kAUGraphErr_OutputNodeErr:
            os_log("kAUGraphErr_OutputNodeErr", log: MIDIManager.midiLog, type: .error)

        case kAUGraphErr_InvalidConnection:
            os_log("kAUGraphErr_InvalidConnection", log: MIDIManager.midiLog, type: .error)

        case kAUGraphErr_CannotDoInCurrentContext:
            os_log("kAUGraphErr_CannotDoInCurrentContext", log: MIDIManager.midiLog, type: .error)

        case kAUGraphErr_InvalidAudioUnit:
            os_log("kAUGraphErr_InvalidAudioUnit", log: MIDIManager.midiLog, type: .error)

            // core audio
            
        case kAudio_UnimplementedError:
            os_log("kAudio_UnimplementedError", log: MIDIManager.midiLog, type: .error)

        case kAudio_FileNotFoundError:
            os_log("kAudio_FileNotFoundError", log: MIDIManager.midiLog, type: .error)

        case kAudio_FilePermissionError:
            os_log("kAudio_FilePermissionError", log: MIDIManager.midiLog, type: .error)

        case kAudio_TooManyFilesOpenError:
            os_log("kAudio_TooManyFilesOpenError", log: MIDIManager.midiLog, type: .error)

        case kAudio_BadFilePathError:
            os_log("kAudio_BadFilePathError", log: MIDIManager.midiLog, type: .error)

        case kAudio_ParamError:
            os_log("kAudio_ParamError", log: MIDIManager.midiLog, type: .error)

        case kAudio_MemFullError:
            os_log("kAudio_MemFullError", log: MIDIManager.midiLog, type: .error)

            
            
            // AudioToolbox
            
        case kAudioToolboxErr_InvalidSequenceType :
            os_log("kAudioToolboxErr_InvalidSequenceType", log: MIDIManager.midiLog, type: .error)

        case kAudioToolboxErr_TrackIndexError :
            os_log("kAudioToolboxErr_TrackIndexError", log: MIDIManager.midiLog, type: .error)

        case kAudioToolboxErr_TrackNotFound :
            os_log("kAudioToolboxErr_TrackNotFound", log: MIDIManager.midiLog, type: .error)

        case kAudioToolboxErr_EndOfTrack :
            os_log("kAudioToolboxErr_EndOfTrack", log: MIDIManager.midiLog, type: .error)

        case kAudioToolboxErr_StartOfTrack :
            os_log("kAudioToolboxErr_StartOfTrack", log: MIDIManager.midiLog, type: .error)

        case kAudioToolboxErr_IllegalTrackDestination :
            os_log("kAudioToolboxErr_IllegalTrackDestination", log: MIDIManager.midiLog, type: .error)

        case kAudioToolboxErr_NoSequence :
            os_log("kAudioToolboxErr_NoSequence", log: MIDIManager.midiLog, type: .error)

        case kAudioToolboxErr_InvalidEventType :
            os_log("kAudioToolboxErr_InvalidEventType", log: MIDIManager.midiLog, type: .error)

        case kAudioToolboxErr_InvalidPlayerState :
            os_log("kAudioToolboxErr_InvalidPlayerState", log: MIDIManager.midiLog, type: .error)

            // AudioUnit
            
        case kAudioUnitErr_InvalidProperty :
            os_log("kAudioUnitErr_InvalidProperty", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_InvalidParameter :
            os_log("kAudioUnitErr_InvalidParameter", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_InvalidElement :
            os_log("kAudioUnitErr_InvalidElement", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_NoConnection :
            os_log("kAudioUnitErr_NoConnection", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_FailedInitialization :
            os_log("kAudioUnitErr_FailedInitialization", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_TooManyFramesToProcess :
            os_log("kAudioUnitErr_TooManyFramesToProcess", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_InvalidFile :
            os_log("kAudioUnitErr_InvalidFile", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_FormatNotSupported :
            os_log("kAudioUnitErr_FormatNotSupported", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_Uninitialized :
            os_log("kAudioUnitErr_Uninitialized", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_InvalidScope :
            os_log("kAudioUnitErr_InvalidScope", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_PropertyNotWritable :
            os_log("kAudioUnitErr_PropertyNotWritable", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_InvalidPropertyValue :
            os_log("kAudioUnitErr_InvalidPropertyValue", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_PropertyNotInUse :
            os_log("kAudioUnitErr_PropertyNotInUse", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_Initialized :
            os_log("kAudioUnitErr_Initialized", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_InvalidOfflineRender :
            os_log("kAudioUnitErr_InvalidOfflineRender", log: MIDIManager.midiLog, type: .error)

        case kAudioUnitErr_Unauthorized :
            os_log("kAudioUnitErr_Unauthorized", log: MIDIManager.midiLog, type: .error)

        default:
            os_log("huh?", log: MIDIManager.midiLog, type: .error)

        }
    }
    
    ///  Create a String from an encoded 4char.
    ///
    ///  - parameter n: The encoded 4char
    ///
    ///  - returns: The String representation.
    class func stringFrom4(n: Int) -> String? {
        
        if var scalar = UnicodeScalar((n >> 24) & 255) {
            if !scalar.isASCII {
                return ""
            }
            var s = String(scalar)
            
            scalar = UnicodeScalar((n >> 16) & 255)!
            if !scalar.isASCII {
                return ""
            }
            s += String(scalar)
            
            
            scalar = UnicodeScalar((n >> 8) & 255)!
            if !scalar.isASCII {
                return ""
            }
            s += String(scalar)
            
            scalar = UnicodeScalar(n & 255)!
            if !scalar.isASCII {
                return ""
            }
            s += String(scalar)
            
            return s
        }
        return nil
    }
    
    ///  Create a String from an encoded 4char.
    ///
    ///  - parameter status: an `OSStatus` containing the encoded 4char.
    ///
    ///  - returns: The String representation. Might be nil.
    class func stringFrom4(status: OSStatus) -> String? {
        let n = Int(status)
        return stringFrom4(n:n)
    }
}



