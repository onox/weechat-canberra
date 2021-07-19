.PHONY: all debug clean install uninstall

all:
	alr build

debug:
	alr build -XWEECHAT_CANBERRA_BUILD_MODE=debug -XWEECHAT_ADA_BUILD_MODE=debug

clean:
	alr clean
	rm -rf build

install:
	install --mode=644 --preserve-timestamps --strip ./build/lib/ada-canberra.so ~/.weechat/plugins/

uninstall:
	rm ~/.weechat/plugins/ada-canberra.so
