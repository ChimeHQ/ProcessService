import Foundation

extension Process {
	public enum Event: Hashable, Sendable {
		case stdout(Data)
		case stderr(Data)
		case terminated(Process.TerminationReason)
	}
}

extension Process.Event: CustomStringConvertible {
	public var description: String {
		switch self {
		case .stdout(let data):
			return "stdout(\(data))"
		case .stderr(let data):
			return "stderr(\(data))"
		case .terminated(.exit):
			return "terminated(exit)"
		case .terminated(.uncaughtSignal):
			return "terminated(signal)"
		case .terminated(_):
			return "terminated(?)"
		}
	}
}
