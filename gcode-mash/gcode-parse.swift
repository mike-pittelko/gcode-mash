//
//  gcode-parse.swift
//  gcode-masher
//
//  Created by Mike Pittelko on 6/15/16.
//  Copyright © 2016 Michael Pittelko. All rights reserved.
//

import Foundation


// Optimizations
//    1)  Redundant sets to G0, G1 motion modes are suppressed
//          if in G0, and G0 received, does not re-emit the G0 in outputString
//          if in G1, and G1 received, does not re-emit the G1 in outputString
//    2)  TODO: Using least distance, reorder the sements in a layer to reduce the rapid distance.  (works in XYZ)
//              First, find the last currentxyz in the segment.
//              Second, find the first currentxy in all the other segments
//              third, select the segment that has the closest start currentxyz. This is the next segment.
//              When you run out of segments in the layer, use the first segment of the next layer as the next segment.
//              Layer depends on Z, so if this is a carve with varying Z in a given "layer" this probably won't work right.
//    3)  TODO: Optimize retraction performance
//              First, find each retract.
//              Second, for each retract, find the next plunge
//              Third, If the plunge is deeper than the deepest plunge so far, convert the plunge to be a rapid
//                   to just above the deepest cut so far, then linear to the original depth.
//    4)  TODO: Optimize redundant plunges -- works with XYZ, not 4+ axis.
//              First, find each tract.
//              Second, find the next plunge
//              Third, If the plunge (xy) is occurring at the location of the last retract (xy), remove the retract. Convert
//                     the plunge to be a linear to the new depth.

//
// Other manipulations
//    1)  If a fatal error is found in a block will flag block with "*" and set FatalError != .None
//    2)  Warnings and Error text will be in Errors string
//    3)
//
// Drop Block Switch is implemented (/).  Any block that has a "/" character at the begining of the line, and the "Switch"
//   is on, will not be executed (it will not manipulate the machine state) but will be output.
// Misc notes:
//   Retraction above or to the "ReferencePlane" marks the end of a given "segment". Defaults to zero, which is assumed
//      to be the top surface of the stock. If it is not, set the reference plane appropriately.
//   Each segment is assumed to be reorderable for a given depth.
//   Each "layer" is the collection of sements at the same depth
//   Annotation: Enables layer, deepest cut, segment display on each output line.  Not that if you do this, the output text
//               is not rerunnable.
//
// If you reorder the words, such that the "last's" are no longer accurate, I strongly recommend that you then rerun the whole
// job, running the "outputstrings" through the parser and generating a whole new set of nodes.
//





class  GCODEParser
{
     
     enum FatalErrorType
     {
          case Unimplemented     // Fatal error, unimplemented functionality
          case Syntax            // Fatal error, bad grammer/syntax
          case Unknown           // Fatal error, unknown cause
          case None              // No fatal error
     }
     
     enum MotionModalGroup
     {
          case None
          case G0
          case G1
          case G2
          case G3
          case G38_2
          case G80
          case G81
          case G82
          case G83
          case G84
          case G85
          case G86
          case G87
          case G88
          case G89
     }
     
     enum PlaneSelectionModalGroup
     {
          case None
          case G17
          case G18
          case G19
     }
     
     enum DistanceModalGroup
     {
          case None
          case G90
          case G91
     }
     
     enum FeedRateModalGroup
     {
          case None
          case G93
          case G94
     }
     enum UnitModalGroup
     {
          case None
          case G20
          case G21
     }
     
     enum CutterRadiusCompensationModalGroup
     {
          case None
          case G40
          case G41
          case G42
     }
     
     enum ToolLengthOffsetModalGroup
     {
          case None
          case G43
          case G49
     }
     
     enum ReturnModeCannedCycleModalGroup
     {
          case None
          case G98
          case G99
     }
     
     enum CoordinateSystemModalGroup
     {
          case None
          case G54
          case G55
          case G56
          case G57
          case G58
          case G59
          case G59_1
          case G59_2
          case G59_3
     }
     
     enum PathControlModalGroup
     {
          case None
          case G61
          case G61_1
          case G64
     }
     
     enum StoppingModalGroup
     {
          case None
          case M0
          case M1
          case M2
          case M30
          case M60
     }
     
     enum ToolChangeModalGroup
     {
          case None
          case M6
     }
     
     enum SpindleModalGroup
     {
          case None
          case M3
          case M4
          case M5
     }
     enum CoolantModalGroup
     {
          case None
          case M7
          case M8
          case M7andM8
          case M9
     }
     enum FeedOverrideModalGroup
     {
          case None
          case M48
          case M49
     }
     enum NonModalGroup
     {
          case None
          case G4
          case G10
          case G28
          case G30
          case G53
          case G92
          case G92_1
          case G92_2
          case G92_3
     }
     
     enum LastMovementWasEnum
     {
          case X
          case Y
          case Z
          case A
          case B
          case C
          case None
     }
     
     let commandletters: String = "ABCDFGHIJKLMNPQRSTXYZ"
     let allletters: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
     
