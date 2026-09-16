.PHONY: setup-signing app install dev clean

setup-signing:
	./scripts/setup-local-signing.sh

app:
	./scripts/build-app.sh

install:
	./scripts/install-app.sh

dev:
	./scripts/dev-reload.sh

clean:
	rm -rf build
