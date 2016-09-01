//: MIDIPlayground - sloppy hack just to see if MIDI works in a playground

import UIKit
import CoreMIDI
import AudioToolbox

// deprecated
//import XCPlayground
import PlaygroundSupport

PlaygroundSupport.PlaygroundPage.current.needsIndefiniteExecution = true

// NB these are deprecated now
//XCPlaygroundPage.currentPage.needsIndefiniteExecution = true
//XCPSetExecutionShouldContinueIndefinitely(continueIndefinitely: true)


var midiClient = MIDIClientRef()

var outputPort = MIDIPortRef()

var inputPort = MIDIPortRef()

func MyMIDINotifyBlock(midiNotification: UnsafePointer<MIDINotification>) {
    print("\ngot a MIDINotification!")
}

var notifyBlock = MyMIDINotifyBlock


var status = MIDIClientCreateWithBlock("com.rockhoppertech.MyMIDIClient" as CFString, &midiClient, notifyBlock)

if status == noErr {
    print("created client \(midiClient)")
} else {
    print("error creating client : \(status)")

}

// cannot set up input port in a playground it seems
func MyMIDIReadBlock(packetList: UnsafePointer<MIDIPacketList>, srcConnRefCon: UnsafeMutableRawPointer?) -> Swift.Void {
    
    let packets = packetList.pointee
    let packet:MIDIPacket = packets.packet
    // etc.
}

var readBlock:MIDIReadBlock = MyMIDIReadBlock

if status == noErr {

    // doesn't like this
//    status = MIDIInputPortCreateWithBlock(midiClient, "com.rockhoppertech.MIDIInputPort" as CFString, &inputPort, readBlock)
//    if status == noErr {
//        print("created input port \(inputPort)")
//    } else {
//        print("error creating input port : \(status)")
//    }
    
    
    status = MIDIOutputPortCreate(midiClient,
                                  "com.rockhoppertech.OutputPort" as CFString,
                                  &outputPort)
    if status == noErr {
        print("created output port \(outputPort)")
    } else {
        print("error creating output port : \(status)")
    }
}

// doesn't enable it. this code works in an app
func enableNetwork() {
    MIDINetworkSession.default().isEnabled = true
    MIDINetworkSession.default().connectionPolicy = .anyone
    
    print("net session enabled \(MIDINetworkSession.default().isEnabled)")
    print("net session networkPort \(MIDINetworkSession.default().networkPort)")
    print("net session networkName \(MIDINetworkSession.default().networkName)")
    print("net session localName \(MIDINetworkSession.default().localName)")
    
}

enableNetwork()



internal func createMusicSequence() -> MusicSequence? {
    
    var musicSequence:MusicSequence?
    var status = NewMusicSequence(&musicSequence)
    if status != noErr {
        print("\(#line) bad status \(status) creating sequence")

    }
    
    if let sequence = musicSequence {
        
        // add a track
        var newtrack: MusicTrack?
        status = MusicSequenceNewTrack(sequence, &newtrack)
        if status != noErr {
            print("error creating track \(status)")

        }
        
        if let track = newtrack {
            
            // bank select msb
            var chanmess = MIDIChannelMessage(status: 0xB0, data1: 0, data2: 0, reserved: 0)
            status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
            if status != noErr {
                print("creating bank select event \(status)")

            }
            // bank select lsb
            chanmess = MIDIChannelMessage(status: 0xB0, data1: 32, data2: 0, reserved: 0)
            status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
            if status != noErr {
                print("creating bank select event \(status)")

            }
            
            // program change. first data byte is the patch, the second data byte is unused for program change messages.
            chanmess = MIDIChannelMessage(status: 0xC0, data1: 0, data2: 0, reserved: 0)
            status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
            if status != noErr {
                print("creating program change event \(status)")

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
                    print("creating new midi note event \(status)")

                }
                beat += 1
            }
            
            // associate the AUGraph with the sequence. In this case, I'm using a virtual destination
            // which will forward the messages so this is commented out here.
            //                status = MusicSequenceSetAUGraph(sequence, self.processingGraph)
            //                checkError(status)
            
            // send it to our virtual destination (which will forward it
            // status = MusicSequenceSetMIDIEndpoint(sequence, self.virtualDestinationEndpointRef)

            
            
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
                    print("got user event AA of length \(userData.length)")
                }
            }
            status = MusicSequenceSetUserCallback(sequence, sequencerCallback, nil)
            
            var event = MusicEventUserData(length: 1, data: (0xAA))
            // add the user event
            let status = MusicTrackNewUserEvent(track, beat + MusicTimeStamp(duration), &event)
            if status != noErr {
            }
            
            
            // Let's see it
            CAShow(UnsafeMutablePointer<MusicSequence>(sequence))
            
            let info = MusicSequenceGetInfoDictionary(sequence)
            print("sequence info \(info)")
            //info[kAFInfoDictionary_Copyright] = "2016 bozosoft"
            
            return sequence
        }
        
    }
    
    return nil
}

var sequence = createMusicSequence()


internal func createMusicPlayer(musicSequence:MusicSequence) -> MusicPlayer? {
    var musicPlayer: MusicPlayer?
    var status = noErr
    
    status = NewMusicPlayer(&musicPlayer)
    if status != noErr {
        print("bad status \(status) creating player")
    }
    
    if let player = musicPlayer {
        
        status = MusicPlayerSetSequence(player, musicSequence)
        if status != noErr {
            print("setting sequence \(status)")
        }
        
        status = MusicPlayerPreroll(player)
        if status != noErr {
            print("prerolling player \(status)")
        }
        
        return player
    } else {
        print("musicplayer is nil")
        return nil
    }
}

var musicPlayer = createMusicPlayer(musicSequence: sequence!)

internal func playMusicPlayer() {
    var status = noErr
    var playing = DarwinBoolean(false)
    
    if let player = musicPlayer {
        status = MusicPlayerIsPlaying(player, &playing)
        if playing != false {
            print("music player is playing. stopping")
            status = MusicPlayerStop(player)
            if status != noErr {
                print("Error stopping \(status)")
                return
            }
        } else {
            print("music player is not playing.")
        }
        
        status = MusicPlayerSetTime(player, 0)
        if status != noErr {
            print("Error setting time \(status)")
            return
        }
        
        print("starting to play")
        status = MusicPlayerStart(player)
        if status != noErr {
            print("Error starting \(status)")
            return
        }
    }
}


playMusicPlayer()

