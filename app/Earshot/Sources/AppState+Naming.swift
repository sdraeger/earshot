import Foundation

/// Which job the speaker-naming window shows, and where it goes after an
/// answer. The scene only opens and closes the window.
extension AppState {
    /// The job the naming window shows: the user's pick while it waits for
    /// names, else the first job waiting. Setting it is the user picking one.
    var shownNamingJobID: UUID? {
        get { pipeline.queue.namingJobID(preferring: selectedNamingJobID) }
        set { selectedNamingJobID = newValue }
    }

    /// Shows `jobID`, or for nil whichever job waits, and pins it so a job
    /// reaching naming later cannot switch the window away from typed names.
    func showNaming(jobID: UUID? = nil) {
        if let jobID { selectedNamingJobID = jobID }
        pinShownNamingJob()
    }

    enum NamingAnswerOutcome: Equatable {
        /// The session did not take the answer; the message says why.
        case refused(String)
        /// The answer was taken and another job waits, now shown.
        case showsNext
        /// The answer was taken and no job waits, so the window closes.
        case finished
    }

    func answerNaming(jobID: UUID, result: PipelineQueue.SpeakerNamingResult) -> NamingAnswerOutcome {
        if let refusal = pipeline.queue.completeSpeakerNaming(jobID: jobID, result: result) {
            return .refused(refusal.message)
        }
        selectedNamingJobID = nil
        pinShownNamingJob()
        return selectedNamingJobID == nil ? .finished : .showsNext
    }
}
