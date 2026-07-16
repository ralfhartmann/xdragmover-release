# Makefile for XDragMover.
#
# Requires Xcode's command line tools (xcodebuild) on macOS.
#
# Targets:
#   make            - build the app (default target)
#   make build      - build the app
#   make test       - run the unit test target (XDragMoverTests)
#   make clean      - clean build products
#   make all        - build, then test (does NOT change the default target)
#   make release    - cut a release from 'dev': test, pause for README review,
#                      bump VERSION.md, merge dev into main, build a package.
#                      Bump type defaults to patch; override with BUMP=minor
#                      or BUMP=major. Must be run from the 'dev' branch with
#                      a clean working tree. See DEVELOPMENT.md.
#   make package    - build a Release .app and zip it into dist/ (also run
#                      as the last step of 'make release'); override the
#                      version used for the zip name with VERSION=..., e.g.
#                      VERSION=0.1.3+abc1234 (defaults to VERSION.md)
#   make bump-version - bump VERSION.md (and MARKETING_VERSION) without
#                      doing anything else; BUMP=major|minor|patch (default patch)
#   make run        - build (into build/, normally signed) and launch the app
#   make debug      - like 'run', but passes --debug so the debug log
#                      window is shown
#   make install    - build a package (like 'make package') and install it
#                      into /Applications, quitting/replacing any existing
#                      copy; override the version with VERSION=... like
#                      'make package'
#   make uninstall  - quit the app if running and remove it from
#                      /Applications
#   make dmg        - build a .dmg installer (drag-to-Applications style)
#                      into dist/; override the version with VERSION=...

PROJECT      := XDragMover.xcodeproj
SCHEME       := XDragMover
CONFIGURATION := Debug
DESTINATION  := platform=macOS
RUN_BUILD_DIR := build

# Building/testing locally without a paid Developer Team configured should
# not require a signing certificate. Used for build/test/clean/package only
# — NOT for run/debug, see the comment there.
CODESIGN_OVERRIDES := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(DESTINATION)'

.DEFAULT_GOAL := build

.PHONY: all build test clean release package bump-version run debug install uninstall dmg

all: build test

build:
	$(XCODEBUILD) $(CODESIGN_OVERRIDES) build

test:
	$(XCODEBUILD) $(CODESIGN_OVERRIDES) test

# Deliberately built WITHOUT $(CODESIGN_OVERRIDES): macOS ties the
# Accessibility permission grant to the app's code signing identity. An
# unsigned/ad-hoc build gets a new identity (CDHash) on every single
# rebuild, so TCC treats each run as a brand-new, unrecognized app and
# re-prompts every time — even if you already granted access. Normal
# (Automatic) signing produces a stable "Sign to Run Locally" identity
# that survives rebuilds, so the grant sticks. Requires a Team selected in
# Xcode (Settings -> Accounts, then pick it in the project's Signing &
# Capabilities tab) — a free personal Team is enough. See DEVELOPMENT.md.
run:
	$(XCODEBUILD) CONFIGURATION_BUILD_DIR=$(RUN_BUILD_DIR) build
	open "$(RUN_BUILD_DIR)/XDragMover.app"

# Same build as 'run', but launched with --debug so the debug log window
# (see AppDelegate.isDebugModeRequested) is shown.
debug:
	$(XCODEBUILD) CONFIGURATION_BUILD_DIR=$(RUN_BUILD_DIR) build
	open "$(RUN_BUILD_DIR)/XDragMover.app" --args --debug

clean:
	$(XCODEBUILD) clean

release:
	./scripts/release.sh $(BUMP)

package:
	./scripts/package.sh $(VERSION)

bump-version:
	./scripts/bump_version.sh $(BUMP)

install:
	./scripts/install.sh $(VERSION)

uninstall:
	./scripts/uninstall.sh

dmg:
	./scripts/make_dmg.sh $(VERSION)
