
duh:
	@echo "Well, what'll it be?"

all:    trace notrace lint

lint:   FORCE
	lslint trace/anviltosser.lsl
	lslint trace/anvilprojectile.lsl
	lslint notrace/anviltosser.lsl
	lslint notrace/anvilprojectile.lsl

notrace: FORCE
	mkdir -p notrace
	../../tools/lslconf.pl notrace.lslc . notrace

trace:  FORCE
	mkdir -p trace
	../../tools/lslconf.pl trace.lslc . trace

FORCE:
