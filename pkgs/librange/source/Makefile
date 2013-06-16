OCAMLMAKEFILE = OCamlMakefile

SOURCES = memoize.ml range_utils.ml parser.mly lexer.mll tinydns.ml \
	  netmask.ml netblocks.ml admins.ml hosts_netblocks.ml evaluate.ml range.ml
RESULT  = range
PACKS = pcre
LIBS = unix
PATH = /usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

LDPATH = -L/usr/local/lib/ocaml/site-lib/pcre/ -L/usr/local/lib -L/usr/lib  -L/usr/local/lib/ocaml


librange.so: camlcode.o librange.o 
	ld -Bsymbolic -shared --whole-archive -o librange.so camlcode.o librange.o /usr/local/lib/ocaml/libunix.a /usr/local/lib/ocaml/libasmrun.a /usr/local/lib/ocaml/site-lib/pcre/libpcre_stubs.a -L/home/tops/lib  /home/tops/lib/libpcre.a  -lm  -ldl

install:
	mkdir -p $(DESTDIR)/usr/include/ $(DESTDIR)/usr/lib/
	install -m 644 range.h $(DESTDIR)/usr/include/
	install -m 755 librange.so $(DESTDIR)/usr/lib/

camlcode.o: ncl
	ocamlopt -I /usr/local/lib/ocaml/site-lib/pcre -output-obj -g -o camlcode.o unix.cmxa pcre.cmxa range_utils.cmx parser.cmx lexer.cmx memoize.cmx tinydns.cmx netmask.cmx admins.cmx netblocks.cmx hosts_netblocks.cmx evaluate.cmx range.cmx

librange.o: librange.c
	gcc -Wall -fPIC  -g -c librange.c -I /usr/local/lib/ocaml

cleaner: clean
	rm -f librange.so librange.o testrange camlcode.o pcre_stubs.o testrange-reps
	rm -rf a b ast.cmi
	rm -f memoize.o memoize.cmx 

include $(OCAMLMAKEFILE)

