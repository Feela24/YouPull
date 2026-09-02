.PHONY: build install standalone-tools verify clean

build:
	./build.sh

install:
	./install.sh

standalone-tools:
	./scripts/fetch-standalone-tools.sh

verify:
	./scripts/verify-standalone.sh

clean:
	rm -rf build
