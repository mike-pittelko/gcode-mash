//
//  Utilities.swift
//  gcode-mash
//
//  Created by Mike Pittelko on 6/28/16.
//  Copyright © 2016 Michael Pittelko. All rights reserved.
//

import Foundation


func DumpABlock(n: GCODEParser)
{
     print( "S: \(n.SourceBlock)  R: \(n.PBlock)  L:\(n.Layer) " )
     print( "--->CP:(\(n.currentPositionA),\(n.currentPositionB),\(n.currentPositionC),\(n.currentPositionX),\(n.currentPositionY),\(n.currentPositionZ))", terminator: "")
     print( String(format: "LL:(%.3f,%.3f,%.3f) LR:(%.3f,%.3f,%.3f)",n.PositionLastLinear.X,n.PositionLastLinear.Y,n.PositionLastLinear.Z,n.PositionLastRapid.X,n.PositionLastRapid.Y,n.PositionLastRapid.Z))
     
}