     var FatalError: FatalErrorType = .None
     var X: Double = 0.0 // x pos
     var Y: Double = 0.0 // y pos
     var Z: Double = 0.0 // z pos
     var A: Double = 0.0 // a pos
     var B: Double = 0.0 // b pos
     var C: Double = 0.0 // c pos
     var F: Double = 0.0 // feed rate
     var S: Double = 0.0 // spindle rate
     var R: Double = 0.0 // Position of retract plane
     var I: Double = 0.0 // Parameters for arcs
     var J: Double = 0.0 // Parameters for arcs
     var N: Double = 0.0  // line number
     var T: Double = 0.0  // tool number
     var P: Int = 0       // Pause/dwell time
     var L: Int = 0       // repeat block count
     var lastLinearX = 0.0
     var lastLinearY = 0.0
     var lastLinearZ = 0.0
     var lastLinearA = 0.0
     var lastLinearB = 0.0
     var lastLinearC = 0.0
     var lastRapidX = 0.0
     var lastRapidY = 0.0
     var lastRapidZ = 0.0
     var lastRapidA = 0.0
     var lastRapidB = 0.0
     var lastRapidC = 0.0
     var currentPositionX = 0.0
     var currentPositionY = 0.0
     var currentPositionZ = 0.0
     var currentPositionA = 0.0
     var currentPositionB = 0.0
     var currentPositionC = 0.0
     var SettingCoordinateSystem = 0
     var CoordinateSystemX: Array <Double> = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
     var CoordinateSystemY: Array <Double> = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
     var CoordinateSystemZ: Array <Double> = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
     var CoordinateSystemA: Array <Double> = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
     var CoordinateSystemB: Array <Double> = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
     var CoordinateSystemC: Array <Double> = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
     var AxisOffsetValuesX = 0.0
     var AxisOffsetValuesY = 0.0
     var AxisOffsetValuesZ = 0.0
     var AxisOffsetValuesA = 0.0
     var AxisOffsetValuesB = 0.0
     var AxisOffsetValuesC = 0.0
     var AtOrAboveReference = false
     
     var SettingDwell = false
     var Dwelling = false
     var ParameterFileOffsetsBeingSet = false
     var ParameterFile: Array <Double> = [Double](count: 5401, repeatedValue: 0.0)
     var NeedFeedRate = false
     var wordsProcessed: Int = 0
     var SegmentNumber = 0
     var SegmentNumberNext = 0
     var Annotate = false
     
     
     var LastMovementWas = LastMovementWasEnum.None
     var MotionMode =  MotionModalGroup.None
     var FeedOverrideMode = FeedOverrideModalGroup.None
     var CoolantMode = CoolantModalGroup.None
     var ToolChangeMode = ToolChangeModalGroup.None
     var SpindleMode = SpindleModalGroup.None
     var StoppingMode = StoppingModalGroup.None
     var PlaneSelectionMode = PlaneSelectionModalGroup.None
     var DistanceMode = DistanceModalGroup.None
     var FeedRateMode = FeedRateModalGroup.G94
     var UnitMode = UnitModalGroup.None
     var CutterRadiusCompensationMode = CutterRadiusCompensationModalGroup.None
     var ToolLengthOffsetMode = ToolLengthOffsetModalGroup.None
     var ReturnModeCannedCycleMode = ReturnModeCannedCycleModalGroup.None
     var CoordinateSystemMode = CoordinateSystemModalGroup.None
     var PathControlMode = PathControlModalGroup.None
     var AbsolutePositioningMode = false
     var FeedRateFound = false
     var BlockDeleteSwitch = false
     var TransitionedAboveReferencePlane = false
     var Layer = 0
     var NextLayer = 0
     var TransitionedToNextLayer = false
     var DeepestCutSoFar = +555555555555.0
     
     var PreviousNode: GCODEParser?
     var OutputString: String = ""
     var Errors: String = ""
     
     // Constants
     let ReferencePlane = 0.0    // Z<=Referenceplane = last move inside this segment.
     
     init()
     {
          
          X = 0.0 // x pos
          Y = 0.0 // y pos
          Z = 0.0 // z pos
          A = 0.0 // a pos
          B = 0.0 // b pos
          C = 0.0 // c pos
          F = 0.0 // feed rate
          S = 0.0 // spindle rate
          R = 0.0 // Position of retract plane
          I = 0.0
          J = 0.0
          N = 0.0  // line number
          T = 0.0  // tool number
          P = 0    // pause/dwell time
          L = 0    // Repeat block count
          lastLinearX = 0.0
          lastLinearY = 0.0
          lastLinearZ = 0.0
          lastLinearA = 0.0
          lastLinearB = 0.0
          lastLinearC = 0.0
          lastRapidX = 0.0
          lastRapidY = 0.0
          lastRapidZ = 0.0
          lastRapidA = 0.0
          lastRapidB = 0.0
          lastRapidC = 0.0
          currentPositionX = 0.0
          currentPositionY = 0.0
          currentPositionZ = 0.0
          currentPositionA = 0.0
          currentPositionB = 0.0
          currentPositionC = 0.0
          CoordinateSystemX = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
          CoordinateSystemY = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
          CoordinateSystemZ = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
          CoordinateSystemA = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
          CoordinateSystemB = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
          CoordinateSystemC = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
          AxisOffsetValuesX = 0.0
          AxisOffsetValuesY = 0.0
          AxisOffsetValuesZ = 0.0
          AxisOffsetValuesA = 0.0
          AxisOffsetValuesB = 0.0
          AxisOffsetValuesC = 0.0
          
          LastMovementWas = LastMovementWasEnum.None
          MotionMode =  MotionModalGroup.None
          FeedOverrideMode = FeedOverrideModalGroup.None
          CoolantMode = CoolantModalGroup.None
          ToolChangeMode = ToolChangeModalGroup.None
          SpindleMode = SpindleModalGroup.None
          StoppingMode = StoppingModalGroup.None
          PlaneSelectionMode = PlaneSelectionModalGroup.None
          DistanceMode = DistanceModalGroup.None
          FeedRateMode = FeedRateModalGroup.G94
          UnitMode = UnitModalGroup.None
          CutterRadiusCompensationMode = CutterRadiusCompensationModalGroup.None
          ToolLengthOffsetMode = ToolLengthOffsetModalGroup.None
          ReturnModeCannedCycleMode = ReturnModeCannedCycleModalGroup.None
          CoordinateSystemMode = CoordinateSystemModalGroup.None
          PathControlMode = PathControlModalGroup.None
          AbsolutePositioningMode = false
          FeedRateFound = false
          wordsProcessed = 0
          FatalError = .None
          
          SettingDwell = false
          Dwelling = false
          ParameterFileOffsetsBeingSet = false
          ParameterFile = [Double](count: 5401, repeatedValue: 0.0)
          ParameterFile[5220] = 1.0  // Current coordinate system
          NeedFeedRate = false
          SettingCoordinateSystem = 0
          BlockDeleteSwitch = false;
          AtOrAboveReference = false;
          TransitionedAboveReferencePlane = false
          SegmentNumber = 0
          SegmentNumberNext = 0
          Layer = 0
          NextLayer = 0
          TransitionedToNextLayer = false
          DeepestCutSoFar = +55555555555.0
          Annotate = false
          
          
     }
     
