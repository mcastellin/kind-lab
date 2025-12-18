#!/usr/bin/env python3
import sys
import json
import base64
import hashlib
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

def int_to_base64(value):
    """Convert an integer to a Base64URL-encoded string."""
    value_hex = format(value, 'x')
    if len(value_hex) % 2 == 1:
        value_hex = '0' + value_hex
    value_bytes = bytes.fromhex(value_hex)
    return base64.urlsafe_b64encode(value_bytes).rstrip(b'=').decode('utf-8')

def calculate_kid(pub_key):
    """
    Calculate the Key ID (kid) exactly as Kubernetes does.
    1. Convert PEM to DER (SubjectPublicKeyInfo format)
    2. SHA-256 Hash the DER bytes
    3. Base64 URL-Safe Encode the hash
    """
    der_bytes = pub_key.public_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
            )
    hash_object = hashlib.sha256(der_bytes)
    return base64.urlsafe_b64encode(hash_object.digest()).rstrip(b'=').decode('utf-8')

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 gen_jwks.py <path_to_public_key.pub>")
        sys.exit(1)

    try:
        with open(sys.argv[1], "rb") as f:
            pub_key_bytes = f.read()
            pub_key = serialization.load_pem_public_key(pub_key_bytes, backend=default_backend())
            numbers = pub_key.public_numbers()

        jwks = {
                "keys": [{
                    "kty": "RSA",
                    "alg": "RS256",
                    "use": "sig",
                    "kid": calculate_kid(pub_key),
                    "n": int_to_base64(numbers.n),
                    "e": int_to_base64(numbers.e),
                    }]
                }

        print(json.dumps(jwks, indent=2))

    except Exception as e:
        print(f"Error processing key: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
