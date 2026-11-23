// tend-eval-score: score an M2 eval results file (plan "Scoring tool and command"; AC-M2-14, 15, 17, 26).
import Foundation
import TendToolsSupport

exit(EvalScoreCommand.run(Array(CommandLine.arguments.dropFirst()), io: .live))