     convenience init(Block: String)
     {
          
          self.init()
          ParseGCodeBlock(Block)
     }
     
     convenience init(last: GCODEParser , Block: String)
     {
          
          self.init()
          PreviousNode = last
          AbsolutePositioningMode = last.AbsolutePositioningMode
          PathControlMode = last.PathControlMode
          CoordinateSystemMode = last.CoordinateSystemMode
          LastMovementWas = last.LastMovementWas
          MotionMode = last.MotionMode
          FeedOverrideMode = last.FeedOverrideMode
          CoolantMode = last.CoolantMode
          ToolChangeMode = last.ToolChangeMode
          SpindleMode = last.SpindleMode
          StoppingMode = last.StoppingMode
          PlaneSelectionMode = last.PlaneSelectionMode
          DistanceMode = last.DistanceMode
          FeedRateMode = last.FeedRateMode
          UnitMode = last.UnitMode
          CutterRadiusCompensationMode = last.CutterRadiusCompensationMode
          ToolLengthOffsetMode = last.ToolLengthOffsetMode
          ReturnModeCannedCycleMode = last.ReturnModeCannedCycleMode
          X = last.X
          Y = last.Y
          Z = last.Z
          A = last.A
          B = last.B
          C = last.C
          F = last.F
          S = last.S
          R = last.R
          I = last.I
          J = last.J
          N = last.N
          T = last.T
          P = last.P
          L = last.L
          lastLinearA = last.lastLinearA
          lastLinearB = last.lastLinearB
          lastLinearC = last.lastLinearA
          lastLinearX = last.lastLinearX
          lastLinearY = last.lastLinearY
          lastLinearZ = last.lastLinearZ
          lastRapidA = last.lastRapidA
          lastRapidB = last.lastRapidB
          lastRapidC = last.lastRapidC
          lastRapidX = last.lastRapidX
          lastRapidY = last.lastRapidY
          lastRapidZ = last.lastRapidZ
          currentPositionA = last.currentPositionA
          currentPositionB = last.currentPositionB
          currentPositionC = last.currentPositionC
          currentPositionX = last.currentPositionX
          currentPositionY = last.currentPositionY
          currentPositionZ = last.currentPositionZ
          CoordinateSystemA = last.CoordinateSystemA
          CoordinateSystemB = last.CoordinateSystemB
          CoordinateSystemC = last.CoordinateSystemC
          CoordinateSystemX = last.CoordinateSystemX
          CoordinateSystemY = last.CoordinateSystemY
          CoordinateSystemZ = last.CoordinateSystemZ
          AxisOffsetValuesA = last.AxisOffsetValuesA
          AxisOffsetValuesB = last.AxisOffsetValuesB
          AxisOffsetValuesC = last.AxisOffsetValuesC
          AxisOffsetValuesX = last.AxisOffsetValuesX
          AxisOffsetValuesY = last.AxisOffsetValuesY
          AxisOffsetValuesZ = last.AxisOffsetValuesZ
          
          SettingDwell = false
          Dwelling = last.Dwelling
          ParameterFileOffsetsBeingSet = false
          ParameterFile = last.ParameterFile
          NeedFeedRate = false
          SettingCoordinateSystem = 0
          FatalError = .None
          BlockDeleteSwitch = last.BlockDeleteSwitch
          AtOrAboveReference = false;
          TransitionedAboveReferencePlane = false
          SegmentNumber = last.SegmentNumberNext
          Layer = last.NextLayer
          NextLayer = Layer
          TransitionedToNextLayer = false
          DeepestCutSoFar = last.DeepestCutSoFar
          Annotate = last.Annotate
          
          ParseGCodeBlock(Block)
          
          
     }
     
     // Set the state of the block delete switch
     // If "true" sitch is on, and any block delete blocks will be skipped (/)
     func BlockDeleteSwitch(state: Bool)
     {
          BlockDeleteSwitch = state
     }
     
