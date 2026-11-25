#!/bin/zsh
# WI-M2-M1 MS-1 evidence run: plan B0–B6 from a clean state at the committed head.
cd $HOME/dharanbro-projects/Tend || exit 1
setopt nullglob
rm -rf build Tend.xcodeproj Packages/*/.build Tools/*/.build "$HOME"/Library/Developer/Xcode/DerivedData/TendAI-* "$HOME"/Library/Developer/Xcode/DerivedData/Tend-*
if [[ -e build || -e Tend.xcodeproj || -n "$(echo Packages/*/.build)" ]]; then echo "clean failed"; exit 1; fi
mkdir -p build/logs
L=build/logs
t() { local name=$1; shift; local s=$(date +%s); "$@"; local rc=$?; echo "$name exit=$rc seconds=$(( $(date +%s) - s ))" >> $L/timings.txt; return 0; }
{
  echo "# B0"; git rev-parse HEAD; echo "--- git status --porcelain (must be empty):"; git status --porcelain; echo "--- end"
  sw_vers; xcodebuild -version; swift --version; xcodegen --version
  echo "--- xcodegen binary:"; shasum -a 256 "$HOME/.local/opt/xcodegen-2.46.0/bin/xcodegen"
  xcrun simctl list runtimes | grep -i ios
  echo "--- tzdata:"; cat /var/db/timezone/zoneinfo/+VERSION
  echo "--- hardware:"; sysctl -n hw.model machdep.cpu.brand_string
} > $L/mac-B0-header.log 2>&1
t B1 zsh -c "swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors > $L/mac-B1-tendcore.log 2>&1"
t B2 zsh -c "swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors > $L/mac-B2-tendingestion.log 2>&1"
t B3 zsh -c "xcodegen generate --spec project.yml > $L/mac-B3-xcodegen.log 2>&1"
t B4 zsh -c "(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1) > $L/mac-B4-tendai-macos.log"
t B5 zsh -c "xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath build/results/B5-hosted.xcresult SWIFT_TREAT_WARNINGS_AS_ERRORS=YES > $L/mac-B5-hosted.log 2>&1"
t B6-release zsh -c "xcodebuild build -project Tend.xcodeproj -scheme Tend -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/dd-release CODE_SIGNING_ALLOWED=NO > $L/mac-B6-release.log 2>&1"
{ echo "find build/dd-release/Build/Products -iname '*TendEval*' (must print nothing):"; find build/dd-release/Build/Products -iname '*TendEval*'; echo "--- end"; } > $L/mac-B6-release-find.log 2>&1
t B6-archive zsh -c "xcodebuild archive -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' -archivePath build/Tend.xcarchive CODE_SIGNING_ALLOWED=NO > $L/mac-B6-archive.log 2>&1"
{ echo "find build/Tend.xcarchive -iname '*TendEval*' (must print nothing):"; find build/Tend.xcarchive -iname '*TendEval*'; echo "--- end"; echo "Products/Applications:"; ls build/Tend.xcarchive/Products/Applications; } > $L/mac-B6-archive-find.log 2>&1
t B6-eval-debug zsh -c "xcodebuild build -project Tend.xcodeproj -scheme TendEval -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/dd-eval CODE_SIGNING_ALLOWED=NO > $L/mac-B6-eval-debug.log 2>&1"
{ A=build/dd-eval/Build/Products/Debug-iphoneos/TendEval.app; echo "bundle:"; ls $A; echo "--- Info.plist keys:"; plutil -p $A/Info.plist | grep -E "CFBundleIdentifier|UIFileSharingEnabled|LSSupportsOpeningDocumentsInPlace"; echo "--- fixture hashes (bundle vs repo):"; for f in inputs.json household.json golden.json results-v1.schema.json MANIFEST.sha256; do echo "$(shasum -a 256 $A/$f | cut -d' ' -f1) $(shasum -a 256 Fixtures/M2/eval/$f | cut -d' ' -f1) $f"; done; } > $L/mac-B6-eval-bundle.log 2>&1
t B6-eval-archive zsh -c "xcodebuild archive -project Tend.xcodeproj -scheme TendEval -destination 'generic/platform=iOS' -archivePath build/TendEval.xcarchive CODE_SIGNING_ALLOWED=NO > $L/mac-B6-eval-archive.log 2>&1"
{ echo "--- git status --porcelain after the run (must be empty):"; git status --porcelain; echo "--- end"; } > $L/mac-B9-after.log 2>&1
echo DONE >> $L/timings.txt
