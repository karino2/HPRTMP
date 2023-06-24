//
//  RTMPService.swift
//  HPRTMPExample
//
//  Created by Huiping Guo on 2022/10/22.
//

import Foundation
import HPRTMP

actor RTMPService: RTMPPublishSessionDelegate {
  func sessionStatusChange(_ session: HPRTMP.RTMPPublishSession, status: HPRTMP.RTMPPublishSession.Status) {
    if status == .publishStart {
      reader.start()
    }
  }
  
  func sessionError(_ session: HPRTMP.RTMPPublishSession, error: HPRTMP.RTMPError) {
    
  }
  
  
  private var session = RTMPPublishSession()
  
  var reader: MP4Reader
  
  private var lastVideoTimestamp: UInt64 = 0
  private var lastAudioTimestamp: UInt64 = 0
  
  init() {
//    let url = URL(string: "rtmp://192.168.11.23/live")!
//    let streamKey = "hello"
//    let port = 1935
//    socket.connect(streamURL: url, streamKey: streamKey, port: port)
    let url = Bundle.main.url(forResource: "720p", withExtension: "mp4")!
    reader = MP4Reader(url: url)
  }
  
  func run() async {
    
    await session.setDelegate(self)
    let publishConfig = PublishConfigure(width: 1280, height: 720, videocodecid: VideoData.CodecId.avc.rawValue, audiocodecid: AudioData.SoundFormat.aac.rawValue, framerate: 30, videoDatarate: 30, audioDatarate: nil, audioSamplerate: nil)
    await session.publish(url: "rtmp://192.168.11.48/live/haha", configure: publishConfig)
    
    
    reader.sendAudioHeader = { data in
      Task {
        await self.session.publishAudioHeader(data: data)
      }
    }
    
    reader.sendVideoHeader = { data in
      Task {
        await self.session.publishVideoHeader(data: data, time: 0)
      }
    }
//    
//    reader.sendAudioBuffer = { data,aacHeader,timestamp in
//      Task {
//        var audioPacketData = Data()
//        audioPacketData.append(aacHeader)
//        audioPacketData.write(AudioData.AACPacketType.raw.rawValue)
//        audioPacketData.append(data)
//        
//        let delta: UInt32
//        if self.lastAudioTimestamp == 0 {
//          delta = 0
//        } else {
//          delta = UInt32(timestamp - self.lastAudioTimestamp)
//        }
//        await self.session.publishAudio(data: audioPacketData, delta: delta)
//        self.lastAudioTimestamp = timestamp
//      }
//    }
    
    reader.sendVideoBuffer = { data,isKeyFrame,timestamp,compositionTime in
      Task {
        guard timestamp >= self.lastVideoTimestamp else { return }
        var descData = Data()
        let frameType = isKeyFrame ? VideoData.FrameType.keyframe : VideoData.FrameType.inter
        let frameAndCode:UInt8 = UInt8(frameType.rawValue << 4 | VideoData.CodecId.avc.rawValue)
        descData.append(Data([frameAndCode]))
        descData.append(Data([VideoData.AVCPacketType.nalu.rawValue]))
        
        let delta: UInt32
        if self.lastVideoTimestamp == 0 {
          delta = 0
        } else {
          delta = UInt32(timestamp - self.lastVideoTimestamp)
        }
        // 24bit
        descData.write24(compositionTime, bigEndian: true)
        descData.append(data)
        
        print("[debug] delta \(delta)")
        await self.session.publishVideo(data: descData, delta: UInt32(delta))
        self.lastVideoTimestamp = timestamp
      }
    }
    
    
    
  }
}
