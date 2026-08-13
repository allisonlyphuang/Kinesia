//
//  BradykinesiaStore.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//



static func save(trial: TapTrial,
                 metrics: BradykinesiaMetrics?,
                 motion: MotionSummary,
                 in context: NSManagedObjectContext) throws {
    // find the dose context
    ////  build an NSFetchRequest for MedicationLog, preidcate timestamp <= now, sorted by timestamp descending, fetchLimit=1 (most recent dose)
    //// if there is no most recent dose, leave TestSession.medicationContext as nil
    
    // compute dayStart, must be midnight local time
    
    TestSession(context:)
    BradykinesiaResult(context:)
    rawCapture(context:)
    
    result.session = session
    
    // encode raw trial
    
    // handle invalid case
    
    try context.save()
}