     ///////////////////////////////////////////////////////
     //
     // Extract a double value from the given word (G1.23)
     //
     ///////////////////////////////////////////////////////
     func ExtractDoubleValue(BlockToParse: String) -> Double
     {
          
          let workingString = BlockToParse.stringByTrimmingCharactersInSet(NSCharacterSet.uppercaseLetterCharacterSet())
          let scan = NSScanner(string: workingString)
          var result = 0.0;
          
          scan.scanDouble(&result)
          
          return (result)
     }
     
     ///////////////////////////////////////////////////////
     //
     // Extract a Int value from the given word (G1.23)
     //
     ///////////////////////////////////////////////////////
     func ExtractIntValue(BlockToParse: String) -> Int
     {
          let workingString = BlockToParse.stringByTrimmingCharactersInSet(NSCharacterSet.uppercaseLetterCharacterSet())
          let scan = NSScanner(string: workingString)
          var result: Int = 0;
          
          scan.scanInteger(&result)
          
          return (result)
     }
     
     
     //return val = emit. if true, re-emit the word
     
     func GCode_P(value: Int) -> Bool
     {
          if (SettingCoordinateSystem == -1)
          {
               P = value
               SettingCoordinateSystem = value
          }
          if (SettingDwell)
          {
               P = value
               Dwelling = true;
               // Whatever we should do for dwell should happen now. We may be between XYZ words, so it has to happen here, not at
               // the end of the block cycle.
          }
          return true
     }
     func GCode_Q(value: Double) -> Bool
     {
          Errors = Errors + "Q \(value)\n"
          return true
     }
     func GCode_T(value: Double) -> Bool  // Select Tool
     {
          if (T == value)
          {
               Errors = Errors + "Redundant Tool Selection (Tool \(T))\n"// Redundant tool selection
               return false
          }
          else
          {
               T = value
               return true
          }
     }
     func GCode_A(value: Double) -> Bool  // A axis value
     {
          var retVal = true
          
          if (SettingCoordinateSystem >= 1)
          {
               CoordinateSystemA[P] = value;
               ParameterFile[5224 + ((P-1)*20)] = value
               return true
          }
          if (ParameterFileOffsetsBeingSet)
          {
               ParameterFile[5214] = value;
               return true
          }
          
          switch (MotionMode)
          {
          case MotionModalGroup.G0 : // Rapid
               lastRapidA = value
               if (AbsolutePositioningMode)
               {
                    currentPositionA = value
               }
               else{
                    currentPositionA = currentPositionA + value;
               }
               
               break
          case MotionModalGroup.G1 : // Linear
               lastLinearA = value
               if (AbsolutePositioningMode)
               {
                    currentPositionA = value
               }
               else{
                    currentPositionA = currentPositionA + value;
               }
               break
               
          default:
               Errors = Errors + "No motion mode, with A word\n"
               break
               
          }
          return retVal
          
     }
     func GCode_B(value: Double) -> Bool  // B axis value
     {
          var retVal = true
          
          if (SettingCoordinateSystem >= 1)
          {
               CoordinateSystemB[P] = value;
               ParameterFile[5225 + ((P-1)*20)] = value
               return true
          }
          if (ParameterFileOffsetsBeingSet)
          {
               ParameterFile[5215] = value;
               return true
          }
          switch (MotionMode)
          {
          case MotionModalGroup.G0 : // Rapid
               lastRapidB = value
               if (AbsolutePositioningMode)
               {
                    currentPositionB = value
               }
               else{
                    currentPositionB = currentPositionA + value;
               }
               
               break
          case MotionModalGroup.G1 : // Linear
               lastLinearB = value
               if (AbsolutePositioningMode)
               {
                    currentPositionB = value
               }
               else{
                    currentPositionB = currentPositionB + value;
               }
               
               break
               
          default:
               Errors = Errors + "No motion mode, with B word\n"
               break
               
               
          }
          return retVal
          
          
          
     }
     func GCode_C(value: Double) -> Bool  // C axis value
     {
          var retVal = true
          
          if (SettingCoordinateSystem >= 1)
          {
               CoordinateSystemC[P] = value;
               ParameterFile[5226 + ((P-1)*20)] = value
               return true
          }
          if (ParameterFileOffsetsBeingSet)
          {
               ParameterFile[5216] = value;
               return true
          }
          
          switch (MotionMode)
          {
          case MotionModalGroup.G0 : // Rapid
               lastRapidC = value
               if (AbsolutePositioningMode)
               {
                    currentPositionC = value
               }
               else{
                    currentPositionC = currentPositionC + value;
               }
               
               break
          case MotionModalGroup.G1 : // Linear
               lastLinearC = value
               if (AbsolutePositioningMode)
               {
                    currentPositionC = value
               }
               else{
                    currentPositionC = currentPositionC + value;
               }
               
               break
               
          default:
               Errors = Errors + "No motion mode, with C word\n"
               break
          }
          return retVal
     }
     func GCode_D(value: Double) -> Bool
     {
          Errors = Errors + "D \(value)\n"
          return true
          
     }
     func GCode_H(value: Double) -> Bool
     {
          Errors = Errors + "H \(value)\n"
          return true
          
     }
     func GCode_I(value: Double) -> Bool
     {
          Errors = Errors + "I \(value)\n"
          return true
          
     }
     func GCode_J(value: Double) -> Bool
     {
          Errors = Errors + "J \(value)\n"
          return true
          
     }
     func GCode_K(value: Double) -> Bool
     {
          Errors = Errors + "K \(value)\n"
          return true
          
     }
     ///////////////////////////////////////////////////////
     //
     // Extracts the G word, places the value and
     // adjusts the machine state for the command
     //
     ///////////////////////////////////////////////////////
     
