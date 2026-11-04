#!/usr/bin/env python3
"""Run the two production disclosure views in an isolated in-memory UI test host."""
import argparse
import pathlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', required=True, help='UUID of an available iOS simulator')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
staging = pathlib.Path(tempfile.mkdtemp(prefix='blip-disclosure-'))
print(f'Test project and results: {staging}', flush=True)
for directory in ('BlipJournal', 'BlipJournalCore', 'BlipJournalTests'):
    shutil.copytree(root / directory, staging / directory,
                    ignore=shutil.ignore_patterns('.build', '.swiftpm'))
shutil.copyfile(root / 'scripts/disclosure-ui/DisclosureHarnessApp.swift',
                staging / 'BlipJournal/App/BlipJournalApp.swift')
shutil.copytree(root / 'scripts/disclosure-ui', staging / 'DisclosureUITests',
                ignore=shutil.ignore_patterns('DisclosureHarnessApp.swift', 'README.md'))
view = staging / 'BlipJournal/Settings/RestoreBackupView.swift'
source = view.read_text()
needle = 'model = RestoreBackupModel(appModel: appModel)'
assert source.count(needle) == 1, 'Update test host injection for the current restore view'
source = source.replace(needle, needle + '; let export = ExportModel(store: appModel.store); '
                        'export.format = .jsonBackup; model?.load(.success(try! export.makeFile())); '
                        'export.cleanUp()')
view.write_text(source)
spec = (root / 'project.yml').read_text()
spec = spec.replace('schemes:\n', '''  DisclosureUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: DisclosureUITests
    dependencies:
      - target: BlipJournal
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.github.basilj-s.DisclosureUITests
        GENERATE_INFOPLIST_FILE: YES
        TEST_TARGET_NAME: BlipJournal
schemes:
''')
spec = spec.replace('        - BlipJournalTests\n', '        - BlipJournalTests\n        - DisclosureUITests\n')
# A separate bundle cannot replace an installed personal journal.
spec = spec.replace('PRODUCT_BUNDLE_IDENTIFIER: io.github.basilj-s.BlipJournal\n',
                    'PRODUCT_BUNDLE_IDENTIFIER: io.github.basilj-s.BlipDisclosureHarness\n')
(staging / 'project.yml').write_text(spec)
# The UI test launches the isolated bundle explicitly.
test = staging / 'DisclosureUITests/BackupDisclosureUITests.swift'
test.write_text(test.read_text().replace('XCUIApplication()',
                'XCUIApplication(bundleIdentifier: "io.github.basilj-s.BlipDisclosureHarness")'))
subprocess.run(['xcodegen', 'generate'], cwd=staging, check=True)
subprocess.run(['xcodebuild', '-project', 'BlipJournal.xcodeproj', '-scheme', 'BlipJournal',
                '-destination', f'platform=iOS Simulator,id={args.simulator}',
                '-derivedDataPath', str(staging / 'build'), '-only-testing:DisclosureUITests',
                '-collect-test-diagnostics', 'never', 'test'], cwd=staging, check=True)
