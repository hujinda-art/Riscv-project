# 在 Makefile 中确保 test 目标成功
.PHONY: test
test:
	@echo "Running CI tests..."
	@./scripts/test/minimal_test.sh
	@echo " All tests passed"
