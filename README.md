<!-- SPDX-License-Identifier: LGPL-2.1-or-later -->
<!-- Copyright (C) 2024 Eric Herman <eric@freesa.org> -->
# ssh-crypt

**Using ssh and ssl to encrypt and decrypt files.**

In most cases, it is far easier (and likely makes more sense) to use GPG.

That said, GPG is not as widely used as as SSH,
even with the rise of GPG-signing git commits.

If GPG is not a viable option,
openssl can be used to encrypt a file using the recipient's OpenSSH public key,
the results of which can be safely sent over an insecure channel.

However, the process is tedious for both the sender and receiver.

There is nothing magic in [this script](ssh-crypt),
one can do all of the steps by hand.
This script only reduces the tedium _slightly_,
and serves as an executable illustration of the processes.

Here is that process, should you wish to do it by hand:

## Encrypting

RSA cannot directly encrypt a piece of data which is larger than the key size
(elliptic curve and most other encryption methods have similar size constraints)
but `openssl` can do
[cipher block chaining](https://en.wikipedia.org/wiki/Cipher_block_chaining)
with a small key on the first block
and for each additional block using the results of the previous block.

As openssl does not directly support encrypting with the recipients public key,
a small one-time-use symmetric key is created.

This key will be used to encrypt the clear-text file.
This key will then be encrypted using the recipient's public key.

The recipient can decrypt the symmetric key using their private key,
and then decrypt the encrypted file using the decrypted symmetric key.

### Create a symmetric key

First, we get 32 random bytes (256 random bits) to use for our symmetric key:

```bash
	openssl rand -out the-secrets-file.symmetric-key 32
```

### Encrypt with the symmetric key

Next, we encrypt the file using the symmetric key:

```bash
	openssl aes-256-cbc \
		-a \
		-md sha512 \
		-pbkdf2 \
		-in   /path/to/the-secrets-file \
		-out  the-secrets-file.enc \
		-pass file:the-secrets-file.symmetric-key
```

### Encrypt the symmetric key with recipient's public key

To encrypt the symmetric key using the recipient's SSH public key,
it must be in [PEM format](https://en.wikipedia.org/wiki/Privacy-Enhanced_Mail).
OpenSSH supports PEM format, but this is not what is typically found,
however we can convert the public key to PEM if needed:

```bash
		ssh-keygen -f /path/to/recipient.pub -e -m pem \
			> recipient.pub.pem
```

Next, using the recipient's SSH public key (in PEM format),
we encrypt the symmetric key:

```bash
	openssl pkeyutl -encrypt \
		-pubin -inkey recipient.pub.pem \
		-in  the-secrets-file.symmetric-key \
		-out the-secrets-file.symmetric-key.bin.enc
```

For ease of emailing, convert to ascii-safe format:

```bash
	openssl base64 -e \
		-in  the-secrets-file.symmetric-key.bin.enc \
		-out the-secrets-file.symmetric-key.asc.enc
```

The symmetric key should not be reused, thus remove it:

```bash
	rm -v the-secrets-file.symmetric-key
	rm -v the-secrets-file.symmetric-key.bin.enc
```

### Send encrypted file and encrypted symmetric key

The following files can now be sent to the recipient:

```
	the-secrets-file.enc
	the-secrets-file.symmetric-key.asc.enc
```

## Decrypting

Naturally, decrypting is a bit like running the encryption steps in reverse.

### Ensure a PEM format version of the private key

The private key file is unlikely to be in PEM format,
and a temporary PEM version may need to be created.

You will have to confirm the passphrase
and create a passphrase for the temp version as well.

```bash
	TMP_PEM_KEY_DIR=$(mktemp -d "/tmp/$USER.pem.XXXXXXXX")
	chmod -v 700 "$TMP_PEM_KEY_DIR"
	cp -v ~/.ssh/id_rsa $TMP_PEM_KEY_DIR/id_rsa
	ssh-keygen -p -m PEM -f $TMP_PEM_KEY_DIR/id_rsa
```

### Decrypt the symmetric key

convert from ascii-safe format


```bash
	openssl base64 -d \
		-in  /path/to/the-secrets-file.symmetric-key.asc.enc \
		-out the-secrets-file.symmetric-key.bin.enc
```

Decrypt the symmetric key using the (PEM format) private key.
You will be prompted to enter the passphrase for the key.

```bash
	openssl pkeyutl -decrypt \
		-inkey $TMP_PEM_KEY_DIR/id_rsa \
		-in    the-secrets-file.symmetric-key.bin.enc \
		-out   the-secrets-file.symmetric-key
```

If the `TMP_PEM_KEY_DIR` was created, it can now be removed:

```bash
		rm -rfv $SC_PEM_KEY_DIR
```

The Binary encrypted symmetric key is no longer needed:

```bash
	rm -v the-secrets-file.symmetric-key.bin.enc
```

### Decrypt the file

Finally, decrypt the main file with the decrypted symmetric key:

```bash
	openssl aes-256-cbc -d \
		-a \
		-md sha512 \
		-pbkdf2 \
		-in   /path/to/the-secrets-file.enc \
		-out  the-secrets-file \
		-pass "file:the-secrets-file.symmetric-key"
```

And remove the obsolete symmetric-key:

```
	rm -v the-secrets-file.symmetric-key
```

## The ssh-crypt command

The `ssh-crypt` utility automates those steps.

It is just a shell script; it is intended to be easy to inspect.

The script can be used for encryption and decryption.

### Script usage

```bash
	ssh-crypt [options] path/to/input/file

	Options:
	 -e, --encrypt=/path/to/recipient/ssh-key.pub
	 -d, --decrypt=/path/to/private/ssh-key
	 -v, --verbose		run in verbose mode
	 -h, --help		display this help
	 -V, --version		display version
```

## Usage Example

Create a file with secrets:

```bash
	echo "hello world" > /tmp/test-file
```

Encrypt the file:

```bash
	ssh-crypt --verbose --encrypt=~/.ssh/id_rsa.pub /tmp/test-file
```

Decrypt the file:

```bash
	ssh-crypt --verbose --decrypt=~/.ssh/id_rsa ./test-file.enc
```

Check that the decrypted results match the input:

```bash
	diff -u /tmp/test-file ./test-file \
	&& echo "SUCCESSS. (/tmp/test-file matches ./test-file)" \
	|| echo "FAIL $?"
```

## Thanks

Bjorn Johansen's [post](https://www.bjornjohansen.com/encrypt-file-using-ssh-key),
while out-of-date,
served as a good starting point for documenting and automating this process.

## License

This is free software;
you can redistribute it and/or modify it under the terms of
the GNU Lesser General Public License
as published by the Free Software Foundation;
either version 2.1 of the License, or (at your option) any later version.

See [COPYING](COPYING)
