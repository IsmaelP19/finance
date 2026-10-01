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
        let reimbursementMovements = try modelContext.fetch(
            FetchDescriptor<Movement>(
                predicate: #Predicate<Movement> {
                    $0.typeRaw == "income" && $0.reimbursementForId != nil
                }
            )
        )
        guard !reimbursementMovements.isEmpty else { return }

        let targetIDs = reimbursementMovements.compactMap(\.reimbursementForId)
        let targetDescriptor = FetchDescriptor<Movement>(
            predicate: #Predicate<Movement> { movement in
                targetIDs.contains(movement.id)
            }
        )
        let targetExpenseIDs = Set(
            try modelContext.fetch(targetDescriptor)
                .filter { $0.type == .expense }
                .map(\.id)
        )

        var didChange = false

        for movement in reimbursementMovements {
            guard let reimbursementForId = movement.reimbursementForId else { continue }
            guard targetExpenseIDs.contains(reimbursementForId) else {
                movement.reimbursementForId = nil
                movement.updatedAt = Date()
                didChange = true
                continue
            }
        }

        if didChange {
            try modelContext.save()
        }
    }
}
