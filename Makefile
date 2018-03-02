.PHONY: build clean test install uninstall clean

all:
		@jbuilder build src/dashc.exe
		cp _build/default/src/dashc.exe dashc.exe
test:
		@jbuilder build src/tests.exe
		jbuilder build @_build/default/src/runtest
clean:
		jbuilder clean