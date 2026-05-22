//
//  MovementIntegrityRepairService.swift
//  Finance
//
//  Created by OpenCode on 15/05/2026.
//

import Foundation
import SwiftData

@MainActor
enum MovementIntegrityRepairService {
    static func repairDanglingReimbursements(in modelContext: ModelContext) throws {
        let movements = try modelContext.fetch(FetchDescriptor<Movement>())
        let expenseIDs = Set(movements.filter { $0.type == .expense }.map(\.id))
        var didChange = false

        for movement in movements where movement.type == .income {
            guard let reimbursementForId = movement.reimbursementForId else { continue }
            guard !expenseIDs.contains(reimbursementForId) else { continue }

            movement.reimbursementForId = nil
            movement.updatedAt = Date()
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
    }
}
