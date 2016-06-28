//
//  main.swift
//  gcode-mash
//
//  Created by Mike Pittelko on 6/22/16.
//  Copyright © 2016 Michael Pittelko. All rights reserved.
//

import Foundation





let cli = CommandLine()

let filePath = StringOption(shortFlag: "f", longFlag: "file", required: true,
                            helpMessage: "Path to the input file.")
let suppressoption = BoolOption(shortFlag: "s", longFlag: "supress",
                          helpMessage: "suppress redundant motion modes.")
let retractoption = BoolOption(shortFlag: "r", longFlag: "retract",
                          helpMessage: "Optimize retract+plunge")
let addonsoption = BoolOption(shortFlag: "a", longFlag: "addon",
                               helpMessage: "Show the addons")
let trimoption = IntOption(shortFlag: "t", longFlag: "trim",
                              helpMessage: "Trim output to this many lines")
let versionoption = BoolOption(shortFlag: "x", longFlag: "version", helpMessage: "Show the revision of the tool")
let zfeed = IntOption(shortFlag: "z", longFlag: "zfeed", helpMessage: "plunge feed rate")

//let help = BoolOption(shortFlag: "h", longFlag: "help",
//                      helpMessage: "Prints a help message.")
let verbose = IntOption(shortFlag: "v", longFlag: "verbose",
                              helpMessage: "Print verbose messages. -v 3 = src->result.")

cli.addOptions(filePath,suppressoption,verbose,retractoption,addonsoption,trimoption,versionoption) //, compress, help, verbosity)

do {
     try cli.parse()
} catch {
     cli.printUsage(error)
     exit(EX_USAGE)
}



func OpenFileAndProcess(file: String)
{
     
     var encoded: UInt = 0
     var text2: String
     var lines: Array<String>
     var program = Array<GCODEParser>()
     var lastone: GCODEParser
     var count = 0
     var SmallestZ: Double = 0.0
     var LargestZ: Double = 0.0
     var SmallestX: Double = 0.0
     var LargestX: Double = 0.0
     var SmallestY: Double = 0.0
     var LargestY: Double = 0.0
     
     
     if (versionoption.wasSet && versionoption.value == true)
     {
          print("Version 0.3")
          exit(0)
     }
     
     do{
          text2 = try String.init(contentsOfFile: file, usedEncoding: &encoded)
          lines = text2.componentsSeparatedByString("\n")
          lastone = GCODEParser.init()
          //lastone.Annotate = true
          if (zfeed.wasSet)
          {
             lastone.ZFeedOverride = Double(zfeed.value!)
          }
          
          if (retractoption.wasSet)
          {
               lastone.OptimizeRetracts = true
          }
          if (suppressoption.wasSet)
          {
               lastone.SuppressRedundantMotionMode = true
          }
          
          
          program.append(lastone)
          
          for word in lines
          {
               lastone = GCODEParser.init(last: program.last!, Block: word)
               
               // Update envelope
               if (lastone.currentPositionX < SmallestX)
               {
                    SmallestX = lastone.currentPositionX
               }
               if (lastone.currentPositionX > LargestX)
               {
                    LargestX = lastone.currentPositionX
               }
               if (lastone.currentPositionY < SmallestY)
               {
                    SmallestY = lastone.currentPositionY
               }
               if (lastone.currentPositionY > LargestY)
               {
                    LargestY = lastone.currentPositionY
               }
               if (lastone.currentPositionZ < SmallestZ)
               {
                    SmallestZ = lastone.currentPositionZ
               }
               if (lastone.currentPositionZ > LargestZ)
               {
                    LargestZ = lastone.currentPositionZ
               }
               
               
               program.append(lastone)
               count = count + 1
               for nexts in lastone.NextStrings
               {
                    count = count + 1
                    lastone = GCODEParser.init(last: program.last!, Block: nexts, opt:false)  // add this one, but don't attempt to optimize
                    program.append(lastone)
                    
               }
               
               count = count + 1
          }
     } catch {
          print("something bad happened. good luck with that.")
          exit(1)
     }
     
     count = 0
     
     //----------------------
     // Find the plunges
     
     // Find the blocks that are Z only
     for n in program
     {
          if (n.InBlock.Z && (!(n.InBlock.X || n.InBlock.Y)))
          {
               // only a Z move in this block
               n.InBlock.OnlyZ = true
          }
     }
     
     // I don't know what to do next with this.
     
     //----------------------
     
     count = 0
     
     for n in program
     {
          count = count + 1
          //if (n.SegmentNumber != n.SegmentNumberNext)
          //{
          //   print("(New Segment \(n.SegmentNumber) Layer: \(n.Layer))")
          //}
          //if (n.Layer != n.PreviousNode!.Layer)
          //{
          //    print("(Layer Change: \(n.Layer), Depth: \(n.DeepestCutSoFar) \(n.UnitString))")
          //}
          //print( n.OutputString.stringByReplacingOccurrencesOfString(" ", withString: "" ) ) // strip out all the spaces while we're at it.
          //print( n.OutputString)

          if (trimoption.wasSet)
          {
               if (count < trimoption.value)
               {
                    print( "\(n.PBlock)")
               }
               
          }
          else  // Not trimming
          {
               if (verbose.value == 3)
               {
                    DumpABlock(n)
               }
               else
               {
                    print( "\(n.PBlock)")
               }
               
          }
          
     }
     
     //print("(Envelope: X:\(SmallestX)->\(LargestX) Y:\(SmallestY)->\(LargestY) Z:\(SmallestZ)->\(LargestZ))")
     
     
}

var TheName: String = ""

OpenFileAndProcess(filePath.value!)

