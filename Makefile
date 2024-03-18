# SPDX-License-Identifier: LGPL-2.1-or-later -->
# Copyright (C) 2024 Eric Herman <eric@freesa.org> -->
# Makefile: ssh-crypt

SHELL=/bin/bash

.PHONY: default
default: test

test/data/test-file:
	mkdir -pv test/data
	echo "hello world" > $@

test/_ssh/id_rsa:
	mkdir -pv test/_ssh
	chmod -v 700 test/_ssh
	ssh-keygen -b 4096 -t rsa -N "" -C "temporary-key" -f $@
	file $@

test/_ssh/id_rsa.pub: test/_ssh/id_rsa
	file $@

test/encrypt/test-file.enc: ssh-crypt \
		test/_ssh/id_rsa.pub \
		test/data/test-file
	mkdir -pv test/encrypt
	cd test/encrypt && \
		../../ssh-crypt -e ../_ssh/id_rsa.pub ../data/test-file

test/decrypt/test-file: ssh-crypt \
		test/_ssh/id_rsa \
		test/encrypt/test-file.enc
	mkdir -pv test/decrypt
	cd test/decrypt && \
		SC_TMP_DECRYPT_SSH_KEYGEN_NO_PASSWORD=1 \
		../../ssh-crypt -d ../_ssh/id_rsa ../encrypt/test-file.enc

.PHONY: check test
check test: test/data/test-file test/decrypt/test-file
	diff -u test/data/test-file test/decrypt/test-file
	@echo "SUCCESS $@"

.PHONY: clean
clean:
	rm -rf test

.PHONY: mrproper
mrproper:
	git clean -dxff
