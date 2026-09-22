APP := PortManager.app

.PHONY: build debug run test clean

build:
	./Scripts/build_app.sh release

debug:
	./Scripts/build_app.sh debug

run: build
	@-pkill -x PortManager 2>/dev/null; true
	open $(APP)

test:
	swift build && .build/debug/PortManager --selftest

clean:
	rm -rf .build $(APP)