     func GCode_Gx(value: Double) -> Bool
     {
          var retVal: Bool = true
          
          switch (value)
          {
          case 0:
               if MotionMode != .G0
               {
                    MotionMode = .G0
               }
               else
               {
                    Errors = Errors + "Motion Mode G0 already set\n"
                    retVal = false
                    
               }
               break
          case 1:
               if MotionMode != .G1
               {
                    MotionMode = .G1
               }
               else
               {
                    Errors = Errors + "Motion Mode G1 already set\n "
                    retVal = false
                    
               }
               if (FeedRateMode == .G93)
               {
                    NeedFeedRate = true
                    FeedRateFound = false
               }
               break
          case 2:
               MotionMode = .G2
               if (FeedRateMode == .G93)
               {
                    NeedFeedRate = true
                    FeedRateFound = false
               }
               Errors = Errors + " Don't understand that motion mode (G2) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 3:
               MotionMode = .G3
               if (FeedRateMode == .G93)
               {
                    NeedFeedRate = true
                    FeedRateFound = false
               }
               Errors = Errors + " Don't understand that motion mode (G3) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 38.2:
               MotionMode = .G38_2
               Errors = Errors + " Don't understand that motion mode (G38.2) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 80:
               MotionMode = .G80  // Cancel motion modes
               break
          case 81:
               MotionMode = .G81
               Errors = Errors + " Don't understand that motion mode (G81) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 82:
               MotionMode = .G82
               Errors = Errors + " Don't understand that motion mode (G82) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 83:
               MotionMode = .G83
               Errors = Errors + " Don't understand that motion mode (G83) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 84:
               MotionMode = .G84
               Errors = Errors + " Don't understand that motion mode (G84) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 85:
               MotionMode = .G85
               Errors = Errors + " Don't understand that motion mode (G85) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 86:
               MotionMode = .G86
               Errors = Errors + " Don't understand that motion mode (G86) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 87:
               MotionMode = .G87
               Errors = Errors + " Don't understand that motion mode (G87) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 88:
               MotionMode = .G88
               Errors = Errors + " Don't understand that motion mode (G88) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
          case 89:
               MotionMode = .G89
               Errors = Errors + " Don't understand that motion mode (G89) yet. Sorry. The rest of the file will be processed incorrectly.\n"  // TODO
               FatalError = .Unimplemented
               break
               
          case 17:
               PlaneSelectionMode = .G17
               break
          case 18:
               PlaneSelectionMode = .G18
               break
          case 19:
               PlaneSelectionMode = .G19
               break
               
          case 90:
               DistanceMode = .G90
               AbsolutePositioningMode = true
               break
          case 91:
               DistanceMode = .G91
               AbsolutePositioningMode = false
               break
               
          case 93:
               FeedRateMode = .G93  // Inverse time mode
               break
          case 93:
               FeedRateMode = .G94 // units per minute mode  (normal mode)
               break
               
          case 20:
               UnitMode = .G20
               break
          case 21:
               UnitMode = .G21
               break
               
          case 40:
               CutterRadiusCompensationMode = .G40
               break
          case 41:
               CutterRadiusCompensationMode = .G41
               break
          case 42:
               CutterRadiusCompensationMode = .G42
               break
               
          case 43:
               ToolLengthOffsetMode = .G43
               break
          case 49:
               ToolLengthOffsetMode = .G49
               break
               
          case 98:
               ReturnModeCannedCycleMode = .G98
               break
          case 99:
               ReturnModeCannedCycleMode = .G99
               break
               
               
          case 54:
               // Offsets zero
               CoordinateSystemMode = .G54
               break
          case 55:
               CoordinateSystemMode = .G55
               break
          case 56:
               CoordinateSystemMode = .G56
               break
          case 57:
               CoordinateSystemMode = .G57
               break
          case 58:
               CoordinateSystemMode = .G58
               break
          case 59:
               CoordinateSystemMode = .G59
               break
          case 59.1:
               CoordinateSystemMode = .G59_1
               break
          case 59.2:
               CoordinateSystemMode = .G59_2
               break
          case 59.4:
               CoordinateSystemMode = .G59_3
               break
               
          case 61:
               PathControlMode = .G61
               break
          case 61.1:
               PathControlMode = .G61_1
               break
          case 64:
               PathControlMode = .G64
               break
               
          case 53:
               if ((MotionMode == .G0) || (MotionMode == .G1) && (CutterRadiusCompensationMode == .G40))
               {
                    AbsolutePositioningMode = true
               }
               else
               {
                    Errors = Errors + "G53 with G0, G1, or G40 in effect\n"
                    FatalError = .Syntax
               }
               break
               
          case 4:// Dwell
               SettingDwell = true;
               break
          case 10: // Set coordinate system data. Px comes next, then XYZABC
               SettingCoordinateSystem = -1
               break
          case 28: // Return Home 1
               GCode_Gx(0)
               GCode_X(ParameterFile[5161])
               GCode_Y(ParameterFile[5162])
               GCode_Z(ParameterFile[5163])
               GCode_A(ParameterFile[5164])
               GCode_B(ParameterFile[5165])
               GCode_C(ParameterFile[5166])
               break
          case 30: // Return home 2
               GCode_Gx(0)  // Rapid home
               GCode_X(ParameterFile[5181])
               GCode_Y(ParameterFile[5182])
               GCode_Z(ParameterFile[5183])
               GCode_A(ParameterFile[5184])
               GCode_B(ParameterFile[5185])
               GCode_C(ParameterFile[5186])
               break
          case 92: // Set offsets
               ParameterFileOffsetsBeingSet = true
               
               break
          case 92.1: // Clear parameters for axis offsets, clear parameter file
               AxisOffsetValuesX = 0.0
               AxisOffsetValuesY = 0.0
               AxisOffsetValuesZ = 0.0
               AxisOffsetValuesA = 0.0
               AxisOffsetValuesB = 0.0
               AxisOffsetValuesC = 0.0
               ParameterFile[5211] = 0.0
               ParameterFile[5212] = 0.0
               ParameterFile[5213] = 0.0
               ParameterFile[5214] = 0.0
               ParameterFile[5215] = 0.0
               ParameterFile[5216] = 0.0
               break
          case 92.2:  // Clear offsets, leave parameter file alone.
               AxisOffsetValuesX = 0.0
               AxisOffsetValuesY = 0.0
               AxisOffsetValuesZ = 0.0
               AxisOffsetValuesA = 0.0
               AxisOffsetValuesB = 0.0
               AxisOffsetValuesC = 0.0
               break
          case 92.3:  // Set axis offsets to those in parameter file.
               AxisOffsetValuesX = ParameterFile[5211]
               AxisOffsetValuesY = ParameterFile[5212]
               AxisOffsetValuesZ = ParameterFile[5213]
               AxisOffsetValuesA = ParameterFile[5214]
               AxisOffsetValuesB = ParameterFile[5215]
               AxisOffsetValuesC = ParameterFile[5216]
               break
               
          default:
               Errors = Errors + "Unknown G\(value)\n "
               break
               
          }
          return retVal
          
     }
     
