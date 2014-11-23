CHICKEN_HOME=$(shell csi -e '(display (chicken-home))')
SHARE=$(shell dirname $(CHICKEN_HOME))
TOP=$(shell dirname $(SHARE))
PACKAGE_DIR=$(SHARE)/scheme
BIN_DIR=$(TOP)/bin
CHICKEN_COMPILER=csc -X r7rs -I $(PACKAGE_DIR)
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
	$(CHICKEN_COMPILER) sync-to-s3.scm -o sync-to-s3


link-libs:
	snow2 install -s -r \
		~/src/snow2/snow2-packages/snow \
		-r ~/src/snow2/snow2-packages/seth \
		$(SNOW2_LIBS)

libs:
	snow2 install $(SNOW2_LIBS)

install: build-chicken
	sudo cp ./sync-to-s3 $(BIN_DIR)

uninstall:
	sudo rm -f $(BIN_DIR)/sync-to-s3


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
