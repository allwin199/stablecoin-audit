lcov :
	rm -rf coverage; \
	forge coverage --report lcov; \
	genhtml lcov.info --output-directory coverage; \
	open coverage/index.html; \



# genhtml --branch-coverage --output "coverage" lcov.info; \