     ///////////////////////////////////////////////////////
     //
     // Extracts the M word, and places the value and
     // adjusts the machine state for the command
     //
     ///////////////////////////////////////////////////////
     
     func GCode_Mx(value: Double) -> Bool
     {
          switch (value)
          {
          case 0:
               StoppingMode = .M0
               break
          case 1:
               StoppingMode = .M1
               break
          case 2:
               StoppingMode = .M2
               DistanceMode = .G90
               PlaneSelectionMode = .G17
               FeedRateMode = .G94
               FeedOverrideMode = .M48
               CutterRadiusCompensationMode = .G40
               SpindleMode = .M5
               MotionMode = .G1
               CoolantMode = .M9
               CoordinateSystemMode = .G54
               GCode_Gx(92.2)
               break
          case 30:
               StoppingMode = .M30
               DistanceMode = .G90
               PlaneSelectionMode = .G17
               FeedRateMode = .G94
               FeedOverrideMode = .M48
               CutterRadiusCompensationMode = .G40
               SpindleMode = .M5
               MotionMode = .G1
               CoolantMode = .M9
               CoordinateSystemMode = .G54
               GCode_Gx(92.2)
               break
          case 60:
               StoppingMode = .M60
               break
               
          case 6:
               ToolChangeMode = .M6   // change the tool
               SpindleMode = .M5      // spindle off
               break
               
          case 3: // Spindle turn CW, ON
               SpindleMode = .M3
               break
          case 4: // Spindle turn CCW, ON
               SpindleMode = .M4
               break
          case 5: // Spindle off
               SpindleMode = .M5
               break
               
          case 7: // coolant on
               if (CoolantMode == .M8)
               {
                    CoolantMode = .M7andM8
               }
               else
               {
                    CoolantMode = .M7
               }
               
          case 8:// mist on
               if (CoolantMode == .M7)
               {
                    CoolantMode = .M7andM8
               }
               else
               {
                    CoolantMode = .M8
               }
               
          case 9: // coolant off
               CoolantMode = .M9
               break
               
          case 48: // enable feed/speed override switches
               FeedOverrideMode = .M48
               break
          case 49: // disable feed/speed override switches
               FeedOverrideMode = .M49
               break
               
          default:
               Errors = Errors + "Unknown M\(value) word\n"
               break
          }
          
          
          return true
          
     }
     
     // I think this is a repeat line word, need to confirm
     func GCode_L(value: Int) -> Bool
     {
          L = value
          Errors = Errors + "L \(value)\n"
          return true
          
     }
     func GCode_N(value: Double) -> Bool  // Line number
     {
          N = value
          return true
          
     }
     func GCode_F(value: Double) -> Bool   // Feed rate. No impact on rapid motion.
     {
          F = value
          FeedRateFound = true;
          return true
          
     }
     func GCode_R(value: Double) -> Bool
     {
          Errors = Errors + "R \(value)\n"
          return true
          
     }
     func GCode_S(value: Double) -> Bool  // Spindle speed
     {
          if (value < 0)
          {
               Errors = Errors + "Attempt to set the spindle speed less than zero. Not set.\n"
               return false;
          }
          S = value
          return true
          
     }
     ///////////////////////////////////////////////////////
     //
     // Extracts the X word, and places the value and
     // adjusts the current position based on the current
     // movement word.
     //
     ///////////////////////////////////////////////////////
     func GCode_X(value: Double) -> Bool
     {
          var retVal: Bool = true;
          
          if (SettingCoordinateSystem >= 1)
          {
               CoordinateSystemX[P] = value;
               ParameterFile[5221 + ((P-1)*20)] = value
               return true
          }
          if (ParameterFileOffsetsBeingSet)
          {
               ParameterFile[5211] = value;
               return true
          }
          
          switch (MotionMode)
          {
          case MotionModalGroup.G0 : // Rapid
               
               if (value == currentPositionX)
               {
                    // Here's a move that didn't need to happen.
               }
               lastRapidX = value
               if (AbsolutePositioningMode)
               {
                    currentPositionX = value
               }
               else{
                    currentPositionX = currentPositionX + value;
               }
               
               break
          case MotionModalGroup.G1 : // Linear
               lastLinearX = value
               if (AbsolutePositioningMode)
               {
                    currentPositionX = value
               }
               else{
                    currentPositionX = currentPositionX + value;
               }
               break
               
          default:
               Errors = Errors + "No motion mode, with X word\n"
               FatalError = .Syntax
               break
               
               
          }
          return retVal
          
     }
     
