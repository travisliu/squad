.PHONY: all test examples

all: test

test:
	cutest ./test/*.rb
