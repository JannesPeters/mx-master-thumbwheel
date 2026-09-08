.PHONY: setup-signing app install clean

setup-signing:
	./scripts/setup-local-signing.sh

app:
	./scripts/build-app.sh

install:
	./scripts/install-app.sh

clean:
	rm -rf build
