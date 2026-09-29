// Package backup produces and restores encrypted backups: a JSON document
// (profiles, nodes, settings, custom rules...) sealed with AES-256-GCM using a
// key derived from the user's passphrase via Argon2id.
package backup

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"

	"golang.org/x/crypto/argon2"
)

var magic = []byte("EZVPNBK1")

const (
	saltLen    = 16
	keyLen     = 32
	argonTime  = 3
	argonMemKB = 64 * 1024
	argonPar   = 2
)

// ErrBadPassphrase is returned when authentication fails (wrong passphrase or
// tampered data — AES-GCM cannot tell them apart).
var ErrBadPassphrase = errors.New("wrong passphrase or corrupted backup")

// Encrypt seals plaintext. Layout: magic | time(u32) | mem(u32) | par(u8) |
// salt | nonce | ciphertext+tag. KDF parameters are stored so they can evolve.
func Encrypt(plaintext []byte, passphrase string) ([]byte, error) {
	if passphrase == "" {
		return nil, errors.New("empty passphrase")
	}
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return nil, err
	}
	key := argon2.IDKey([]byte(passphrase), salt, argonTime, argonMemKB, argonPar, keyLen)
	gcm, err := newGCM(key)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	var hdr bytes.Buffer
	hdr.Write(magic)
	_ = binary.Write(&hdr, binary.BigEndian, uint32(argonTime))
	_ = binary.Write(&hdr, binary.BigEndian, uint32(argonMemKB))
	hdr.WriteByte(argonPar)
	hdr.Write(salt)
	hdr.Write(nonce)
	// The header is authenticated as additional data.
	ct := gcm.Seal(nil, nonce, plaintext, hdr.Bytes())
	return append(hdr.Bytes(), ct...), nil
}

// Decrypt opens a backup produced by Encrypt.
func Decrypt(blob []byte, passphrase string) ([]byte, error) {
	hdrLen := len(magic) + 4 + 4 + 1 + saltLen + 12
	if len(blob) < hdrLen+16 || !bytes.HasPrefix(blob, magic) {
		return nil, errors.New("not an EasyVPN backup")
	}
	off := len(magic)
	t := binary.BigEndian.Uint32(blob[off:])
	m := binary.BigEndian.Uint32(blob[off+4:])
	par := blob[off+8]
	off += 9
	if t == 0 || t > 10 || m < 8*1024 || m > 1<<20 || par == 0 || par > 16 {
		return nil, fmt.Errorf("unsupported KDF parameters")
	}
	salt := blob[off : off+saltLen]
	nonce := blob[off+saltLen : off+saltLen+12]
	key := argon2.IDKey([]byte(passphrase), salt, t, m, par, keyLen)
	gcm, err := newGCM(key)
	if err != nil {
		return nil, err
	}
	pt, err := gcm.Open(nil, nonce, blob[hdrLen:], blob[:hdrLen])
	if err != nil {
		return nil, ErrBadPassphrase
	}
	return pt, nil
}

func newGCM(key []byte) (cipher.AEAD, error) {
	blk, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(blk)
}
