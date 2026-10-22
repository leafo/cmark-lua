CBITS = ext
# Rock version: the upstream cmark version plus a counter for releases of
# these bindings. ext/UPSTREAM records the exact upstream commit.
VERSION=0.31.2.1
REVISION=1
ROCKSPEC=cmark-$(VERSION)-$(REVISION).rockspec
CFLAGS = -fPIC -O2 -I$(CBITS)
CMARK_DIR ?= ../cmark
C_SOURCES=$(wildcard $(CBITS)/*.c $(CBITS)/*.h $(CBITS)/*.inc)
LUA ?= lua
LUA_INCDIR ?= $(shell luarocks config variables.LUA_INCDIR)
LIBFLAG = -shared
ifeq ($(shell uname),Darwin)
LIBFLAG = -bundle -undefined dynamic_lookup
endif

.PHONY: clean test all rock rockspec upload update check

all: rock

rock: $(ROCKSPEC)
	luarocks --local make $(ROCKSPEC)

upload: rock
	moonrocks upload $(ROCKSPEC)

rockspec: $(ROCKSPEC)

$(ROCKSPEC): rockspec.in Makefile
	sed -e "s/_VERSION/$(VERSION)/g; s/_REVISION/$(REVISION)/g" $< > $@

# Builds the module in place. test.t loads ./cmark.so in preference to an
# installed rock.
cmark.so: cmark_lua.c $(wildcard $(CBITS)/*.c)
	$(CC) $(CFLAGS) $(LIBFLAG) $(if $(LUA_INCDIR),-I$(LUA_INCDIR)) -o $@ cmark_lua.c $(CBITS)/*.c

update: $(C_SOURCES) $(CBITS)/COPYING spec-tests.lua
	git -C $(CMARK_DIR) describe --tags --long > $(CBITS)/UPSTREAM
	git -C $(CMARK_DIR) rev-parse HEAD >> $(CBITS)/UPSTREAM

spec-tests.lua: $(CMARK_DIR)/test/spec.txt
	python3 $(CMARK_DIR)/test/spec_tests.py -d --spec $(CMARK_DIR)/test/spec.txt | sed -e 's/^\([ \t]*\)"\([^"]*\)":/\1\2 = /' | sed -e 's/^\[/return {/' | sed -e 's/^\]/}/' > $@

$(CBITS)/cmark_export.h: $(CMARK_DIR)/build/src/cmark_export.h
	cp $< $@

$(CBITS)/cmark_version.h: $(CMARK_DIR)/build/src/cmark_version.h
	cp $< $@

$(CBITS)/COPYING: $(CMARK_DIR)/COPYING
	cp $< $@

$(CBITS)/%: $(CMARK_DIR)/src/%
	cp $< $@

check:
	luacheck cmark/builder.lua

# requires prove, and luarocks install luacheck lua-testmore
test: cmark.so check
	prove --exec $(LUA) test.t

clean:
	rm -f cmark.so *.o $(CBITS)/*.o $(ROCKSPEC) *.rock
