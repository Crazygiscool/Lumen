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

pub fn encrypt(data: &[u8], key: &[u8; 32]) -> (Vec<u8>, Vec<u8>) {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));

    let nonce: [u8; 12] = rand::random();
    let nonce_obj = Nonce::from_slice(&nonce);

    let ciphertext = cipher
        .encrypt(nonce_obj, data)
        .expect("Encryption failed");

    (ciphertext, nonce.to_vec())
}

pub fn decrypt(ciphertext: &[u8], nonce: &[u8], key: &[u8; 32]) -> Result<Vec<u8>, String> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce_obj = Nonce::from_slice(nonce);

    match cipher.decrypt(nonce_obj, ciphertext) {
        Ok(plaintext) => Ok(plaintext),
        Err(_) => Err("Decryption failed".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn test_encryption_roundtrip(s in "\\PC*") {
            let password = "test_password";
            let salt: [u8; 16] = [0u8; 16];
            let key = derive_key(password, &salt);

            let data = s.as_bytes();
            let (encrypted, nonce) = encrypt(data, &key);
            let decrypted = decrypt(&encrypted, &nonce, &key).unwrap();

            prop_assert_eq!(data, &decrypted[..]);
        }

        #[test]
        fn test_encryption_fails_with_wrong_password(s in "\\PC*", pw1 in "\\PC*", pw2 in "\\PC*") {
            prop_assume!(pw1 != pw2);
            let salt: [u8; 16] = [0u8; 16];
            let key1 = derive_key(&pw1, &salt);
            let key2 = derive_key(&pw2, &salt);

            let data = s.as_bytes();
            let (encrypted, nonce) = encrypt(data, &key1);
            let decrypted = decrypt(&encrypted, &nonce, &key2);

            prop_assert!(decrypted.is_err());
        }
    }
}
