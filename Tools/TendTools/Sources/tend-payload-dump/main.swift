// tend-payload-dump: print a cloud request body for a recording (WI-M2-M6), built by the WI-M2-10 payload builder.
import Foundation
import TendToolsSupport

exit(PayloadDumpCommand.run(Array(CommandLine.arguments.dropFirst()), io: .live))
