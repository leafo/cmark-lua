CBITS = ext
# Rock version: the upstream cmark version plus a counter for releases of
# these bindings. ext/UPSTREAM records the exact upstream commit.
VERSION=0.31.2.1
REVISION=1
ROCKSPEC=cmark-$(VERSION)-$(REVISION).rockspec
CFLAGS = -fPIC -O3 -I$(CBITS) -I.
CMARK_DIR ?= ../cmark
OBJS = $(subst .c,.o,$(wildcard $(CBITS)/*.c))
C_SOURCES=$(wildcard $(CBITS)/*.c $(CBITS)/*.h $(CBITS)/*.inc)
LUASTATIC=lua-5.2.4/src/liblua.a

.PHONY: clean distclean test all rock rockspec upload update check

all: rock

rock: $(ROCKSPEC)
	luarocks --local make $(ROCKSPEC)

upload: rock
	moonrocks upload $(ROCKSPEC)

rockspec: $(ROCKSPEC)

$(ROCKSPEC): rockspec.in Makefile
	sed -e "s/_VERSION/$(VERSION)/g; s/_REVISION/$(REVISION)/g" $< > $@

cmark.so: cmark_lua.o $(OBJS)
	$(CC) -shared -o $@ -I$(CBITS) -llua $^

cmark-lua.a: cmark_lua.o $(OBJS)
	ar rcs $@ $^ $(LUASTATIC)

update: $(C_SOURCES) spec-tests.lua
	git -C $(CMARK_DIR) describe --tags --long > $(CBITS)/UPSTREAM
	git -C $(CMARK_DIR) rev-parse HEAD >> $(CBITS)/UPSTREAM

# requires luarocks install luacheck lua-TestMore
spec-tests.lua: $(CMARK_DIR)/test/spec.txt
	python3 $(CMARK_DIR)/test/spec_tests.py -d --spec $(CMARK_DIR)/test/spec.txt | sed -e 's/^\([ \t]*\)"\([^"]*\)":/\1\2 = /' | sed -e 's/^\[/return {/' | sed -e 's/^\]/}/' > $@

$(CBITS)/config.h: $(CMARK_DIR)/build/src/config.h
	cp $< $@

$(CBITS)/cmark_export.h: $(CMARK_DIR)/build/src/cmark_export.h
	cp $< $@

$(CBITS)/cmark_version.h: $(CMARK_DIR)/build/src/cmark_version.h
	cp $< $@

$(CBITS)/%: $(CMARK_DIR)/src/%
	cp $< $@

check:
	luacheck cmark/builder.lua

test: check
	prove test.t

clean:
	rm -rf *.o $(CBITS)/*.o $(ROCKSPEC)

distclean: clean
	rm cmark.so