     ///////////////////////////////////////////////////////
     //
     // Extracts the Y word, and places the value and
     // adjusts the current position based on the current
     // movement mode.
     //
     ///////////////////////////////////////////////////////
     func GCode_Y(value: Double) -> Bool
     {
          var retVal: Bool = true;
          
          if (SettingCoordinateSystem >= 1)
          {
               CoordinateSystemY[P] = value;
               ParameterFile[5222 + ((P-1)*20)] = value
               return true
          }
          if (ParameterFileOffsetsBeingSet)
          {
               ParameterFile[5212] = value;
               return true
          }
          
          switch (MotionMode)
          {
          case MotionModalGroup.G0 : // Rapid
               lastRapidY = value
               if (AbsolutePositioningMode)
               {
                    currentPositionY = value
               }
               else{
                    currentPositionY = currentPositionY + value;
               }
               
               break
          case MotionModalGroup.G1 : // Linear
               lastLinearY = value
               if (AbsolutePositioningMode)
               {
                    currentPositionY = value
               }
               else{
                    currentPositionY = currentPositionY + value;
               }
               break
               
          default:
               Errors = Errors + "No motion mode, with Y word\n"
               FatalError = .Syntax
               break
               
               
          }
          return retVal
          
     }
     
     ///////////////////////////////////////////////////////
     //
     // Extracts the Z word, and places the value and
     // adjusts the current position based on the current
     // movement mode.
     //
     ///////////////////////////////////////////////////////
     
     func GCode_Z(value: Double) -> Bool
     {
          var retVal: Bool = true;
          var lastPositionZ = 0.0
          
          if (SettingCoordinateSystem >= 1)
          {
               CoordinateSystemZ[P] = value;
               ParameterFile[5223 + ((P-1)*20)] = value
               return true
          }
          if (ParameterFileOffsetsBeingSet)
          {
               ParameterFile[5213] = value;
               return true
          }
          
          switch (MotionMode)
          {
          case MotionModalGroup.G0 : // Rapid
               lastPositionZ = currentPositionZ
               
               lastRapidZ = value
               if (AbsolutePositioningMode)
               {
                    currentPositionZ = value
               }
               else{
                    currentPositionZ = currentPositionZ + value;
               }
               if (currentPositionZ >= ReferencePlane) && ( lastPositionZ < ReferencePlane)
               {
                    TransitionedAboveReferencePlane = true
               }
               if (currentPositionZ < DeepestCutSoFar)  // Are we cutting a new layer?
               {
                    DeepestCutSoFar = currentPositionZ
                    Layer = Layer + 1
                    NextLayer = Layer
               }
               
               
               break
          case MotionModalGroup.G1 : // Linear
               lastPositionZ = currentPositionZ
               lastLinearZ = value
               if (AbsolutePositioningMode)
               {
                    currentPositionZ = value
               }
               else{
                    currentPositionZ = currentPositionZ + value;
               }
               if (currentPositionZ >= ReferencePlane) && ( lastPositionZ < ReferencePlane)
               {
                    TransitionedAboveReferencePlane = true
               }
               if (currentPositionZ < DeepestCutSoFar)  // Are we cutting a new layer?
               {
                    DeepestCutSoFar = currentPositionZ
                    Layer = Layer + 1
                    NextLayer = Layer
               }
               
               
               break
               
          default:
               Errors = Errors + "No motion mode, with Z word\n"
               FatalError = .Syntax
               break
               
               
          }
          return retVal
     }
     
     ///////////////////////////////////////////////////////
     //
     // Handler for a gcode word we don't understand the
     // letter for.
     //
     ///////////////////////////////////////////////////////
     
     func GCode_Unknown(word: String) -> Bool
     {
          Errors = Errors + "Unknown GCODE word \"\(word)\"\n"
          return true
     }
     
     
     
     ///////////////////////////////////////////////////////
     //
     // Parse a line of text (a block) and dispatch each
     // gcode word to a handler for extraction and further
     // processing.  When this exits, all the class values
     // will have been set, and a new output string will be
     // present.  Any errors detected will be listed in the
     // Errors string. The object state should reflect the
     // current state the machine should be in, including
     // modes, positions, and parameters.
     //
     ///////////////////////////////////////////////////////
     
