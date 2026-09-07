.PHONY: gen build test run demo clean release package
gen build test run demo clean release package:
	$(MAKE) -C macos $@
