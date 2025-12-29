//! AES-256 encryption and Argon2 key derivation for journal entries

use aes_gcm::{Aes256Gcm, Key, Nonce};
use aes_gcm::aead::Aead;
use aes_gcm::KeyInit;
use argon2::{self, Argon2};

pub fn derive_key(password: &str, salt: &[u8]) -> [u8; 32] {
    let argon2 = Argon2::default();
    let mut key = [0u8; 32];
    argon2
        .hash_password_into(password.as_bytes(), salt, &mut key)
        .expect("Key derivation failed");
    key
}

pub fn encrypt(text: &str, key: &[u8; 32]) -> (Vec<u8>, Vec<u8>) {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));

    // Generate a random 96-bit nonce (AES-GCM standard)
    let nonce: [u8; 12] = rand::random();
    let nonce_obj = Nonce::from_slice(&nonce);

    let ciphertext = cipher
        .encrypt(nonce_obj, text.as_bytes())
        .expect("Encryption failed");

    (ciphertext, nonce.to_vec())
}

pub fn decrypt(ciphertext: &[u8], nonce: &[u8], key: &[u8; 32]) -> String {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce_obj = Nonce::from_slice(nonce);

    let plaintext = cipher
        .decrypt(nonce_obj, ciphertext)
        .expect("Decryption failed");

    String::from_utf8(plaintext).expect("Invalid UTF-8")
}