     func ParseGCodeBlock(BlockToParse: String)
     {
          
          var workingBlock: String = BlockToParse
          
          workingBlock = workingBlock.capitalizedString   // convert any lower case to upper
          
          // There may be more than one space between words, so take them all out, they're eas(ish) to put back in.
          // If we leave the multiples in, the tokenizer will split the spaces into "empty" tokens, which is
          // less than desirable. At the same time, there might be spaces missing between words, so we have to put
          // them in anyway.
          workingBlock = workingBlock.stringByReplacingOccurrencesOfString(" ", withString: "" )  // strip spaces
          
          // Per ansi standard, none of the spaces are required, and are ignored if present,
          // so this if a simple way of normalizing the whole thing. This isn't particularly efficient, but it's simple.
          // In the course of doing this, we're doing to run through all the text 26 times.  Yuck.
          
          for ch in allletters.characters
          {
               workingBlock = workingBlock.stringByReplacingOccurrencesOfString("\(ch)", withString: " \(ch)" )  // replace letters with space+letter.
          }
          
          // workingBlock (one line) now has all caps, with each word separated by a space
          
          let components: Array<String>   // This will hold each of the words in the block
          
          components = workingBlock.componentsSeparatedByString(" ")  // ok, now we're all tokenized, all spaces stripped
          
          // components is an array of substrings, each one is one gcode command word
          var isCommentBlock = false  // Haven't hit a comment yet. It's a special case.
          
          
          for word in components  // Now, walk the words, calling the handler for each one.
          {
               if (isCommentBlock) // If we've entered a comment block, dump the rest of the words in the block
               {
                    OutputString = OutputString +  word + " "
               }
               else
               {
                    
                    if !word.isEmpty  // In case something went goofy and we got an empty token
                    {
                         let ch : Character = word.characters.first!
                         wordsProcessed = wordsProcessed + 1;
                         
                         switch (ch)
                         {
                         case "G":  // G code - workhorse
                              if GCode_Gx(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "M":  // M code (usually states)
                              if GCode_Mx(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "L": // Repeat line (canned cycle?) TODO
                              if GCode_L(ExtractIntValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "N":  // Line number
                              if GCode_N(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "F":  // Feed rate
                              if GCode_F(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "R":  // Retract level parameter
                              if GCode_R(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "S":  // Almost always spindle speed
                              if GCode_S(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "X":  // almost always X position
                              if GCode_X(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "Y":  // Almost always Y position
                              if GCode_Y(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "Z":  // Almost always Z position
                              if GCode_Z(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "A":  // Almost always A axis rotation
                              if GCode_A(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "B":  // Almost always B axis rotation
                              if GCode_B(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "C":  // Almost always C axis rotation
                              if GCode_C(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "D":  // Arc parameter
                              if GCode_D(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "H":
                              if GCode_H(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "I": // Arc parameter
                              if GCode_I(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "J": // Arc parameter
                              if GCode_J(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "P":  // Almost always dwell time
                              if GCode_P(ExtractIntValue(word)) { OutputString = OutputString + word + " "}
                              break
                         case "Q":
                              if GCode_Q(ExtractDoubleValue(word)) { OutputString = OutputString + word + " "}
                              break
                         case "T":  // Tool to select with next tool change
                              if GCode_T(ExtractDoubleValue(word)) { OutputString = OutputString  + word + " "}
                              break
                         case "%":    // Start or end of file
                              OutputString = OutputString  + word + " "
                              break
                         case "(":   // Comment. Should dump everything from here to end of line
                              isCommentBlock = true
                              OutputString = OutputString + " " + word
                              break
                         case "/":   // Line has block delete flag.
                              if (BlockDeleteSwitch)  // If block delete switch on, ignore the line
                              {
                                   OutputString = OutputString  + word
                                   isCommentBlock = true;
                              }
                              break
                              
                              
                         default:
                              if GCode_Unknown(word)  { OutputString = OutputString + " " + word }
                              break
                         }
                    }
               }
               
               
          }
          
          SettingCoordinateSystem = 0   // This is always clear at end of block
          SettingDwell = false          // Must always be clear at end of block
          ParameterFileOffsetsBeingSet = false
          isCommentBlock = false
          if (NeedFeedRate) // inverse time mode, and we need a feed rate in this block
          {
               if (!FeedRateFound)
               {
                    Errors = Errors + "Feed rate (Fxx.xx) missing from G1,G2,G3 in inverse time mode (G93)\n"
                    FatalError = .Syntax
               }
               NeedFeedRate = false;
          }
          
          if (TransitionedAboveReferencePlane)
          {
               // We are at or above reference - we retracted.
               AtOrAboveReference = true
               // The next block will be in the next segment.
               SegmentNumberNext = SegmentNumber + 1
          }
          else
          {
               AtOrAboveReference = false
               SegmentNumberNext = SegmentNumber
          }
          
          if (Annotate)
          {
               OutputString = "Seg:\(SegmentNumber) dZ=\(DeepestCutSoFar) Lyr=\(Layer) | " + OutputString
          }
          
     }
     
     
}


func OpenFileAndProcess(file: String)
{
     
     var encoded: UInt = 0
     var text2: String
     var lines: Array<String>
     var program = Dictionary<String,GCODEParser>()
     var lastone: GCODEParser
     var count = 0
     
     
     
     do{
          text2 = try String.init(contentsOfFile: file, usedEncoding: &encoded)
          lines = text2.componentsSeparatedByString("\n")
          program.updateValue(GCODEParser.init(), forKey: "0")
          
          for word in lines
          {
               count = count + 1
               program.updateValue(GCODEParser.init(last: program["\(count-1)"]!, Block: word), forKey: "\(count)")
          }
     } catch {(print("bad"))}
     
     lastone = program["\(count-1)"]!
     
     
     
}

