
VERSION=0.1

SNOW2_LIBS='(srfi 13)' \
	   '(srfi 29)' \
	   '(srfi 37)' \
	   '(srfi 69)' \
           '(snow snowlib)' \
	   '(snow filesys)' \
	   '(snow genport)' \
	   '(snow zlib)' \
	   '(snow tar)' \
	   '(seth crypt md5)' \
	   '(seth aws s3)' \
	   '(seth port-extras)'

all:

link-libs:
	snow2 install -s -r \
		~/src/snow2/snow2-packages/snow \
		-r ~/src/snow2/snow2-packages/seth \
		$(SNOW2_LIBS)

libs:
	snow2 install $(SNOW2_LIBS)

dist:
	rm -rf sync-to-s3-$(VERSION)
	mkdir sync-to-s3-$(VERSION)
	cp sync-to-s3.scm sync-to-s3-$(VERSION)/
	cp -r seth snow srfi sync-to-s3-$(VERSION)/
	tar cvf sync-to-s3-$(VERSION).tar sync-to-s3-$(VERSION)/
	gzip -9 sync-to-s3-$(VERSION).tar
	rm -rf sync-to-s3-$(VERSION)

clean:
	rm -rf *~ sync-to-s3 seth snow srfi
