.PHONY: setup preflight convert validate serve smoke check

setup:
	./scripts/setup_toolchain.sh

preflight:
	./scripts/preflight.sh

convert:
	./scripts/convert.sh

validate:
	./scripts/validate.sh

serve:
	./scripts/serve.sh

smoke:
	./scripts/smoke_test.sh

check:
	./scripts/check_repo.sh
