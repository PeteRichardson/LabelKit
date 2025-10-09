//  reminders
//
//  Created by Peter Richardson on 10/5/25.
//

import EventKit
import Foundation


/// EKReminder is not Sendable, so create a subset that includes
/// what we need, and is Sendable
public struct ReminderSummary: Sendable, Equatable {
    public let title: String
    public let priority: Int
    public let dueDate: Date?
    public let isCompleted: Bool
}

public enum ReminderError: Error {
    case accessDenied
}

/// A protocol we can use to swap in a Mock reminder provider
/// in Unit Tests
public protocol RemindersProviding: Sendable {
    func getUncompleted() async throws -> [ReminderSummary]
}

/// Class that does nothing but asynchronously get an array
/// of uncompleted reminders (summarized into ReminderSummary records)
///
/// It sits on MainActor because EKEventStore isn't properly async yet
@MainActor public final class Reminders: RemindersProviding {
    
    // EKEventStore must be used on the main actor. We create and access it only from MainActor.
    private let store: EKEventStore = EKEventStore()

    // Get Uncompleted reminders or throw ReminderError.accessDenied
    public func getUncompleted() async throws -> [ReminderSummary] {
        // Request permission and wait for response (we are on the main actor)
        let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestFullAccessToReminders { granted, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }

        guard granted else { throw ReminderError.accessDenied }

        // Fetch reminders (still on main actor) and map to sendable summaries
        let summaries: [ReminderSummary] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ReminderSummary], Error>) in
            let predicate = store.predicateForReminders(in: nil)
            store.fetchReminders(matching: predicate) { fetched in
                // Ensure we resume on the main actor so EKReminder instances never cross actors
                Task { @MainActor in
                    let incomplete = (fetched ?? []).filter { !$0.isCompleted }
                    let mapped: [ReminderSummary] = incomplete.map { reminder in
                        ReminderSummary(
                            title: reminder.title ?? "",
                            priority: reminder.priority,
                            dueDate: reminder.dueDateComponents?.date,
                            isCompleted: reminder.isCompleted
                        )
                    }
                    continuation.resume(returning: mapped)
                }
            }
        }

        return summaries
    }
    
    public init() {}
}

