.PHONY: build clean test install uninstall clean

all:
		@dune build --profile release src/dashc.exe
		cp _build/default/src/dashc.exe dashc.exe
test:
		@dune build src/tests.exe
		dune build @_build/default/src/runtest
clean:
		dune clean
