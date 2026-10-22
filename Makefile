.PHONY: build test run app dmg icon clean

build:
	swift build

test:
	swift test

run:
	swift run PhotosOrganizer

app:
	scripts/build-app.sh

dmg:
	scripts/make-dmg.sh

icon:
	swift scripts/make-icon.swift

clean:
	rm -rf .build dist
