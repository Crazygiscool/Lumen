//! AES-256 encryption and Argon2 key derivation for journal entries

use aes_gcm::{Aes256Gcm, Key, Nonce};
use aes_gcm::aead::{Aead, NewAead};
use argon2::{self, Config};
use rand::Rng;

pub fn derive_key(password: &str, salt: &[u8]) -> [u8; 32] {
    let config = Config::default();
    let key = argon2::hash_raw(password.as_bytes(), salt, &config).expect("Key derivation failed");
    let mut key_arr = [0u8; 32];
    key_arr.copy_from_slice(&key[..32]);
    key_arr
}

pub fn encrypt(text: &str, key: &[u8; 32]) -> (Vec<u8>, Vec<u8>) {
    let cipher = Aes256Gcm::new(Key::from_slice(key));
    let nonce: [u8; 12] = rand::thread_rng().gen();
    let nonce_obj = Nonce::from_slice(&nonce);
    let ciphertext = cipher.encrypt(nonce_obj, text.as_bytes()).expect("Encryption failed");
    (ciphertext, nonce.to_vec())
}

pub fn decrypt(ciphertext: &[u8], nonce: &[u8], key: &[u8; 32]) -> String {
    let cipher = Aes256Gcm::new(Key::from_slice(key));
    let nonce_obj = Nonce::from_slice(nonce);
    let plaintext = cipher.decrypt(nonce_obj, ciphertext).expect("Decryption failed");
    String::from_utf8(plaintext).expect("Invalid UTF-8")
}
