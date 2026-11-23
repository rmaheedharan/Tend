// tend-payload-dump: print a cloud request body for a recording (WI-M2-M6). A stub until WI-M2-10.
import Foundation
import TendToolsSupport

exit(PayloadDumpCommand.run(Array(CommandLine.arguments.dropFirst()), io: .live))
